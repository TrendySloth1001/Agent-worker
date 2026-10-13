import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../data/chat_api.dart';

/// What to do when an answer's stream breaks (chat and overlay). A dropped
/// connection, a server restart (redeploy) or a proxy gateway error is
/// retried automatically with backoff, re-sending the same turn: the server
/// has no per-message dedupe, so the answer is regenerated cleanly and the
/// partial text stays on screen until the new text starts. When the retries
/// are spent, the answer shows a calm "Answer interrupted · Retry" instead
/// of an error line.
abstract final class StreamRetry {
  /// Waits before each automatic retry; its length is the retry count.
  static const delays = [Duration(seconds: 2), Duration(seconds: 6)];

  /// Gateway statuses a restarting server / proxy answers with.
  static const _gatewayStatuses = {502, 503, 504};

  /// The server's "draining for a redeploy" code (backend lifecycle.ts).
  static const restartingCode = 'restarting';

  /// The phase a reply shows while it waits to retry.
  static const reconnectingPhase = 'reconnecting';

  /// The wait before retry number [attempt] + 1, or null when spent.
  static Duration? delay(int attempt) =>
      attempt < delays.length ? delays[attempt] : null;

  /// Whether [error] is a broken connection worth retrying (null: the stream
  /// closed without its `done` event). Answers the server refused on
  /// purpose (limits, bad input, a model error event) are not.
  static bool retryable(Object? error) => switch (error) {
    null => true,
    ApiException(:final status, :final code) =>
      code == restartingCode ||
          (code == null && _gatewayStatuses.contains(status)),
    SocketException() ||
    HandshakeException() ||
    http.ClientException() ||
    TimeoutException() ||
    HttpException() => true,
    _ => false,
  };
}
