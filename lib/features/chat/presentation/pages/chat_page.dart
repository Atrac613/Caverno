import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/services/browser_session_service.dart';
import '../../../../core/services/coding_terminal_service.dart';
import '../../../../core/services/security_scoped_bookmark_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../../../core/types/workspace_mode.dart';
import '../../../dashboard/presentation/widgets/dashboard_view.dart';
import '../../../personal_eval/presentation/pages/personal_eval_record_page.dart';
import '../../../project_farm/presentation/project_task_review_launcher.dart';
import '../../../project_farm/presentation/widgets/project_task_progress_section.dart';
import '../../../remote_coding/presentation/remote_coding_page.dart';
import '../../../routines/domain/entities/routine.dart';
import '../../../routines/presentation/pages/routine_detail_view.dart';
import '../../../routines/presentation/pages/routines_home_page.dart';
import '../../../routines/presentation/providers/routine_scheduler.dart';
import '../../../routines/presentation/providers/routines_notifier.dart';
import '../../../routines/presentation/widgets/routine_editor_launcher.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/model_list_provider.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/llm_session_log_store.dart';
import '../../data/datasources/session_logging_chat_datasource.dart';
import '../../domain/entities/coding_project.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_goal.dart';
import '../../domain/entities/conversation_plan_artifact.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/turn_diff.dart';
import '../../domain/services/composer_assistant_mode_resolver.dart';
import '../../domain/services/conversation_plan_projection_service.dart';
import '../coordinators/chat_dropped_attachments.dart';
import '../coordinators/chat_dropped_attachments_take.dart';
import '../coordinators/chat_page_composer_runtime_coordinator.dart';
import '../coordinators/chat_page_workspace_navigation_coordinator.dart';
import '../coordinators/coding_project_picker.dart';
import '../coordinators/feedback_slash_command_coordinator.dart';
import '../coordinators/goal_slash_command_coordinator.dart';
import '../coordinators/plan_review_action_coordinator.dart';
import '../coordinators/slash_command_action_coordinator.dart';
import '../coordinators/workflow_task_action_coordinator.dart';
import '../coordinators/workflow_task_run_coordinator.dart';
import '../providers/chat_notifier.dart';
import '../providers/chat_state.dart';
import '../providers/coding_environment_snapshot_provider.dart';
import '../providers/coding_projects_notifier.dart';
import '../providers/coding_worktree_session_launcher.dart';
import '../providers/conversations_notifier.dart';
import '../providers/custom_slash_commands_notifier.dart';
import '../providers/feedback_submission_provider.dart';
import '../providers/html_preview_provider.dart';
import '../providers/pro_reasoning_run_notifier.dart';
import '../providers/worktree_agent_task_launcher.dart';
import '../providers/worktree_agent_task_orchestrator.dart';
import '../slash_commands/slash_command.dart';
import '../slash_commands/slash_command_catalog.dart';
import '../slash_commands/slash_command_prompt_template.dart';
import '../widgets/approval/approval_dialog_route.dart';
import '../widgets/background_process_panel.dart';
import '../widgets/chat_error_banner.dart';
import '../widgets/chat_page_scaffold.dart';
import '../widgets/chat_right_sidebar.dart';
import '../widgets/conversation_drawer.dart';
import '../widgets/conversation_goal_status_presentation.dart';
import '../widgets/conversation_work_time_section.dart';
import '../widgets/file_workspace_viewer_sheet.dart';
import '../widgets/flutter_run_issue_list.dart';
import '../widgets/local_llm_health_section.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../widgets/message_input_send_handler.dart';
import '../widgets/mobile_keyboard_dismiss.dart';
import '../widgets/participant_roster_bar.dart';
import '../widgets/plan/awaiting_you_sheet.dart';
import '../widgets/plan/compact_plan_footer_card.dart';
import '../widgets/plan/plan_hydrated_task_row.dart';
import '../widgets/plan/plan_open_question_section.dart';
import '../widgets/plan/plan_review_sheet.dart';
import '../widgets/pro_reasoning_progress_card.dart';
import '../widgets/project_run_control_section.dart';
import '../widgets/queued_messages_strip.dart';
import '../widgets/session_log_details_section.dart';
import '../widgets/subagent_task_banner.dart';
import '../widgets/terminal/coding_terminal_dock.dart';
import '../widgets/thread_message_list_view.dart';
import '../widgets/token_usage_indicator.dart';
import '../widgets/tool_perimeter_summary.dart';
import '../widgets/turn_rollback_confirmation_dialog.dart';
import '../widgets/workflow_status_presentation.dart';
import '../widgets/worktree_agent_task_banner.dart';
import 'approval_dialog_presenter.dart';
import 'approval_sheet_dispatcher.dart';
import 'thread_scroll_coordinator.dart';

