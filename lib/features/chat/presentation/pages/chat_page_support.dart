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

extension _ChatPageSlashCommandSupport on _ChatPageState {
  Future<SlashCommandExecutionResult> _submitFeedbackCommand(
    Conversation? currentConversation,
    String feedbackText,
  ) async {
    final settings = ref.read(settingsNotifierProvider);
    if (!settings.feedbackUploadEnabled) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: 'chat.slash_feedback_disabled'.tr(),
      );
    }
    if (!settings.isFeedbackUploadConfigured) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: 'chat.slash_feedback_not_configured'.tr(),
      );
    }
    if (currentConversation == null) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: 'chat.slash_feedback_no_session'.tr(),
      );
    }
    final loggingEnabled =
        LlmSessionLogStore.isEnabled(
          settingsEnabled: settings.enableLlmSessionLogs,
        ) &&
        !settings.demoMode;
    if (!loggingEnabled) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: 'chat.slash_feedback_requires_logs'.tr(),
      );
    }

    final context = LlmSessionLogContext(
      workspaceMode: currentConversation.workspaceMode,
      sessionId: currentConversation.id,
      sessionTitle: currentConversation.title,
      conversationId: currentConversation.id,
      phase: 'feedback',
    );
    final sessionLogFile = await ref
        .read(llmSessionLogStoreProvider)
        .fileForContext(context, create: false);

    try {
      final result = await ref
          .read(feedbackSubmissionServiceProvider)
          .submit(
            FeedbackSubmissionInput(
              endpointUrl: settings.normalizedFeedbackEndpointUrl,
              authToken: settings.normalizedFeedbackEndpointAuthToken,
              feedbackText: feedbackText,
              sessionLogFile: sessionLogFile,
              context: context,
              conversationMessageCount: currentConversation.messages.length,
            ),
          );
      return SlashCommandExecutionResult(
        feedbackMessage: 'chat.slash_feedback_sent'.tr(
          namedArgs: {'key': result.objectKey},
        ),
      );
    } on FeedbackSubmissionException catch (error) {
      if (error.message == FeedbackSubmissionService.missingSessionLogMessage) {
        return SlashCommandExecutionResult.keepInput(
          feedbackMessage: 'chat.slash_feedback_no_session_log'.tr(),
        );
      }
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: 'chat.slash_feedback_failed'.tr(
          namedArgs: {'error': error.message},
        ),
      );
    } catch (error) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: 'chat.slash_feedback_failed'.tr(
          namedArgs: {'error': '$error'},
        ),
      );
    }
  }

  _WorktreeAgentCommandArgs _parseWorktreeAgentCommandArgs(String args) {
    final trimmed = args.trim();
    final match = RegExp(r'(^|\s)--verify(?:\s+|$)').firstMatch(trimmed);
    final verifyMarkerStart = match == null
        ? trimmed.length
        : match.start + (match.group(1)?.length ?? 0);
    final prefix = trimmed.substring(0, verifyMarkerStart).trim();
    final runMarker = RegExp(r'(^|\s)--run(?=\s|$)');
    final runAfterQueue = runMarker.hasMatch(prefix);
    final prompt = prefix.replaceFirst(runMarker, ' ').trim();
    if (match == null) {
      return _WorktreeAgentCommandArgs(
        prompt: prompt,
        runAfterQueue: runAfterQueue,
      );
    }

    return _WorktreeAgentCommandArgs(
      prompt: prompt,
      verificationCommand: trimmed.substring(match.end).trim(),
      hasVerificationMarker: true,
      runAfterQueue: runAfterQueue,
    );
  }
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
            title: _worktreeAgentTaskTitle(prompt),
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
