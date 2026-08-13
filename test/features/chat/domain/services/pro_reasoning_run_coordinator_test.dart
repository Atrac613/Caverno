import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/pro_reasoning_models.dart';
import 'package:caverno/features/chat/domain/services/pro_reasoning_run_coordinator.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

void main() {
  test(
    'deadline skips remaining stages but still dispatches synthesis',
    () async {
      var now = DateTime.utc(2026, 8, 13, 10);
      final stages = <ProReasoningStage>[];
      var investigationCalls = 0;
      var exploreCalls = 0;
      var critiqueCalls = 0;
      ProReasoningSynthesisRequest? synthesis;
      final coordinator = ProReasoningRunCoordinator(
        clock: () => now,
        runFrame: (question, deadline) async {
          now = deadline;
          return const ProReasoningFrame(
            subQuestions: ['Question'],
            investigationSteps: ['Inspect evidence'],
            successCriteria: ['Be correct'],
            requiresInvestigation: true,
          );
        },
        runInvestigation: (question, frame, maxIterations, deadline) async {
          investigationCalls++;
          return 'evidence';
        },
        runExplore: (request) async {
          exploreCalls++;
          return const ProReasoningExploreResult();
        },
        runCritique: (question, frame, evidence, candidates, deadline) async {
          critiqueCalls++;
          return ProReasoningCritique.fallback(candidates);
        },
        runSynthesis: (request) async => synthesis = request,
      );

      final result = await coordinator.run(
        question: 'Question',
        depth: ProReasoningDepth.standard,
        isCancelled: () => false,
        onProgress: (progress) => stages.add(progress.stage),
      );

      expect(investigationCalls, 0);
      expect(exploreCalls, 0);
      expect(critiqueCalls, 0);
      expect(stages, [ProReasoningStage.frame, ProReasoningStage.synthesize]);
      expect(synthesis, isNotNull);
      expect(synthesis!.deadlineHit, isTrue);
      expect(synthesis!.cancelRequested, isFalse);
      expect(result.deadlineHit, isTrue);
      expect(result.synthesisDispatched, isTrue);
    },
  );

  test(
    'zero surviving candidates bypass critique and synthesize directly',
    () async {
      final stages = <ProReasoningStage>[];
      var critiqueCalls = 0;
      ProReasoningSynthesisRequest? synthesis;
      final coordinator = ProReasoningRunCoordinator(
        clock: () => DateTime.utc(2026, 8, 13, 10),
        runFrame: (question, deadline) async => const ProReasoningFrame(
          subQuestions: ['Question'],
          investigationSteps: [],
          successCriteria: ['Be correct'],
          requiresInvestigation: false,
        ),
        runInvestigation: (question, frame, maxIterations, deadline) async =>
            '',
        runExplore: (request) async => ProReasoningExploreResult(
          requestedCandidateCount: request.candidateCount,
          attemptedCandidateCount: request.candidateCount,
        ),
        runCritique: (question, frame, evidence, candidates, deadline) async {
          critiqueCalls++;
          return ProReasoningCritique.fallback(candidates);
        },
        runSynthesis: (request) async => synthesis = request,
      );

      final result = await coordinator.run(
        question: 'Question',
        depth: ProReasoningDepth.deep,
        isCancelled: () => false,
        onProgress: (progress) => stages.add(progress.stage),
      );

      expect(critiqueCalls, 0);
      expect(stages, [
        ProReasoningStage.frame,
        ProReasoningStage.explore,
        ProReasoningStage.synthesize,
      ]);
      expect(synthesis!.candidates, isEmpty);
      expect(synthesis!.critique.winnerIndex, isNull);
      expect(result.exploreResult.requestedCandidateCount, 3);
      expect(result.synthesisDispatched, isTrue);
    },
  );

  test(
    'cancellation after exploration synthesizes the partial result',
    () async {
      var cancelled = false;
      var critiqueCalls = 0;
      ProReasoningSynthesisRequest? synthesis;
      final candidate = _candidate(0);
      final coordinator = ProReasoningRunCoordinator(
        clock: () => DateTime.utc(2026, 8, 13, 10),
        runFrame: (question, deadline) async => const ProReasoningFrame(
          subQuestions: ['Question'],
          investigationSteps: [],
          successCriteria: ['Be correct'],
          requiresInvestigation: false,
        ),
        runInvestigation: (question, frame, maxIterations, deadline) async =>
            '',
        runExplore: (request) async {
          cancelled = true;
          return ProReasoningExploreResult(
            candidates: [candidate],
            endpointLabels: const ['Host'],
            requestedCandidateCount: request.candidateCount,
            attemptedCandidateCount: 1,
          );
        },
        runCritique: (question, frame, evidence, candidates, deadline) async {
          critiqueCalls++;
          return ProReasoningCritique.fallback(candidates);
        },
        runSynthesis: (request) async => synthesis = request,
      );

      final result = await coordinator.run(
        question: 'Question',
        depth: ProReasoningDepth.max,
        isCancelled: () => cancelled,
        onProgress: (_) {},
      );

      expect(critiqueCalls, 0);
      expect(synthesis!.cancelRequested, isTrue);
      expect(synthesis!.deadlineHit, isFalse);
      expect(synthesis!.candidates, [candidate]);
      expect(synthesis!.critique.winnerIndex, 0);
      expect(result.cancelRequested, isTrue);
      expect(result.synthesisDispatched, isTrue);
    },
  );
}

ProReasoningCandidate _candidate(int index) => ProReasoningCandidate(
  index: index,
  answer: 'Candidate answer',
  angle: 'Angle',
  model: 'test-model',
  endpointId: 'endpoint',
  endpointLabel: 'Host',
  thinkingRequested: true,
  thinkingObserved: true,
  duration: const Duration(seconds: 1),
);
