import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/services/browser_session_service.dart';
import '../../../../core/services/macos_computer_use_service.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../../../core/types/workspace_mode.dart';
import '../../../dashboard/presentation/widgets/dashboard_view.dart';
import '../../../routines/domain/entities/routine.dart';
import '../../../routines/presentation/pages/routine_detail_view.dart';
import '../../../routines/presentation/pages/routines_home_page.dart';
import '../../../routines/presentation/providers/routine_scheduler.dart';
import '../../../routines/presentation/providers/routines_notifier.dart';
import '../../../routines/presentation/widgets/routine_editor_launcher.dart';
import '../../../remote_coding/presentation/remote_coding_page.dart';
import '../../../personal_eval/presentation/pages/personal_eval_record_page.dart';
import '../providers/coding_projects_notifier.dart';
import '../../../settings/presentation/providers/model_list_provider.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/file_rollback_checkpoint_store.dart';
import '../../data/datasources/llm_session_log_store.dart';
import '../../data/datasources/session_logging_chat_datasource.dart';
import '../../domain/entities/coding_project.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_goal.dart';
import '../../domain/entities/conversation_plan_artifact.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/turn_diff.dart';
import '../../domain/services/conversation_plan_diff_service.dart';
import '../../domain/services/conversation_plan_document_builder.dart';
import '../../domain/services/conversation_execution_recovery_service.dart';
import '../../domain/services/conversation_goal_auto_continue_policy.dart';
import '../../domain/services/conversation_plan_execution_coordinator.dart';
import '../../domain/services/conversation_plan_projection_service.dart';
import '../../domain/services/feedback_submission_service.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../coordinators/workflow_task_run_coordinator.dart';
import '../providers/chat_notifier.dart';
import '../providers/chat_state.dart';
import '../providers/coding_environment_snapshot_provider.dart';
import '../providers/conversations_notifier.dart';
import '../providers/coding_worktree_session_launcher.dart';
import '../providers/custom_slash_commands_notifier.dart';
import '../providers/feedback_submission_provider.dart';
import '../providers/worktree_agent_task_launcher.dart';
import '../providers/worktree_agent_task_orchestrator.dart';
import '../slash_commands/slash_command.dart';
import '../slash_commands/slash_command_prompt_template.dart';
import '../widgets/conversation_drawer.dart';
import '../widgets/approval/ble_connect_approval_sheet.dart';
import '../widgets/approval/computer_use_action_approval_sheet.dart';
import '../widgets/approval/file_operation_approval_sheet.dart';
import '../widgets/approval/git_command_approval_sheet.dart';
import '../widgets/approval/local_command_approval_sheet.dart';
import '../widgets/approval/participant_tool_approval_sheet.dart';
import '../widgets/approval/serial_open_approval_sheet.dart';
import '../widgets/approval/ssh_command_approval_sheet.dart';
import '../widgets/approval/ssh_connect_approval_sheet.dart';
import '../widgets/file_workspace_viewer_sheet.dart';
import '../widgets/subagent_task_banner.dart';
import '../widgets/worktree_agent_task_banner.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../widgets/participant_roster_bar.dart';
import '../widgets/tool_perimeter_summary.dart';
import '../widgets/workflow_status_presentation.dart';
import '../widgets/chat_image_drop_target.dart';
import '../widgets/plan/compact_plan_footer_card.dart';
import '../widgets/queued_messages_strip.dart';
import '../widgets/session_log_details_section.dart';
import '../widgets/token_usage_indicator.dart';
import '../widgets/plan/plan_document_approval_sheet.dart';
import '../widgets/plan/plan_document_editor_sheet.dart';
import '../widgets/plan/plan_hydrated_task_row.dart';
import '../widgets/plan/plan_markdown_preview.dart';
import '../widgets/plan/plan_open_question_section.dart';
import '../widgets/plan/plan_review_sheet.dart';
import '../widgets/plan/plan_revision_history_sheet.dart';

