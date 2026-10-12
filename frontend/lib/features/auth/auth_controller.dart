import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/app_config.dart';
import '../../core/constants/auth_constants.dart';
import '../../data/auth_models.dart';
import '../../data/chat_api.dart';

enum AuthStatus { restoring, signedOut, signedIn }

/// Who is signed in, and their tokens. The access token lives only in
/// memory; the refresh token is kept in secure storage. One instance.
class AuthController extends ChangeNotifier {
  AuthController._();
  static final instance = AuthController._();

  final _storage = const FlutterSecureStorage();
  http.Client _plain = http.Client();

  /// Swaps the HTTP client (tests).
  @visibleForTesting
  set debugHttp(http.Client client) => _plain = client;

  AuthStatus status = AuthStatus.restoring;
  AuthUser? user;

  /// Why the user was signed out, shown once on the login screen.
  String? notice;

  String? _access;
  DateTime? _accessExpires;
  String? _refresh;
  Future<bool>? _refreshing;

  /// Runs on every sign-out, to drop per-user caches.
  final _onSignOut = <VoidCallback>[];
  void addSignOutHook(VoidCallback hook) => _onSignOut.add(hook);

  String? get accessToken => _access;
  bool get signedIn => status == AuthStatus.signedIn;

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}/auth$path');

  /// This device's label for the sessions list (also sent by GitHub sign-in).
  static String get device => _device;

  static String get _device {
    final os = Platform.operatingSystem;
    final version = Platform.operatingSystemVersion.split(' ').take(3);
    return '${os[0].toUpperCase()}${os.substring(1)} ${version.join(' ')}'
        .trim();
  }

  // ---- start ----------------------------------------------------------

  /// Restores the saved session: refresh token -> new access token.
  /// Offline keeps the cached account so the app still opens.
  Future<void> restore() async {
    try {
      _refresh = await _storage.read(key: AuthKeys.refreshToken);
      final cached = await _storage.read(key: AuthKeys.user);
      if (cached != null) {
        user = AuthUser.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      }
    } catch (_) {
      _refresh = null;
    }
    if (_refresh == null) {
      _setSignedOut();
      return;
    }
    final ok = await refresh();
    if (ok || (status != AuthStatus.signedOut && user != null)) {
      status = AuthStatus.signedIn;
      notifyListeners();
    } else if (status != AuthStatus.signedOut) {
      _setSignedOut();
    }
  }

  // ---- sign in / up ---------------------------------------------------

  Future<void> login(String email, String password) => _start('/login', {
    'email': email.trim(),
    'password': password,
    'device': _device,
  });

  Future<void> register(String name, String email, String password) =>
      _start('/register', {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'device': _device,
        // Proves the owner when registering the server's OWNER_EMAIL.
        if (AppConfig.apiToken.isNotEmpty) 'ownerToken': AppConfig.apiToken,
      });

  /// "Continue with Google": [idToken] from Google Sign-In, checked by the
  /// server, which signs in, links by verified email, or creates the account.
  Future<void> signInWithGoogle(String idToken) =>
      _start('/google', {'idToken': idToken, 'device': _device});

  /// "Continue with GitHub": the session from a finished device flow, stored
  /// exactly like a password sign-in.
  Future<void> signInWithSession(Map<String, dynamic> session) async {
    await _apply(session);
    notice = null;
    status = AuthStatus.signedIn;
    notifyListeners();
  }

  Future<void> _start(String path, Map<String, dynamic> body) async {
    final http.Response res;
    try {
      res = await _plain
          .post(
            _uri(path),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(AuthDurations.request);
    } catch (_) {
      throw const ApiException(AuthStrings.errNetwork);
    }
    if (res.statusCode >= 400) {
      throw ApiException(
        errorMessage(res.body, res.statusCode),
        status: res.statusCode,
      );
    }
    await _apply(jsonDecode(res.body) as Map<String, dynamic>);
    notice = null;
    status = AuthStatus.signedIn;
    notifyListeners();
  }

  Future<void> _apply(Map<String, dynamic> j) async {
    _access = j['accessToken'] as String?;
    _accessExpires = DateTime.tryParse(j['accessExpiresAt'] as String? ?? '');
    _refresh = j['refreshToken'] as String?;
    final next = AuthUser.fromJson(j['user'] as Map<String, dynamic>);
    final switched = user != null && user!.id != next.id;
    user = next;
    if (switched) _runSignOutHooks();
    try {
      await _storage.write(key: AuthKeys.refreshToken, value: _refresh);
      await _storage.write(key: AuthKeys.user, value: jsonEncode(next));
    } catch (_) {
      // Storage trouble only costs staying signed in across restarts.
    }
  }

  /// Updates the cached account after a profile edit.
  Future<void> updateUser(AuthUser next) async {
    user = next;
    notifyListeners();
    try {
      await _storage.write(key: AuthKeys.user, value: jsonEncode(next));
    } catch (_) {}
  }

  // ---- tokens ---------------------------------------------------------

  /// Makes sure the access token is valid for a while; refreshes if not.
  Future<void> ensureFresh() async {
    if (_refresh == null) return;
    final exp = _accessExpires;
    if (_access != null &&
        exp != null &&
        exp.difference(DateTime.now()) > AuthDurations.refreshSkew) {
      return;
    }
    await refresh();
  }

  /// After a 401 sent with [usedToken]: refreshes unless another request
  /// already did. True when a newer access token is ready.
  Future<bool> recover(String? usedToken) async {
    if (_access != null && _access != usedToken) return true;
    return refresh();
  }

  /// One refresh at a time: concurrent callers share it, so a rotated
  /// refresh token is never presented twice.
  Future<bool> refresh() => _refreshing ??= _doRefresh(true).whenComplete(() {
    _refreshing = null;
  });

  Future<bool> _doRefresh(bool mayRetry) async {
    // The assistant overlay runs a second copy of this controller (its own
    // isolate) on the same stored session: whichever refreshed last holds
    // the live token, so start from what storage has now.
    final (read, stored) = await _storedRefresh();
    if (read) {
      if (stored == null) {
        if (_refresh != null) await signOut(callServer: false);
        return false;
      }
      _refresh = stored;
    }
    final token = _refresh;
    if (token == null) return false;
    final http.Response res;
    try {
      res = await _plain
          .post(
            _uri('/refresh'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': token, 'device': _device}),
          )
          .timeout(AuthDurations.request);
    } catch (_) {
      return false; // offline: keep the session, try again later
    }
    if (res.statusCode == 200) {
      await _apply(jsonDecode(res.body) as Map<String, dynamic>);
      return true;
    }
    if (res.statusCode == 401 || res.statusCode == 400) {
      // The other copy may have rotated this token a moment ago: adopt its
      // newer one instead of signing out.
      if (mayRetry && await _rotatedElsewhere(token)) return _doRefresh(false);
      await signOut(callServer: false, reason: AuthStrings.sessionExpired);
    }
    return false;
  }

  /// (could read, stored refresh token). A failed read keeps memory's.
  Future<(bool, String?)> _storedRefresh() async {
    try {
      return (true, await _storage.read(key: AuthKeys.refreshToken));
    } catch (_) {
      return (false, null);
    }
  }

  /// Waits briefly for storage to hold a token other than [used].
  Future<bool> _rotatedElsewhere(String used) async {
    for (var i = 0; i < AuthDurations.syncPolls; i++) {
      final (read, stored) = await _storedRefresh();
      if (!read) return false;
      if (stored != null && stored != used) return true;
      await Future<void>.delayed(AuthDurations.syncPoll);
    }
    return false;
  }

  /// Picks up a sign-in, sign-out or account switch made by the other copy
  /// (app or assistant overlay) since this one last looked.
  Future<void> syncFromStorage() async {
    final (read, stored) = await _storedRefresh();
    if (!read || stored == _refresh) return;
    if (stored == null) {
      _access = null;
      _accessExpires = null;
      _refresh = null;
      user = null;
      _setSignedOut();
      return;
    }
    String? cachedId;
    try {
      final cached = await _storage.read(key: AuthKeys.user);
      if (cached != null) {
        cachedId = AuthUser.fromJson(
          jsonDecode(cached) as Map<String, dynamic>,
        ).id;
      }
    } catch (_) {}
    if (status == AuthStatus.signedIn && cachedId == user?.id) {
      // Same account, newer token: the access token stays valid meanwhile.
      _refresh = stored;
      return;
    }
    _access = null;
    _accessExpires = null;
    await restore();
  }

  // ---- sign out -------------------------------------------------------

  /// Ends the session here (and on the server unless [callServer] is false).
  Future<void> signOut({bool callServer = true, String? reason}) async {
    final token = _refresh;
    _access = null;
    _accessExpires = null;
    _refresh = null;
    user = null;
    notice = reason;
    try {
      await _storage.delete(key: AuthKeys.refreshToken);
      await _storage.delete(key: AuthKeys.user);
    } catch (_) {}
    if (callServer && token != null) {
      unawaited(
        _plain
            .post(
              _uri('/logout'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({'refreshToken': token}),
            )
            .timeout(AuthDurations.request)
            .then((_) {}, onError: (_) {}),
      );
    }
    _setSignedOut();
  }

  void _setSignedOut() {
    final wasIn = status == AuthStatus.signedIn;
    status = AuthStatus.signedOut;
    if (wasIn) _runSignOutHooks();
    notifyListeners();
  }

  void _runSignOutHooks() {
    for (final hook in List.of(_onSignOut)) {
      try {
        hook();
      } catch (_) {}
    }
  }
}
