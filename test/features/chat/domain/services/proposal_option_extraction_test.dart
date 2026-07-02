import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/proposal_option_extraction.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';

void main() {
  group('PlanningDecisionPromotion', () {
    test('promotes English alternative open questions into decisions', () {
      final decisions =
          PlanningDecisionPromotion.promoteOpenQuestionsToPlanningPrompts(
            const ['Which should we prioritize first: backend, API, or UI?'],
            decisionAnswers: const [],
          );

      expect(decisions, hasLength(1));
      expect(decisions.first.question, contains('prioritize first'));
      expect(decisions.first.options.map((option) => option.label), [
        'backend',
        'API',
        'UI',
      ]);
      expect(decisions.first.options.map((option) => option.id), [
        'backend',
        'api',
        'ui',
      ]);
    });

    test('promotes Japanese ordered open questions into decisions', () {
      final decisions =
          PlanningDecisionPromotion.promoteOpenQuestionsToPlanningPrompts(
            const ['CLI先行かUI先行か？'],
            decisionAnswers: const [],
          );

      expect(decisions, hasLength(1));
      expect(decisions.first.options.map((option) => option.label), [
        'CLI先行',
        'UI先行',
      ]);
      expect(decisions.first.options.map((option) => option.id), [
        'cli先行',
        'ui先行',
      ]);
    });

    test('removes open questions already resolved by answers', () {
      const proposal = WorkflowProposalDraft(
        workflowStage: ConversationWorkflowStage.clarify,
        workflowSpec: ConversationWorkflowSpec(
          openQuestions: [
            'Should we use polling or webhooks?',
            'What is the deployment environment?',
          ],
        ),
      );

      final filtered = PlanningDecisionPromotion.removeAnsweredOpenQuestions(
        proposal,
        const [
          WorkflowPlanningDecisionAnswer(
            decisionId: 'transport',
            question: 'Should we use polling or webhooks?',
            optionId: 'polling',
            optionLabel: 'polling',
          ),
        ],
      );

      expect(filtered.workflowSpec.openQuestions, [
        'What is the deployment environment?',
      ]);
    });

    test('merges workflow decision answers in place by decision id', () {
      final current = <WorkflowPlanningDecisionAnswer>[
        const WorkflowPlanningDecisionAnswer(
          decisionId: 'scope',
          question: 'Which scope should the plan target?',
          optionId: 'minimal',
          optionLabel: 'Minimal',
        ),
      ];

      PlanningDecisionPromotion.mergeWorkflowDecisionAnswers(current, const [
        WorkflowPlanningDecisionAnswer(
          decisionId: 'scope',
          question: 'Which scope should the plan target?',
          optionId: 'full',
          optionLabel: 'Full',
        ),
        WorkflowPlanningDecisionAnswer(
          decisionId: 'format',
          question: 'Which output format should we use?',
          optionId: 'json',
          optionLabel: 'JSON',
        ),
      ]);

      expect(current, hasLength(2));
      expect(current.first.optionId, 'full');
      expect(current.last.decisionId, 'format');
    });

    test('filters duplicate and answered workflow decisions', () {
      const decisions = [
        WorkflowPlanningDecision(
          id: 'scope',
          question: 'Which scope should the plan target?',
          options: [
            WorkflowPlanningDecisionOption(id: 'minimal', label: 'Minimal'),
          ],
        ),
        WorkflowPlanningDecision(
          id: 'scope',
          question: 'Which scope should the plan target?',
          options: [WorkflowPlanningDecisionOption(id: 'full', label: 'Full')],
        ),
        WorkflowPlanningDecision(
          id: 'format',
          question: 'Which output format should we use?',
          options: [WorkflowPlanningDecisionOption(id: 'json', label: 'JSON')],
        ),
      ];

      final unresolved =
          PlanningDecisionPromotion.filterUnansweredWorkflowDecisions(
            decisions,
            decisionAnswers: const [
              WorkflowPlanningDecisionAnswer(
                decisionId: 'scope',
                question: 'Which scope should the plan target?',
                optionId: 'minimal',
                optionLabel: 'Minimal',
              ),
            ],
          );

      expect(unresolved.map((decision) => decision.id), ['format']);
    });
  });
}
