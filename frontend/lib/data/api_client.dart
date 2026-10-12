import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../features/auth/auth_controller.dart';

/// The one HTTP path to the backend. Adds the current access token, and on a
/// 401 refreshes once and retries (requests with a replayable body). When the
/// refresh fails, [AuthController] signs out, which shows the login screen.
/// Requests to other hosts pass through untouched (no token leaves the app).
class AuthClient extends http.BaseClient {
  /// [inner] stays owned by the caller (closing it cancels the request);
  /// without it the client makes and owns its own.
  AuthClient([http.Client? inner])
    : _inner = inner ?? http.Client(),
      _owns = inner == null;

  final http.Client _inner;
  final bool _owns;

  /// True for URLs on the API origin (same scheme, host and port, and under
  /// the base path on a `/` boundary). A look-alike such as
  /// `https://api.example.com.evil.tld` never matches.
  static bool _ours(Uri url) => isApiUrl(url, Uri.parse(AppConfig.apiBaseUrl));

  @visibleForTesting
  static bool isApiUrl(Uri url, Uri base) {
    if (url.scheme != base.scheme ||
        url.host != base.host ||
        url.port != base.port) {
      return false;
    }
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    if (prefix.isNotEmpty &&
        url.path != prefix &&
        !url.path.startsWith('$prefix/')) {
      return false;
    }
    return !url.path.startsWith('/auth/refresh');
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_ours(request.url)) return _inner.send(request);
    final auth = AuthController.instance;
    await auth.ensureFresh();
    final used = _authorize(request);
    // Copied before sending: a sent request cannot be sent again.
    final retry = request is http.Request ? _copy(request) : null;
    final response = await _inner.send(request);
    if (response.statusCode != 401 || !auth.signedIn) return response;
    if (retry == null) {
      // Not replayable (streamed upload): refresh for next time, report 401.
      unawaited(auth.recover(used));
      return response;
    }
    await response.stream.drain<void>().catchError((_) {});
    if (!await auth.recover(used)) {
      return http.StreamedResponse(
        Stream.value(_expiredBody),
        401,
        request: request,
        headers: const {'content-type': 'application/json'},
      );
    }
    _authorize(retry);
    return _inner.send(retry);
  }

  static final _expiredBody =
      '{"error":{"code":"unauthorized","message":"Session expired"}}'.codeUnits;

  /// Sets the bearer header; returns the token used.
  static String? _authorize(http.BaseRequest r) {
    final token = AuthController.instance.accessToken;
    if (token == null) {
      r.headers.remove('Authorization');
    } else {
      r.headers['Authorization'] = 'Bearer $token';
    }
    return token;
  }

  static http.Request _copy(http.Request r) => http.Request(r.method, r.url)
    ..headers.addAll(r.headers)
    ..bodyBytes = r.bodyBytes
    ..followRedirects = r.followRedirects
    ..maxRedirects = r.maxRedirects
    ..persistentConnection = r.persistentConnection;

  @override
  void close() {
    if (_owns) _inner.close();
  }
}

/// Shared client for one-off calls (`apiHttp.get(...)`).
final apiHttp = AuthClient();
