import 'package:flutter_test/flutter_test.dart';

import '../../tool/ll6_prefix_stability_measurement.dart';

void main() {
  test('extracts llama.cpp timing fields and cache ratio', () {
    final sample = Ll6TimingSample.fromResponseJson({
      'timings': {
        'cache_n': 75,
        'prompt_n': 100,
        'prompt_ms': 123.4,
        'predicted_n': 8,
        'predicted_ms': 250,
        'prompt_per_second': '810.5',
        'predicted_per_second': 32.0,
      },
    });

    expect(sample.cacheN, 75);
    expect(sample.promptN, 100);
    expect(sample.promptMs, 123.4);
    expect(sample.predictedN, 8);
    expect(sample.predictedMs, 250);
    expect(sample.promptPerSecond, 810.5);
    expect(sample.predictedPerSecond, 32.0);
    expect(sample.cachePromptRatio, 0.75);
    expect(sample.cachedPromptShare, closeTo(0.42857, 0.00001));
    expect(sample.toJson()['cachePromptRatio'], 0.75);
    expect(sample.toJson()['cachedPromptShare'], closeTo(0.42857, 0.00001));
  });

  test('builds changed default tools and fixed prefix-stable tools', () {
    final defaultInitial = buildLl6MeasurementRequestBody(
      mode: Ll6MeasurementMode.defaultDynamic,
      requestPhase: Ll6MeasurementRequestPhase.initial,
      model: 'local',
      toolCount: 3,
      maxTokens: 8,
      idSlot: 4,
    );
    final defaultFollowUp = buildLl6MeasurementRequestBody(
      mode: Ll6MeasurementMode.defaultDynamic,
      requestPhase: Ll6MeasurementRequestPhase.followUp,
      model: 'local',
      toolCount: 3,
      maxTokens: 8,
      idSlot: 4,
    );
    final stableInitial = buildLl6MeasurementRequestBody(
      mode: Ll6MeasurementMode.prefixStable,
      requestPhase: Ll6MeasurementRequestPhase.initial,
      model: 'local',
      toolCount: 3,
      maxTokens: 8,
      idSlot: 5,
    );
    final stableFollowUp = buildLl6MeasurementRequestBody(
      mode: Ll6MeasurementMode.prefixStable,
      requestPhase: Ll6MeasurementRequestPhase.followUp,
      model: 'local',
      toolCount: 3,
      maxTokens: 8,
      idSlot: 5,
    );

    expect(_toolNames(defaultInitial), ['tool_search']);
    expect(_toolNames(defaultFollowUp), ['ll6_measure_tool_2']);
    expect(_toolNames(stableInitial), [
      'tool_search',
      'll6_measure_tool_0',
      'll6_measure_tool_1',
      'll6_measure_tool_2',
    ]);
    expect(_toolNames(stableFollowUp), _toolNames(stableInitial));
    expect(defaultFollowUp['messages'], hasLength(4));
    expect(stableInitial['id_slot'], 5);
  });

  test(
    'runs both modes and reports follow-up cache-ratio improvement',
    () async {
      final requests = <Map<String, dynamic>>[];
      final responses = [
        _timingResponse(cacheN: 5, promptN: 100),
        _timingResponse(cacheN: 20, promptN: 100),
        _timingResponse(cacheN: 5, promptN: 100),
        _timingResponse(cacheN: 80, promptN: 100),
      ];
      final options = Ll6MeasurementOptions(
        baseUrl: 'http://localhost:1234/v1',
        model: 'local',
        apiKey: 'no-key',
        toolCount: 3,
        maxTokens: 8,
        timeout: const Duration(seconds: 1),
        outputPath: null,
        format: Ll6MeasurementOutputFormat.json,
        idSlot: 7,
      );

      final summary = await runLl6PrefixStabilityMeasurement(
        options: options,
        generatedAt: DateTime.utc(2026, 6, 14, 1, 2, 3),
        sender: (body) async {
          requests.add(body);
          return responses[requests.length - 1];
        },
      );

      expect(requests, hasLength(4));
      expect(requests[0]['id_slot'], 7);
      expect(requests[1]['id_slot'], 7);
      expect(requests[2]['id_slot'], 8);
      expect(requests[3]['id_slot'], 8);
      expect(summary.defaultFollowUpRatio, 0.2);
      expect(summary.prefixStableFollowUpRatio, 0.8);
      expect(summary.defaultFollowUpCachedShare, closeTo(0.1667, 0.0001));
      expect(summary.prefixStableFollowUpCachedShare, closeTo(0.4444, 0.0001));
      expect(summary.absoluteRatioImprovement, closeTo(0.6, 0.0001));
      expect(summary.relativeRatioImprovement, closeTo(3.0, 0.0001));
      expect(summary.improved, isTrue);

      final json = summary.toJson();
      expect(json['schemaName'], 'caverno_ll6_prefix_stability_measurement');
      expect(json['schemaVersion'], 1);
      expect(json['generatedAt'], '2026-06-14T01:02:03.000Z');
      expect((json['comparison'] as Map<String, dynamic>)['improved'], isTrue);
      expect(
        (json['comparison']
            as Map<String, dynamic>)['prefixStableFollowUpCachedPromptShare'],
        closeTo(0.4444, 0.0001),
      );
      expect(summary.toMarkdown(), contains('`prefix_stable`'));
    },
  );
}

List<String> _toolNames(Map<String, dynamic> request) {
  final tools = request['tools'] as List;
  return tools
      .map((tool) {
        final toolMap = Map<String, dynamic>.from(tool as Map);
        final functionMap = Map<String, dynamic>.from(
          toolMap['function'] as Map,
        );
        return functionMap['name'] as String;
      })
      .toList(growable: false);
}

Map<String, dynamic> _timingResponse({
  required int cacheN,
  required int promptN,
}) {
  return {
    'choices': const [],
    'timings': {'cache_n': cacheN, 'prompt_n': promptN, 'prompt_ms': 100.0},
  };
}
