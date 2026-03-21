import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../utils/logger.dart';

/// VOICEVOX speaker entry returned by `/speakers`.
class VoicevoxSpeaker {
  VoicevoxSpeaker({
    required this.name,
    required this.speakerId,
    required this.styleName,
  });

  final String name;
  final int speakerId;
  final String styleName;

  /// Display label shown in the settings UI.
  String get displayName => '$name ($styleName)';
}

/// VOICEVOX TTS service.
/// Calls the VOICEVOX engine REST API to synthesize speech from text.
class VoicevoxService {
  VoicevoxService({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  String baseUrl;
  final http.Client _client;

  /// Synthesize text to WAV audio bytes.
  ///
  /// Two-step process:
  /// 1. POST `/audio_query` to create a query JSON.
  /// 2. POST `/synthesis` with the query to produce WAV audio.
  Future<Uint8List> synthesize(String text, {int speakerId = 0}) async {
    if (text.trim().isEmpty) {
      return Uint8List(0);
    }

    // Step 1: Create an audio query.
    final queryUri = Uri.parse('$baseUrl/audio_query').replace(
      queryParameters: {
        'text': text,
        'speaker': speakerId.toString(),
      },
    );

    appLog('[VOICEVOX] audio_query: speaker=$speakerId, text=${text.length} chars');
    final queryResponse = await _client.post(queryUri);

    if (queryResponse.statusCode != 200) {
      appLog('[VOICEVOX] audio_query error: ${queryResponse.statusCode}');
      throw Exception(
        'VOICEVOX audio_query failed: ${queryResponse.statusCode} ${queryResponse.body}',
      );
    }

    final queryJson = queryResponse.body;

    // Step 2: Synthesize audio from the query.
    final synthUri = Uri.parse('$baseUrl/synthesis').replace(
      queryParameters: {
        'speaker': speakerId.toString(),
      },
    );

    final synthResponse = await _client.post(
      synthUri,
      headers: {'Content-Type': 'application/json'},
      body: queryJson,
    );

    if (synthResponse.statusCode != 200) {
      appLog('[VOICEVOX] synthesis error: ${synthResponse.statusCode}');
      throw Exception(
        'VOICEVOX synthesis failed: ${synthResponse.statusCode} ${synthResponse.body}',
      );
    }

    appLog('[VOICEVOX] Synthesized: ${synthResponse.bodyBytes.length} bytes');
    return synthResponse.bodyBytes;
  }

  /// Retrieve the list of available speakers.
  Future<List<VoicevoxSpeaker>> getSpeakers() async {
    final uri = Uri.parse('$baseUrl/speakers');
    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      appLog('[VOICEVOX] speakers error: ${response.statusCode}');
      throw Exception(
        'VOICEVOX speakers failed: ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body) as List;
    final speakers = <VoicevoxSpeaker>[];

    for (final entry in decoded) {
      final name = entry['name'] as String? ?? '';
      final styles = entry['styles'] as List? ?? [];
      for (final style in styles) {
        speakers.add(
          VoicevoxSpeaker(
            name: name,
            speakerId: style['id'] as int? ?? 0,
            styleName: style['name'] as String? ?? '',
          ),
        );
      }
    }

    appLog('[VOICEVOX] Found ${speakers.length} speaker styles');
    return speakers;
  }

  /// Check whether the VOICEVOX engine is reachable.
  Future<bool> isAvailable() async {
    try {
      final uri = Uri.parse('$baseUrl/speakers');
      final response = await _client.get(uri).timeout(
        const Duration(seconds: 3),
      );
      return response.statusCode == 200;
    } catch (e) {
      appLog('[VOICEVOX] Availability check failed: $e');
      return false;
    }
  }
}
