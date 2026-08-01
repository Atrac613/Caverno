// Same-library extension on [ChatNotifier]: task proposal parsing delegates to
// a domain service while preserving private call sites.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, unused_element

part of 'chat_notifier.dart';

extension ChatNotifierTaskProposalParser on ChatNotifier {
  TaskProposalParser get _taskProposalParser {
    final jsonRepairFeedback = _planningJsonRepairFeedbackBinding();
    return TaskProposalParser(
      qualityService: _taskProposalQualityService,
      createId: _uuid.v4,
      jsonRepairFeedback: jsonRepairFeedback,
      workflowProposalParser: _buildWorkflowProposalParser(jsonRepairFeedback),
    );
  }

  WorkflowTaskProposalDraft? _buildTaskProposalTruncationFallback({
    required Conversation currentConversation,
    required String rawContent,
    required bool projectLooksEmpty,
    ConversationWorkflowSpec? workflowSpecOverride,
  }) {
    return _taskProposalParser.buildTruncationFallback(
      currentConversation: currentConversation,
      rawContent: rawContent,
      projectLooksEmpty: projectLooksEmpty,
      workflowSpecOverride: workflowSpecOverride,
    );
  }

  WorkflowTaskProposalDraft? _parseTaskProposalMap(
    Map<String, dynamic> decoded,
  ) {
    return _taskProposalParser.parseTaskProposalMap(decoded);
  }

}
