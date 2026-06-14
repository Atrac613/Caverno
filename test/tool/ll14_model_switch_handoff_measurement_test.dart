import 'package:flutter_test/flutter_test.dart';

import '../../tool/ll14_model_switch_handoff_measurement.dart';

void main() {
  test('parses options from args and environment', () {
    final options = Ll14ModelSwitchMeasurementOptions.parse(
      [
        '--turn-count',
        '24',
        '--turn-detail-chars=180',
        '--max-tokens',
        '8',
        '--format',
        'json',
      ],
      environment: const {
        'CAVERNO_LLM_BASE_URL': 'http://host:1234/v1',
        'CAVERNO_LLM_MODEL': 'next-model',
        'CAVERNO_LLM_PREVIOUS_MODEL': 'previous-model',
        'CAVERNO_LLM_API_KEY': 'secret',
      },
    );

    expect(options, isNotNull);
    expect(options!.baseUrl, 'http://host:1234/v1');
    expect(options.model, 'next-model');
    expect(options.previousModel, 'previous-model');
    expect(options.apiKey, 'secret');
    expect(options.turnCount, 24);
    expect(options.turnDetailChars, 180);
    expect(options.maxTokens, 8);
    expect(options.format, Ll14MeasurementOutputFormat.json);
    expect(
      options.chatCompletionsEndpoint.toString(),
      'http://host:1234/v1/chat/completions',
    );
  });

  test('builds a compact handoff request instead of full history replay', () {
    final fixture = buildLl14MeasurementFixture(
      turnCount: 32,
      turnDetailChars: 320,
    );
    final fullHistory = buildLl14MeasurementRequestBody(
      mode: Ll14MeasurementMode.fullHistoryReplay,
      fixture: fixture,
      model: 'next-model',
      previousModel: 'previous-model',
      maxTokens: 8,
    );
    final handoff = buildLl14MeasurementRequestBody(
      mode: Ll14MeasurementMode.modelSwitchHandoff,
      fixture: fixture,
      model: 'next-model',
      previousModel: 'previous-model',
      maxTokens: 8,
    );

    final fullStats = summarizeLl14RequestBody(fullHistory);
    final handoffStats = summarizeLl14RequestBody(handoff);
    final handoffMessages = handoff['messages'] as List<dynamic>;
    final handoffText = handoffMessages
        .map((message) => (message as Map)['content'] as String)
        .join('\n');

    expect(handoffStats.messageCount, lessThan(fullStats.messageCount));
    expect(
      handoffStats.estimatedPromptTokens,
      lessThan(fullStats.estimatedPromptTokens),
    );
    expect(handoffText, contains('MODEL SWITCH HANDOFF BRIEF'));
    expect(handoffText, contains('Previous model: previous-model'));
    expect(handoffText, contains('Next model: next-model'));
    expect(handoffText, contains('Earlier conversation summary'));
    expect(
      handoffText,
      contains(
        'claims are unverified unless supported by retained tool results',
      ),
    );
  });

  test(
    'runs both modes and reports prompt reduction with timing proxy',
    () async {
      final requests = <Map<String, dynamic>>[];
      final options = Ll14ModelSwitchMeasurementOptions(
        baseUrl: 'http://localhost:1234/v1',
        model: 'next-model',
        previousModel: 'previous-model',
        apiKey: 'no-key',
        turnCount: 28,
        turnDetailChars: 300,
        maxTokens: 8,
        timeout: const Duration(seconds: 1),
        outputPath: null,
        format: Ll14MeasurementOutputFormat.json,
      );

      final summary = await runLl14ModelSwitchHandoffMeasurement(
        options: options,
        generatedAt: DateTime.utc(2026, 6, 14, 1, 2, 3),
        sender: (body) async {
          requests.add(body);
          return _timingResponse(
            promptN: requests.length == 1 ? 1200 : 420,
            promptMs: requests.length == 1 ? 900.0 : 260.0,
          );
        },
      );

      expect(requests, hasLength(2));
      expect(
        (requests.first['messages'] as List<dynamic>).length,
        greaterThan((requests.last['messages'] as List<dynamic>).length),
      );
      expect(summary.estimatedPromptReduced, isTrue);
      expect(summary.estimatedPromptTokenReduction, greaterThan(0));
      expect(summary.estimatedPromptTokenReductionRatio, greaterThan(0));
      expect(summary.promptMsReduction, 640.0);
      expect(summary.promptMsReductionRatio, closeTo(0.7111, 0.0001));
      expect(summary.promptMsImproved, isTrue);

      final json = summary.toJson();
      expect(
        json['schemaName'],
        'caverno_ll14_model_switch_handoff_measurement',
      );
      expect(json['schemaVersion'], 1);
      expect(json['generatedAt'], '2026-06-14T01:02:03.000Z');
      expect(
        (json['comparison'] as Map<String, dynamic>)['promptMsImproved'],
        isTrue,
      );
      expect(summary.toMarkdown(), contains('LL14 Model-Switch Handoff'));
    },
  );
}

Map<String, dynamic> _timingResponse({
  required int promptN,
  required double promptMs,
}) {
  return {
    'choices': const [],
    'timings': {'prompt_n': promptN, 'prompt_ms': promptMs},
  };
}
