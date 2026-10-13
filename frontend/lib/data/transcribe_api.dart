import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/constants/app_config.dart';
import '../core/constants/error_copy.dart';
import '../core/constants/voice.dart';
import 'api_client.dart';
import 'chat_api.dart';

/// What `POST /assist/transcribe` returns.
class Transcript {
  const Transcript(this.text, [this.language = '']);
  final String text;
  final String language;
}

/// Sends a recording to the server for Whisper transcription.
class TranscribeApi {
  TranscribeApi({http.Client Function()? makeClient})
    : _makeClient = makeClient ?? http.Client.new;

  final http.Client Function() _makeClient;

  Future<Transcript> transcribe(String path, {String? language}) async {
    final file = File(path);
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('${AppConfig.apiBaseUrl}/assist/transcribe'),
          )
          ..headers.addAll(apiHeaders())
          ..fields.addAll({'language': ?language})
          ..files.add(
            http.MultipartFile(
              'file',
              file.openRead(),
              await file.length(),
              filename: 'voice.${VoiceConfig.fileExtension}',
              contentType: MediaType('audio', 'mp4'),
            ),
          );
    final client = AuthClient(_makeClient());
    try {
      final streamed = await client
          .send(request)
          .timeout(VoiceConfig.requestTimeout);
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode >= 400) {
        throw ApiException.fromResponse(body, streamed.statusCode);
      }
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) {
        throw const ApiException(ErrorCopy.generic);
      }
      return Transcript(
        (json['text'] as String? ?? '').trim(),
        json['language'] as String? ?? '',
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(ErrorCopy.transcribeFailed);
    } finally {
      client.close();
    }
  }
}
