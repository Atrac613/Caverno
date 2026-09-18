import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_difficulty_ladder.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_tool_depth_ladder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports an unrun staircase as measured by nobody', () {
    final ladder = LiveLlmDiagnosticToolDepthLadder.fromReport(_report());

    expect(ladder.isMeasured, isFalse);
    expect(ladder.passedStageCount, 0);
    expect(ladder.nextStageDepth, 2);
    expect(
      ladder.stages.map((stage) => stage.state).toSet(),
      {LiveLlmDiagnosticDifficultyStageState.notMeasured},
    );
    expect(ladder.toJson()['suite'], 'tool-depth-v1');
    expect(ladder.toJson()['measured'], isFalse);
  });

  // Distinct from never running: this run asked and the model lost state at
  // the very first rung.
  test('a run that cleared no rung reports failures, not silence', () {
    final ladder = LiveLlmDiagnosticToolDepthLadder.fromReport(
      _report(depth: 0, attempted: const [2]),
    );

    expect(ladder.isMeasured, isFalse);
    expect(
      ladder.stages.first.state,
      LiveLlmDiagnosticDifficultyStageState.failed,
    );
  });

  test('maps a partial depth onto the rungs', () {
    final ladder = LiveLlmDiagnosticToolDepthLadder.fromReport(
      _report(depth: 3, attempted: const [2, 3, 4]),
    );

    expect(ladder.isMeasured, isTrue);
    expect(ladder.passedStageCount, 2);
    expect(ladder.nextStageDepth, 4);
    expect(ladder.stages.map((stage) => stage.passed), [true, true, false]);
    expect(ladder.toJson()['measuredDepth'], 3);
    expect(ladder.toJson()['unit'], 'sequential_tool_calls');
  });

  test('offers no next rung once the staircase is cleared', () {
    const ladder = LiveLlmDiagnosticToolDepthLadder(measuredDepth: 4);

    expect(ladder.passedStageCount, 3);
    expect(ladder.nextStageDepth, isNull);
    expect(ladder.toJson().containsKey('nextStageDepth'), isFalse);
  });

  // The axis exists to stay separate from the context ladder: a model can be
  // strong at one and weak at the other, and one number would hide it.
  test('carries its own suite id, axis and unit', () {
    expect(LiveLlmDiagnosticToolDepthLadder.suite, 'tool-depth-v1');
    expect(LiveLlmDiagnosticToolDepthLadder.axis, 'tool_state_depth');
    expect(
      LiveLlmDiagnosticToolDepthLadder.suite,
      isNot(LiveLlmDiagnosticDifficultyLadder.suite),
    );
  });
}

LiveLlmDiagnosticReport _report({int? depth, List<int> attempted = const []}) {
  return LiveLlmDiagnosticReport(
    startedAt: DateTime.utc(2026, 9, 18),
    baseUrl: 'http://localhost:1234/v1',
    model: 'test-model',
    demoMode: false,
    mcpEnabled: false,
    toolDepthMetrics: depth == null
        ? null
        : LiveLlmDiagnosticToolDepthMetrics(
            deepestPassedDepth: depth,
            attemptedDepths: attempted,
          ),
  );
}
