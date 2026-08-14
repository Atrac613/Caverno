import '../entities/live_llm_diagnostic.dart';

class LiveLlmDiagnosticDifficultyStage {
  const LiveLlmDiagnosticDifficultyStage({
    required this.promptTokens,
    required this.passed,
  });

  final int promptTokens;
  final bool passed;

  Map<String, dynamic> toJson() => {
    'promptTokens': promptTokens,
    'passed': passed,
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
  const LiveLlmDiagnosticDifficultyLadder({required this.measuredPromptTokens});

  factory LiveLlmDiagnosticDifficultyLadder.fromReport(
    LiveLlmDiagnosticReport report,
  ) => LiveLlmDiagnosticDifficultyLadder(
    measuredPromptTokens:
        report.effectiveContextMetrics?.maxSuccessfulPromptTokens ?? 0,
  );

  static const id = 'ladder';
  static const version = 1;
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

  bool get isMeasured => measuredPromptTokens > 0;

  List<LiveLlmDiagnosticDifficultyStage> get stages => List.unmodifiable([
    for (final target in stagePromptTokens)
      LiveLlmDiagnosticDifficultyStage(
        promptTokens: target,
        passed: measuredPromptTokens >= target,
      ),
  ]);

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

  int? get nextStagePromptTokens {
    for (final target in stagePromptTokens) {
      if (measuredPromptTokens < target) return target;
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
    'highestPassedStagePromptTokens': highestPassedStagePromptTokens,
    'nextStagePromptTokens': ?nextStagePromptTokens,
    'stages': stages.map((stage) => stage.toJson()).toList(),
  };
}
