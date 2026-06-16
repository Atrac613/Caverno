import 'package:flutter_test/flutter_test.dart';

import '../../tool/ll22_warmup_measurement.dart';

void main() {
  test('extracts llama.cpp timing fields and cached share', () {
    final sample = Ll22TimingSample.fromResponseJson({
      'timings': {
        'cache_n': 900,
        'prompt_n': 100,
        'prompt_ms': 130.0,
        'predicted_ms': 40.0,
        'prompt_per_second': '770.0',
      },
    });

    expect(sample.cacheN, 900);
    expect(sample.promptN, 100);
    expect(sample.promptMs, 130.0);
    expect(sample.predictedMs, 40.0);
    expect(sample.promptPerSecond, 770.0);
    expect(sample.cachedPromptShare, closeTo(0.9, 0.0001));
    expect(sample.hasCacheTiming, isTrue);
  });

  test('builds a sized system prompt with the nonce at the head', () {
    final prompt = buildLl22SystemPrompt(nonce: 'warm-42', promptChars: 1200);
    expect(prompt.startsWith('RUN-NONCE: warm-42'), isTrue);
    expect(prompt, contains('<repo_map>'));
    expect(prompt, contains('</repo_map>'));
    // Padded to at least the requested size.
    expect(prompt.length, greaterThanOrEqualTo(1200));
  });

  test('measured and warm-up bodies share the same prefix for a nonce', () {
    final options = _options(idSlot: 3);
    final measured = buildLl22MeasuredRequestBody(
      options: options,
      nonce: 'warm-1',
      idSlot: 4,
    );
    final warmup = buildLl22WarmupRequestBody(
      options: options,
      nonce: 'warm-1',
      idSlot: 4,
    );

    final measuredSystem =
        (measured['messages'] as List).first as Map<String, dynamic>;
    final warmupSystem =
        (warmup['messages'] as List).first as Map<String, dynamic>;
    // Same warmed prefix: the system prompt and tool list match.
    expect(warmupSystem['content'], measuredSystem['content']);
    expect(warmup['tools'], measured['tools']);
    expect(warmup['id_slot'], 4);
    // Warm-up generates a single token; the measured turn generates more.
    expect(warmup['max_tokens'], 1);
    expect(measured['max_tokens'], 16);
  });

  test(
    'runs cold then warm-up + warm and reports prompt_ms reduction',
    () async {
      final requests = <Map<String, dynamic>>[];
      // cold (uncached), warm-up (uncached prime), warm measured (cached).
      final responses = [
        _timingResponse(cacheN: 0, promptN: 1000, promptMs: 900.0),
        _timingResponse(cacheN: 0, promptN: 1000, promptMs: 905.0),
        _timingResponse(cacheN: 980, promptN: 20, promptMs: 60.0),
      ];
      final summary = await runLl22WarmupMeasurement(
        options: _options(idSlot: 7),
        generatedAt: DateTime.utc(2026, 6, 16, 3, 0, 0),
        sender: (body) async {
          requests.add(body);
          return responses[requests.length - 1];
        },
      );

      expect(requests, hasLength(3));
      // Cold on the base slot; warm-up + warm on the next slot.
      expect(requests[0]['id_slot'], 7);
      expect(requests[1]['id_slot'], 8);
      expect(requests[2]['id_slot'], 8);

      expect(summary.coldPromptMs, 900.0);
      expect(summary.warmPromptMs, 60.0);
      expect(summary.promptMsReductionAbs, closeTo(840.0, 0.0001));
      expect(summary.promptMsReductionPct, closeTo(0.9333, 0.0001));
      expect(summary.coldCachedShare, closeTo(0.0, 0.0001));
      expect(summary.warmCachedShare, closeTo(0.98, 0.0001));
      expect(summary.improved, isTrue);

      final json = summary.toJson();
      expect(json['schemaName'], 'caverno_ll22_warmup_measurement');
      expect(json['schemaVersion'], 1);
      expect(json['generatedAt'], '2026-06-16T03:00:00.000Z');
      expect((json['comparison'] as Map<String, dynamic>)['improved'], isTrue);
      expect(summary.toMarkdown(), contains('LL22 Idle Warm-Up Measurement'));
      expect(summary.toMarkdown(), contains('`warm`'));
    },
  );
}

Ll22MeasurementOptions _options({int? idSlot}) {
  return Ll22MeasurementOptions(
    baseUrl: 'http://localhost:1234/v1',
    model: 'local',
    apiKey: 'no-key',
    toolCount: 3,
    promptChars: 800,
    maxTokens: 16,
    warmupMaxTokens: 1,
    timeout: const Duration(seconds: 1),
    outputPath: null,
    format: Ll22MeasurementOutputFormat.json,
    idSlot: idSlot,
  );
}

Map<String, dynamic> _timingResponse({
  required int cacheN,
  required int promptN,
  required double promptMs,
}) {
  return {
    'choices': const [],
    'timings': {'cache_n': cacheN, 'prompt_n': promptN, 'prompt_ms': promptMs},
  };
}
