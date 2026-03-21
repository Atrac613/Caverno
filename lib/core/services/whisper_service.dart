import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../utils/logger.dart';

/// Whisper STT service.
/// Sends audio to an OpenAI-compatible `/v1/audio/transcriptions` endpoint.
class WhisperService {
  WhisperService({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  String baseUrl;
  final http.Client _client;

  /// Transcribe WAV audio bytes to text via Whisper API.
  Future<String> transcribe(
    Uint8List wavBytes, {
    String language = 'ja',
    String model = 'whisper-1',
  }) async {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    final isV1 = base.endsWith('/v1');
    final endpoint = isV1 ? '/audio/transcriptions' : '/inference';
    final uri = Uri.parse('$base$endpoint');

    final request = http.MultipartRequest('POST', uri)
      ..fields['model'] = model
      ..fields['language'] = language
      ..fields['response_format'] = 'json'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          wavBytes,
          filename: 'audio.wav',
        ),
      );

    appLog('[Whisper] Sending ${wavBytes.length} bytes to $uri');

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      appLog('[Whisper] Error: ${response.statusCode} ${response.body}');
      throw Exception(
        'Whisper transcription failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final text = (decoded['text'] as String?)?.trim() ?? '';
    appLog('[Whisper] Transcribed: $text');
    return text;
  }

  /// Check whether the Whisper server is reachable.
  ///
  /// Tries multiple known endpoints since whisper.cpp versions differ
  /// in which routes they expose.
  Future<bool> isAvailable() async {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    final isV1 = base.endsWith('/v1');

    // Candidates in order of likelihood.
    final candidates = isV1
        ? ['$base/models']
        : ['$base/props', '$base/health', base];

    for (final url in candidates) {
      try {
        final response = await _client.get(Uri.parse(url)).timeout(
          const Duration(seconds: 3),
        );
        if (response.statusCode < 500) {
          return true;
        }
      } catch (_) {
        // Try next candidate.
      }
    }

    appLog('[Whisper] Availability check failed for all endpoints');
    return false;
  }
}
