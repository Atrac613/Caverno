import '../../../settings/domain/entities/app_settings.dart';

enum ProReasoningStage {
  idle,
  frame,
  investigate,
  explore,
  critique,
  synthesize,
}

extension ProReasoningDepthBudget on ProReasoningDepth {
  int get candidateCount => switch (this) {
    ProReasoningDepth.standard => 2,
    ProReasoningDepth.deep => 3,
    ProReasoningDepth.max => 4,
  };

  Duration get deadline => switch (this) {
    ProReasoningDepth.standard => const Duration(minutes: 6),
    ProReasoningDepth.deep => const Duration(minutes: 10),
    ProReasoningDepth.max => const Duration(minutes: 20),
  };

  int get investigationIterations => switch (this) {
    ProReasoningDepth.standard => 4,
    ProReasoningDepth.deep => 6,
    ProReasoningDepth.max => 10,
  };
}

final class ProReasoningFrame {
  const ProReasoningFrame({
    required this.subQuestions,
    required this.investigationSteps,
    required this.successCriteria,
    required this.requiresInvestigation,
  });

  factory ProReasoningFrame.fallback(String question) => ProReasoningFrame(
    subQuestions: <String>[question.trim()],
    investigationSteps: const <String>[],
    successCriteria: const <String>[
      'Answer the question directly.',
      'Separate supported facts from uncertainty.',
    ],
    requiresInvestigation: false,
  );

  final List<String> subQuestions;
  final List<String> investigationSteps;
  final List<String> successCriteria;
  final bool requiresInvestigation;
}

final class ProReasoningCandidate {
  const ProReasoningCandidate({
    required this.index,
    required this.answer,
    required this.angle,
    required this.model,
    required this.endpointId,
    required this.endpointLabel,
    required this.thinkingRequested,
    required this.thinkingObserved,
    required this.duration,
    this.reasoning = '',
    this.slotId,
    this.promptTokens,
    this.completionTokens,
  });

  final int index;
  final String answer;
  final String reasoning;
  final String angle;
  final String model;
  final String endpointId;
  final String endpointLabel;
  final bool thinkingRequested;
  final bool thinkingObserved;
  final Duration duration;
  final int? slotId;
  final int? promptTokens;
  final int? completionTokens;

  bool get isUsable => answer.trim().isNotEmpty;
}

final class ProReasoningExploreResult {
  const ProReasoningExploreResult({
    this.candidates = const <ProReasoningCandidate>[],
    this.endpointLabels = const <String>[],
    this.requestedCandidateCount = 0,
    this.attemptedCandidateCount = 0,
  });

  final List<ProReasoningCandidate> candidates;
  final List<String> endpointLabels;
  final int requestedCandidateCount;
  final int attemptedCandidateCount;
}

final class ProReasoningCritique {
  const ProReasoningCritique({
    required this.winnerIndex,
    required this.ranking,
    required this.contradictions,
    required this.assessment,
  });

  factory ProReasoningCritique.fallback(
    List<ProReasoningCandidate> candidates,
  ) => ProReasoningCritique(
    winnerIndex: candidates.isEmpty ? null : candidates.first.index,
    ranking: candidates.map((candidate) => candidate.index).toList(),
    contradictions: const <String>[],
    assessment: candidates.isEmpty
        ? 'No candidate answer survived; use a direct answer.'
        : 'Use the first surviving candidate and verify uncertain claims.',
  );

  final int? winnerIndex;
  final List<int> ranking;
  final List<String> contradictions;
  final String assessment;
}

final class ProReasoningProgress {
  const ProReasoningProgress({
    required this.stage,
    required this.startedAt,
    required this.deadline,
    this.completedCandidates = 0,
    this.requestedCandidates = 0,
    this.endpointLabels = const <String>[],
    this.deadlineHit = false,
    this.cancelRequested = false,
  });

  final ProReasoningStage stage;
  final DateTime startedAt;
  final DateTime deadline;
  final int completedCandidates;
  final int requestedCandidates;
  final List<String> endpointLabels;
  final bool deadlineHit;
  final bool cancelRequested;
}

final class ProReasoningExploreRequest {
  const ProReasoningExploreRequest({
    required this.question,
    required this.frame,
    required this.evidence,
    required this.candidateCount,
    required this.deadline,
    required this.isCancelled,
    this.cancelSignal,
    required this.onProgress,
  });

  final String question;
  final ProReasoningFrame frame;
  final String evidence;
  final int candidateCount;
  final DateTime deadline;
  final bool Function() isCancelled;
  final Future<void>? cancelSignal;
  final void Function({
    required int completed,
    required int requested,
    required List<String> endpointLabels,
  })
  onProgress;
}

final class ProReasoningSynthesisRequest {
  const ProReasoningSynthesisRequest({
    required this.question,
    required this.frame,
    required this.evidence,
    required this.candidates,
    required this.critique,
    required this.deadlineHit,
    required this.cancelRequested,
  });

  final String question;
  final ProReasoningFrame frame;
  final String evidence;
  final List<ProReasoningCandidate> candidates;
  final ProReasoningCritique critique;
  final bool deadlineHit;
  final bool cancelRequested;
}

final class ProReasoningRunResult {
  const ProReasoningRunResult({
    required this.startedAt,
    required this.finishedAt,
    required this.frame,
    required this.evidence,
    required this.exploreResult,
    required this.critique,
    required this.deadlineHit,
    required this.cancelRequested,
    required this.synthesisDispatched,
    this.stageErrors = const <String, String>{},
  });

  final DateTime startedAt;
  final DateTime finishedAt;
  final ProReasoningFrame frame;
  final String evidence;
  final ProReasoningExploreResult exploreResult;
  final ProReasoningCritique critique;
  final bool deadlineHit;
  final bool cancelRequested;
  final bool synthesisDispatched;
  final Map<String, String> stageErrors;
}
