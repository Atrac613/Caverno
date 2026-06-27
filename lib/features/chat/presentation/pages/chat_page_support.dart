part of 'chat_page.dart';

@visibleForTesting
bool Function()? debugRemoteCodingMobilePlatformOverride;

@visibleForTesting
bool isRemoteCodingMobilePlatform() {
  final override = debugRemoteCodingMobilePlatformOverride;
  if (override != null) {
    return override();
  }
  return !kIsWeb && (Platform.isAndroid || Platform.isIOS);
}

@visibleForTesting
bool shouldPresentDesktopApproval(ChatInteractionOrigin origin) {
  return origin == ChatInteractionOrigin.local;
}

@visibleForTesting
bool shouldShowContextStatusWidget(ChatState chatState) {
  return chatState.messages.isNotEmpty ||
      chatState.queuedMessages.isNotEmpty ||
      chatState.promptTokens > 0 ||
      chatState.completionTokens > 0 ||
      chatState.totalTokens > 0 ||
      chatState.estimatedPromptTokens > 0 ||
      chatState.contextSurgerySnapshot.hasData;
}

class _WorktreeAgentCommandArgs {
  const _WorktreeAgentCommandArgs({
    required this.prompt,
    this.verificationCommand = '',
    this.hasVerificationMarker = false,
    this.runAfterQueue = false,
  });

  final String prompt;
  final String verificationCommand;
  final bool hasVerificationMarker;
  final bool runAfterQueue;
}

enum _RightSidebarTab { companion, files }

String _formatTokenCount(int count) {
  if (count >= 1000000) {
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }
  if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(1)}k';
  }
  return count.toString();
}

String _formatGitCommandForDisplay(String command) {
  final normalized = GitTools.normalizeCommand(command);
  if (normalized.isEmpty) {
    return 'git';
  }
  return 'git $normalized';
}

String _buildPlanEditSeed(Conversation currentConversation) {
  final planArtifact = currentConversation.effectivePlanArtifact;
  if (planArtifact.hasApproved) {
    return 'Please revise the saved plan for this thread based on the following adjustment:\n- ';
  }
  return 'Please adjust the current draft plan for this thread as follows:\n- ';
}
