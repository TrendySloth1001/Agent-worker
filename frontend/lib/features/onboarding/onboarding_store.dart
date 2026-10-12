import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_config.dart';
import '../../core/constants/onboarding.dart';
import '../../data/account_api.dart';
import '../../data/auth_models.dart';
import '../../data/conversations_api.dart';
import '../auth/auth_controller.dart';

/// Whether an account still needs the first-run tour.
enum TourNeed { show, skip, unknown }

/// Remembers, per account, that the first-run tour was done.
///
/// The server's `user.onboarded` is the source of truth (it follows the
/// account to every phone); a local flag keyed by user id covers offline
/// finishes and older servers without the flag. Accounts on an older server
/// that already have chats are treated as onboarded.
class OnboardingStore {
  OnboardingStore({
    Future<SharedPreferences> Function()? prefs,
    Future<bool> Function()? hasChats,
    Future<AuthUser?> Function(bool done)? remote,
  }) : _prefs = prefs ?? SharedPreferences.getInstance,
       _hasChats = hasChats ?? _defaultHasChats,
       _remote = remote ?? _defaultRemote;

  static OnboardingStore instance = OnboardingStore();

  final Future<SharedPreferences> Function() _prefs;
  final Future<bool> Function() _hasChats;
  final Future<AuthUser?> Function(bool done) _remote;

  static Future<bool> _defaultHasChats() async =>
      (await ConversationsApi(AppConfig.apiBaseUrl).list(limit: 1)).isNotEmpty;

  static Future<AuthUser?> _defaultRemote(bool done) =>
      const AccountApi().setOnboarded(done);

  Future<bool> _localDone(String id) async {
    try {
      return (await _prefs()).getBool(OnboardingPrefs.done(id)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _setLocal(String id) async {
    try {
      await (await _prefs()).setBool(OnboardingPrefs.done(id), true);
    } catch (_) {}
  }

  /// Fast answer from the local flag and the server's flag; [TourNeed.unknown]
  /// when only the chat list can tell (see [resolveUnknown]).
  Future<TourNeed> need(AuthUser user) async {
    if (await _localDone(user.id)) {
      // Finished here while the server did not hear about it: tell it now.
      if (user.onboarded == false) unawaited(_sync(user));
      return TourNeed.skip;
    }
    switch (user.onboarded) {
      case true:
        await _setLocal(user.id);
        return TourNeed.skip;
      case false:
        return TourNeed.show;
      case null:
        return TourNeed.unknown;
    }
  }

  /// Older servers: a new account has no chats yet. Errors and timeouts
  /// count as onboarded, so nobody is pushed through the tour by mistake.
  Future<bool> resolveUnknown(AuthUser user) async {
    bool chats;
    try {
      chats = await _hasChats().timeout(OnboardingDurations.decide);
    } catch (_) {
      chats = true;
    }
    if (chats) await _setLocal(user.id);
    return !chats;
  }

  /// The tour was finished or skipped by [user].
  Future<void> markDone(AuthUser user) async {
    await _setLocal(user.id);
    final auth = AuthController.instance;
    if (auth.user?.id == user.id && auth.user?.onboarded != true) {
      await auth.updateUser(auth.user!.copyWith(onboarded: true));
    }
    unawaited(_sync(user));
  }

  Future<void> _sync(AuthUser user) async {
    try {
      await _remote(true);
    } catch (e) {
      // Offline or an older server: the local flag still holds.
      debugPrint('onboarding: server flag not saved ($e)');
    }
  }
}
