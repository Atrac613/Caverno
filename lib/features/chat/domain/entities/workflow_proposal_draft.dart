import 'package:freezed_annotation/freezed_annotation.dart';

import 'conversation_workflow.dart';

part 'workflow_proposal_draft.freezed.dart';

class WorkflowPlanningDecisionOption {
  const WorkflowPlanningDecisionOption({
    required this.id,
    required this.label,
    this.description = '',
  });

  final String id;
  final String label;
  final String description;
}

class WorkflowPlanningDecision {
  const WorkflowPlanningDecision({
    required this.id,
    required this.question,
    this.help = '',
    this.allowFreeText = false,
    this.freeTextPlaceholder = '',
    required this.options,
  });

  final String id;
  final String question;
  final String help;
  final bool allowFreeText;
  final String freeTextPlaceholder;
  final List<WorkflowPlanningDecisionOption> options;
}

class WorkflowPlanningDecisionAnswer {
  const WorkflowPlanningDecisionAnswer({
    required this.decisionId,
    required this.question,
    required this.optionId,
    required this.optionLabel,
  });

  final String decisionId;
  final String question;
  final String optionId;
  final String optionLabel;
}

@freezed
abstract class WorkflowProposalDraft with _$WorkflowProposalDraft {
  const factory WorkflowProposalDraft({
    required ConversationWorkflowStage workflowStage,
    required ConversationWorkflowSpec workflowSpec,
  }) = _WorkflowProposalDraft;
}
