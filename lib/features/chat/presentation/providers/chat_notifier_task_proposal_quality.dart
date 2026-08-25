// Same-library extension on [ChatNotifier]: task / workflow proposal quality
// delegates to the extracted quality service while keeping private notifier
// call sites stable during the decomposition.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, unused_element

part of 'chat_notifier.dart';

extension ChatNotifierTaskProposalQuality on ChatNotifier {
  WorkflowTaskProposalQualityService get _taskProposalQualityService =>
      WorkflowTaskProposalQualityService(createId: _uuid.v4);

  TaskProposalQualityGateFallback get _taskProposalFallback =>
      TaskProposalQualityGateFallback(
        quality: _taskProposalQualityService,
        parser: _workflowProposalParser,
      );

  PlanningRetryContextBuilder get _planningRetryContext =>
      PlanningRetryContextBuilder(_taskProposalQualityService);

  WorkflowTaskProposalDraft? _preferTaskProposalRetryCandidate({
    required WorkflowTaskProposalDraft? current,
    required WorkflowTaskProposalDraft candidate,
  }) {
    return _taskProposalQualityService.preferTaskProposalRetryCandidate(
      current: current,
      candidate: candidate,
    );
  }

  List<ConversationWorkflowTask> _buildHeuristicTaskProposalFallbackTasks({
    required List<String> contextLines,
    required bool projectLooksEmpty,
  }) {
    return _taskProposalQualityService.buildHeuristicTaskProposalFallbackTasks(
      contextLines: contextLines,
      projectLooksEmpty: projectLooksEmpty,
    );
  }

  WorkflowTaskProposalDraft _finalizeTaskProposalDraft(
    WorkflowTaskProposalDraft proposal, {
    required PlanningResearchContext researchContext,
  }) {
    return _taskProposalQualityService.finalizeTaskProposalDraft(
      proposal,
      projectLooksEmpty: PlanningRetryContextBuilder.projectLooksEmpty(
        researchContext,
      ),
    );
  }

  List<ConversationWorkflowTask> _reorderTaskProposalTasks(
    List<ConversationWorkflowTask> tasks, {
    required bool projectLooksEmpty,
  }) {
    return _taskProposalQualityService.reorderTaskProposalTasks(
      tasks,
      projectLooksEmpty: projectLooksEmpty,
    );
  }
}
