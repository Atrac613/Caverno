// Same-library extension on [ChatNotifier]: task / workflow proposal quality
// delegates to the extracted quality service while keeping private notifier
// call sites stable during the decomposition.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, unused_element

part of 'chat_notifier.dart';

extension ChatNotifierTaskProposalQuality on ChatNotifier {
  WorkflowTaskProposalQualityService get _taskProposalQualityService =>
      WorkflowTaskProposalQualityService(createId: _uuid.v4);

  bool _isReasoningWorkflowProposalPlausible(WorkflowProposalDraft proposal) {
    return _taskProposalQualityService.isReasoningWorkflowProposalPlausible(
      proposal,
    );
  }

  bool _isReasoningTaskProposalPlausible(WorkflowTaskProposalDraft proposal) {
    return _taskProposalQualityService.isReasoningTaskProposalPlausible(
      proposal,
    );
  }

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
      projectLooksEmpty: _projectLooksEmptyForTaskPlanning(researchContext),
    );
  }

  List<ConversationWorkflowTask> _sanitizeTaskProposalTasks(
    Iterable<ConversationWorkflowTask> tasks,
  ) {
    return _taskProposalQualityService.sanitizeTaskProposalTasks(tasks);
  }

  bool _taskProposalNeedsRetry(
    WorkflowTaskProposalDraft original,
    WorkflowTaskProposalDraft finalized,
    bool projectLooksEmpty,
  ) {
    return _taskProposalQualityService.taskProposalNeedsRetry(
      original,
      finalized,
      projectLooksEmpty,
    );
  }

  bool _taskProposalNeedsRetryForWorkflow(
    WorkflowTaskProposalDraft original,
    WorkflowTaskProposalDraft finalized,
    bool projectLooksEmpty,
    ConversationWorkflowSpec workflowSpec,
  ) {
    return _taskProposalQualityService.taskProposalNeedsRetryForWorkflow(
      original,
      finalized,
      projectLooksEmpty,
      workflowSpec,
    );
  }

  bool _workflowPrefersExplicitSingleTask(
    ConversationWorkflowSpec workflowSpec,
  ) {
    return _taskProposalQualityService.workflowPrefersExplicitSingleTask(
      workflowSpec,
    );
  }

  Set<String> _explicitFirstSliceTargetFiles(
    ConversationWorkflowSpec workflowSpec,
  ) {
    return _taskProposalQualityService.explicitFirstSliceTargetFiles(
      workflowSpec,
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
