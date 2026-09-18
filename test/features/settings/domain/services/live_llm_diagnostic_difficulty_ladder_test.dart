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

  // A rung past the endpoint's published window was never attemptable.
  // Reporting it as failed blames the model for the ladder's reach.
  test('marks stages past the published window out of range', () {
    final ladder = LiveLlmDiagnosticDifficultyLadder.fromReport(
      _report(measuredPromptTokens: 32900, advertisedContextTokens: 40960),
    );

    expect(ladder.stages.map((stage) => stage.state), [
      LiveLlmDiagnosticDifficultyStageState.passed,
      LiveLlmDiagnosticDifficultyStageState.passed,
      LiveLlmDiagnosticDifficultyStageState.passed,
      LiveLlmDiagnosticDifficultyStageState.passed,
      LiveLlmDiagnosticDifficultyStageState.outOfRange,
      LiveLlmDiagnosticDifficultyStageState.outOfRange,
    ]);
    expect(ladder.attemptableStageCount, 4);
    // The endpoint cannot be asked to beat 65536, so nothing is offered.
    expect(ladder.nextStagePromptTokens, isNull);
    expect(ladder.toJson()['advertisedContextTokens'], 40960);
    expect(ladder.toJson()['attemptableStageCount'], 4);
  });

  test('a stage inside the window still fails as a failure', () {
    final ladder = LiveLlmDiagnosticDifficultyLadder.fromReport(
      _report(measuredPromptTokens: 8300, advertisedContextTokens: 40960),
    );

    expect(
      ladder.stages[2].state,
      LiveLlmDiagnosticDifficultyStageState.failed,
    );
    expect(ladder.nextStagePromptTokens, 16384);
  });

  // Silence is not a limit: most servers publish no window at all, and calling
  // every large rung out of range would hide the axis the ladder exists for.
  test('leaves every stage attemptable when nothing is published', () {
    final ladder = LiveLlmDiagnosticDifficultyLadder.fromReport(
      _report(measuredPromptTokens: 4200),
    );

    expect(ladder.attemptableStageCount, 6);
    expect(ladder.stages.every((stage) => stage.attemptable), isTrue);
    expect(ladder.nextStagePromptTokens, 8192);
    expect(ladder.toJson().containsKey('advertisedContextTokens'), isFalse);
  });

  // A measurement outranks the advertisement. An endpoint that answered at a
  // size it never published was not limited by what it said.
  test('a measured pass outranks a smaller published window', () {
    const ladder = LiveLlmDiagnosticDifficultyLadder(
      measuredPromptTokens: 70000,
      advertisedContextTokens: 40960,
    );

    expect(
      ladder.stages[4].state,
      LiveLlmDiagnosticDifficultyStageState.passed,
    );
    expect(ladder.highestPassedStagePromptTokens, 65536);
  });
}

LiveLlmDiagnosticReport _report({
  int measuredPromptTokens = 0,
  int advertisedContextTokens = 0,
}) {
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
            advertisedContextTokens: advertisedContextTokens,
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
