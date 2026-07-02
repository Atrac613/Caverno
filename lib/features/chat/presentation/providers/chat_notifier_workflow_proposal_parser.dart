// Same-library extension on [ChatNotifier]: workflow proposal parsing delegates
// to a domain service while preserving private call sites.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, unused_element

part of 'chat_notifier.dart';

extension ChatNotifierWorkflowProposalParser on ChatNotifier {
  WorkflowProposalParser get _workflowProposalParser => WorkflowProposalParser(
    qualityService: _taskProposalQualityService,
    onJsonRepair: _recordPlanningJsonRepairRuntimeFeedback,
  );

  WorkflowProposalParseResult? _parseWorkflowProposalResponse(
    String rawContent,
  ) {
    return _workflowProposalParser.parse(rawContent);
  }

  WorkflowProposalParseResult? _parseWorkflowProposalResponseWithFallback(
    String rawContent,
  ) {
    return _workflowProposalParser.parseWithFallback(rawContent);
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

  ConversationWorkflowStage? _parseWorkflowStage(Object? rawStage) {
    return _workflowProposalParser.parseWorkflowStage(rawStage);
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

  WorkflowProposalDraft? _parseWorkflowProposalFromSections(String rawContent) {
    return _workflowProposalParser.parseWorkflowProposalFromSections(
      rawContent,
    );
  }

  WorkflowProposalDraft? _parseWorkflowProposalFromLooseJson(
    String rawContent,
  ) {
    return _workflowProposalParser.parseWorkflowProposalFromLooseJson(
      rawContent,
    );
  }

  WorkflowProposalDraft? _parseWorkflowProposalFromNarrative(
    String rawContent,
  ) {
    return _workflowProposalParser.parseWorkflowProposalFromNarrative(
      rawContent,
    );
  }

  String? _extractNarrativeWorkflowGoal(String rawContent) {
    return _workflowProposalParser.extractNarrativeWorkflowGoal(rawContent);
  }

  String _trimNarrativeWorkflowGoalCandidate(String rawValue) {
    return _workflowProposalParser.trimNarrativeWorkflowGoalCandidate(rawValue);
  }

  String? _sanitizeNarrativeWorkflowGoal(String rawValue) {
    return _workflowProposalParser.sanitizeNarrativeWorkflowGoal(rawValue);
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

  String? _deriveWorkflowFallbackGoalFromConversation(
    Conversation currentConversation,
  ) {
    return _workflowProposalParser.deriveWorkflowFallbackGoalFromConversation(
      currentConversation,
    );
  }
}
