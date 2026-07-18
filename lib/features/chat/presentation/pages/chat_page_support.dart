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
bool shouldPresentDesktopQuestion(ChatInteractionOrigin origin) {
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

String _formatTokenCount(int count) {
  if (count >= 1000000) {
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }
  if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(1)}k';
  }
  return count.toString();
}

extension _ChatPageWorktreeComposerSupport on _ChatPageState {
  Future<String> _startWorktreeSessionFromComposer(
    String prompt,
    CodingProject activeProject, {
    required String languageCode,
  }) async {
    final result = await ref
        .read(codingWorktreeSessionLauncherProvider)
        .create(
          CodingWorktreeSessionLaunchRequest(
            title: worktreeAgentTaskTitle(prompt),
            prompt: prompt,
            codingProjectId: activeProject.id,
            projectRootPath: activeProject.normalizedRootPath,
          ),
        );
    _leaveDashboard();
    ref
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: activeProject.id,
          worktreePath: result.plan.worktreePath,
        );
    final currentAssistantMode = ref
        .read(settingsNotifierProvider)
        .assistantMode;
    if (currentAssistantMode == AssistantMode.general) {
      await ref
          .read(settingsNotifierProvider.notifier)
          .updateAssistantMode(AssistantMode.coding);
    }
    unawaited(
      ref
          .read(chatNotifierProvider.notifier)
          .sendMessage(prompt, languageCode: languageCode),
    );
    return result.plan.branchName;
  }
}
