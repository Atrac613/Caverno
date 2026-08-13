import '../../../settings/domain/entities/app_settings.dart';
import 'pro_reasoning_models.dart';

typedef ProReasoningFrameRunner =
    Future<ProReasoningFrame> Function(String question, DateTime deadline);
typedef ProReasoningInvestigationRunner =
    Future<String> Function(
      String question,
      ProReasoningFrame frame,
      int maxIterations,
      DateTime deadline,
    );
typedef ProReasoningExploreRunner =
    Future<ProReasoningExploreResult> Function(
      ProReasoningExploreRequest request,
    );
typedef ProReasoningCritiqueRunner =
    Future<ProReasoningCritique> Function(
      String question,
      ProReasoningFrame frame,
      String evidence,
      List<ProReasoningCandidate> candidates,
      DateTime deadline,
    );
typedef ProReasoningSynthesisRunner =
    Future<void> Function(ProReasoningSynthesisRequest request);

final class ProReasoningRunCoordinator {
  ProReasoningRunCoordinator({
    required ProReasoningFrameRunner runFrame,
    required ProReasoningInvestigationRunner runInvestigation,
    required ProReasoningExploreRunner runExplore,
    required ProReasoningCritiqueRunner runCritique,
    required ProReasoningSynthesisRunner runSynthesis,
    DateTime Function()? clock,
  }) : _runFrame = runFrame,
       _runInvestigation = runInvestigation,
       _runExplore = runExplore,
       _runCritique = runCritique,
       _runSynthesis = runSynthesis,
       _clock = clock ?? DateTime.now;

  final ProReasoningFrameRunner _runFrame;
  final ProReasoningInvestigationRunner _runInvestigation;
  final ProReasoningExploreRunner _runExplore;
  final ProReasoningCritiqueRunner _runCritique;
  final ProReasoningSynthesisRunner _runSynthesis;
  final DateTime Function() _clock;

  Future<ProReasoningRunResult> run({
    required String question,
    required ProReasoningDepth depth,
    required bool Function() isCancelled,
    required void Function(ProReasoningProgress progress) onProgress,
  }) async {
    final startedAt = _clock();
    final deadline = startedAt.add(depth.deadline);
    final errors = <String, String>{};
    var frame = ProReasoningFrame.fallback(question);
    var evidence = '';
    var exploreResult = ProReasoningExploreResult(
      requestedCandidateCount: depth.candidateCount,
    );
    var critique = ProReasoningCritique.fallback(const []);

    void emit(
      ProReasoningStage stage, {
      int completedCandidates = 0,
      int? requestedCandidates,
      List<String> endpointLabels = const <String>[],
    }) {
      onProgress(
        ProReasoningProgress(
          stage: stage,
          startedAt: startedAt,
          deadline: deadline,
          completedCandidates: completedCandidates,
          requestedCandidates: requestedCandidates ?? depth.candidateCount,
          endpointLabels: endpointLabels,
          deadlineHit: _deadlineReached(deadline),
          cancelRequested: isCancelled(),
        ),
      );
    }

    if (!_shouldSynthesize(deadline, isCancelled)) {
      emit(ProReasoningStage.frame);
      try {
        frame = await _runFrame(question, deadline);
      } catch (error) {
        errors['frame'] = error.toString();
      }
    }

    if (frame.requiresInvestigation &&
        !_shouldSynthesize(deadline, isCancelled)) {
      emit(ProReasoningStage.investigate);
      try {
        evidence = await _runInvestigation(
          question,
          frame,
          depth.investigationIterations,
          deadline,
        );
      } catch (error) {
        errors['investigate'] = error.toString();
      }
    }

    if (!_shouldSynthesize(deadline, isCancelled)) {
      emit(ProReasoningStage.explore);
      try {
        exploreResult = await _runExplore(
          ProReasoningExploreRequest(
            question: question,
            frame: frame,
            evidence: evidence,
            candidateCount: depth.candidateCount,
            deadline: deadline,
            isCancelled: isCancelled,
            onProgress:
                ({
                  required completed,
                  required requested,
                  required endpointLabels,
                }) => emit(
                  ProReasoningStage.explore,
                  completedCandidates: completed,
                  requestedCandidates: requested,
                  endpointLabels: endpointLabels,
                ),
          ),
        );
      } catch (error) {
        errors['explore'] = error.toString();
      }
    }

    critique = ProReasoningCritique.fallback(exploreResult.candidates);
    if (exploreResult.candidates.isNotEmpty &&
        !_shouldSynthesize(deadline, isCancelled)) {
      emit(
        ProReasoningStage.critique,
        completedCandidates: exploreResult.candidates.length,
        requestedCandidates: exploreResult.requestedCandidateCount,
        endpointLabels: exploreResult.endpointLabels,
      );
      try {
        critique = await _runCritique(
          question,
          frame,
          evidence,
          exploreResult.candidates,
          deadline,
        );
      } catch (error) {
        errors['critique'] = error.toString();
      }
    }

    final deadlineHit = _deadlineReached(deadline);
    final cancelRequested = isCancelled();
    emit(
      ProReasoningStage.synthesize,
      completedCandidates: exploreResult.candidates.length,
      requestedCandidates: exploreResult.requestedCandidateCount,
      endpointLabels: exploreResult.endpointLabels,
    );
    var synthesisDispatched = false;
    try {
      await _runSynthesis(
        ProReasoningSynthesisRequest(
          question: question,
          frame: frame,
          evidence: evidence,
          candidates: exploreResult.candidates,
          critique: critique,
          deadlineHit: deadlineHit,
          cancelRequested: cancelRequested,
        ),
      );
      synthesisDispatched = true;
    } catch (error) {
      errors['synthesize'] = error.toString();
    }

    return ProReasoningRunResult(
      startedAt: startedAt,
      finishedAt: _clock(),
      frame: frame,
      evidence: evidence,
      exploreResult: exploreResult,
      critique: critique,
      deadlineHit: deadlineHit,
      cancelRequested: cancelRequested,
      synthesisDispatched: synthesisDispatched,
      stageErrors: Map<String, String>.unmodifiable(errors),
    );
  }

  bool _shouldSynthesize(DateTime deadline, bool Function() isCancelled) =>
      isCancelled() || _deadlineReached(deadline);

  bool _deadlineReached(DateTime deadline) => !_clock().isBefore(deadline);
}
