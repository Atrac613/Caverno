import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_difficulty_ladder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports an explicit unmeasured ladder without capability claims', () {
    final ladder = LiveLlmDiagnosticDifficultyLadder.fromReport(_report());

    expect(ladder.isMeasured, isFalse);
    expect(ladder.passedStageCount, 0);
    expect(ladder.highestPassedStagePromptTokens, 0);
    expect(ladder.nextStagePromptTokens, 4096);
    expect(ladder.toJson()['suite'], 'ladder-v2');
    expect(ladder.toJson()['measured'], isFalse);
  });

  test('maps the measured lower bound onto fixed physical-token stages', () {
    final ladder = LiveLlmDiagnosticDifficultyLadder.fromReport(
      _report(measuredPromptTokens: 16498),
    );

    expect(ladder.isMeasured, isTrue);
    expect(ladder.passedStageCount, 3);
    expect(ladder.highestPassedStagePromptTokens, 16384);
    expect(ladder.nextStagePromptTokens, 32768);
    expect(ladder.stages.map((stage) => stage.passed), [
      true,
      true,
      true,
      false,
      false,
      false,
    ]);
    expect(ladder.toJson()['unit'], 'prompt_tokens');
  });

  test('reports completion when the top v1 stage is reached', () {
    const ladder = LiveLlmDiagnosticDifficultyLadder(
      measuredPromptTokens: 131072,
    );

    expect(ladder.passedStageCount, 6);
    expect(ladder.highestPassedStagePromptTokens, 131072);
    expect(ladder.nextStagePromptTokens, isNull);
  });
}

LiveLlmDiagnosticReport _report({int measuredPromptTokens = 0}) {
  return LiveLlmDiagnosticReport(
    startedAt: DateTime.utc(2026, 8, 14),
    baseUrl: 'http://localhost:1234/v1',
    model: 'test-model',
    demoMode: false,
    mcpEnabled: false,
    effectiveContextMetrics: measuredPromptTokens == 0
        ? null
        : LiveLlmDiagnosticEffectiveContextMetrics(
            configuredMaximumTokens: 32768,
            trials: [
              LiveLlmDiagnosticContextTrial(
                requestedApproximateTokens: 16384,
                elapsed: const Duration(milliseconds: 50),
                passed: true,
                promptTokens: measuredPromptTokens,
              ),
            ],
          ),
  );
}
