import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../data/chat_api.dart';

/// Friendly, non-technical copy for everything that can go wrong. Raw server
/// text, exception strings, status codes and model names never reach users:
/// [friendlyError] and [friendlyException] turn them into these lines.
/// Owner-only telemetry keeps the raw details.
abstract final class ErrorCopy {
  static const generic = 'Something went wrong — please try again.';
  static const offline =
      "Can't reach sparky — check your connection and try again.";
  static const timeout = 'That took too long — try again.';
  static const rateLimited = "You're going fast — give it a few seconds.";
  static const busy = 'sparky is busy right now — try again in a minute.';
  static const dailyLimit = "You've reached today's limit.";
  static const storageLimit =
      "You're out of storage space. Free some up in Settings → Storage.";
  static const unavailable =
      "That isn't available right now — try again in a minute.";
  static const badRequest = "That didn't work — please check it and try again.";
  static const tooLarge = 'That file is too big.';
  static const unsupportedFile = "That file type isn't supported.";
  static const notFound = "We couldn't find that. It may have been deleted.";
  static const sessionExpired = 'Your session expired — please sign in again.';
  static const forbidden = "You don't have access to that.";
  static const githubNotConnected = 'Connect GitHub to use this.';
  static const githubScopeMissing =
      'GitHub needs more access for this — reconnect GitHub and try again.';
  static const githubNotMergeable = "This pull request can't be merged yet.";
  static const githubInvalid =
      "GitHub didn't accept that — check it and try again.";
  static const connectorNotConnected = 'Connect this app first to use it.';
  static const connectorReauth =
      'This app needs you to sign in again — reconnect it in Settings.';
  static const connectorRateLimited =
      'That app is limiting requests — try again in a minute.';
  static const connectorTimeout = "That app didn't answer in time — try again.";
  static const connectorUnavailable =
      "That app isn't reachable right now — try again later.";
  static const docBusy = 'This document is busy — try again in a moment.';
  static const docRunning = 'This document is still being written.';
  static const assistFailed = "Couldn't finish that — please try again.";
  static const invalidCredentials = "That email and password don't match.";
  static const limitReached =
      "You've hit the limit here. Remove something first.";
  static const uploadFailed = "Couldn't upload that file — please try again.";
  static const downloadFailed = "Couldn't download that file — try again.";
  static const transcribeFailed = "Couldn't make out the audio — try again.";
  static const fileFailed = "Couldn't process this file.";
  static const sourceFailed = "Couldn't add this source — try again.";

  // Chat notices (shown above a reply).
  static const noticeAttachmentFailed =
      "Couldn't read one of your files, so I answered without it.";
  static const noticeKbUnavailable =
      "Your knowledge base isn't available right now, so I answered without it.";
  static const noticeWebSearchFailed =
      "Web search didn't work this time, so I answered without it.";
  static const noticeRoundTableSkipped =
      'Short message, so I answered without the round table.';
  static const noticeRoundTableDegraded =
      'The round table was short-handed, so I answered on my own.';
  static const noticeVisionUnavailable =
      "Couldn't read that image, so I answered from your text.";
  static const noticeTimeBudget =
      'This document ran out of time — resume to finish the rest.';
  static const noticeContinuationFailed =
      "Couldn't continue a cut-off section, so I kept what was written.";

  /// Every user-facing line above (checked by tests).
  static const all = [
    generic,
    offline,
    timeout,
    rateLimited,
    busy,
    dailyLimit,
    storageLimit,
    unavailable,
    badRequest,
    tooLarge,
    unsupportedFile,
    notFound,
    sessionExpired,
    forbidden,
    githubNotConnected,
    githubScopeMissing,
    githubNotMergeable,
    githubInvalid,
    connectorNotConnected,
    connectorReauth,
    connectorRateLimited,
    connectorTimeout,
    connectorUnavailable,
    docBusy,
    docRunning,
    assistFailed,
    invalidCredentials,
    limitReached,
    uploadFailed,
    downloadFailed,
    transcribeFailed,
    fileFailed,
    sourceFailed,
    noticeAttachmentFailed,
    noticeKbUnavailable,
    noticeWebSearchFailed,
    noticeRoundTableSkipped,
    noticeRoundTableDegraded,
    noticeVisionUnavailable,
    noticeTimeBudget,
    noticeContinuationFailed,
  ];

  /// Backend error code → friendly line.
  static const codes = <String, String>{
    'rate_limited': rateLimited,
    'fair_use': rateLimited,
    'daily_limit': dailyLimit,
    'storage_limit': storageLimit,
    'all_models_failed': busy,
    'model_busy': busy,
    'busy': busy,
    'upstream_failed': busy,
    'upstream_timeout': timeout,
    'unavailable': unavailable,
    'internal': generic,
    'bad_request': badRequest,
    'payload_too_large': tooLarge,
    'unsupported_media_type': unsupportedFile,
    'not_found': notFound,
    'unauthorized': sessionExpired,
    'invalid_refresh': sessionExpired,
    'forbidden': forbidden,
    'github_not_connected': githubNotConnected,
    'github_scope_missing': githubScopeMissing,
    'github_not_mergeable': githubNotMergeable,
    'github_invalid': githubInvalid,
    'connector_not_connected': connectorNotConnected,
    'connector_reauth': connectorReauth,
    'connector_rate_limited': connectorRateLimited,
    'connector_timeout': connectorTimeout,
    'connector_unavailable': connectorUnavailable,
    'doc_busy': docBusy,
    'doc_running': docRunning,
    'assist_failed': assistFailed,
    'invalid_credentials': invalidCredentials,
    'limit_reached': limitReached,
  };