part 'chat_page_approval_listeners.dart';
part 'chat_page_browser_builders.dart';
part 'chat_page_companion_builders.dart';
part 'chat_page_empty_state_builders.dart';
part 'chat_page_goal_builders.dart';
part 'chat_page_header_builders.dart';
part 'chat_page_plan_builders.dart';
part 'chat_page_support.dart';
part 'chat_page_turn_rollback_support.dart';
part 'chat_page_workflow_support.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, this.showDashboardOnStartup = true});

  final bool showDashboardOnStartup;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _threadScroll = ThreadScrollCoordinator();
  final _workflowPanelScrollController = ScrollController();
  final ApprovalDialogPresenter _approvalDialogs = ApprovalDialogPresenter();
  final Set<String> _rolledBackTurnDiffIds = <String>{};
  final _projectTaskReviews = ProjectTaskReviewLauncher();
  final _uuid = const Uuid();
  bool _isPresentingPlanReviewSheet = false;
  String? _trackedPlanGenerationConversationId;
  String? _lastAutoPresentedPlanReviewDraftKey;
  bool _wasGeneratingPlanForTrackedConversation = false;
  bool _isCompanionSidebarVisible = true;
  String _composerPrefillText = '';
  int _composerPrefillVersion = 0;
  late bool _showDashboard;
  FileWorkspaceViewerRequest? _fileWorkspaceViewerRequest;
  ChatRightSidebarTab _rightSidebarTab = ChatRightSidebarTab.companion;
  String? _switchingCompanionBranchName;
  final ChatDroppedAttachments _droppedAttachments = ChatDroppedAttachments();
  static const double _browserPanelBreakpoint = 1280;
  static const double _browserPanelWidth = 480;
  static const double _compactBrowserPanelHeightFraction = 0.55;
  static const double _compactBrowserChatReserveHeight = 220;

  ChatPageComposerRuntimeCoordinator get _composerRuntimeCoordinator =>
      ChatPageComposerRuntimeCoordinator(
        ref: ref,
        leaveDashboard: _leaveDashboard,
      );

  /// Reused browser webview preserves the live page while panes toggle.
  final GlobalKey _browserWebViewKey = GlobalKey();
  Widget? _browserWebView;
  @override
  void initState() {
    super.initState();
    _showDashboard = widget.showDashboardOnStartup;
    ref.read(routineSchedulerProvider);
  }

  @override
  void dispose() {
    _threadScroll.dispose();
    _workflowPanelScrollController.dispose();
    super.dispose();
  }

  void _openFileWorkspaceViewer(FileWorkspaceViewerRequest request) {
    if (!mounted) {
      _fileWorkspaceViewerRequest = request;
      _rightSidebarTab = ChatRightSidebarTab.files;
      _isCompanionSidebarVisible = true;
      return;
    }
    final availableWidth = MediaQuery.maybeOf(context)?.size.width;
    if (availableWidth != null &&
        availableWidth < chatCompanionSidebarBreakpoint) {
      unawaited(
        showFileWorkspaceViewerPanel(context: context, request: request),
      );
      return;
    }
    setState(() {
      _fileWorkspaceViewerRequest = request;
      _rightSidebarTab = ChatRightSidebarTab.files;
      _isCompanionSidebarVisible = true;
    });
  }

  void _closeFileWorkspaceViewer() {
    if (!mounted) {
      _fileWorkspaceViewerRequest = null;
      _rightSidebarTab = ChatRightSidebarTab.companion;
      return;
    }
    setState(() {
      _fileWorkspaceViewerRequest = null;
      _rightSidebarTab = ChatRightSidebarTab.companion;
    });
  }

  void _toggleCompanionSidebar() {
    setState(() {
      _isCompanionSidebarVisible = !_isCompanionSidebarVisible;
    });
  }

  Widget _buildThreadMessageItem(
    BuildContext context,
    int index, {
    required ChatState chatState,
    required ConversationsState conversationsState,
    required bool isCodingWorkspace,
  }) {
    final onReselect = isCodingWorkspace ? _pickAndActivateProject : null;
    if (index >= chatState.messages.length) {
      return MessageBubble(
        key: const ValueKey('plan-status-message'),
        message: _buildPlanStatusMessage(context, chatState: chatState),
        onOpenFileWorkspaceViewer: _openFileWorkspaceViewer,
        onReselectProject: onReselect,
      );
    }
    final message = chatState.messages[index];
    final turnDiff = conversationsState.currentConversation
        ?.turnDiffForAssistantMessage(message.id);
    final canRewind =
        !chatState.isLoading &&
        !message.isStreaming &&
        index < chatState.messages.length - 1;
    return MessageBubble(
      key: ValueKey(message.id),
      message: message,
      conversationId: conversationsState.currentConversationId,
      turnDiff: turnDiff,
      onOpenTurnDiff: turnDiff == null
          ? null
          : () =>
                _openFileWorkspaceViewer(_buildTurnDiffViewerRequest(turnDiff)),
      onOpenFileWorkspaceViewer: _openFileWorkspaceViewer,
      canRewind: canRewind,
      onRewindToHere: canRewind
          ? () => _rewindConversationToMessage(context, message)
          : null,
      onReselectProject: onReselect,
    );
  }

  void _openDashboard() {
    if (!mounted) {
      _showDashboard = true;
      return;
    }
    setState(() {
      _showDashboard = true;
    });
  }

  void _leaveDashboard() {
    if (!_showDashboard) {
      return;
    }
    if (!mounted) {
      _showDashboard = false;
      return;
    }
    setState(() {
      _showDashboard = false;
    });
  }

  ChatPageWorkspaceNavigationCoordinator get _workspaceNavigationCoordinator =>
      ChatPageWorkspaceNavigationCoordinator(
        conversationsNotifier: ref.read(conversationsNotifierProvider.notifier),
        codingProjectsNotifier: ref.read(
          codingProjectsNotifierProvider.notifier,
        ),
        readConversationsState: () => ref.read(conversationsNotifierProvider),
        readCodingProjectsState: () => ref.read(codingProjectsNotifierProvider),
        readAssistantMode: () =>
            ref.read(settingsNotifierProvider).assistantMode,
        updateAssistantMode: ref
            .read(settingsNotifierProvider.notifier)
            .updateAssistantMode,
        leaveDashboard: _leaveDashboard,
        clearRoutineSelection: () =>
            ref.read(routinesNotifierProvider.notifier).selectRoutine(null),
      );

  Future<void> _switchWorkspaceMode(WorkspaceMode workspaceMode) =>
      _workspaceNavigationCoordinator.switchWorkspaceMode(workspaceMode);

  Future<void> _activateCodingProject(
    String projectId, {
    bool createFreshOnFirstOpen = false,
  }) => _workspaceNavigationCoordinator.activateCodingProject(
    projectId,
    createFreshOnFirstOpen: createFreshOnFirstOpen,
  );

  List<SlashCommandDefinition> _buildSlashCommands(
    BuildContext context,
    List<SlashCommandPromptTemplate> customPromptTemplates,
  ) {
    return buildSlashCommandCatalog(
      text: _resolveSlashCommandText,
      customPromptTemplates: customPromptTemplates,
    );
  }

  String _resolveSlashCommandText(
    String key, {
    Map<String, String>? namedArgs,
  }) => key.tr(namedArgs: namedArgs);

  Future<SlashCommandExecutionResult> _handleSlashCommand(
    BuildContext context,
    SlashCommandInvocation invocation, {
    required bool isLoading,
    required bool isCodingWorkspace,
    required CodingProject? activeProject,
    required Conversation? currentConversation,
    required ConversationsState conversationsState,
    required List<SlashCommandPromptTemplate> customPromptTemplates,
  }) async {
    if (isLoading && !invocation.definition.enabledWhileLoading) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: 'chat.slash_blocked_while_loading'.tr(),
      );
    }
    if (invocation.definition.promptTemplateId == 'review' ||
        invocation.definition.action == SlashCommandAction.review) {
      final settings = ref.read(settingsNotifierProvider);
      if (!isCodingWorkspace || activeProject == null) {
        return SlashCommandExecutionResult.keepInput(
          feedbackMessage: 'chat.slash_review_unavailable'.tr(),
        );
      }
      if (!settings.hasCodeReviewRoute) {
        return SlashCommandExecutionResult.keepInput(
          feedbackMessage: 'chat.slash_review_not_configured'.tr(),
        );
      }
      final template = builtInSlashCommandPromptTemplates.firstWhere(
        (template) => template.id == 'review',
      );
      unawaited(
        ref
            .read(chatNotifierProvider.notifier)
            .sendMessage(
              template.expand(
                args: invocation.args,
                commandName: invocation.commandName,
              ),
              languageCode: context.locale.languageCode,
              purpose: PrimaryTurnPurpose.codeReview,
              bypassPlanMode: true,
            ),
      );
      return SlashCommandExecutionResult.handled;
    }
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final coordinator = SlashCommandActionCoordinator(
      conversationsNotifier: conversationsNotifier,
      clearMessages: chatNotifier.clearMessages,
      cancelStreaming: _composerRuntimeCoordinator.cancelActiveResponse,
      dismissPlanProposal: chatNotifier.dismissPlanProposal,
      updateAssistantMode: ref
          .read(settingsNotifierProvider.notifier)
          .updateAssistantMode,
      leaveDashboard: _leaveDashboard,
      showHelp: (commands) =>
          _composerRuntimeCoordinator.showSlashCommandHelp(context, commands),
      handleGoal:
          (conversation, args, {required sendObjectiveAsInitialPrompt}) =>
              GoalSlashCommandCoordinator(
                conversationsNotifier: conversationsNotifier,
                showGoalEditor: (conversation) =>
                    _showGoalEditor(context, conversation),
                sendInitialPrompt: (objective) {
                  unawaited(
                    chatNotifier.sendMessage(
                      objective,
                      languageCode: context.mounted
                          ? context.locale.languageCode
                          : 'en',
                    ),
                  );
                },
                text: _resolveSlashCommandText,
              ).handle(
                currentConversation: conversation,
                args: args,
                sendObjectiveAsInitialPrompt: sendObjectiveAsInitialPrompt,
              ),
      submitFeedback: (conversation, feedbackText) =>
          FeedbackSlashCommandCoordinator(
            sessionLogStore: ref.read(llmSessionLogStoreProvider),
            feedbackSubmissionClient: ref.read(
              feedbackSubmissionServiceProvider,
            ),
            text: _resolveSlashCommandText,
          ).handle(
            settings: ref.read(settingsNotifierProvider),
            currentConversation: conversation,
            feedbackText: feedbackText,
          ),
      startProReasoning: (question) =>
          _composerRuntimeCoordinator.startProReasoning(context, question),
      enqueueWorktreeAgent: ref.read(worktreeAgentTaskLauncherProvider).enqueue,
      startReadyWorktreeAgents: (request) async {
        await ref
            .read(worktreeAgentTaskRunControllerProvider.notifier)
            .startAndExecuteReady(request);
      },
      text: _resolveSlashCommandText,
    );
    return coordinator.handle(
      invocation,
      commandContext: SlashCommandActionContext(
        isLoading: isLoading,
        isCodingWorkspace: isCodingWorkspace,
        activeProject: activeProject,
        currentConversation: currentConversation,
        conversationsState: conversationsState,
        customPromptTemplates: customPromptTemplates,
      ),
    );
  }

  Future<void> _pickAndActivateProject() {
    return pickAndActivateCodingProject(
      bookmarks: ref.read(securityScopedBookmarkServiceProvider),
      projects: ref.read(codingProjectsNotifierProvider.notifier),
      isMounted: () => mounted,
      activate: _activateCodingProject,
    );
  }

  Future<void> _selectDrawerConversation(String conversationId) async {
    await _workspaceNavigationCoordinator.selectConversation(conversationId);
    if (!mounted) return;
    unawaited(
      _projectTaskReviews.start(
        ref: ref,
        conversationId: conversationId,
        languageCode: context.locale.languageCode,
        isMounted: () => mounted,
        showMessage: (message) => ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message))),
      ),
    );
  }

  void _createDrawerChatConversation() {
    _leaveDashboard();
    ref
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(workspaceMode: WorkspaceMode.chat);
  }

  void _createDrawerCodingThread(String projectId) {
    _leaveDashboard();
    ref
        .read(conversationsNotifierProvider.notifier)
        .startDraftConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: projectId,
        );
  }

  Widget _buildConversationDrawer({
    required bool closeOnAction,
    double? width,
    bool useRemoteCodingDrawer = false,
  }) {
    return ConversationDrawer(
      closeOnAction: closeOnAction,
      width: width,
      codingWorkspaceDrawerBuilder: useRemoteCodingDrawer
          ? (context, closeDrawer) =>
                RemoteCodingDrawerSection(closeDrawer: closeDrawer)
          : null,
      onWorkspaceModeSelected: _switchWorkspaceMode,
      onCodingProjectSelected: _activateCodingProject,
      onConversationSelected: _selectDrawerConversation,
      onAddCodingProject: _pickAndActivateProject,
      onOpenDashboard: _openDashboard,
      onCreateChatConversation: _createDrawerChatConversation,
      onCreateCodingThread: _createDrawerCodingThread,
      isDashboardSelected: _showDashboard,
    );
  }

  void _takeDrop(void Function() record) {
    if (!mounted) return;
    setState(record);
  }

  Widget _buildMediaDropTarget({required bool enabled, required Widget child}) {
    return wrapChatMediaDropTarget(
      enabled: enabled,
      videoEnabled: ref
          .watch(settingsNotifierProvider)
          .videoAttachmentsAvailable,
      dropped: _droppedAttachments,
      takeDrop: _takeDrop,
      child: child,
    );
  }

  Future<void> _rewindConversationToMessage(
    BuildContext context,
    Message message,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rewind conversation?'),
        content: const Text(
          'Messages after this point will be removed. Local file changes are not restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rewind'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final rewound = await ref
        .read(conversationsNotifierProvider.notifier)
        .rewindCurrentConversationToMessage(message.id);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          rewound
              ? 'Conversation rewound.'
              : 'Could not rewind to that message.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatNotifierProvider);
    final proReasoningState = ref.watch(proReasoningRunProvider);
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    final conversationsState = ref.watch(conversationsNotifierProvider);
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final codingProjectsState = ref.watch(codingProjectsNotifierProvider);
    final customSlashCommandTemplates = ref.watch(
      customSlashCommandsNotifierProvider,
    );

    // Scroll when the message list changes.
    ref.listen(chatNotifierProvider, _threadScroll.onChatStateChanged);

    ref.listen<String?>(
      conversationsNotifierProvider.select(
        (state) => state.currentConversationId,
      ),
      (previous, next) {
        if (previous == next || next == null) {
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          conversationsNotifier.ensureCurrentPlanArtifactBackfilled();
        });
      },
    );

    _registerApprovalDialogListeners(context);

    final settings = ref.watch(settingsNotifierProvider);
    final isDashboardVisible = _showDashboard;
    final isRoutinesWorkspace =
        !isDashboardVisible &&
        conversationsState.activeWorkspaceMode == WorkspaceMode.routines;
    final isCodingWorkspace =
        !isDashboardVisible &&
        conversationsState.activeWorkspaceMode == WorkspaceMode.coding;
    final isComposerBusy = chatState.isLoading || proReasoningState.isRunning;
    final showChatApprovalMode =
        !isDashboardVisible &&
        !isCodingWorkspace &&
        !isRoutinesWorkspace &&
        settings.exposesGatedChatTools;
    final routinesState = ref.watch(routinesNotifierProvider);
    final selectedRoutine =
        isRoutinesWorkspace && routinesState.selectedRoutineId != null
        ? ref
              .read(routinesNotifierProvider.notifier)
              .findRoutine(routinesState.selectedRoutineId!)
        : null;
    final isMobileRemoteCoding =
        isCodingWorkspace && isRemoteCodingMobilePlatform();
    final activeProject = codingProjectsState.findById(
      conversationsState.activeProjectId,
    );
    final currentConversation = conversationsState.currentConversation;
    final isPlanMode =
        !isDashboardVisible &&
        (currentConversation?.isPlanningSession ?? false);
    final effectiveAssistantMode = ComposerAssistantModeResolver.resolve(
      settingsMode: settings.assistantMode,
      isPlanningSession: isPlanMode,
      isCodingWorkspace: isCodingWorkspace,
      hasConversation: currentConversation != null,
    );
    final rawTitle = isDashboardVisible
        ? 'dashboard.title'.tr()
        : currentConversation?.title ??
              (isCodingWorkspace && activeProject != null
                  ? defaultConversationTitle
                  : 'Caverno');
    final currentTitle = rawTitle == defaultConversationTitle
        ? (isCodingWorkspace
              ? 'chat.new_thread'.tr()
              : 'chat.new_conversation'.tr())
        : rawTitle;
    final canCompose =
        !isDashboardVisible && (!isCodingWorkspace || activeProject != null);
    final shouldShowPlanFooterCard =
        isCodingWorkspace &&
        activeProject != null &&
        currentConversation != null &&
        currentConversation.hasPlanArtifact &&
        !(chatState.isGeneratingWorkflowProposal ||
            chatState.isGeneratingTaskProposal);
    final shouldShowPlanStatusMessage =
        isCodingWorkspace &&
        activeProject != null &&
        currentConversation != null &&
        isPlanMode &&
        (chatState.isGeneratingWorkflowProposal ||
            chatState.isGeneratingTaskProposal ||
            ((chatState.workflowProposalError != null ||
                    chatState.taskProposalError != null) &&
                !currentConversation.hasPlanArtifact &&
                chatState.workflowProposalDraft == null &&
                chatState.taskProposalDraft == null));
    final canShowCompanionPanel =
        !isDashboardVisible &&
        !isMobileRemoteCoding &&
        ((isRoutinesWorkspace && selectedRoutine != null) ||
            (currentConversation != null &&
                !isRoutinesWorkspace &&
                (!isCodingWorkspace || activeProject != null)));
    // Needs a project root and a real PTY; see CodingTerminalDock.
    final terminalWorkingDirectory =
        isCodingWorkspace &&
            !isDashboardVisible &&
            !isMobileRemoteCoding &&
            CodingTerminalDock.isSupported
        ? activeProject?.normalizedRootPath
        : null;
    final shouldShowCodingDraftComposer =
        isCodingWorkspace &&
        activeProject != null &&
        currentConversation == null &&
        chatState.messages.isEmpty;
    _threadScroll.syncThread(
      conversationId: conversationsState.currentConversationId,
      isMessageListVisible:
          !isDashboardVisible &&
          !isRoutinesWorkspace &&
          !isMobileRemoteCoding &&
          !shouldShowCodingDraftComposer &&
          canCompose &&
          chatState.messages.isNotEmpty,
    );
    final isWideForCompanion =
        MediaQuery.sizeOf(context).width >= chatCompanionSidebarBreakpoint;
    _maybePresentPlanReviewSheet(
      context,
      currentConversation: currentConversation,
      chatState: chatState,
      isPlanMode: isPlanMode,
    );

    final usePersistentDrawer =
        !isMobileRemoteCoding &&
        MediaQuery.sizeOf(context).width >= chatPagePersistentDrawerBreakpoint;
    void submitComposerMessage(
      String message,
      String? imageBase64,
      String? imageMimeType,
      String? originalImagePath,
      String? originalImageMimeType, {
      VideoAttachmentDraft? video,
      String? modelContent,
      String? attachmentPath,
      bool interrupt = false,
    }) {
      setState(() {
        _composerPrefillText = '';
        _composerPrefillVersion++;
      });
      _leaveDashboard();
      unawaited(
        chatNotifier.sendMessage(
          message,
          modelContent: modelContent,
          attachmentPath: attachmentPath,
          imageBase64: imageBase64,
          imageMimeType: imageMimeType,
          originalImagePath: originalImagePath,
          originalImageMimeType: originalImageMimeType,
          video: video,
          languageCode: context.locale.languageCode,
          interrupt: interrupt,
        ),
      );
    }

    // Send and interrupt take the same payload and differ only in whether the
    // running turn is joined, so one factory makes both rather than two
    // hand-written forwarders that have to be edited together.
    MessageInputSendHandler composerSender({bool interrupt = false}) =>
        (
          message,
          imageBase64,
          imageMimeType,
          originalImagePath,
          originalImageMimeType, {
          video,
          modelContent,
          attachmentPath,
        }) => submitComposerMessage(
          message,
          imageBase64,
          imageMimeType,
          originalImagePath,
          originalImageMimeType,
          video: video,
          modelContent: modelContent,
          attachmentPath: attachmentPath,
          interrupt: interrupt,
        );
    final handleComposerSend = composerSender();
    final handleComposerInterrupt = composerSender(interrupt: true);

    bool handleProReasoningSend(String question) =>
        _composerRuntimeCoordinator.startProReasoning(context, question);

    Widget buildMessageInput({bool floating = false}) {
      final input = MessageInput(
        onSend: handleComposerSend,
        onInterrupt: proReasoningState.isRunning
            ? null
            : handleComposerInterrupt,
        onCancel: _composerRuntimeCoordinator.cancelActiveResponse,
        isLoading: isComposerBusy,
        assistantMode: effectiveAssistantMode,
        onAssistantModeSelected: (mode) =>
            _composerRuntimeCoordinator.selectAssistantMode(
              mode,
              isCodingWorkspace: isCodingWorkspace,
              currentConversation: currentConversation,
            ),
        slashCommands: _buildSlashCommands(
          context,
          customSlashCommandTemplates,
        ),
        onSlashCommand: (invocation) => _handleSlashCommand(
          context,
          invocation,
          isLoading: isComposerBusy,
          isCodingWorkspace: isCodingWorkspace,
          activeProject: activeProject,
          currentConversation: currentConversation,
          conversationsState: conversationsState,
          customPromptTemplates: customSlashCommandTemplates,
        ),
        onProReasoningSend: handleProReasoningSend,
        isCodingWorkspace: isCodingWorkspace,
        showChatApprovalMode: showChatApprovalMode,
        inputHintKey: isCodingWorkspace
            ? (isPlanMode
                  ? 'message.input_hint_plan'
                  : 'message.input_hint_coding')
            : 'message.input_hint',
        composerPrefillText: _composerPrefillText,
        composerPrefillVersion: _composerPrefillVersion,
        droppedImageAttachment: _droppedAttachments.image,
        droppedVideoAttachment: _droppedAttachments.video,
        droppedFileAttachment: _droppedAttachments.file,
        onDroppedImageHandled: () =>
            _takeDrop(() => _droppedAttachments.image = null),
        onDroppedVideoHandled: () =>
            _takeDrop(() => _droppedAttachments.video = null),
        onDroppedFileHandled: () =>
            _takeDrop(() => _droppedAttachments.file = null),
        // Where a session starts is a choice about a session that has not run
        // yet, so the selector shows only while the thread is still empty.
        // Offering it inside a thread already under way implies that thread
        // could move to a worktree, which it cannot.
        onWorktreeSessionSend:
            isCodingWorkspace &&
                activeProject != null &&
                chatState.messages.isEmpty
            ? (prompt) => _startWorktreeSessionFromComposer(
                prompt,
                activeProject,
                languageCode: context.locale.languageCode,
              )
            : null,
        codingGoal: isCodingWorkspace ? currentConversation?.goal : null,
        goalAutoContinueCount: chatState.goalAutoContinueCount,
        goalAutoContinueBudget: chatState.goalAutoContinueBudget,
        goalAutoContinueNotice: chatState.goalAutoContinueNotice,
        onCodingGoalEdit: isCodingWorkspace && currentConversation != null
            ? () => _showGoalEditor(context, currentConversation)
            : null,
        onCodingGoalMarkComplete:
            isCodingWorkspace && currentConversation?.goal?.hasObjective == true
            ? () => _markGoalCompleted(context)
            : null,
        onCodingGoalMarkBlocked:
            isCodingWorkspace && currentConversation?.goal?.hasObjective == true
            ? () => _markGoalBlocked(context, currentConversation!.goal!)
            : null,
        onCodingGoalReactivate:
            isCodingWorkspace && currentConversation?.goal?.hasObjective == true
            ? () => _reactivateGoal(context)
            : null,
        onCodingGoalClear:
            isCodingWorkspace && currentConversation?.goal?.hasObjective == true
            ? () => _clearGoal(context)
            : null,
        isFloating: floating,
      );
      final showProProgress = !isCodingWorkspace && proReasoningState.isRunning;
      if (currentConversation == null ||
          currentConversation.workspaceMode != WorkspaceMode.chat) {
        if (!showProProgress) return input;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProReasoningProgressCard(
              progress: proReasoningState.progress,
              onCancel: _composerRuntimeCoordinator.cancelActiveResponse,
            ),
            input,
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ParticipantRosterBar(
            participants: currentConversation.participants,
            config: currentConversation.participantTurnConfig,
            endpoints: settings.enabledAdditionalLlmEndpoints,
            primaryModel: settings.effectiveModel,
            referencedParticipantIds: {
              for (final message in currentConversation.messages)
                if (message.participantId != null) message.participantId!,
            },
            enabled: !isComposerBusy,
            runtime: chatState.participantTurnRuntime,
            onStopRequested: chatNotifier.requestParticipantTurnStop,
            onContinueRequested: () {
              unawaited(chatNotifier.continueParticipantTurns());
            },
            onChanged: ({required participants, required config}) async {
              await conversationsNotifier.updateConversationParticipants(
                currentConversation.id,
                participants: participants,
                participantTurnConfig: config,
              );
            },
          ),
          if (showProProgress)
            ProReasoningProgressCard(
              progress: proReasoningState.progress,
              onCancel: _composerRuntimeCoordinator.cancelActiveResponse,
            ),
          input,
        ],
      );
    }

    Widget buildRoutineDetailBody(Routine routine) {
      final detailView = RoutineDetailView(
        key: ValueKey('routine-detail-${routine.id}'),
        routineId: routine.id,
        onClose: () =>
            ref.read(routinesNotifierProvider.notifier).selectRoutine(null),
      );

      return LayoutBuilder(
        builder: (context, _) {
          final showRoutineCompanionSidebar =
              canShowCompanionPanel &&
              _isCompanionSidebarVisible &&
              MediaQuery.sizeOf(context).width >=
                  chatCompanionSidebarBreakpoint;
          if (!showRoutineCompanionSidebar) return detailView;
          return ChatRightSidebarLayout(
            content: detailView,
            sidebar: SizedBox(
              width: chatCompanionSidebarWidth,
              child: _buildRoutineCompanionPanel(
                context,
                routine: routine,
                showLeadingBorder: false,
              ),
            ),
          );
        },
      );
    }

    Widget buildWorkspaceBody() {
      return isDashboardVisible
          ? const DashboardView()
          : isRoutinesWorkspace
          ? (selectedRoutine != null
                ? buildRoutineDetailBody(selectedRoutine)
                : const RoutinesHomePage())
          : isMobileRemoteCoding
          ? const RemoteCodingPage()
          : _buildMediaDropTarget(
              enabled: canCompose,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showCompanionSidebar =
                      canShowCompanionPanel &&
                      currentConversation != null &&
                      _isCompanionSidebarVisible &&
                      MediaQuery.sizeOf(context).width >=
                          chatCompanionSidebarBreakpoint;
                  final sidebarConversation = showCompanionSidebar
                      ? currentConversation
                      : null;
                  final chatContent = Column(
                    children: [
                      if (chatState.error != null)
                        ChatErrorBanner(message: chatState.error!),
                      if (currentConversation?.hasCompactionArtifact ?? false)
                        _buildConversationCompactionBanner(
                          context,
                          currentConversation!,
                        ),
                      // Message list
                      Expanded(
                        child: shouldShowCodingDraftComposer
                            ? _buildCodingDraftComposer(
                                context,
                                activeProject,
                                buildMessageInput(floating: true),
                              )
                            : !canCompose
                            ? _buildCodingProjectEmptyState(context)
                            : chatState.messages.isEmpty
                            ? _buildEmptyState(
                                context,
                                isCodingWorkspace: isCodingWorkspace,
                              )
                            : ThreadMessageListView(
                                controller: _threadScroll.controller,
                                onScrollNotification:
                                    _threadScroll.handleScrollNotification,
                                itemCount:
                                    chatState.messages.length +
                                    (shouldShowPlanStatusMessage ? 1 : 0),
                                itemBuilder: (context, index) =>
                                    _buildThreadMessageItem(
                                      context,
                                      index,
                                      chatState: chatState,
                                      conversationsState: conversationsState,
                                      isCodingWorkspace: isCodingWorkspace,
                                    ),
                                scrollToBottomVisibility: isCodingWorkspace
                                    ? _threadScroll.showScrollToBottomButton
                                    : null,
                                onScrollToBottom: _threadScroll.scrollToBottom,
                              ),
                      ),
                      if (!shouldShowCodingDraftComposer &&
                          canCompose &&
                          shouldShowPlanFooterCard)
                        _buildFooterPlanCard(
                          context,
                          currentConversation: currentConversation,
                          chatState: chatState,
                          isPlanMode: isPlanMode,
                        ),
                      if (!shouldShowCodingDraftComposer &&
                          canCompose &&
                          (chatState.queuedMessages.isNotEmpty ||
                              chatState.steeringMessages.isNotEmpty))
                        QueuedMessagesStrip.forChat(
                          chatState,
                          onRemove: chatNotifier.removeQueuedMessage,
                          onInterrupt: chatNotifier.interruptWithQueuedMessage,
                        ),
                      if (canCompose && !shouldShowCodingDraftComposer)
                        buildMessageInput(),
                      if (!shouldShowCodingDraftComposer &&
                          canCompose &&
                          shouldShowContextStatusWidget(chatState))
                        _buildTokenUsageBar(context, chatState, settings),
                    ],
                  );
                  final coreBody = showCompanionSidebar
                      ? ChatRightSidebarLayout(
                          content: chatContent,
                          sidebar: ChatRightSidebarPanel(
                            availableWidth: constraints.maxWidth,
                            companionPanel: _buildCompanionPanel(
                              context,
                              currentConversation: sidebarConversation!,
                              chatState: chatState,
                              activeProject: activeProject,
                              showLeadingBorder: false,
                            ),
                            fileViewer: _fileWorkspaceViewerRequest
                                ?.buildViewer(
                                  onClose: _closeFileWorkspaceViewer,
                                ),
                            processPanel: BackgroundProcessPanel.of(
                              sidebarConversation.id,
                            ),
                            selectedTab: _rightSidebarTab,
                            onSelected: (selection) {
                              setState(() {
                                _rightSidebarTab = selection;
                              });
                            },
                          ),
                        )
                      : chatContent;
                  // The run log spans the full width, under both the
                  // conversation and the sidebar: it belongs to the project,
                  // not to either column. It renders nothing until a run
                  // starts.
                  return _wrapWithBrowserPane(
                    context,
                    coreBody,
                    availableWidth: MediaQuery.sizeOf(context).width,
                    availableHeight: constraints.maxHeight,
                  );
                },
              ),
            );
    }

    final currentThreadId = currentConversation?.id;
    final workspaceBody = CodingTerminalDock(
      workingDirectory: terminalWorkingDirectory,
      threadId: currentThreadId,
      runProjectRoot: activeProject == null || currentConversation == null
          ? ''
          : _effectiveCodingProjectForConversation(
              currentConversation: currentConversation,
              activeProject: activeProject,
            ).normalizedRootPath,
      onSendIssueToChat: (issue) =>
          _prefillCompanionPrompt(flutterRunIssuePrompt(issue)),
      child: buildWorkspaceBody(),
    );
    final taskBanner = SubagentTaskBanner(conversationId: currentThreadId);
    final scaffold = usePersistentDrawer
        ? ChatPageScaffold.persistent(
            workspaceBody: workspaceBody,
            taskBanner: taskBanner,
            drawer: _buildConversationDrawer(
              closeOnAction: false,
              width: chatPagePersistentDrawerWidth,
            ),
            header: _buildPersistentWorkspaceHeader(
              context,
              isRoutinesWorkspace: isRoutinesWorkspace,
              isCodingWorkspace: isCodingWorkspace,
              isMobileRemoteCoding: isMobileRemoteCoding,
              activeProject: activeProject,
              currentTitle: currentTitle,
              settings: settings,
              canCompose: canCompose,
              canShowCompanionPanel: canShowCompanionPanel,
              canShowCodingTerminal: terminalWorkingDirectory != null,
              isWideForCompanion: isWideForCompanion,
              currentConversation: currentConversation,
              selectedRoutine: selectedRoutine,
              conversationsState: conversationsState,
              conversationsNotifier: conversationsNotifier,
              chatState: chatState,
              routineTitle: selectedRoutine?.trimmedName,
            ),
          )
        : ChatPageScaffold.compact(
            workspaceBody: workspaceBody,
            taskBanner: taskBanner,
            title: _buildWorkspaceHeaderTitle(
              context,
              isRoutinesWorkspace: isRoutinesWorkspace,
              isCodingWorkspace: isCodingWorkspace,
              activeProject: activeProject,
              currentTitle: currentTitle,
              settings: settings,
              prominent: false,
              routineTitle: selectedRoutine?.trimmedName,
            ),
            actions: _buildWorkspaceHeaderActions(
              context,
              activeProject: activeProject,
              settings: settings,
              canShowCompanionPanel: canShowCompanionPanel,
              canShowCodingTerminal: terminalWorkingDirectory != null,
              isWideForCompanion: isWideForCompanion,
              currentConversation: currentConversation,
              selectedRoutine: selectedRoutine,
              chatState: chatState,
              compact: false,
            ),
            drawer: _buildConversationDrawer(
              closeOnAction: true,
              useRemoteCodingDrawer: isMobileRemoteCoding,
            ),
            // The compact routines home has no persistent create affordance.
            floatingActionButton: isRoutinesWorkspace && selectedRoutine == null
                ? FloatingActionButton(
                    onPressed: () => _createRoutineFromHome(context),
                    tooltip: 'routines.create_cta'.tr(),
                    child: const Icon(Icons.add),
                  )
                : null,
          );
    return wrapWithMobileKeyboardDismiss(scaffold);
  }

  Future<void> _createRoutineFromHome(BuildContext context) async {
    final createdId = await showRoutineEditor(context, ref);
    if (createdId == null || !mounted) {
      return;
    }
    ref.read(routinesNotifierProvider.notifier).selectRoutine(createdId);
  }

  Future<void> _editPlanInChat(
    BuildContext context, {
    required Conversation currentConversation,
  }) async {
    final composerPrefillText = await _planReviewActionCoordinator.prepareEdit(
      currentConversation: currentConversation,
    );
    if (composerPrefillText == null) {
      return;
    }

    setState(() {
      _composerPrefillText = composerPrefillText;
      _composerPrefillVersion++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _threadScroll.scrollToBottom();
    });
  }

  Future<void> _cancelPlanReview(
    BuildContext context, {
    required Conversation currentConversation,
  }) async {
    final completed = await _planReviewActionCoordinator.cancelReview(
      currentConversation: currentConversation,
    );
    if (!completed) {
      return;
    }
    setState(() {
      _composerPrefillText = '';
      _composerPrefillVersion++;
    });
  }

  Future<void> _approveCurrentPlanAndStart(
    BuildContext context, {
    required Conversation currentConversation,
  }) async {
    final languageCode = context.locale.languageCode;
    final messenger = ScaffoldMessenger.of(context);
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    final outcome = await _planReviewActionCoordinator.approveCurrentPlan(
      currentConversation: currentConversation,
    );
    switch (outcome) {
      case PlanReviewApprovalMissingDocument() || PlanReviewApprovalAborted():
        return;
      case PlanReviewApprovalBlocked(:final errorMessage):
        if (!context.mounted) {
          return;
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'chat.plan_document_approval_blocked'.tr(
                namedArgs: {'error': errorMessage},
              ),
            ),
          ),
        );
        return;
      case PlanReviewApprovalReady(
        :final executionConversation,
        :final nextTask,
      ):
        setState(() {
          _composerPrefillText = '';
          _composerPrefillVersion++;
        });
        messenger.showSnackBar(
          SnackBar(content: Text('chat.plan_proposal_started'.tr())),
        );
        if (nextTask == null) {
          await chatNotifier.sendMessage(
            'chat.plan_proposal_execute_prompt'.tr(),
            languageCode: languageCode,
            bypassPlanMode: true,
          );
          return;
        }
        if (!context.mounted) {
          return;
        }
        await _runWorkflowTask(
          context,
          currentConversation: executionConversation,
          task: nextTask,
        );
    }
  }

  PlanReviewActionCoordinator get _planReviewActionCoordinator =>
      PlanReviewActionCoordinator(
        conversationsNotifier: ref.read(conversationsNotifierProvider.notifier),
        readCurrentConversation: () =>
            ref.read(conversationsNotifierProvider).currentConversation,
        dismissPlanProposal: () =>
            ref.read(chatNotifierProvider.notifier).dismissPlanProposal(),
        isPageMounted: () => mounted,
        now: DateTime.now,
      );

  Future<void> _setWorkflowTaskStatus({
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
    required ConversationWorkflowTaskStatus status,
    String summary = '',
    DateTime? lastRunAt,
    DateTime? lastValidationAt,
    ConversationExecutionValidationStatus? validationStatus,
    String? blockedReason,
    String? lastValidationCommand,
    String? lastValidationSummary,
    ConversationExecutionTaskEventType? eventType,
  }) async {
    await _workflowTaskActionCoordinator.setTaskStatus(
      currentConversation: currentConversation,
      task: task,
      status: status,
      summary: summary,
      lastRunAt: lastRunAt,
      lastValidationAt: lastValidationAt,
      validationStatus: validationStatus,
      blockedReason: blockedReason,
      lastValidationCommand: lastValidationCommand,
      lastValidationSummary: lastValidationSummary,
      eventType: eventType,
    );
  }

  WorkflowTaskActionCoordinator get _workflowTaskActionCoordinator =>
      WorkflowTaskActionCoordinator(
        conversationsNotifier: ref.read(conversationsNotifierProvider.notifier),
        readCurrentConversation: () =>
            ref.read(conversationsNotifierProvider).currentConversation,
        createTaskId: _uuid.v4,
        dismissTaskProposal: () =>
            ref.read(chatNotifierProvider.notifier).dismissTaskProposal(),
      );

  String? _activeProjectRootPath() {
    final conversationsState = ref.read(conversationsNotifierProvider);
    final activeProjectId = conversationsState.activeProjectId?.trim();
    if (activeProjectId == null || activeProjectId.isEmpty) {
      return null;
    }

    final projectsState = ref.read(codingProjectsNotifierProvider);
    final rootPath = projectsState.findById(activeProjectId)?.rootPath.trim();
    if (rootPath == null || rootPath.isEmpty) {
      return null;
    }
    return rootPath;
  }

  WorkflowTaskRunCoordinator _createWorkflowTaskRunCoordinator(
    BuildContext context,
  ) => WorkflowTaskRunCoordinator(
    chatNotifier: ref.read(chatNotifierProvider.notifier),
    conversationsNotifier: ref.read(conversationsNotifierProvider.notifier),
    readCurrentConversation: () =>
        ref.read(conversationsNotifierProvider).currentConversation,
    readActiveProjectRoot: _activeProjectRootPath,
    updateTaskStatus: (update) => _setWorkflowTaskStatus(
      currentConversation: update.currentConversation,
      task: update.task,
      status: update.status,
      summary: update.summary,
      lastRunAt: update.lastRunAt,
      lastValidationAt: update.lastValidationAt,
      validationStatus: update.validationStatus,
      blockedReason: update.blockedReason,
      lastValidationCommand: update.lastValidationCommand,
      lastValidationSummary: update.lastValidationSummary,
      eventType: update.eventType,
    ),
    isPageMounted: () => mounted,
    isContextMounted: () => context.mounted,
    now: DateTime.now,
  );

  Future<void> _runWorkflowTask(
    BuildContext context, {
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
  }) => _createWorkflowTaskRunCoordinator(context).runTask(
    currentConversation: currentConversation,
    task: task,
    languageCode: context.locale.languageCode,
    promptText: WorkflowTaskExecutionPromptText(
      intro: 'chat.workflow_task_use_prompt_intro'.tr(
        namedArgs: {'title': task.title},
      ),
      targetFilesLabel: 'chat.workflow_task_target_files'.tr(),
      validationLabel: 'chat.workflow_task_validation'.tr(),
      notesLabel: 'chat.workflow_task_notes'.tr(),
      outro: task.status == ConversationWorkflowTaskStatus.completed
          ? 'chat.workflow_task_review_prompt_outro'.tr()
          : 'chat.workflow_task_use_prompt_outro'.tr(),
    ),
  );
}
