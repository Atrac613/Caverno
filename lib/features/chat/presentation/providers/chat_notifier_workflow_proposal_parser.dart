// Same-library extension on [ChatNotifier]: workflow proposal parsing delegates
// to a domain service while preserving private call sites.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, unused_element

part of 'chat_notifier.dart';

extension ChatNotifierWorkflowProposalParser on ChatNotifier {
  WorkflowProposalParser get _workflowProposalParser =>
      _buildWorkflowProposalParser(_planningJsonRepairFeedbackBinding());

  WorkflowProposalParser _buildWorkflowProposalParser(
    RuntimeSamplerFeedbackEventBinding? jsonRepairFeedback,
  ) {
    return WorkflowProposalParser(
      qualityService: _taskProposalQualityService,
      jsonRepairFeedback: jsonRepairFeedback,
    );
  }



  WorkflowProposalDraft? _buildWorkflowProposalFallback({
    WorkflowProposalDraft? latestProposal,
    required List<WorkflowPlanningDecision> outstandingDecisions,
  }) {
    return _workflowProposalParser.buildFallback(
      latestProposal: latestProposal,
      outstandingDecisions: outstandingDecisions,
    );
  }

  WorkflowProposalDraft? _buildWorkflowProposalTruncationFallback({
    required Conversation currentConversation,
    required String rawContent,
    required List<WorkflowPlanningDecisionAnswer> decisionAnswers,
  }) {
    return _workflowProposalParser.buildTruncationFallback(
      currentConversation: currentConversation,
      rawContent: rawContent,
      decisionAnswers: decisionAnswers,
    );
  }


  ConversationWorkflowStage? _inferWorkflowStageFromProposal(
    Map<String, dynamic> decoded,
  ) {
    return _workflowProposalParser.inferWorkflowStageFromProposal(decoded);
  }

  WorkflowProposalDraft? _parseWorkflowProposalMap(
    Map<String, dynamic> decoded,
  ) {
    return _workflowProposalParser.parseWorkflowProposalMap(decoded);
  }

  WorkflowProposalParsedDecisions? _parseWorkflowDecisionResponseMap(
    Map<String, dynamic> decoded,
  ) {
    return _workflowProposalParser.parseWorkflowDecisionResponseMap(decoded);
  }







  List<String> _extractNarrativeWorkflowList(
    String rawContent, {
    required List<String> keys,
  }) {
    return _workflowProposalParser.extractNarrativeWorkflowList(
      rawContent,
      keys: keys,
    );
  }

}