  /// Codes whose server message is specific and worth showing (when it
  /// passes [isUserSafe]); others always use their constant.
  static const specific = {
    'bad_request',
    'not_found',
    'daily_limit',
    'storage_limit',
    'limit_reached',
    'forbidden',
    'invalid_credentials',
    'connector_not_connected',
    'connector_reauth',
    'connector_rate_limited',
    'connector_unavailable',
    'github_not_mergeable',
  };

  /// Chat / document notice code → friendly line. Codes mapped to null are
  /// silent (model switches are never shown).
  static const notices = <String, String?>{
    'fallback': null,
    'vision_model': null,
    'attachment_failed': noticeAttachmentFailed,
    'kb_unavailable': noticeKbUnavailable,
    'kb_failed': noticeKbUnavailable,
    'embeddings_down': noticeKbUnavailable,
    'web_search_failed': noticeWebSearchFailed,
    'round_table_skipped': noticeRoundTableSkipped,
    'round_table_degraded': noticeRoundTableDegraded,
    'vision_unavailable': noticeVisionUnavailable,
    'time_budget': noticeTimeBudget,
    'continuation_failed': noticeContinuationFailed,
  };
}

/// Text that reads like it was written for developers.
final _devText = RegExp(
  r'\b(HTTP|status\s*\d{3}|401|403|404|408|409|413|415|422|429|502|503|504|'
  r'Exception|\w+Error|Error:|stack|trace|undefined|null|NaN|provider|quota|'
  r'ollama|groq|openrouter|nvidia|gemini|gemma|llama|mistral|qwen|deepseek|'
  r'openai|gpt|GraphQL|multipart|form-data|UUID|JSON|ECONN\w*|ETIMEDOUT|'
  r'socket|errno|Validation Failed|not configured|'
  r'[A-Z][A-Z0-9]*_[A-Z0-9_]+)\b'
  r'|https?://|[`{}<>\[\]]|=>|\b[a-z]+:[\w/.-]+|[0-9a-f]{8}-[0-9a-f]{4}|'
  r'\b[a-z0-9]{24,}\b',
  caseSensitive: false,
);

/// The longest server text we show as-is.
const _maxSafeLength = 160;

/// True when [message] is plain, short, non-technical text.
bool isUserSafe(String? message) {
  final m = message?.trim() ?? '';
  return m.isNotEmpty && m.length <= _maxSafeLength && !_devText.hasMatch(m);
}

/// [message] when it is user-safe, else [fallback].
String safeOr(String? message, String fallback) =>
    isUserSafe(message) ? message!.trim() : fallback;

/// [message] when it is user-safe, else null.
String? safeOrNull(String? message) =>
    isUserSafe(message) ? message!.trim() : null;

/// A friendly line for a backend error: its code's constant, or the server
/// [message] when the code is specific (or unknown) and the text is safe.
String friendlyError({String? code, String? message, int? status}) {
  final known = code == null ? null : ErrorCopy.codes[code];
  if (code == 'daily_limit') {
    return isUserSafe(message)
        ? dailyLimitMessage(message!.trim())
        : ErrorCopy.dailyLimit;
  }
  if (known != null) {
    return ErrorCopy.specific.contains(code) ? safeOr(message, known) : known;
  }
  // Unknown or no code on a client error (e.g. a form check): its message
  // if it is safe. Server-side failures (5xx) always get a constant.
  final serverSide = status != null && status >= 500;
  if (!serverSide && isUserSafe(message)) return message!.trim();
  return _byStatus(status);
}

String _byStatus(int? status) => switch (status) {
  401 => ErrorCopy.sessionExpired,
  403 => ErrorCopy.forbidden,
  404 => ErrorCopy.notFound,
  408 || 504 => ErrorCopy.timeout,
  413 => ErrorCopy.tooLarge,
  415 => ErrorCopy.unsupportedFile,
  429 => ErrorCopy.rateLimited,
  final int s when s >= 500 => ErrorCopy.busy,
  _ => ErrorCopy.generic,
};

/// A friendly line for any caught error.
String friendlyException(Object e) {
  if (e is ApiException) {
    // Its message was made friendly when it was built; recheck anyway.
    if (isUserSafe(e.message)) return e.message.trim();
    return friendlyError(code: e.code, status: e.status);
  }
  if (e is TimeoutException) return ErrorCopy.timeout;
  if (e is SocketException ||
      e is HandshakeException ||
      e is http.ClientException) {
    return ErrorCopy.offline;
  }
  return ErrorCopy.generic;
}

/// A friendly chat/document notice, or null when nothing should show.
String? friendlyNotice(String code, String message) {
  if (ErrorCopy.notices.containsKey(code)) return ErrorCopy.notices[code];
  return safeOrNull(message);
}
