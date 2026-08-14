// Same-library extension on [ChatNotifier]; see the domain collector.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierPlanningResearch on ChatNotifier {
  Future<PlanningResearchContext> _buildPlanningResearchContext({
    required Conversation currentConversation,
    int? interactionGeneration,
    ConversationWorkflowStage? workflowStageOverride,
    ConversationWorkflowSpec? workflowSpecOverride,
  }) async {
    final toolService = _mcpToolService;
    // Research the planning turn's project, not the visible thread's project.
    final projectRoot = _codingProjectForTurn(
      currentConversation,
    )?.rootPath.trim();
    if (toolService == null ||
        currentConversation.workspaceMode != WorkspaceMode.coding ||
        projectRoot == null ||
        projectRoot.isEmpty) {
      return const PlanningResearchContext();
    }

    appLog('[Workflow] Planning research pass started');

    final context = await TurnProjectRoot.runScoped(
      TurnProjectRoot(projectRoot),
      () => TurnThread.runScoped(
        currentConversation.id,
        () =>
            PlanningResearchCollector(
              runTool: (toolCall) => _dispatchToolCall(
                toolCall,
                interactionGeneration: interactionGeneration,
                projectRoot: projectRoot,
              ),
              extractPlainText:
                  ProposalParsingTextUtils.extractPlainTextForProposal,
            ).collect(
              currentConversation: currentConversation,
              workflowStageOverride: workflowStageOverride,
              workflowSpecOverride: workflowSpecOverride,
            ),
      ),
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
