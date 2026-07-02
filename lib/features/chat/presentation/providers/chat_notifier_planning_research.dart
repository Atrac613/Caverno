// Same-library extension on [ChatNotifier]: planning research collection stays
// behind the notifier boundary while the low-state collection logic lives in a
// domain service.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierPlanningResearch on ChatNotifier {
  Future<PlanningResearchContext> _buildPlanningResearchContext({
    required Conversation currentConversation,
    ConversationWorkflowStage? workflowStageOverride,
    ConversationWorkflowSpec? workflowSpecOverride,
  }) async {
    final toolService = _mcpToolService;
    final projectRoot = _getActiveProjectRootPath();
    if (toolService == null ||
        currentConversation.workspaceMode != WorkspaceMode.coding ||
        projectRoot == null ||
        projectRoot.isEmpty) {
      return const PlanningResearchContext();
    }

    appLog('[Workflow] Planning research pass started');

    final context =
        await PlanningResearchCollector(
          runTool: (toolCall) => _dispatchToolCall(toolCall),
          extractPlainText: _extractPlainTextForProposal,
        ).collect(
          currentConversation: currentConversation,
          workflowStageOverride: workflowStageOverride,
          workflowSpecOverride: workflowSpecOverride,
        );

    if (!context.hasContent) {
      appLog('[Workflow] Planning research pass found no grounded context');
    } else {
      appLog(
        '[Workflow] Planning research pass collected '
        '${context.keyFiles.length} file(s), '
        '${context.matchedLines.length} match(es), '
        '${context.fileNotes.length} note(s)',
      );
    }

    return context;
  }
}
