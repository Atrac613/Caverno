import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_planning_progress.dart';

void main() {
  group('isPlanningProposalReady', () {
    test(
      'treats persisted drafts as ready even if generation flags were stale',
      () {
        final isReady = isPlanningProposalReady(
          hasWorkflowDraft: true,
          hasTaskDraft: true,
          hasPendingDecision: false,
          workflowError: null,
          taskError: null,
          logs: const <String>[],
        );

        expect(isReady, isTrue);
      },
    );

    test('treats workflow and task ready markers in logs as ready', () {
      final isReady = isPlanningProposalReady(
        hasWorkflowDraft: false,
        hasTaskDraft: false,
        hasPendingDecision: false,
        workflowError: null,
        taskError: null,
        logs: const <String>[
          '[Workflow] Workflow proposal ready',
          '[Workflow] Task proposal ready',
        ],
      );

      expect(isReady, isTrue);
    });

    test('treats retry recovery markers as ready', () {
      final isReady = isPlanningProposalReady(
        hasWorkflowDraft: false,
        hasTaskDraft: false,
        hasPendingDecision: false,
        workflowError: null,
        taskError: null,
        logs: const <String>[
          '[Workflow] Workflow proposal recovered on retry',
          '[Workflow] Task proposal recovered on retry',
        ],
      );

      expect(isReady, isTrue);
    });

    test('does not treat planning as ready while a decision is pending', () {
      final isReady = isPlanningProposalReady(
        hasWorkflowDraft: true,
        hasTaskDraft: true,
        hasPendingDecision: true,
        workflowError: null,
        taskError: null,
        logs: const <String>[
          '[Workflow] Workflow proposal ready',
          '[Workflow] Task proposal ready',
        ],
      );

      expect(isReady, isFalse);
    });
  });

  group('resolvePlanningSubphase', () {
    test('returns taskDraftReady when logs show both drafts are ready', () {
      final subphase = resolvePlanningSubphase(
        hasPendingDecision: false,
        hasWorkflowDraft: false,
        hasTaskDraft: false,
        isGeneratingWorkflowProposal: true,
        isGeneratingTaskProposal: true,
        logs: const <String>[
          '[Workflow] Workflow proposal ready',
          '[Workflow] Task proposal ready',
        ],
      );

      expect(subphase, 'taskDraftReady');
    });

    test('returns taskDraftReady when task proposal was recovered on retry', () {
      final subphase = resolvePlanningSubphase(
        hasPendingDecision: false,
        hasWorkflowDraft: false,
        hasTaskDraft: false,
        isGeneratingWorkflowProposal: true,
        isGeneratingTaskProposal: true,
        logs: const <String>[
          '[Workflow] Workflow proposal ready',
          '[Workflow] Task proposal recovered on retry',
        ],
      );

      expect(subphase, 'taskDraftReady');
    });
  });
}