part 'chat_page_empty_state_builders.dart';
part 'chat_page_approval_listeners.dart';
part 'chat_page_browser_builders.dart';
part 'chat_page_companion_builders.dart';
part 'chat_page_goal_builders.dart';
part 'chat_page_header_builders.dart';
part 'chat_page_mobile_support.dart';
part 'chat_page_plan_builders.dart';
part 'chat_page_support.dart';
part 'chat_page_turn_rollback_support.dart';
part 'chat_page_workflow_builders.dart';
part 'chat_page_workflow_support.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, this.showDashboardOnStartup = true});

  final bool showDashboardOnStartup;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _scrollController = ScrollController();
  final _workflowPanelScrollController = ScrollController();
  final Set<String> _activeApprovalDialogIds = <String>{};
  final Set<String> _rolledBackTurnDiffIds = <String>{};
  final _uuid = const Uuid();
  String? _workflowPanelConversationId;
  bool _isApprovedPlanExpanded = false;
  bool _isPresentingPlanReviewSheet = false;
  String? _trackedPlanGenerationConversationId;
  String? _lastAutoPresentedPlanReviewDraftKey;
  bool _wasGeneratingPlanForTrackedConversation = false;
  bool _wasShowingPlanDraft = false;
  bool _isCompanionSidebarVisible = true;
  String _composerPrefillText = '';
  int _composerPrefillVersion = 0;
  bool _isScrollToBottomScheduled = false;
  bool _scheduledScrollShouldAnimate = false;
  bool _autoFollowBottom = true;
  late bool _showDashboard;
  FileWorkspaceViewerRequest? _fileWorkspaceViewerRequest;
  _RightSidebarTab _rightSidebarTab = _RightSidebarTab.companion;
  int _droppedImageAttachmentId = 0;
  String? _switchingCompanionBranchName;
  MessageInputImageAttachment? _droppedImageAttachment;
  static const double _companionSidebarBreakpoint = 1180;
  static const double _companionSidebarWidth = 344;
  static const double _persistentDrawerBreakpoint = 900;
  static const double _persistentDrawerWidth = 320;
  static const double _browserPanelBreakpoint = 1280;
  static const double _browserPanelWidth = 480;
  static const double _fileWorkspacePanelMinWidth = 420;
  static const double _fileWorkspacePanelMaxWidth = 720;
  static const double _compactBrowserPanelHeightFraction = 0.55;
  static const double _compactBrowserChatReserveHeight = 220;

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
    _scrollController.dispose();
    _workflowPanelScrollController.dispose();
    super.dispose();
  }

  void _openFileWorkspaceViewer(FileWorkspaceViewerRequest request) {
    if (!mounted) {
      _fileWorkspaceViewerRequest = request;
      _rightSidebarTab = _RightSidebarTab.files;
      _isCompanionSidebarVisible = true;
      return;
    }
    final availableWidth = MediaQuery.maybeOf(context)?.size.width;
    if (availableWidth != null &&
        availableWidth < _companionSidebarBreakpoint) {
      unawaited(
        showFileWorkspaceViewerPanel(context: context, request: request),
      );
      return;
    }
    setState(() {
      _fileWorkspaceViewerRequest = request;
      _rightSidebarTab = _RightSidebarTab.files;
      _isCompanionSidebarVisible = true;
    });
  }

  void _closeFileWorkspaceViewer() {
    if (!mounted) {
      _fileWorkspaceViewerRequest = null;
      _rightSidebarTab = _RightSidebarTab.companion;
      return;
    }
    setState(() {
      _fileWorkspaceViewerRequest = null;
      _rightSidebarTab = _RightSidebarTab.companion;
    });
  }

  void _toggleCompanionSidebar() {
    setState(() {
      _isCompanionSidebarVisible = !_isCompanionSidebarVisible;
    });
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

  bool _isNearScrollBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <= 80;
  }

  /// Tracks deliberate user scrolling so streaming auto-scroll backs off when
  /// the user scrolls up to read history and resumes once they return to the
  /// bottom. Programmatic `animateTo`/`jumpTo` never emit a
  /// [UserScrollNotification], so this reacts only to real gestures and is
  /// therefore immune to the scroll position lagging behind streamed content.
  bool _handleScrollNotification(ScrollNotification notification) {
    // Ignore notifications bubbling up from scrollables nested inside messages.
    if (notification.depth != 0) {
      return false;
    }
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward) {
        // Dragging toward older messages: stop following the live stream.
        _autoFollowBottom = false;
      }
    } else if (notification is ScrollEndNotification && !_autoFollowBottom) {
      // Re-engage following once the user settles back near the bottom.
      if (_isNearScrollBottom()) {
        _autoFollowBottom = true;
      }
    }
    return false;
  }

  void _scheduleScrollToBottom({required bool animated}) {
    _scheduledScrollShouldAnimate = _scheduledScrollShouldAnimate || animated;
    if (_isScrollToBottomScheduled) {
      return;
    }

    _isScrollToBottomScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shouldAnimate = _scheduledScrollShouldAnimate;
      _isScrollToBottomScheduled = false;
      _scheduledScrollShouldAnimate = false;
      if (!mounted) {
        return;
      }
      _scrollToBottom(animated: shouldAnimate);
    });
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) {
      return;
    }
    final target = _scrollController.position.maxScrollExtent;
    if (animated) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      return;
    }
    _scrollController.jumpTo(target);
  }

  Widget _buildRightSidebarPanel(
    BuildContext context, {
    required FileWorkspaceViewerRequest? request,
    required double availableWidth,
    required Conversation currentConversation,
    required ChatState chatState,
    required CodingProject? activeProject,
  }) {
    final theme = Theme.of(context);
    final hasFileWorkspaceViewer = request != null;
    final panelWidth = hasFileWorkspaceViewer && availableWidth.isFinite
        ? (availableWidth * 0.42)
              .clamp(_fileWorkspacePanelMinWidth, _fileWorkspacePanelMaxWidth)
              .toDouble()
        : _companionSidebarWidth;
    final companionPanel = _buildCompanionPanel(
      context,
      currentConversation: currentConversation,
      chatState: chatState,
      activeProject: activeProject,
      showLeadingBorder: false,
    );

    if (!hasFileWorkspaceViewer) {
      return SizedBox(width: panelWidth, child: companionPanel);
    }

    final selectedTab = _rightSidebarTab;

    return SizedBox(
      width: panelWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(color: theme.colorScheme.surface),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<_RightSidebarTab>(
                  key: const ValueKey('right-sidebar-tabs'),
                  showSelectedIcon: false,
                  selected: {selectedTab},
                  segments: const [
                    ButtonSegment(
                      value: _RightSidebarTab.companion,
                      icon: Icon(Icons.view_sidebar_outlined, size: 18),
                      label: Text('Companion'),
                    ),
                    ButtonSegment(
                      value: _RightSidebarTab.files,
                      icon: Icon(Icons.description_outlined, size: 18),
                      label: Text('Files'),
                    ),
                  ],
                  onSelectionChanged: (selection) {
                    setState(() {
                      _rightSidebarTab = selection.single;
                    });
                  },
                ),
              ),
            ),
            Divider(height: 1, thickness: 1, color: theme.dividerColor),
            Expanded(
              child: IndexedStack(
                index: selectedTab == _RightSidebarTab.companion ? 0 : 1,
                children: [
                  companionPanel,
                  request.buildViewer(onClose: _closeFileWorkspaceViewer),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wrapWithRightSidebar(
    BuildContext context,
    Widget chatContent, {
    required FileWorkspaceViewerRequest? request,
    required double availableWidth,
    required Conversation currentConversation,
    required ChatState chatState,
    required CodingProject? activeProject,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: chatContent),
        VerticalDivider(width: 1, thickness: 1, color: theme.dividerColor),
        _buildRightSidebarPanel(
          context,
          request: request,
          availableWidth: availableWidth,
          currentConversation: currentConversation,
          chatState: chatState,
          activeProject: activeProject,
        ),
      ],
    );
  }

  Future<void> _switchWorkspaceMode(WorkspaceMode workspaceMode) async {
    _leaveDashboard();
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final projectsState = ref.read(codingProjectsNotifierProvider);
    final settingsNotifier = ref.read(settingsNotifierProvider.notifier);
    final currentAssistantMode = ref
        .read(settingsNotifierProvider)
        .assistantMode;

    if (workspaceMode == WorkspaceMode.chat) {
      conversationsNotifier.activateWorkspace(
        workspaceMode: WorkspaceMode.chat,
        createIfMissing: true,
        createFreshOnFirstOpen: true,
      );
      await settingsNotifier.updateAssistantMode(AssistantMode.general);
      return;
    }

    if (workspaceMode == WorkspaceMode.routines) {
      conversationsNotifier.activateWorkspace(
        workspaceMode: WorkspaceMode.routines,
        createIfMissing: false,
      );
      // Always land on the routines home view when entering the workspace.
      ref.read(routinesNotifierProvider.notifier).selectRoutine(null);
      return;
    }

    final projectId =
        ref.read(conversationsNotifierProvider).activeProjectId ??
        projectsState.selectedProjectId;
    if (projectId != null) {
      await _activateCodingProject(projectId, createFreshOnFirstOpen: true);
      return;
    }

    conversationsNotifier.activateWorkspace(
      workspaceMode: WorkspaceMode.coding,
      projectId: null,
      createIfMissing: false,
    );
    await settingsNotifier.updateAssistantMode(
      currentAssistantMode == AssistantMode.general
          ? AssistantMode.coding
          : currentAssistantMode,
    );
  }

  Future<void> _activateCodingProject(
    String projectId, {
    bool createFreshOnFirstOpen = false,
  }) async {
    _leaveDashboard();
    ref.read(codingProjectsNotifierProvider.notifier).selectProject(projectId);
    ref
        .read(conversationsNotifierProvider.notifier)
        .activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: projectId,
          createIfMissing: createFreshOnFirstOpen,
          createFreshOnFirstOpen: createFreshOnFirstOpen,
          deferFreshConversationCreation: createFreshOnFirstOpen,
        );

    final currentAssistantMode = ref
        .read(settingsNotifierProvider)
        .assistantMode;
    await ref
        .read(settingsNotifierProvider.notifier)
        .updateAssistantMode(
          currentAssistantMode == AssistantMode.general
              ? AssistantMode.coding
              : currentAssistantMode,
        );
  }

  List<SlashCommandDefinition> _buildSlashCommands(
    BuildContext context,
    List<SlashCommandPromptTemplate> customPromptTemplates,
  ) {
    return [
      SlashCommandDefinition(
        name: 'help',
        action: SlashCommandAction.help,
        description: 'chat.slash_help_desc'.tr(),
        enabledWhileLoading: true,
      ),
      SlashCommandDefinition(
        name: 'new',
        action: SlashCommandAction.newConversation,
        description: 'chat.slash_new_desc'.tr(),
      ),
      SlashCommandDefinition(
        name: 'clear',
        action: SlashCommandAction.clear,
        description: 'chat.slash_clear_desc'.tr(),
      ),
      SlashCommandDefinition(
        name: 'general',
        action: SlashCommandAction.general,
        description: 'chat.slash_general_desc'.tr(),
      ),
      SlashCommandDefinition(
        name: 'coding',
        action: SlashCommandAction.coding,
        description: 'chat.slash_coding_desc'.tr(),
        aliases: const ['code'],
      ),
      SlashCommandDefinition(
        name: 'plan',
        action: SlashCommandAction.plan,
        description: 'chat.slash_plan_desc'.tr(),
      ),
      SlashCommandDefinition(
        name: 'goal',
        action: SlashCommandAction.goal,
        description: 'chat.slash_goal_desc'.tr(),
        argumentHint: '[objective] | pause | resume | clear | auto on|off',
        argumentRequirement: SlashCommandArgumentRequirement.optional,
      ),
      SlashCommandDefinition(
        name: 'cancel',
        action: SlashCommandAction.cancel,
        description: 'chat.slash_cancel_desc'.tr(),
        enabledWhileLoading: true,
      ),
      SlashCommandDefinition(
        name: 'feedback',
        action: SlashCommandAction.feedback,
        description: 'chat.slash_feedback_desc'.tr(),
        argumentHint: '<feedback>',
        argumentRequirement: SlashCommandArgumentRequirement.required,
      ),
      SlashCommandDefinition(
        name: 'agent',
        action: SlashCommandAction.worktreeAgent,
        description: 'chat.slash_agent_desc'.tr(),
        aliases: const ['worktree', 'worktree-agent'],
        argumentHint: '<task> [--run] [--verify <command>]',
        argumentRequirement: SlashCommandArgumentRequirement.required,
      ),
      for (final template in builtInSlashCommandPromptTemplates)
        template.toDefinition(
          descriptionOverride: 'chat.slash_${template.id}_desc'.tr(),
        ),
      for (final template in customPromptTemplates) template.toDefinition(),
    ];
  }

  Future<void> _selectAssistantModeFromComposer(
    AssistantMode mode, {
    required bool isCodingWorkspace,
    required Conversation? currentConversation,
  }) async {
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final settingsNotifier = ref.read(settingsNotifierProvider.notifier);
    if (mode == AssistantMode.plan) {
      if (!isCodingWorkspace || currentConversation == null) {
        return;
      }
      await conversationsNotifier.enterPlanningSession();
      return;
    }

    if (currentConversation?.isPlanningSession ?? false) {
      await conversationsNotifier.exitPlanningSession();
      ref.read(chatNotifierProvider.notifier).dismissPlanProposal();
    }
    await settingsNotifier.updateAssistantMode(mode);
  }

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

    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );

    switch (invocation.definition.action) {
      case SlashCommandAction.help:
        await _showSlashCommandHelp(
          context,
          _buildSlashCommands(context, customPromptTemplates),
        );
        return SlashCommandExecutionResult.handled;
      case SlashCommandAction.newConversation:
        if (isCodingWorkspace && activeProject != null) {
          _leaveDashboard();
          conversationsNotifier.startDraftConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: activeProject.id,
          );
        } else {
          _leaveDashboard();
          conversationsNotifier.createNewConversation(
            workspaceMode: conversationsState.activeWorkspaceMode,
            projectId: activeProject?.id,
          );
        }
        return SlashCommandExecutionResult(
          feedbackMessage: isCodingWorkspace
              ? 'chat.slash_new_thread_started'.tr()
              : 'chat.slash_new_conversation_started'.tr(),
        );
      case SlashCommandAction.clear:
        chatNotifier.clearMessages();
        await conversationsNotifier.updateCurrentConversation(
          const <Message>[],
        );
        return SlashCommandExecutionResult(
          feedbackMessage: 'chat.slash_cleared'.tr(),
        );
      case SlashCommandAction.general:
        await _selectAssistantModeFromComposer(
          AssistantMode.general,
          isCodingWorkspace: isCodingWorkspace,
          currentConversation: currentConversation,
        );
        return SlashCommandExecutionResult(
          feedbackMessage: 'chat.slash_mode_changed'.tr(
            namedArgs: {'mode': 'settings.assistant_general'.tr()},
          ),
        );
      case SlashCommandAction.coding:
        await _selectAssistantModeFromComposer(
          AssistantMode.coding,
          isCodingWorkspace: isCodingWorkspace,
          currentConversation: currentConversation,
        );
        return SlashCommandExecutionResult(
          feedbackMessage: 'chat.slash_mode_changed'.tr(
            namedArgs: {'mode': 'settings.assistant_coding'.tr()},
          ),
        );
      case SlashCommandAction.plan:
        if (!isCodingWorkspace || currentConversation == null) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: 'chat.slash_plan_unavailable'.tr(),
          );
        }
        await conversationsNotifier.enterPlanningSession();
        return SlashCommandExecutionResult(
          feedbackMessage: 'chat.slash_plan_started'.tr(),
        );
      case SlashCommandAction.goal:
        var goalConversation = currentConversation;
        final shouldStartGoalPrompt = goalConversation == null;
        if (goalConversation == null && isCodingWorkspace) {
          goalConversation = conversationsNotifier.ensureCurrentConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: activeProject?.id ?? conversationsState.activeProjectId,
          );
        }
        if (!isCodingWorkspace || goalConversation == null) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: 'chat.slash_goal_unavailable'.tr(),
          );
        }
        return _handleGoalSlashCommand(
          context,
          goalConversation,
          invocation.args,
          sendObjectiveAsInitialPrompt: shouldStartGoalPrompt,
        );
      case SlashCommandAction.cancel:
        if (!isLoading) {
          return SlashCommandExecutionResult(
            feedbackMessage: 'chat.slash_cancel_idle'.tr(),
          );
        }
        chatNotifier.cancelStreaming();
        return SlashCommandExecutionResult(
          feedbackMessage: 'chat.slash_cancelled'.tr(),
        );
      case SlashCommandAction.feedback:
        return _submitFeedbackCommand(currentConversation, invocation.args);
      case SlashCommandAction.worktreeAgent:
        if (!isCodingWorkspace || activeProject == null) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: 'chat.slash_agent_unavailable'.tr(),
          );
        }
        final agentArgs = _parseWorktreeAgentCommandArgs(invocation.args);
        if (agentArgs.prompt.isEmpty) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: 'chat.slash_agent_prompt_required'.tr(),
          );
        }
        if (agentArgs.hasVerificationMarker &&
            agentArgs.verificationCommand.isEmpty) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: 'chat.slash_agent_verify_required'.tr(),
          );
        }
        try {
          final result = await ref
              .read(worktreeAgentTaskLauncherProvider)
              .enqueue(
                WorktreeAgentTaskLaunchRequest(
                  title: _worktreeAgentTaskTitle(agentArgs.prompt),
                  prompt: agentArgs.prompt,
                  codingProjectId: activeProject.id,
                  projectRootPath: activeProject.normalizedRootPath,
                  verificationCommand: agentArgs.verificationCommand,
                ),
              );
          if (agentArgs.runAfterQueue) {
            unawaited(
              ref
                  .read(worktreeAgentTaskRunControllerProvider.notifier)
                  .startAndExecuteReady(
                    WorktreeAgentTaskRunRequest(
                      fallbackProjectRootPath: activeProject.normalizedRootPath,
                    ),
                  ),
            );
            return SlashCommandExecutionResult(
              feedbackMessage: 'chat.slash_agent_queued_and_started'.tr(
                namedArgs: {'branch': result.task.branchName},
              ),
            );
          }
          return SlashCommandExecutionResult(
            feedbackMessage: 'chat.slash_agent_queued'.tr(
              namedArgs: {'branch': result.task.branchName},
            ),
          );
        } catch (error) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: 'chat.slash_agent_failed'.tr(
              namedArgs: {'error': '$error'},
            ),
          );
        }
      case SlashCommandAction.review:
      case SlashCommandAction.fix:
      case SlashCommandAction.explain:
      case SlashCommandAction.test:
      case SlashCommandAction.promptTemplate:
        final template = _findPromptTemplateForInvocation(
          invocation,
          customPromptTemplates,
        );
        if (template == null) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: 'message.slash_command_failed'.tr(),
          );
        }
        return SlashCommandExecutionResult.sendPrompt(
          template.expand(
            args: invocation.args,
            commandName: invocation.commandName,
          ),
        );
    }
  }

  String _worktreeAgentTaskTitle(String prompt) {
    final firstLine = prompt
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => 'Worktree agent');
    const maxTitleLength = 80;
    if (firstLine.length <= maxTitleLength) {
      return firstLine;
    }
    return '${firstLine.substring(0, maxTitleLength - 3).trimRight()}...';
  }

  SlashCommandPromptTemplate? _findPromptTemplateForInvocation(
    SlashCommandInvocation invocation,
    List<SlashCommandPromptTemplate> customPromptTemplates,
  ) {
    final templateId =
        invocation.definition.promptTemplateId ??
        switch (invocation.definition.action) {
          SlashCommandAction.review => 'review',
          SlashCommandAction.fix => 'fix',
          SlashCommandAction.explain => 'explain',
          SlashCommandAction.test => 'test',
          _ => null,
        };
    if (templateId == null) {
      return null;
    }
    return findSlashCommandPromptTemplate(templateId, [
      ...builtInSlashCommandPromptTemplates,
      ...customPromptTemplates,
    ]);
  }

  Future<void> _showSlashCommandHelp(
    BuildContext context,
    List<SlashCommandDefinition> commands,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            shrinkWrap: true,
            itemCount: commands.length + 1,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'chat.slash_commands_title'.tr(),
                    style: theme.textTheme.titleLarge,
                  ),
                );
              }
              final command = commands[index - 1];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.terminal),
                title: Text(command.usage),
                subtitle: Text(command.description),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _pickAndActivateProject() async {
    final selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory == null || !mounted) return;

    final project = await ref
        .read(codingProjectsNotifierProvider.notifier)
        .addProject(selectedDirectory);
    if (project == null || !mounted) return;

    await _activateCodingProject(project.id, createFreshOnFirstOpen: true);
  }

  Future<void> _selectDrawerConversation(String conversationId) async {
    _leaveDashboard();
    final conversationsState = ref.read(conversationsNotifierProvider);
    final conversation = conversationsState.conversations
        .where((item) => item.id == conversationId)
        .firstOrNull;
    if (conversation == null) {
      return;
    }

    final normalizedProjectId = conversation.normalizedProjectId;
    if (conversation.workspaceMode == WorkspaceMode.coding &&
        normalizedProjectId != null) {
      ref
          .read(codingProjectsNotifierProvider.notifier)
          .selectProject(normalizedProjectId);
    }

    ref
        .read(conversationsNotifierProvider.notifier)
        .selectConversation(conversationId);

    final settingsNotifier = ref.read(settingsNotifierProvider.notifier);
    final currentAssistantMode = ref
        .read(settingsNotifierProvider)
        .assistantMode;
    switch (conversation.workspaceMode) {
      case WorkspaceMode.chat:
        await settingsNotifier.updateAssistantMode(AssistantMode.general);
        break;
      case WorkspaceMode.coding:
        await settingsNotifier.updateAssistantMode(
          currentAssistantMode == AssistantMode.general
              ? AssistantMode.coding
              : currentAssistantMode,
        );
        break;
      case WorkspaceMode.routines:
        break;
    }
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

  Widget _buildImageDropTarget(
    BuildContext context, {
    required bool enabled,
    required Widget child,
  }) {
    return ChatImageDropTarget(
      enabled: enabled,
      child: child,
      onImageDropped: (bytes, mimeType, filePath) {
        if (!mounted) return;
        final attachment = MessageInputImageAttachment(
          id: ++_droppedImageAttachmentId,
          bytes: bytes,
          mimeType: mimeType,
          filePath: filePath,
        );
        setState(() {
          _droppedImageAttachment = attachment;
        });
      },
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

  Future<void> _showWorkflowDecisionDialog(
    BuildContext context,
    PendingWorkflowDecision pending,
  ) async {
    final approvedAnswer =
        await showModalBottomSheet<WorkflowPlanningDecisionAnswer>(
          context: context,
          isDismissible: false,
          enableDrag: true,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (sheetContext) => _WorkflowDecisionSheet(pending: pending),
        );

    if (!mounted) return;

    ref
        .read(chatNotifierProvider.notifier)
        .resolveWorkflowDecision(id: pending.id, answer: approvedAnswer);
  }

  Future<void> _showAskUserQuestionDialog(
    BuildContext context,
    PendingAskUserQuestion pending,
  ) async {
    final answer = await showModalBottomSheet<AskUserQuestionAnswer>(
      context: context,
      isDismissible: false,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AskUserQuestionSheet(pending: pending),
    );

    if (!mounted) return;

    ref
        .read(chatNotifierProvider.notifier)
        .resolveAskUserQuestion(id: pending.id, answer: answer);
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatNotifierProvider);
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
    ref.listen(chatNotifierProvider, (previous, next) {
      final messageCountChanged =
          previous?.messages.length != next.messages.length;
      if (messageCountChanged) {
        // A message was added or removed: snap to the newest entry and resume
        // following the live stream.
        _autoFollowBottom = true;
        _scheduleScrollToBottom(animated: true);
        return;
      }
      // Same message count: only react to the last message growing while it
      // streams, and only while the user has not scrolled up to read history.
      if (next.messages.isEmpty || !next.messages.last.isStreaming) {
        return;
      }
      if (!_autoFollowBottom) {
        return;
      }
      _scheduleScrollToBottom(animated: false);
    });

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
    final effectiveAssistantMode = isPlanMode
        ? AssistantMode.plan
        : switch (settings.assistantMode) {
            AssistantMode.plan =>
              isCodingWorkspace ? AssistantMode.coding : AssistantMode.general,
            final mode => mode,
          };
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
    final shouldShowCodingDraftComposer =
        isCodingWorkspace &&
        activeProject != null &&
        currentConversation == null &&
        chatState.messages.isEmpty;
    final isWideForCompanion =
        MediaQuery.sizeOf(context).width >= _companionSidebarBreakpoint;
    _maybePresentPlanReviewSheet(
      context,
      currentConversation: currentConversation,
      chatState: chatState,
      isPlanMode: isPlanMode,
    );

    final usePersistentDrawer =
        !isMobileRemoteCoding &&
        MediaQuery.sizeOf(context).width >= _persistentDrawerBreakpoint;
    void handleComposerSend(
      String message,
      String? imageBase64,
      String? imageMimeType,
      String? originalImagePath,
      String? originalImageMimeType,
    ) {
      setState(() {
        _composerPrefillText = '';
        _composerPrefillVersion++;
      });
      _leaveDashboard();
      final languageCode = context.locale.languageCode;
      unawaited(
        chatNotifier.sendMessage(
          message,
          imageBase64: imageBase64,
          imageMimeType: imageMimeType,
          originalImagePath: originalImagePath,
          originalImageMimeType: originalImageMimeType,
          languageCode: languageCode,
        ),
      );
    }

    Widget buildMessageInput({bool floating = false}) {
      final input = MessageInput(
        onSend: handleComposerSend,
        onCancel: () => chatNotifier.cancelStreaming(),
        isLoading: chatState.isLoading,
        assistantMode: effectiveAssistantMode,
        onAssistantModeSelected: (mode) => _selectAssistantModeFromComposer(
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
          isLoading: chatState.isLoading,
          isCodingWorkspace: isCodingWorkspace,
          activeProject: activeProject,
          currentConversation: currentConversation,
          conversationsState: conversationsState,
          customPromptTemplates: customSlashCommandTemplates,
        ),
        isCodingWorkspace: isCodingWorkspace,
        showChatApprovalMode: showChatApprovalMode,
        inputHintKey: isCodingWorkspace
            ? (isPlanMode
                  ? 'message.input_hint_plan'
                  : 'message.input_hint_coding')
            : 'message.input_hint',
        composerPrefillText: _composerPrefillText,
        composerPrefillVersion: _composerPrefillVersion,
        droppedImageAttachment: _droppedImageAttachment,
        onWorktreeSessionSend: isCodingWorkspace && activeProject != null
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
      if (currentConversation == null ||
          currentConversation.workspaceMode != WorkspaceMode.chat) {
        return input;
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ParticipantRosterBar(
            participants: currentConversation.participants,
            config: currentConversation.participantTurnConfig,
            endpoints: settings.enabledNamedEndpoints,
            primaryModel: settings.effectiveModel,
            referencedParticipantIds: {
              for (final message in currentConversation.messages)
                if (message.participantId != null) message.participantId!,
            },
            enabled: !chatState.isLoading,
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
              MediaQuery.sizeOf(context).width >= _companionSidebarBreakpoint;
          if (!showRoutineCompanionSidebar) return detailView;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: detailView),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(context).dividerColor,
              ),
              SizedBox(
                width: _companionSidebarWidth,
                child: _buildRoutineCompanionPanel(
                  context,
                  routine: routine,
                  showLeadingBorder: false,
                ),
              ),
            ],
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
          : _buildImageDropTarget(
              context,
              enabled: canCompose,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showCompanionSidebar =
                      canShowCompanionPanel &&
                      currentConversation != null &&
                      _isCompanionSidebarVisible &&
                      MediaQuery.sizeOf(context).width >=
                          _companionSidebarBreakpoint;
                  final sidebarConversation = showCompanionSidebar
                      ? currentConversation
                      : null;
                  final chatContent = Column(
                    children: [
                      // Error banner
                      if (chatState.error != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  chatState.error!,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
                            : NotificationListener<ScrollNotification>(
                                onNotification: _handleScrollNotification,
                                child: ListView.builder(
                                  key: const ValueKey('chat-message-list'),
                                  controller: _scrollController,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  itemCount:
                                      chatState.messages.length +
                                      (shouldShowPlanStatusMessage ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index >= chatState.messages.length) {
                                      return MessageBubble(
                                        key: const ValueKey(
                                          'plan-status-message',
                                        ),
                                        message: _buildPlanStatusMessage(
                                          context,
                                          chatState: chatState,
                                        ),
                                        onOpenFileWorkspaceViewer:
                                            _openFileWorkspaceViewer,
                                        onReselectProject: isCodingWorkspace
                                            ? _pickAndActivateProject
                                            : null,
                                      );
                                    }
                                    final message = chatState.messages[index];
                                    final turnDiff = currentConversation
                                        ?.turnDiffForAssistantMessage(
                                          message.id,
                                        );
                                    final canRewind =
                                        !chatState.isLoading &&
                                        !message.isStreaming &&
                                        index < chatState.messages.length - 1;
                                    return MessageBubble(
                                      key: ValueKey(message.id),
                                      message: message,
                                      turnDiff: turnDiff,
                                      onOpenTurnDiff: turnDiff == null
                                          ? null
                                          : () => _openFileWorkspaceViewer(
                                              _buildTurnDiffViewerRequest(
                                                turnDiff,
                                              ),
                                            ),
                                      onOpenFileWorkspaceViewer:
                                          _openFileWorkspaceViewer,
                                      canRewind: canRewind,
                                      onRewindToHere: canRewind
                                          ? () => _rewindConversationToMessage(
                                              context,
                                              message,
                                            )
                                          : null,
                                      onReselectProject: isCodingWorkspace
                                          ? _pickAndActivateProject
                                          : null,
                                    );
                                  },
                                ),
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
                          shouldShowContextStatusWidget(chatState))
                        _buildTokenUsageBar(context, chatState, settings),
                      if (!shouldShowCodingDraftComposer &&
                          canCompose &&
                          chatState.queuedMessages.isNotEmpty)
                        QueuedMessagesStrip(
                          messages: chatState.queuedMessages,
                          onRemove: chatNotifier.removeQueuedMessage,
                        ),
                      if (canCompose && !shouldShowCodingDraftComposer)
                        buildMessageInput(),
                    ],
                  );
                  final coreBody = showCompanionSidebar
                      ? _wrapWithRightSidebar(
                          context,
                          chatContent,
                          request: _fileWorkspaceViewerRequest,
                          availableWidth: constraints.maxWidth,
                          currentConversation: sidebarConversation!,
                          chatState: chatState,
                          activeProject: activeProject,
                        )
                      : chatContent;
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

    Widget buildScaffoldBody() {
      final workspaceBody = buildWorkspaceBody();
      if (!usePersistentDrawer) {
        return workspaceBody;
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _persistentDrawerWidth,
            child: _buildConversationDrawer(
              closeOnAction: false,
              width: _persistentDrawerWidth,
            ),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Theme.of(context).dividerColor,
          ),
          Expanded(
            child: Column(
              children: [
                _buildPersistentWorkspaceHeader(
                  context,
                  isRoutinesWorkspace: isRoutinesWorkspace,
                  isCodingWorkspace: isCodingWorkspace,
                  isMobileRemoteCoding: isMobileRemoteCoding,
                  activeProject: activeProject,
                  currentTitle: currentTitle,
                  settings: settings,
                  canCompose: canCompose,
                  canShowCompanionPanel: canShowCompanionPanel,
                  isWideForCompanion: isWideForCompanion,
                  currentConversation: currentConversation,
                  selectedRoutine: selectedRoutine,
                  conversationsState: conversationsState,
                  conversationsNotifier: conversationsNotifier,
                  chatState: chatState,
                  routineTitle: selectedRoutine?.trimmedName,
                ),
                Expanded(child: workspaceBody),
              ],
            ),
          ),
        ],
      );
    }

    final scaffold = Scaffold(
      appBar: usePersistentDrawer
          ? null
          : AppBar(
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
                isWideForCompanion: isWideForCompanion,
                currentConversation: currentConversation,
                selectedRoutine: selectedRoutine,
                chatState: chatState,
                compact: false,
              ),
            ),
      drawer: usePersistentDrawer
          ? null
          : _buildConversationDrawer(
              closeOnAction: true,
              useRemoteCodingDrawer: isMobileRemoteCoding,
            ),
      // The persistent drawer exposes a create button in its routines list, but
      // the temporary drawer closes after switching workspaces and leaves the
      // read-only home dashboard without one. Surface a create FAB so mobile can
      // still add routines from the home view.
      floatingActionButton:
          isRoutinesWorkspace && !usePersistentDrawer && selectedRoutine == null
          ? FloatingActionButton(
              onPressed: () => _createRoutineFromHome(context),
              tooltip: 'routines.create_cta'.tr(),
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          const SubagentTaskBanner(),
          Expanded(child: buildScaffoldBody()),
        ],
      ),
    );
    return _wrapWithMobileKeyboardDismiss(scaffold);
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
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    if (!currentConversation.isPlanningSession) {
      await conversationsNotifier.enterPlanningSession();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _composerPrefillText = _buildPlanEditSeed(currentConversation);
      _composerPrefillVersion++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _scrollToBottom();
    });
  }

  Future<void> _cancelPlanReview(
    BuildContext context, {
    required Conversation currentConversation,
  }) async {
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final latestConversation =
        ref.read(conversationsNotifierProvider).currentConversation ??
        currentConversation;
    final planArtifact = latestConversation.effectivePlanArtifact;

    if (planArtifact.hasApproved && planArtifact.hasPendingEdits) {
      final approvedMarkdown = planArtifact.normalizedApprovedMarkdown ?? '';
      final updatedAt = DateTime.now();
      final nextArtifact = planArtifact
          .copyWith(draftMarkdown: approvedMarkdown, updatedAt: updatedAt)
          .recordRevision(
            markdown: approvedMarkdown,
            kind: ConversationPlanRevisionKind.restored,
            label: 'Cancelled draft changes and restored approved plan',
            createdAt: updatedAt,
          );
      await conversationsNotifier.updateCurrentPlanArtifact(
        planArtifact: nextArtifact,
      );
    } else if (!planArtifact.hasApproved) {
      await conversationsNotifier.updateCurrentPlanArtifact(
        clearPlanArtifact: true,
      );
    }

    await conversationsNotifier.exitPlanningSession();
    ref.read(chatNotifierProvider.notifier).dismissPlanProposal();
    if (!mounted) {
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
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    final latestConversation =
        ref.read(conversationsNotifierProvider).currentConversation ??
        currentConversation;
    final currentArtifact = latestConversation.effectivePlanArtifact;
    final draftMarkdown =
        currentArtifact.normalizedDraftMarkdown ??
        currentArtifact.normalizedApprovedMarkdown;
    if (draftMarkdown == null) {
      return;
    }

    final validation = ConversationPlanProjectionService.validateDocument(
      markdown: draftMarkdown,
      requireTasks: true,
    );
    if (!validation.isValid || validation.projection == null) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'chat.plan_document_approval_blocked'.tr(
              namedArgs: {
                'error':
                    validation.errorMessage ??
                    'plan document could not be parsed',
              },
            ),
          ),
        ),
      );
      return;
    }

    final approvedWorkflowStage = switch (validation.workflowStage) {
      ConversationWorkflowStage.tasks ||
      ConversationWorkflowStage.implement ||
      ConversationWorkflowStage.review => validation.workflowStage!,
      _ =>
        validation.previewTasks.isEmpty
            ? ConversationWorkflowStage.tasks
            : ConversationWorkflowStage.implement,
    };
    final approvedMarkdown =
        ConversationPlanProjectionService.replaceWorkflowStage(
          markdown: draftMarkdown,
          workflowStage: approvedWorkflowStage,
        );
    final updatedAt = DateTime.now();
    final nextArtifact = currentArtifact
        .copyWith(
          draftMarkdown: approvedMarkdown,
          approvedMarkdown: approvedMarkdown,
          updatedAt: updatedAt,
        )
        .recordRevision(
          markdown: approvedMarkdown,
          kind: ConversationPlanRevisionKind.approved,
          label: 'Approved plan from timeline review',
          createdAt: updatedAt,
        );

    await conversationsNotifier.updateCurrentPlanArtifact(
      planArtifact: nextArtifact,
      clearPlanArtifact: !nextArtifact.hasContent,
    );
    final refreshed = await conversationsNotifier
        .refreshCurrentWorkflowProjectionFromApprovedPlan();
    if (!mounted) {
      return;
    }
    if (!refreshed && validation.workflowSpec != null) {
      await conversationsNotifier.updateCurrentWorkflow(
        workflowStage: approvedWorkflowStage,
        workflowSpec: validation.workflowSpec!,
      );
    }

    await conversationsNotifier.exitPlanningSession();
    chatNotifier.dismissPlanProposal();

    if (!mounted) {
      return;
    }

    setState(() {
      _isApprovedPlanExpanded = false;
      _composerPrefillText = '';
      _composerPrefillVersion++;
    });

    messenger.showSnackBar(
      SnackBar(content: Text('chat.plan_proposal_started'.tr())),
    );
    final executionConversation =
        ref.read(conversationsNotifierProvider).currentConversation ??
        latestConversation;
    var nextTask = ConversationPlanExecutionCoordinator.nextTask(
      executionConversation,
    );
    if (nextTask == null && validation.workflowSpec != null) {
      await conversationsNotifier.updateCurrentWorkflow(
        workflowStage: approvedWorkflowStage,
        workflowSpec: validation.workflowSpec!,
      );
      if (!mounted) {
        return;
      }
      final refreshedExecutionConversation =
          ref.read(conversationsNotifierProvider).currentConversation ??
          executionConversation;
      nextTask = ConversationPlanExecutionCoordinator.nextTask(
        refreshedExecutionConversation,
      );
    }
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

  Future<void> _showWorkflowEditor(
    BuildContext context,
    Conversation currentConversation, {
    ConversationWorkflowStage? initialWorkflowStage,
    ConversationWorkflowSpec? initialWorkflowSpec,
    bool dismissWorkflowProposalOnSave = false,
  }) async {
    if (currentConversation.shouldPreferPlanDocument) {
      if (currentConversation.hasPlanArtifact) {
        await _showPlanDocumentEditor(
          context,
          currentConversation,
          preferDraft: currentConversation.isPlanningSession,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('chat.workflow_edit_blocked_by_plan'.tr())),
        );
      }
      return;
    }

    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final result = await showModalBottomSheet<_WorkflowEditorSubmission>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _WorkflowEditorSheet(
        currentConversation: currentConversation,
        initialWorkflowStage: initialWorkflowStage,
        initialWorkflowSpec: initialWorkflowSpec,
        workflowStageLabelBuilder: _workflowStageLabel,
      ),
    );
    if (result == null) {
      return;
    }

    switch (result.action) {
      case _WorkflowEditorAction.clear:
        await conversationsNotifier.updateCurrentWorkflow(
          workflowStage: ConversationWorkflowStage.idle,
          clearWorkflowSpec: true,
        );
        await conversationsNotifier.updateCurrentPlanArtifact(
          clearPlanArtifact: true,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('chat.workflow_cleared'.tr())));
        }
      case _WorkflowEditorAction.save:
        await conversationsNotifier.updateCurrentWorkflow(
          workflowStage: result.workflowStage,
          workflowSpec: result.workflowSpec.hasContent
              ? result.workflowSpec
              : null,
          clearWorkflowSpec: !result.workflowSpec.hasContent,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('chat.workflow_saved'.tr())));
        }
    }

    if (dismissWorkflowProposalOnSave) {
      ref.read(chatNotifierProvider.notifier).dismissWorkflowProposal();
    }
  }

  Future<void> _applyWorkflowProposal(
    BuildContext context, {
    required Conversation currentConversation,
    required WorkflowProposalDraft proposal,
  }) async {
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    final nextSpec = proposal.workflowSpec.copyWith(
      tasks: currentConversation.effectiveWorkflowSpec.tasks,
    );

    await conversationsNotifier.updateCurrentWorkflow(
      workflowStage: proposal.workflowStage,
      workflowSpec: nextSpec.hasContent ? nextSpec : null,
      clearWorkflowSpec: !nextSpec.hasContent,
    );
    chatNotifier.dismissWorkflowProposal();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('chat.workflow_saved'.tr())));
    }
  }

  Future<void> _applyTaskProposal(
    BuildContext context, {
    required Conversation currentConversation,
    required WorkflowTaskProposalDraft proposal,
  }) async {
    await _replaceWorkflowTasks(
      currentConversation: currentConversation,
      tasks: proposal.tasks,
      workflowStage: ConversationWorkflowStage.tasks,
    );
    ref.read(chatNotifierProvider.notifier).dismissTaskProposal();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('chat.workflow_task_saved'.tr())));
    }
  }

  Future<void> _runWorkflowQuickAction(
    BuildContext context, {
    required _WorkflowQuickAction action,
  }) async {
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final chatNotifier = ref.read(chatNotifierProvider.notifier);

    await conversationsNotifier.updateCurrentWorkflow(
      workflowStage: action.targetStage,
    );
    if (!context.mounted) {
      return;
    }

    await chatNotifier.sendMessage(
      action.promptKey.tr(),
      languageCode: context.locale.languageCode,
      bypassPlanMode: true,
    );
  }

  Future<void> _handleWorkflowTaskMenuAction(
    BuildContext context, {
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
    required _WorkflowTaskMenuAction action,
  }) async {
    switch (action) {
      case _WorkflowTaskMenuAction.markPending:
        await _setWorkflowTaskStatus(
          currentConversation: currentConversation,
          task: task,
          status: ConversationWorkflowTaskStatus.pending,
          summary: 'Moved back to pending from the task menu.',
        );
      case _WorkflowTaskMenuAction.markInProgress:
        await _setWorkflowTaskStatus(
          currentConversation: currentConversation,
          task: task,
          status: ConversationWorkflowTaskStatus.inProgress,
          summary: 'Marked in progress from the task menu.',
        );
      case _WorkflowTaskMenuAction.markCompleted:
        await _setWorkflowTaskStatus(
          currentConversation: currentConversation,
          task: task,
          status: ConversationWorkflowTaskStatus.completed,
          summary: 'Marked complete from the task menu.',
          eventType: ConversationExecutionTaskEventType.completed,
        );
      case _WorkflowTaskMenuAction.markBlocked:
        await _setWorkflowTaskStatus(
          currentConversation: currentConversation,
          task: task,
          status: ConversationWorkflowTaskStatus.blocked,
          summary: 'Marked blocked from the task menu.',
          blockedReason: 'This task is blocked and needs follow-up.',
          eventType: ConversationExecutionTaskEventType.blocked,
        );
      case _WorkflowTaskMenuAction.markUnblocked:
        await _markWorkflowTaskUnblocked(
          context,
          currentConversation: currentConversation,
          task: task,
        );
      case _WorkflowTaskMenuAction.editBlockedReason:
        await _editWorkflowTaskBlockedReason(
          context,
          currentConversation: currentConversation,
          task: task,
        );
      case _WorkflowTaskMenuAction.replanFromBlocker:
        await _replanFromBlockedTask(
          context,
          currentConversation: currentConversation,
          task: task,
        );
      case _WorkflowTaskMenuAction.edit:
        if (currentConversation.shouldPreferPlanDocument) {
          return;
        }
        await _showWorkflowTaskEditor(
          context,
          currentConversation: currentConversation,
          task: task,
        );
      case _WorkflowTaskMenuAction.delete:
        if (currentConversation.shouldPreferPlanDocument) {
          return;
        }
        await _replaceWorkflowTasks(
          currentConversation: currentConversation,
          tasks: currentConversation.effectiveWorkflowSpec.tasks
              .where((item) => item.id != task.id)
              .toList(growable: false),
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('chat.workflow_task_deleted'.tr())),
          );
        }
    }
  }

  Future<void> _showWorkflowTaskEditor(
    BuildContext context, {
    required Conversation currentConversation,
    ConversationWorkflowTask? task,
  }) async {
    if (currentConversation.shouldPreferPlanDocument) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('chat.workflow_task_edit_blocked_by_plan'.tr()),
          ),
        );
      }
      return;
    }

    final result = await showModalBottomSheet<_WorkflowTaskEditorSubmission>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _WorkflowTaskEditorSheet(
        task: task,
        statusLabelBuilder: _workflowTaskStatusLabel,
      ),
    );
    if (result == null) {
      return;
    }

    switch (result.action) {
      case _WorkflowTaskEditorAction.delete:
        if (task == null) {
          return;
        }
        await _replaceWorkflowTasks(
          currentConversation: currentConversation,
          tasks: currentConversation.effectiveWorkflowSpec.tasks
              .where((item) => item.id != task.id)
              .toList(growable: false),
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('chat.workflow_task_deleted'.tr())),
          );
        }
      case _WorkflowTaskEditorAction.save:
        final existingTasks = currentConversation.effectiveWorkflowSpec.tasks;
        final nextTask = result.task.id.isEmpty
            ? result.task.copyWith(id: _uuid.v4())
            : result.task;
        final taskIndex = existingTasks.indexWhere(
          (item) => item.id == nextTask.id,
        );
        final nextTasks = [...existingTasks];
        if (taskIndex >= 0) {
          nextTasks[taskIndex] = nextTask;
        } else {
          nextTasks.add(nextTask);
        }
        await _replaceWorkflowTasks(
          currentConversation: currentConversation,
          tasks: nextTasks,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('chat.workflow_task_saved'.tr())),
          );
        }
    }
  }

  Future<void> _replaceWorkflowTasks({
    required Conversation currentConversation,
    required List<ConversationWorkflowTask> tasks,
    ConversationWorkflowStage? workflowStage,
  }) async {
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final latestConversation =
        ref.read(conversationsNotifierProvider).currentConversation ??
        currentConversation;
    final nextSpec = latestConversation.effectiveWorkflowSpec.copyWith(
      tasks: tasks,
    );

    await conversationsNotifier.updateCurrentWorkflow(
      workflowStage: workflowStage,
      workflowSpec: nextSpec.hasContent ? nextSpec : null,
      clearWorkflowSpec: !nextSpec.hasContent,
    );
  }

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
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );

    if (currentConversation.shouldPreferPlanDocument) {
      await conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: task.id,
        status: status,
        allowStatusRegression: true,
        lastRunAt: lastRunAt,
        lastValidationAt: lastValidationAt,
        validationStatus: validationStatus,
        summary: summary,
        blockedReason: status == ConversationWorkflowTaskStatus.blocked
            ? blockedReason
            : '',
        lastValidationCommand: lastValidationCommand,
        lastValidationSummary: lastValidationSummary,
        eventType: eventType,
        eventSummary: summary,
      );
      if (status == ConversationWorkflowTaskStatus.completed) {
        await conversationsNotifier.updateCurrentWorkflow(
          workflowStage: ConversationWorkflowStage.review,
          preserveWorkflowProjection: true,
        );
      } else if (status == ConversationWorkflowTaskStatus.inProgress ||
          status == ConversationWorkflowTaskStatus.blocked) {
        await conversationsNotifier.updateCurrentWorkflow(
          workflowStage: ConversationWorkflowStage.implement,
          preserveWorkflowProjection: true,
        );
      }
      return;
    }

    final tasks = currentConversation.effectiveWorkflowSpec.tasks
        .map(
          (item) => item.id == task.id ? item.copyWith(status: status) : item,
        )
        .toList(growable: false);
    await _replaceWorkflowTasks(
      currentConversation: currentConversation,
      tasks: tasks,
      workflowStage: status == ConversationWorkflowTaskStatus.completed
          ? ConversationWorkflowStage.review
          : ConversationWorkflowStage.implement,
    );
  }

  Future<void> _markWorkflowTaskUnblocked(
    BuildContext context, {
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
  }) async {
    await _setWorkflowTaskStatus(
      currentConversation: currentConversation,
      task: task,
      status: ConversationWorkflowTaskStatus.pending,
      summary: 'Cleared the blocker and moved the task back to pending.',
      blockedReason: '',
      eventType: ConversationExecutionTaskEventType.unblocked,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('chat.workflow_task_unblocked'.tr())),
    );
  }

  Future<void> _editWorkflowTaskBlockedReason(
    BuildContext context, {
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
  }) async {
    if (!currentConversation.shouldPreferPlanDocument) {
      return;
    }

    final existingReason =
        currentConversation
            .executionProgressForTask(task.id)
            ?.normalizedBlockedReason ??
        'This task is blocked and needs follow-up.';
    final result = await _showBlockedReasonEditor(
      context,
      initialReason: existingReason,
    );
    if (result == null) {
      return;
    }

    final nextReason = result.trim();
    if (nextReason.isEmpty) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('chat.workflow_task_blocked_reason_required'.tr()),
        ),
      );
      return;
    }

    await _setWorkflowTaskStatus(
      currentConversation: currentConversation,
      task: task,
      status: ConversationWorkflowTaskStatus.blocked,
      summary: 'Updated the blocker details from the approved plan flow.',
      blockedReason: nextReason,
      eventType: ConversationExecutionTaskEventType.blocked,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('chat.workflow_task_blocked_reason_saved'.tr())),
    );
  }

  Future<String?> _showBlockedReasonEditor(
    BuildContext context, {
    required String initialReason,
  }) async {
    final controller = TextEditingController(text: initialReason);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('chat.workflow_task_blocked_reason_editor_title'.tr()),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: 'chat.workflow_task_blocked_reason_editor_hint'.tr(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text('common.save'.tr()),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _replanFromBlockedTask(
    BuildContext context, {
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
  }) async {
    if (!currentConversation.shouldPreferPlanDocument) {
      return;
    }

    final latestConversation =
        ref.read(conversationsNotifierProvider).currentConversation ??
        currentConversation;
    final blockedReason =
        latestConversation
            .executionProgressForTask(task.id)
            ?.normalizedBlockedReason ??
        'This task is currently blocked.';
    await _startScopedReplan(
      context,
      currentConversation: latestConversation,
      task: task,
      snackBarMessage: 'chat.workflow_task_replan_from_blocker_started'.tr(),
      eventSummary:
          'Started a blocker-focused replan from the approved plan flow.',
      planningContext:
          ConversationPlanExecutionCoordinator.buildBlockedTaskReplanContext(
            conversation: latestConversation,
            task: task,
            blockedReason: blockedReason,
          ),
    );
  }

  Future<void> _replanCurrentTask(
    BuildContext context, {
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
  }) async {
    if (!currentConversation.shouldPreferPlanDocument) {
      return;
    }

    await _startScopedReplan(
      context,
      currentConversation: currentConversation,
      task: task,
      snackBarMessage: 'chat.plan_document_replan_current_task_started'.tr(),
      eventSummary:
          'Started a current-task-focused replan from the approved plan flow.',
      planningContext:
          ConversationPlanExecutionCoordinator.buildScopedTaskReplanContext(
            conversation: currentConversation,
            task: task,
          ),
    );
  }

  Future<void> _replanValidationPath(
    BuildContext context, {
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
  }) async {
    if (!currentConversation.shouldPreferPlanDocument) {
      return;
    }

    await _startScopedReplan(
      context,
      currentConversation: currentConversation,
      task: task,
      snackBarMessage: 'chat.plan_document_replan_validation_started'.tr(),
      eventSummary:
          'Started a validation-path-focused replan from the approved plan flow.',
      planningContext:
          ConversationPlanExecutionCoordinator.buildValidationScopedReplanContext(
            conversation: currentConversation,
            task: task,
          ),
    );
  }

  Future<void> _startScopedReplan(
    BuildContext context, {
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
    required String snackBarMessage,
    required String eventSummary,
    required String planningContext,
  }) async {
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    final languageCode = context.locale.languageCode;

    if (!currentConversation.isPlanningSession) {
      await conversationsNotifier.enterPlanningSession();
    }

    await conversationsNotifier.appendCurrentExecutionTaskEvent(
      taskId: task.id,
      eventType: ConversationExecutionTaskEventType.replanned,
      summary: eventSummary,
    );

    await chatNotifier.generatePlanProposalWithContext(
      languageCode: languageCode,
      additionalPlanningContext: planningContext,
    );

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(snackBarMessage)));
  }

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

  Future<void> _runWorkflowTaskValidation(
    BuildContext context, {
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
  }) => _createWorkflowTaskRunCoordinator(context).runValidation(
    currentConversation: currentConversation,
    task: task,
    languageCode: context.locale.languageCode,
    promptText: WorkflowTaskValidationPromptText(
      intro: 'chat.workflow_task_validation_prompt_intro'.tr(
        namedArgs: {'title': task.title},
      ),
      targetFilesLabel: 'chat.workflow_task_target_files'.tr(),
      validationLabel: 'chat.workflow_task_validation'.tr(),
      outro: 'chat.workflow_task_validation_prompt_outro'.tr(),
    ),
  );

  String _workflowProjectionStatusLabelKey(Conversation currentConversation) =>
      WorkflowStatusPresentation.workflowProjectionStatusLabelKey(
        currentConversation,
      );

  String _planDocumentEditLabelKey(
    Conversation currentConversation, {
    required bool isPlanMode,
  }) => WorkflowStatusPresentation.planDocumentEditLabelKey(
    currentConversation,
    isPlanMode: isPlanMode,
  );

  String _planDocumentHeaderEditTooltipKey(
    Conversation currentConversation, {
    required bool isPlanMode,
  }) => WorkflowStatusPresentation.planDocumentHeaderEditTooltipKey(
    currentConversation,
    isPlanMode: isPlanMode,
  );

  Color _workflowProjectionStatusColor(
    BuildContext context,
    Conversation currentConversation,
  ) => WorkflowStatusPresentation.workflowProjectionStatusColor(
    context,
    currentConversation,
  );

  String _workflowStageLabel(ConversationWorkflowStage stage) =>
      WorkflowStatusPresentation.workflowStageLabel(stage);

  String _workflowTaskStatusLabel(ConversationWorkflowTaskStatus status) =>
      WorkflowStatusPresentation.workflowTaskStatusLabel(status);

  String _workflowValidationStatusLabel(
    ConversationExecutionValidationStatus status,
  ) => WorkflowStatusPresentation.workflowValidationStatusLabel(status);

  String _workflowTaskEventSummary(
    BuildContext context,
    ConversationExecutionTaskEvent event,
  ) => WorkflowStatusPresentation.workflowTaskEventSummary(context, event);

  String _planDocumentDiffEntryLabel(
    BuildContext context,
    ConversationPlanTaskDiffEntry entry,
  ) => WorkflowStatusPresentation.planDocumentDiffEntryLabel(context, entry);

  Color _workflowTaskStatusColor(
    BuildContext context,
    ConversationWorkflowTaskStatus status,
  ) => WorkflowStatusPresentation.workflowTaskStatusColor(context, status);

  ConversationWorkflowStage? _recommendedWorkflowStage(
    ConversationWorkflowStage stage,
  ) => WorkflowStatusPresentation.recommendedWorkflowStage(stage);

  Future<void> _showSshConnectDialog(
    BuildContext context,
    PendingSshConnect pending,
  ) async {
    final approval = await SshConnectApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveSshConnect(id: pending.id, approval: approval);
  }

  Future<void> _showSshCommandDialog(
    BuildContext context,
    PendingSshCommand pending,
  ) async {
    final approved = await SshCommandApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveSshCommand(id: pending.id, approved: approved ?? false);
  }

  Future<void> _showGitCommandDialog(
    BuildContext context,
    PendingGitCommand pending,
  ) async {
    final approved = await GitCommandApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveGitCommand(id: pending.id, approved: approved ?? false);
  }

  Future<void> _showLocalCommandDialog(
    BuildContext context,
    PendingLocalCommand pending,
  ) async {
    final approval = await LocalCommandApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveLocalCommand(
          id: pending.id,
          approval: approval ?? const LocalCommandApproval(approved: false),
        );
  }

  Future<void> _showComputerUseActionDialog(
    BuildContext context,
    PendingComputerUseAction pending,
  ) async {
    final decision = await ComputerUseActionApprovalSheet.show(
      context,
      pending,
      stopHelperWork: () =>
          ref.read(macosComputerUseServiceProvider).stopHelperWork(),
    );

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveComputerUseAction(
          id: pending.id,
          approved: decision?.approved ?? false,
          armed: decision?.armed ?? !pending.requiresSmokeArming,
        );
  }

  Future<void> _showFileOperationDialog(
    BuildContext context,
    PendingFileOperation pending,
  ) async {
    final approved = await FileOperationApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveFileOperation(id: pending.id, approved: approved ?? false);
  }

  Future<void> _showParticipantToolApprovalDialog(
    BuildContext context,
    PendingParticipantToolApproval pending,
  ) async {
    final approved = await ParticipantToolApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveParticipantToolApproval(
          id: pending.id,
          approved: approved ?? false,
        );
  }

  Future<void> _showBleConnectDialog(
    BuildContext context,
    PendingBleConnect pending,
  ) async {
    final approved = await BleConnectApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveBleConnect(id: pending.id, approved: approved ?? false);
  }

  Future<void> _showSerialOpenDialog(
    BuildContext context,
    PendingSerialOpen pending,
  ) async {
    final approved = await SerialOpenApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveSerialOpen(id: pending.id, approved: approved ?? false);
  }
}
