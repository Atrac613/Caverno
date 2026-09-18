import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_difficulty_ladder.dart';
import 'live_llm_tool_depth_staircase.dart';

/// The second LL39 headroom axis: how many sequential tool calls a model can
/// carry state through.
///
/// Separate from the effective-context ladder rather than folded into it. The
/// two measure different things and a model can be strong at one and weak at
/// the other, so a single number would hide exactly the difference the axis
/// exists to expose. It is unscored for the same reason the context ladder is:
/// `cavernobench` is a conformance floor and must stay comparable across its
/// own history, while headroom belongs on an axis that reports a depth.
///
/// Reuses [LiveLlmDiagnosticDifficultyStageState] so a reader who has learned
/// one ladder can read this one, including the distinction between a rung the
/// model failed and a rung nobody ran.
class LiveLlmDiagnosticToolDepthLadder {
  const LiveLlmDiagnosticToolDepthLadder({
    required this.measuredDepth,
    this.measurementAttempted = true,
  });

  factory LiveLlmDiagnosticToolDepthLadder.fromReport(
    LiveLlmDiagnosticReport report,
  ) => LiveLlmDiagnosticToolDepthLadder(
    measuredDepth: report.toolDepthMetrics?.deepestPassedDepth ?? 0,
    measurementAttempted: report.toolDepthMetrics != null,
  );

  static const id = 'tool-depth';
  /// v2 hardened the rungs after v1 measured 4 of 4 on its first live run and
  /// so separated nothing. Depths from the two versions are not comparable,
  /// which is what the version is for.
  static const version = 2;
  static const axis = 'tool_state_depth';
  static const unit = 'sequential_tool_calls';

  static String get suite => '$id-v$version';

  /// The deepest rung cleared, or 0 when none was.
  final int measuredDepth;

  final bool measurementAttempted;

  bool get isMeasured => measuredDepth > 0;

  List<LiveLlmDiagnosticDifficultyStage> get stages => List.unmodifiable([
    for (final depth in LiveLlmToolDepthStaircase.stageDepths)
      LiveLlmDiagnosticDifficultyStage(
        promptTokens: depth,
        state: !measurementAttempted
            ? LiveLlmDiagnosticDifficultyStageState.notMeasured
            : measuredDepth >= depth
            ? LiveLlmDiagnosticDifficultyStageState.passed
            : LiveLlmDiagnosticDifficultyStageState.failed,
      ),
  ]);

  int get passedStageCount => LiveLlmToolDepthStaircase.stageDepths
      .where((depth) => measuredDepth >= depth)
      .length;

  int? get nextStageDepth {
    for (final depth in LiveLlmToolDepthStaircase.stageDepths) {
      if (measuredDepth < depth) return depth;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'suiteId': id,
    'suiteVersion': version,
    'suite': suite,
    'axis': axis,
    'unit': unit,
    'measured': isMeasured,
    'measuredDepth': measuredDepth,
    'passedStageCount': passedStageCount,
    'stageCount': LiveLlmToolDepthStaircase.stageDepths.length,
    'nextStageDepth': ?nextStageDepth,
    'stages': [
      for (final stage in stages)
        {'depth': stage.promptTokens, 'passed': stage.passed, 'state': stage.state.name},
    ],
  };
}
