import '../entities/live_llm_diagnostic.dart';

/// What a rung of the ladder measured.
///
/// [outOfRange] is not a failure: the endpoint published a context window too
/// small to hold this prompt, so the stage was never attemptable. Reporting it
/// as `passed: false` would blame the model for the harness's reach -- the
/// same conflation that once scored a vision model blind on an image too small
/// for its tower to resolve.
enum LiveLlmDiagnosticDifficultyStageState { passed, failed, outOfRange }

class LiveLlmDiagnosticDifficultyStage {
  const LiveLlmDiagnosticDifficultyStage({
    required this.promptTokens,
    required this.state,
  });

  final int promptTokens;
  final LiveLlmDiagnosticDifficultyStageState state;

  bool get passed =>
      state == LiveLlmDiagnosticDifficultyStageState.passed;

  bool get attemptable =>
      state != LiveLlmDiagnosticDifficultyStageState.outOfRange;

  Map<String, dynamic> toJson() => {
    'promptTokens': promptTokens,
    'passed': passed,
    'state': state.name,
  };
}

/// Separately versioned LL39 headroom above bounded conformance.
///
/// The first ladder axis promotes the existing effective-context marker recall
/// measurement into fixed physical-token stages. It deliberately has no point
/// total: the raw measured lower bound remains the primary comparison value,
/// while stages make the next harder target explicit and independently
/// versionable from `cavernobench`.
class LiveLlmDiagnosticDifficultyLadder {
  const LiveLlmDiagnosticDifficultyLadder({
    required this.measuredPromptTokens,
    this.advertisedContextTokens = 0,
  });

  factory LiveLlmDiagnosticDifficultyLadder.fromReport(
    LiveLlmDiagnosticReport report,
  ) => LiveLlmDiagnosticDifficultyLadder(
    measuredPromptTokens:
        report.effectiveContextMetrics?.maxSuccessfulPromptTokens ?? 0,
    advertisedContextTokens:
        report.effectiveContextMetrics?.advertisedContextTokens ?? 0,
  );

  static const id = 'ladder';
  static const version = 2;
  static const axis = 'effective_context_recall';
  static const unit = 'prompt_tokens';
  static const stagePromptTokens = <int>[
    4096,
    8192,
    16384,
    32768,
    65536,
    131072,
  ];

  static String get suite => '$id-v$version';

  final int measuredPromptTokens;

  /// 0 when the endpoint published no window, which leaves every stage
  /// attemptable: silence is not a limit.
  final int advertisedContextTokens;

  bool get isMeasured => measuredPromptTokens > 0;

  bool _isOutOfRange(int target) =>
      advertisedContextTokens > 0 && target > advertisedContextTokens;

  List<LiveLlmDiagnosticDifficultyStage> get stages => List.unmodifiable([
    for (final target in stagePromptTokens)
      LiveLlmDiagnosticDifficultyStage(
        promptTokens: target,
        state: measuredPromptTokens >= target
            ? LiveLlmDiagnosticDifficultyStageState.passed
            // A measurement outranks the advertisement: an endpoint that
            // actually answered at this size was not limited by what it said.
            : _isOutOfRange(target)
            ? LiveLlmDiagnosticDifficultyStageState.outOfRange
            : LiveLlmDiagnosticDifficultyStageState.failed,
      ),
  ]);

  /// Stages this endpoint could ever be asked to clear.
  int get attemptableStageCount =>
      stagePromptTokens.where((target) => !_isOutOfRange(target)).length;

  int get passedStageCount => stagePromptTokens
      .where((target) => measuredPromptTokens >= target)
      .length;

  int get highestPassedStagePromptTokens {
    var highest = 0;
    for (final target in stagePromptTokens) {
      if (measuredPromptTokens < target) break;
      highest = target;
    }
    return highest;
  }

  /// The next rung worth aiming at, or null when there is none. A stage past
  /// the endpoint's published window is not a target, so it is skipped rather
  /// than offered as the next thing to beat.
  int? get nextStagePromptTokens {
    for (final target in stagePromptTokens) {
      if (measuredPromptTokens >= target) continue;
      return _isOutOfRange(target) ? null : target;
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
    'measuredPromptTokens': measuredPromptTokens,
    'passedStageCount': passedStageCount,
    'stageCount': stagePromptTokens.length,
    'attemptableStageCount': attemptableStageCount,
    if (advertisedContextTokens > 0)
      'advertisedContextTokens': advertisedContextTokens,
    'highestPassedStagePromptTokens': highestPassedStagePromptTokens,
    'nextStagePromptTokens': ?nextStagePromptTokens,
    'stages': stages.map((stage) => stage.toJson()).toList(),
  };
}
