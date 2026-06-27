import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/services/browser_session_service.dart';
import '../../../../core/services/macos_computer_use_service.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../../../core/types/workspace_mode.dart';
import '../../../dashboard/presentation/widgets/dashboard_view.dart';
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
import '../../data/datasources/chat_remote_datasource.dart';
import '../../data/datasources/file_rollback_checkpoint_store.dart';
import '../../data/datasources/git_tools.dart';
import '../../data/datasources/llm_session_log_store.dart';
import '../../domain/entities/coding_project.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_goal.dart';
import '../../domain/entities/conversation_plan_artifact.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/turn_diff.dart';
import '../../domain/services/coding_command_output_guardrail_service.dart';
import '../../domain/services/conversation_plan_diff_service.dart';
import '../../domain/services/conversation_plan_document_builder.dart';
import '../../domain/services/conversation_execution_progress_inference.dart';
import '../../domain/services/conversation_execution_recovery_service.dart';
import '../../domain/services/conversation_goal_suggestion_service.dart';
import '../../domain/services/conversation_plan_execution_coordinator.dart';
import '../../domain/services/conversation_plan_execution_guardrails.dart';
import '../../domain/services/conversation_plan_projection_service.dart';
import '../../domain/services/conversation_validation_tool_result_inference.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../providers/chat_notifier.dart';
import '../providers/chat_state.dart';
import '../providers/coding_environment_snapshot_provider.dart';
import '../providers/conversations_notifier.dart';
import '../providers/custom_slash_commands_notifier.dart';
import '../providers/session_log_details_provider.dart';
import '../providers/worktree_agent_task_launcher.dart';
import '../providers/worktree_agent_task_orchestrator.dart';
import '../slash_commands/slash_command.dart';
import '../slash_commands/slash_command_prompt_template.dart';
import '../widgets/conversation_drawer.dart';
import '../widgets/file_workspace_viewer_sheet.dart';
import '../widgets/subagent_task_banner.dart';
import '../widgets/worktree_agent_task_banner.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../widgets/participant_roster_bar.dart';
import '../widgets/tool_perimeter_summary.dart';
import '../widgets/plan/compact_plan_footer_card.dart';
import '../widgets/queued_messages_strip.dart';
import '../widgets/token_usage_indicator.dart';
import '../widgets/plan/plan_document_approval_sheet.dart';
import '../widgets/plan/plan_document_editor_sheet.dart';
import '../widgets/plan/plan_hydrated_task_row.dart';
import '../widgets/plan/plan_markdown_preview.dart';
import '../widgets/plan/plan_open_question_section.dart';
import '../widgets/plan/plan_review_sheet.dart';
import '../widgets/plan/plan_revision_history_sheet.dart';

part 'chat_page_empty_state_builders.dart';
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
  bool _isImageDragActive = false;
  bool _isScrollToBottomScheduled = false;
  bool _scheduledScrollShouldAnimate = false;
  bool _autoFollowBottom = true;
  late bool _showDashboard;
  FileWorkspaceViewerRequest? _fileWorkspaceViewerRequest;
  _RightSidebarTab _rightSidebarTab = _RightSidebarTab.companion;
  int _droppedImageAttachmentId = 0;
  String? _switchingCompanionBranchName;
  MessageInputImageAttachment? _droppedImageAttachment;
  String? _pendingCodingGoalConversationId;
  String? _codingGoalSuggestionConversationId;

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

  /// The built-in browser webview is built once and reused so toggling the
  /// pane (or moving between wide and compact layouts) preserves the live page.
  final GlobalKey _browserWebViewKey = GlobalKey();
  Widget? _browserWebView;

  static const Set<String> _imageDropExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.gif',
    '.heic',
    '.heif',
    '.tif',
    '.tiff',
    '.bmp',
  };

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

  void _setPendingCodingGoalConversationId(String? conversationId) {
    if (!mounted) {
      _pendingCodingGoalConversationId = conversationId;
      return;
    }
    setState(() {
      _pendingCodingGoalConversationId = conversationId;
    });
  }

  void _setCodingGoalSuggestionConversationId(String? conversationId) {
    if (!mounted) {
      _codingGoalSuggestionConversationId = conversationId;
      return;
    }
    setState(() {
      _codingGoalSuggestionConversationId = conversationId;
    });
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

  void _showApprovalDialogOnce(String id, Future<void> Function() showDialog) {
    if (!_activeApprovalDialogIds.add(id)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _activeApprovalDialogIds.remove(id);
        return;
      }

      try {
        await showDialog();
      } finally {
        _activeApprovalDialogIds.remove(id);
      }
    });
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
        name: 'cancel',
        action: SlashCommandAction.cancel,
        description: 'chat.slash_cancel_desc'.tr(),
        enabledWhileLoading: true,
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
    final theme = Theme.of(context);
    return DropTarget(
      enable: enabled,
      onDragEntered: (_) {
        if (!_isImageDragActive) {
          setState(() => _isImageDragActive = true);
        }
      },
      onDragExited: (_) {
        if (_isImageDragActive) {
          setState(() => _isImageDragActive = false);
        }
      },
      onDragDone: (details) {
        unawaited(_handleImageDrop(context, details.files));
      },
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: enabled && _isImageDragActive ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                child: Container(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(
                          alpha: 0.86,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'message.drop_image_overlay'.tr(),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleImageDrop(
    BuildContext context,
    List<DropItem> items,
  ) async {
    if (_isImageDragActive && mounted) {
      setState(() => _isImageDragActive = false);
    }

    final imageItem = _firstImageDropItem(items);
    if (imageItem == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('message.drop_image_unsupported'.tr())),
      );
      return;
    }

    try {
      final bytes = await _readDropItemBytes(imageItem);
      final attachment = MessageInputImageAttachment(
        id: ++_droppedImageAttachmentId,
        bytes: bytes,
        mimeType: _mimeTypeForDropItem(imageItem),
        filePath: _dropItemPathForImageHandling(imageItem),
      );
      if (!mounted) return;
      setState(() {
        _droppedImageAttachment = attachment;
      });
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('message.drop_image_failed'.tr())));
      debugPrint('Failed to read dropped image: $e');
    }
  }

  DropItem? _firstImageDropItem(List<DropItem> items) {
    for (final item in items) {
      if (item is DropItemDirectory) {
        continue;
      }
      if (_isImageDropItem(item)) {
        return item;
      }
    }
    return null;
  }

  bool _isImageDropItem(DropItem item) {
    final mimeType = item.mimeType?.toLowerCase();
    if (mimeType != null && mimeType.startsWith('image/')) {
      return true;
    }

    final path = _dropItemPathForImageHandling(item).toLowerCase();
    return _imageDropExtensions.any((extension) => path.endsWith(extension));
  }

  Future<Uint8List> _readDropItemBytes(DropItem item) async {
    final bookmark = item.extraAppleBookmark;
    final shouldStartSecurityScope =
        Platform.isMacOS && bookmark != null && bookmark.isNotEmpty;
    var securityScopeStarted = false;

    try {
      if (shouldStartSecurityScope) {
        securityScopeStarted = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: bookmark);
      }
      return item.readAsBytes();
    } finally {
      if (securityScopeStarted && bookmark != null) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark,
        );
      }
    }
  }

  String _dropItemPathForImageHandling(DropItem item) {
    if (item.path.trim().isNotEmpty) {
      return item.path;
    }
    return item.name;
  }

  String _mimeTypeForDropItem(DropItem item) {
    final mimeType = item.mimeType;
    if (mimeType != null && mimeType.toLowerCase().startsWith('image/')) {
      return mimeType;
    }

    final path = _dropItemPathForImageHandling(item).toLowerCase();
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.webp')) return 'image/webp';
    if (path.endsWith('.gif')) return 'image/gif';
    if (path.endsWith('.heic')) return 'image/heic';
    if (path.endsWith('.heif')) return 'image/heif';
    if (path.endsWith('.tif') || path.endsWith('.tiff')) return 'image/tiff';
    if (path.endsWith('.bmp')) return 'image/bmp';
    return 'image/jpeg';
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

    // SSH connect confirmation dialog. Dialogs are deferred to the next
    // frame so they don't fire during a build / InheritedElement
    // lifecycle transition (avoids `_dependents.isEmpty` assertions).
    ref.listen<PendingSshConnect?>(
      chatNotifierProvider.select((s) => s.pendingSshConnect),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showSshConnectDialog(context, next),
          );
        }
      },
    );

    // SSH per-command confirmation dialog.
    ref.listen<PendingSshCommand?>(
      chatNotifierProvider.select((s) => s.pendingSshCommand),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showSshCommandDialog(context, next),
          );
        }
      },
    );

    // Git write-command confirmation dialog.
    ref.listen<PendingGitCommand?>(
      chatNotifierProvider.select((s) => s.pendingGitCommand),
      (prev, next) {
        if (next != null &&
            shouldPresentDesktopApproval(next.origin) &&
            prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showGitCommandDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingLocalCommand?>(
      chatNotifierProvider.select((s) => s.pendingLocalCommand),
      (prev, next) {
        if (next != null &&
            shouldPresentDesktopApproval(next.origin) &&
            prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showLocalCommandDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingComputerUseAction?>(
      chatNotifierProvider.select((s) => s.pendingComputerUseAction),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showComputerUseActionDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingBrowserAction?>(
      chatNotifierProvider.select((s) => s.pendingBrowserAction),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showBrowserActionDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingFileOperation?>(
      chatNotifierProvider.select((s) => s.pendingFileOperation),
      (prev, next) {
        if (next != null &&
            shouldPresentDesktopApproval(next.origin) &&
            prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showFileOperationDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingWorkflowDecision?>(
      chatNotifierProvider.select((s) => s.pendingWorkflowDecision),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showWorkflowDecisionDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingAskUserQuestion?>(
      chatNotifierProvider.select((s) => s.pendingAskUserQuestion),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showAskUserQuestionDialog(context, next),
          );
        }
      },
    );

    // BLE connect confirmation dialog.
    ref.listen<PendingBleConnect?>(
      chatNotifierProvider.select((s) => s.pendingBleConnect),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showBleConnectDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingSerialOpen?>(
      chatNotifierProvider.select((s) => s.pendingSerialOpen),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showSerialOpenDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingParticipantToolApproval?>(
      chatNotifierProvider.select((s) => s.pendingParticipantToolApproval),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showParticipantToolApprovalDialog(context, next),
          );
        }
      },
    );

    final settings = ref.watch(settingsNotifierProvider);
    final isDashboardVisible = _showDashboard;
    final isRoutinesWorkspace =
        !isDashboardVisible &&
        conversationsState.activeWorkspaceMode == WorkspaceMode.routines;
    final isCodingWorkspace =
        !isDashboardVisible &&
        conversationsState.activeWorkspaceMode == WorkspaceMode.coding;
    // Chat-mode permission selector gates the shared approval for high-risk
    // chat tools (browser, SSH, BLE, serial). Only shown when at least one of
    // them is exposed.
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
    // The companion panel is available in coding (with a project) and in plain
    // chat. Coding surfaces git/progress/sources plus the session log; chat
    // surfaces only the session log section.
    final canShowCompanionPanel =
        currentConversation != null &&
        !isDashboardVisible &&
        !isRoutinesWorkspace &&
        !isMobileRemoteCoding &&
        (!isCodingWorkspace || activeProject != null);
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
      if (isCodingWorkspace &&
          currentConversation != null &&
          _isCodingGoalSuggestionInProgressFor(currentConversation)) {
        setState(() {
          _composerPrefillText = message;
          _composerPrefillVersion++;
        });
        return;
      }
      setState(() {
        _composerPrefillText = '';
        _composerPrefillVersion++;
      });
      _leaveDashboard();
      final languageCode = context.locale.languageCode;
      if (isCodingWorkspace &&
          currentConversation != null &&
          _isCodingGoalSetupPendingFor(currentConversation) &&
          message.trim().isNotEmpty) {
        unawaited(
          _sendMessageAfterPendingGoalSetup(
            context,
            currentConversation: currentConversation,
            message: message,
            imageBase64: imageBase64,
            imageMimeType: imageMimeType,
            originalImagePath: originalImagePath,
            originalImageMimeType: originalImageMimeType,
            languageCode: languageCode,
          ).then((sent) {
            if (sent || !mounted) {
              return;
            }
            final activeConversation = ref
                .read(conversationsNotifierProvider)
                .currentConversation;
            if (activeConversation?.id != currentConversation.id) {
              return;
            }
            setState(() {
              _composerPrefillText = message;
              _composerPrefillVersion++;
            });
          }),
        );
        return;
      }
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
        codingGoal: isCodingWorkspace ? currentConversation?.goal : null,
        isCodingGoalSetupPending:
            isCodingWorkspace &&
            _isCodingGoalSetupPendingFor(currentConversation),
        isCodingGoalSuggestionInProgress:
            isCodingWorkspace &&
            _isCodingGoalSuggestionInProgressFor(currentConversation),
        onCodingGoalSwitchChanged:
            isCodingWorkspace && currentConversation != null
            ? (enabled, draftText) => _handleGoalSwitch(
                context,
                currentConversation,
                enabled,
                pendingUserMessage: draftText,
              )
            : null,
        onCodingGoalEmptySwitchEnabled:
            isCodingWorkspace && currentConversation != null
            ? () => _deferGoalSetupUntilSend(currentConversation)
            : null,
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

    Widget buildWorkspaceBody() {
      return isDashboardVisible
          ? const DashboardView()
          : isRoutinesWorkspace
          ? (selectedRoutine != null
                ? RoutineDetailView(
                    key: ValueKey('routine-detail-${selectedRoutine.id}'),
                    routineId: selectedRoutine.id,
                    onClose: () => ref
                        .read(routinesNotifierProvider.notifier)
                        .selectRoutine(null),
                  )
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
                      _isCompanionSidebarVisible &&
                      MediaQuery.sizeOf(context).width >=
                          _companionSidebarBreakpoint;
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
                      // Token usage indicator
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
                      // Input area
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
                          currentConversation: currentConversation,
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
          const WorktreeAgentTaskBanner(),
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

  Future<void> _runWorkflowTask(
    BuildContext context, {
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
  }) async {
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    final languageCode = context.locale.languageCode;
    final previousAssistantMessageId = _latestAssistantMessageId(
      ref.read(conversationsNotifierProvider).currentConversation ??
          currentConversation,
    );

    await _setWorkflowTaskStatus(
      currentConversation: currentConversation,
      task: task,
      status: task.status == ConversationWorkflowTaskStatus.completed
          ? ConversationWorkflowTaskStatus.completed
          : ConversationWorkflowTaskStatus.inProgress,
      summary: task.status == ConversationWorkflowTaskStatus.completed
          ? 'Reopened the completed task for review.'
          : 'Started from the approved plan execution flow.',
      lastRunAt: task.status == ConversationWorkflowTaskStatus.completed
          ? null
          : DateTime.now(),
      eventType: task.status == ConversationWorkflowTaskStatus.completed
          ? null
          : ConversationExecutionTaskEventType.started,
    );
    if (!context.mounted) {
      return;
    }

    await chatNotifier.sendMessage(
      ConversationPlanExecutionCoordinator.buildTaskPrompt(
        task: task,
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
      languageCode: languageCode,
      bypassPlanMode: true,
    );
    if (!mounted || !context.mounted) {
      return;
    }

    final toolResults = chatNotifier.takeLatestToolResults();
    final hiddenAssistantResponse = chatNotifier
        .takeLatestHiddenAssistantResponse();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: task,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: toolResults,
          fallbackAssistantResponse: hiddenAssistantResponse,
        );
    final completionPromoted = toolResultApplied
        ? await _maybePromoteCompletionFromValidationToolResults(
            task: task,
            toolResults: toolResults,
          )
        : false;
    final recoveredFromValidation =
        !toolResultApplied &&
        await _maybeRecoverFromValidationFirstExecution(
          task: task,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromFailure =
        !toolResultApplied &&
        !recoveredFromValidation &&
        await _maybeRecoverFromToolFailureSignals(
          task: task,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromMissingTarget =
        !toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        await _maybeRecoverFromMissingTargetValidationFailure(
          task: task,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromPythonRuntimeDependency =
        !toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        !recoveredFromMissingTarget &&
        await _maybeRecoverFromMissingPythonRuntimeDependency(
          task: task,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromPythonTestDependency =
        !toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonRuntimeDependency &&
        await _maybeRecoverFromMissingPythonTestDependency(
          task: task,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromPythonImport =
        !toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonRuntimeDependency &&
        !recoveredFromPythonTestDependency &&
        await _maybeRecoverFromPythonSrcLayoutValidationFailure(
          task: task,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromDrift =
        !toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonRuntimeDependency &&
        !recoveredFromPythonTestDependency &&
        !recoveredFromPythonImport &&
        await _maybeRecoverFromTaskDrift(
          task: task,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final assistantEvidenceApplied =
        !completionPromoted &&
            !recoveredFromValidation &&
            !recoveredFromFailure &&
            !recoveredFromMissingTarget &&
            !recoveredFromPythonTestDependency &&
            !recoveredFromPythonImport &&
            !recoveredFromDrift
        ? await _captureExecutionProgressFromLatestAssistantEvidence(
            task: task,
            previousAssistantMessageId: previousAssistantMessageId,
            isValidationRun: false,
            fallbackAssistantResponse:
                hiddenAssistantResponse ??
                chatNotifier.takeLatestHiddenAssistantResponse(),
          )
        : false;
    if (!toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonTestDependency &&
        !recoveredFromPythonImport &&
        !recoveredFromDrift) {
      await _maybeRecoverFromToolLessExecution(
        task: task,
        languageCode: languageCode,
        toolResults: toolResults,
        assistantEvidenceApplied: assistantEvidenceApplied,
        fallbackAssistantResponse:
            hiddenAssistantResponse ??
            chatNotifier.takeLatestHiddenAssistantResponse(),
      );
    }
    if (!context.mounted) {
      return;
    }
    await _continueToNextPendingTaskIfNeeded(context, completedTask: task);
  }

  Future<void> _runWorkflowTaskValidation(
    BuildContext context, {
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
  }) async {
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    final languageCode = context.locale.languageCode;
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final previousAssistantMessageId = _latestAssistantMessageId(
      ref.read(conversationsNotifierProvider).currentConversation ??
          currentConversation,
    );
    final validationCommand = task.validationCommand.trim();
    final validationStartedAt = DateTime.now();
    await _setWorkflowTaskStatus(
      currentConversation: currentConversation,
      task: task,
      status: task.status == ConversationWorkflowTaskStatus.completed
          ? ConversationWorkflowTaskStatus.completed
          : ConversationWorkflowTaskStatus.inProgress,
      summary: 'Ran the saved validation step from the approved plan.',
      lastValidationAt: validationStartedAt,
      validationStatus: ConversationExecutionValidationStatus.unknown,
      lastValidationCommand: validationCommand,
      lastValidationSummary: validationCommand.isEmpty
          ? 'Started validation using the saved task context.'
          : 'Started validation with the saved command.',
    );
    if (!context.mounted) {
      return;
    }

    await chatNotifier.sendMessage(
      ConversationPlanExecutionCoordinator.buildValidationPrompt(
        task: task,
        intro: 'chat.workflow_task_validation_prompt_intro'.tr(
          namedArgs: {'title': task.title},
        ),
        targetFilesLabel: 'chat.workflow_task_target_files'.tr(),
        validationLabel: 'chat.workflow_task_validation'.tr(),
        outro: 'chat.workflow_task_validation_prompt_outro'.tr(),
      ),
      languageCode: languageCode,
      bypassPlanMode: true,
    );
    final validationToolResults = chatNotifier.takeLatestToolResults();
    final toolResultApplied = await conversationsNotifier
        .updateCurrentValidationProgressFromToolResults(
          task: task,
          toolResults: validationToolResults
              .map(
                (result) => ConversationValidationToolResultInput(
                  toolName: result.name,
                  rawResult: result.result,
                ),
              )
              .toList(growable: false),
        );
    final completionPromoted = toolResultApplied
        ? await _maybePromoteCompletionFromValidationToolResults(
            task: task,
            toolResults: validationToolResults,
          )
        : false;
    final recoveredFromMissingTarget =
        toolResultApplied &&
        !completionPromoted &&
        await _maybeRecoverFromMissingTargetValidationFailure(
          task: task,
          languageCode: languageCode,
          toolResults: validationToolResults,
        );
    final recoveredFromPythonRuntimeDependency =
        toolResultApplied &&
        !completionPromoted &&
        !recoveredFromMissingTarget &&
        await _maybeRecoverFromMissingPythonRuntimeDependency(
          task: task,
          languageCode: languageCode,
          toolResults: validationToolResults,
        );
    final recoveredFromPythonTestDependency =
        toolResultApplied &&
        !completionPromoted &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonRuntimeDependency &&
        await _maybeRecoverFromMissingPythonTestDependency(
          task: task,
          languageCode: languageCode,
          toolResults: validationToolResults,
        );
    final recoveredFromPythonImport =
        toolResultApplied &&
        !completionPromoted &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonRuntimeDependency &&
        !recoveredFromPythonTestDependency &&
        await _maybeRecoverFromPythonSrcLayoutValidationFailure(
          task: task,
          languageCode: languageCode,
          toolResults: validationToolResults,
        );
    if (!toolResultApplied ||
        (!completionPromoted &&
            !recoveredFromMissingTarget &&
            !recoveredFromPythonRuntimeDependency &&
            !recoveredFromPythonTestDependency &&
            !recoveredFromPythonImport)) {
      await _captureExecutionProgressFromLatestAssistantEvidence(
        task: task,
        previousAssistantMessageId: previousAssistantMessageId,
        isValidationRun: true,
        fallbackAssistantResponse: chatNotifier
            .takeLatestHiddenAssistantResponse(),
      );
    }
    if (!context.mounted) {
      return;
    }
    await _continueToNextPendingTaskIfNeeded(context, completedTask: task);
  }

  Future<void> _continueToNextPendingTaskIfNeeded(
    BuildContext context, {
    required ConversationWorkflowTask completedTask,
    int depth = 0,
  }) async {
    if (depth >= 8) {
      return;
    }

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return;
    }

    final latestCompletedTask = currentConversation.projectedExecutionTasks
        .where((task) => task.id == completedTask.id)
        .firstOrNull;
    if (latestCompletedTask == null ||
        latestCompletedTask.status !=
            ConversationWorkflowTaskStatus.completed) {
      return;
    }

    final nextTask = ConversationPlanExecutionCoordinator.nextTask(
      currentConversation,
    );
    if (nextTask == null || nextTask.id == latestCompletedTask.id) {
      return;
    }

    final languageCode = context.locale.languageCode;
    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    await _setWorkflowTaskStatus(
      currentConversation: currentConversation,
      task: nextTask,
      status: ConversationWorkflowTaskStatus.inProgress,
      summary:
          'Auto-continued to the next saved task after completing "${latestCompletedTask.title}".',
      lastRunAt: DateTime.now(),
      eventType: ConversationExecutionTaskEventType.started,
    );

    if (!context.mounted) {
      return;
    }

    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    await chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildAutoContinueTaskPrompt(
        completedTask: latestCompletedTask,
        nextTask: nextTask,
      ),
      languageCode: languageCode,
    );
    if (!context.mounted) {
      return;
    }
    final toolResults = chatNotifier.takeLatestToolResults();
    final hiddenAssistantResponse = chatNotifier
        .takeLatestHiddenAssistantResponse();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: nextTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: toolResults,
          fallbackAssistantResponse: hiddenAssistantResponse,
        );
    final completionPromoted = toolResultApplied
        ? await _maybePromoteCompletionFromValidationToolResults(
            task: nextTask,
            toolResults: toolResults,
          )
        : false;
    final recoveredFromValidation =
        !toolResultApplied &&
        await _maybeRecoverFromValidationFirstExecution(
          task: nextTask,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromFailure =
        !toolResultApplied &&
        !recoveredFromValidation &&
        await _maybeRecoverFromToolFailureSignals(
          task: nextTask,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromMissingTarget =
        !toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        await _maybeRecoverFromMissingTargetValidationFailure(
          task: nextTask,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromPythonRuntimeDependency =
        !toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        !recoveredFromMissingTarget &&
        await _maybeRecoverFromMissingPythonRuntimeDependency(
          task: nextTask,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromPythonTestDependency =
        !toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonRuntimeDependency &&
        await _maybeRecoverFromMissingPythonTestDependency(
          task: nextTask,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromPythonImport =
        !toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonRuntimeDependency &&
        !recoveredFromPythonTestDependency &&
        await _maybeRecoverFromPythonSrcLayoutValidationFailure(
          task: nextTask,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromDrift =
        !toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonRuntimeDependency &&
        !recoveredFromPythonTestDependency &&
        !recoveredFromPythonImport &&
        await _maybeRecoverFromTaskDrift(
          task: nextTask,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final assistantEvidenceApplied =
        !completionPromoted &&
            !recoveredFromValidation &&
            !recoveredFromFailure &&
            !recoveredFromMissingTarget &&
            !recoveredFromPythonTestDependency &&
            !recoveredFromPythonImport &&
            !recoveredFromDrift
        ? await _captureExecutionProgressFromLatestAssistantEvidence(
            task: nextTask,
            previousAssistantMessageId: previousAssistantMessageId,
            isValidationRun: false,
            fallbackAssistantResponse:
                hiddenAssistantResponse ??
                chatNotifier.takeLatestHiddenAssistantResponse(),
          )
        : false;
    if (!toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonTestDependency &&
        !recoveredFromPythonImport &&
        !recoveredFromDrift) {
      await _maybeRecoverFromToolLessExecution(
        task: nextTask,
        languageCode: languageCode,
        toolResults: toolResults,
        assistantEvidenceApplied: assistantEvidenceApplied,
        fallbackAssistantResponse:
            hiddenAssistantResponse ??
            chatNotifier.takeLatestHiddenAssistantResponse(),
      );
    }
    if (!context.mounted) {
      return;
    }
    await _continueToNextPendingTaskIfNeeded(
      context,
      completedTask: nextTask,
      depth: depth + 1,
    );
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

  List<String> _existingWorkspaceTargetFiles(ConversationWorkflowTask task) {
    final projectRoot = _activeProjectRootPath();
    if (projectRoot == null || projectRoot.isEmpty) {
      return const <String>[];
    }

    final existingTargets = <String>[];
    for (final target
        in ConversationPlanExecutionGuardrails.effectiveTargetPathsForTask(
          task,
        )) {
      final normalizedTarget = target.trim().replaceAll('\\', '/');
      if (normalizedTarget.isEmpty) {
        continue;
      }
      final resolvedPath = normalizedTarget.startsWith('/')
          ? normalizedTarget
          : '$projectRoot/$normalizedTarget';
      if (File(resolvedPath).existsSync() ||
          Directory(resolvedPath).existsSync()) {
        existingTargets.add(normalizedTarget);
      }
    }
    return existingTargets.toList(growable: false);
  }

  Future<bool> _maybeFinalizeScaffoldFromWorkspaceTargets({
    required ConversationWorkflowTask task,
  }) async {
    final existingTargetFiles = _existingWorkspaceTargetFiles(task);
    final canFinalize =
        ConversationPlanExecutionGuardrails.canFinalizeScaffoldFromWorkspaceTargets(
          task: task,
          existingTargetPaths: existingTargetFiles,
        );
    if (!canFinalize) {
      return false;
    }

    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final validationCommand = task.validationCommand.trim();
    const summary =
        'Marked complete after confirming every scaffold target file existed in the workspace.';
    await conversationsNotifier.updateCurrentExecutionTaskProgress(
      taskId: task.id,
      status: ConversationWorkflowTaskStatus.completed,
      summary: summary,
      validationStatus: validationCommand.isEmpty
          ? ConversationExecutionValidationStatus.unknown
          : ConversationExecutionValidationStatus.passed,
      lastValidationAt: validationCommand.isEmpty ? null : DateTime.now(),
      lastValidationCommand: validationCommand.isEmpty
          ? null
          : validationCommand,
      lastValidationSummary: validationCommand.isEmpty ? null : summary,
      eventType: ConversationExecutionTaskEventType.completed,
      eventSummary: summary,
    );
    return true;
  }

  Future<bool> _maybeRecoverFromTaskDrift({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!mounted) {
      return false;
    }
    if (toolResults.isEmpty || _toolResultsContainFailure(toolResults)) {
      return false;
    }

    final assessment = ConversationPlanExecutionGuardrails.assessTaskDrift(
      task: task,
      toolResults: toolResults,
      changedFilePaths: _latestTurnChangedFilePaths(),
    );
    if (!assessment.hasDrift) {
      return false;
    }

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed) {
      return false;
    }

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    await chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildTaskDriftRecoveryPrompt(
        task: latestTask,
        unrelatedTouchedPaths: assessment.unrelatedTouchedPaths,
        scaffoldCommands: assessment.scaffoldCommands,
        alreadyTouchedTargetFiles: assessment.touchedTargetFiles,
        repeatedTargetFiles: assessment.repeatedTargetFiles,
        remainingTargetFiles: assessment.remainingTargetFiles,
      ),
      languageCode: languageCode,
    );

    return _captureExecutionProgressFromLatestToolResults(
      task: latestTask,
      previousAssistantMessageId: previousAssistantMessageId,
      toolResults: chatNotifier.takeLatestToolResults(),
    );
  }

  Future<bool> _maybeRecoverFromToolFailureSignals({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!mounted) {
      return false;
    }
    if (toolResults.isEmpty || !_toolResultsContainFailure(toolResults)) {
      return false;
    }

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed) {
      return false;
    }

    final existingTargetFiles = _existingWorkspaceTargetFiles(latestTask);
    final missingTargetFiles =
        ConversationPlanExecutionGuardrails.missingWorkspaceTargetFiles(
          task: latestTask,
          existingTargetPaths: existingTargetFiles,
        );
    final isScaffoldTask =
        ConversationPlanExecutionGuardrails.looksLikeScaffoldTask(latestTask);
    final unavailableToolNames =
        ConversationPlanExecutionGuardrails.unavailableToolNames(toolResults);
    final editMismatchPaths =
        ConversationPlanExecutionGuardrails.editMismatchPaths(toolResults);
    final malformedFileMutationPaths =
        ConversationPlanExecutionGuardrails.malformedFileMutationPaths(
          toolResults,
        );
    final hasMalformedFileMutationFailure =
        ConversationPlanExecutionGuardrails.hasMalformedFileMutationFailure(
          toolResults,
        );
    final shouldAttemptScaffoldRecovery =
        isScaffoldTask && missingTargetFiles.isNotEmpty;
    if (latestTask.status == ConversationWorkflowTaskStatus.blocked &&
        !shouldAttemptScaffoldRecovery) {
      return false;
    }
    if (unavailableToolNames.isEmpty &&
        editMismatchPaths.isEmpty &&
        !hasMalformedFileMutationFailure &&
        !shouldAttemptScaffoldRecovery) {
      return false;
    }

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    await chatNotifier.sendHiddenPrompt(
      shouldAttemptScaffoldRecovery
          ? existingTargetFiles.isEmpty
                ? ConversationPlanExecutionCoordinator.buildScaffoldMissingTargetRecoveryPrompt(
                    task: latestTask,
                    missingTargetFiles: missingTargetFiles,
                  )
                : ConversationPlanExecutionCoordinator.buildScaffoldRemainingTargetRecoveryPrompt(
                    task: latestTask,
                    existingTargetFiles: existingTargetFiles,
                    missingTargetFiles: missingTargetFiles,
                  )
          : ConversationPlanExecutionCoordinator.buildToolFailureRecoveryPrompt(
              task: latestTask,
              unavailableToolNames: unavailableToolNames,
              editMismatchPaths: editMismatchPaths,
              malformedFileMutationPaths: malformedFileMutationPaths,
              hasMalformedFileMutationFailure: hasMalformedFileMutationFailure,
            ),
      languageCode: languageCode,
    );

    final recoveryToolResults = chatNotifier.takeLatestToolResults();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: recoveryToolResults,
        );
    final completionPromoted = toolResultApplied
        ? await _maybePromoteCompletionFromValidationToolResults(
            task: latestTask,
            toolResults: recoveryToolResults,
          )
        : false;
    final recoveredFromMissingTarget =
        toolResultApplied &&
        !completionPromoted &&
        await _maybeRecoverFromMissingTargetValidationFailure(
          task: latestTask,
          languageCode: languageCode,
          toolResults: recoveryToolResults,
        );
    final recoveredFromPythonTestDependency =
        toolResultApplied &&
        !completionPromoted &&
        !recoveredFromMissingTarget &&
        await _maybeRecoverFromMissingPythonTestDependency(
          task: latestTask,
          languageCode: languageCode,
          toolResults: recoveryToolResults,
        );
    final recoveredFromPythonImport =
        toolResultApplied &&
        !completionPromoted &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonTestDependency &&
        await _maybeRecoverFromPythonSrcLayoutValidationFailure(
          task: latestTask,
          languageCode: languageCode,
          toolResults: recoveryToolResults,
        );
    final onlyReadMismatchedFiles =
        editMismatchPaths.isNotEmpty &&
        recoveryToolResults.isNotEmpty &&
        recoveryToolResults.every((toolResult) {
          if (toolResult.name != 'read_file') {
            return false;
          }
          final path =
              toolResult.arguments['path']?.toString().trim().replaceAll(
                '\\',
                '/',
              ) ??
              '';
          return editMismatchPaths.any((candidate) => candidate == path);
        });
    if (!toolResultApplied &&
        !completionPromoted &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonImport &&
        onlyReadMismatchedFiles) {
      await chatNotifier.sendHiddenPrompt(
        ConversationPlanExecutionCoordinator.buildEditMismatchRetryPrompt(
          task: latestTask,
          editMismatchPaths: editMismatchPaths,
        ),
        languageCode: languageCode,
      );

      final retryToolResults = chatNotifier.takeLatestToolResults();
      final retryApplied = await _captureExecutionProgressFromLatestToolResults(
        task: latestTask,
        previousAssistantMessageId: previousAssistantMessageId,
        toolResults: retryToolResults,
      );
      if (retryApplied || _taskReachedTerminalStatus(latestTask.id)) {
        return true;
      }
    }
    if (!toolResultApplied ||
        (!completionPromoted &&
            !recoveredFromMissingTarget &&
            !recoveredFromPythonTestDependency &&
            !recoveredFromPythonImport)) {
      final assistantResult =
          await _captureExecutionProgressFromLatestAssistantEvidence(
            task: latestTask,
            previousAssistantMessageId: previousAssistantMessageId,
            isValidationRun: false,
            fallbackAssistantResponse: chatNotifier
                .takeLatestHiddenAssistantResponse(),
          );
      if (!assistantResult && recoveryToolResults.isEmpty) {
        return false;
      }
    }

    if (!mounted) {
      return false;
    }
    final refreshedConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (refreshedConversation == null) {
      return false;
    }
    final refreshedTask = refreshedConversation.projectedExecutionTasks
        .where((item) => item.id == latestTask.id)
        .firstOrNull;
    if (refreshedTask == null) {
      return false;
    }
    return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
        refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
  }

  Future<bool> _maybeRecoverFromMissingTargetValidationFailure({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!mounted) {
      return false;
    }
    if (toolResults.isEmpty || !_toolResultsContainFailure(toolResults)) {
      return false;
    }

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed ||
        latestTask.status == ConversationWorkflowTaskStatus.blocked) {
      return false;
    }

    final missingTargetFile =
        ConversationPlanExecutionGuardrails.missingTargetFileFromValidationFailure(
          task: latestTask,
          toolResults: toolResults,
        );
    if (missingTargetFile == null) {
      return false;
    }

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    final failedCommand =
        ConversationPlanExecutionGuardrails.failedPythonValidationCommand(
          task: latestTask,
          toolResults: toolResults,
        ) ??
        latestTask.validationCommand.trim();
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    await chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildMissingTargetFileRecoveryPrompt(
        task: latestTask,
        missingTargetFiles: [missingTargetFile],
        failedCommand: failedCommand,
      ),
      languageCode: languageCode,
    );

    final recoveryToolResults = chatNotifier.takeLatestToolResults();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: recoveryToolResults,
        );
    final recoveredFromValidation =
        !toolResultApplied &&
        await _maybeRecoverFromValidationFirstExecution(
          task: latestTask,
          languageCode: languageCode,
          toolResults: recoveryToolResults,
        );
    if (toolResultApplied ||
        recoveredFromValidation ||
        _taskReachedTerminalStatus(latestTask.id)) {
      return true;
    }

    final assistantResult =
        await _captureExecutionProgressFromLatestAssistantEvidence(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          isValidationRun: false,
          fallbackAssistantResponse: chatNotifier
              .takeLatestHiddenAssistantResponse(),
        );
    if (!assistantResult) {
      return false;
    }

    if (!mounted) {
      return false;
    }
    final refreshedConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (refreshedConversation == null) {
      return false;
    }
    final refreshedTask = refreshedConversation.projectedExecutionTasks
        .where((item) => item.id == latestTask.id)
        .firstOrNull;
    if (refreshedTask == null) {
      return false;
    }
    return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
        refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
  }

  Future<bool> _maybeRecoverFromMissingPythonTestDependency({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!mounted) {
      return false;
    }
    if (toolResults.isEmpty || !_toolResultsContainFailure(toolResults)) {
      return false;
    }

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed ||
        latestTask.status == ConversationWorkflowTaskStatus.blocked) {
      return false;
    }

    final missingDependency =
        ConversationPlanExecutionGuardrails.missingPythonTestDependency(
          task: latestTask,
          toolResults: toolResults,
        );
    if (missingDependency == null) {
      return false;
    }

    final failedCommand =
        ConversationPlanExecutionGuardrails.failedPythonValidationCommand(
          task: latestTask,
          toolResults: toolResults,
        ) ??
        latestTask.validationCommand.trim();
    final fallbackCommand =
        ConversationPlanExecutionGuardrails.suggestPythonTestDependencyFallbackCommand(
          task: latestTask,
          failedCommand: failedCommand,
          missingDependency: missingDependency,
        );
    if (fallbackCommand == null) {
      return false;
    }

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    await chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildPythonTestDependencyRecoveryPrompt(
        task: latestTask,
        failedCommand: failedCommand,
        fallbackCommand: fallbackCommand,
        missingDependency: missingDependency,
      ),
      languageCode: languageCode,
    );

    final recoveryToolResults = chatNotifier.takeLatestToolResults();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: recoveryToolResults,
        );
    if (toolResultApplied || _taskReachedTerminalStatus(latestTask.id)) {
      return true;
    }

    final assistantResult =
        await _captureExecutionProgressFromLatestAssistantEvidence(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          isValidationRun: false,
          fallbackAssistantResponse: chatNotifier
              .takeLatestHiddenAssistantResponse(),
        );
    if (!assistantResult) {
      return false;
    }

    if (!mounted) {
      return false;
    }
    final refreshedConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (refreshedConversation == null) {
      return false;
    }
    final refreshedTask = refreshedConversation.projectedExecutionTasks
        .where((item) => item.id == latestTask.id)
        .firstOrNull;
    if (refreshedTask == null) {
      return false;
    }
    return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
        refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
  }

  Future<bool> _maybeRecoverFromMissingPythonRuntimeDependency({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!mounted) {
      return false;
    }
    if (toolResults.isEmpty || !_toolResultsContainFailure(toolResults)) {
      return false;
    }

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed) {
      return false;
    }

    final missingDependency =
        ConversationPlanExecutionGuardrails.missingPythonRuntimeDependency(
          task: latestTask,
          toolResults: toolResults,
        );
    if (missingDependency == null) {
      return false;
    }

    final failedCommand =
        ConversationPlanExecutionGuardrails.failedPythonValidationCommand(
          task: latestTask,
          toolResults: toolResults,
        ) ??
        latestTask.validationCommand.trim();

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    await chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildPythonRuntimeDependencyRecoveryPrompt(
        task: latestTask,
        failedCommand: failedCommand,
        missingDependency: missingDependency,
      ),
      languageCode: languageCode,
    );

    final recoveryToolResults = chatNotifier.takeLatestToolResults();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: recoveryToolResults,
        );
    if (toolResultApplied || _taskReachedTerminalStatus(latestTask.id)) {
      return true;
    }

    final assistantResult =
        await _captureExecutionProgressFromLatestAssistantEvidence(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          isValidationRun: false,
          fallbackAssistantResponse: chatNotifier
              .takeLatestHiddenAssistantResponse(),
        );
    if (!assistantResult && recoveryToolResults.isEmpty) {
      return false;
    }

    if (!mounted) {
      return false;
    }
    final refreshedConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (refreshedConversation == null) {
      return false;
    }
    final refreshedTask = refreshedConversation.projectedExecutionTasks
        .where((item) => item.id == latestTask.id)
        .firstOrNull;
    if (refreshedTask == null) {
      return false;
    }
    return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
        refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
  }

  Future<bool> _maybeRecoverFromValidationFirstExecution({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!mounted) {
      return false;
    }
    if (toolResults.isEmpty || _toolResultsContainFailure(toolResults)) {
      return false;
    }

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed ||
        latestTask.status == ConversationWorkflowTaskStatus.blocked ||
        latestTask.validationCommand.trim().isEmpty) {
      return false;
    }

    final missingWorkspaceTargets =
        ConversationPlanExecutionGuardrails.missingWorkspaceTargetFiles(
          task: latestTask,
          existingTargetPaths: _existingWorkspaceTargetFiles(latestTask),
        );
    if (missingWorkspaceTargets.isNotEmpty) {
      return false;
    }

    final completionAssessment =
        ConversationPlanExecutionGuardrails.assessTaskCompletion(
          task: latestTask,
          toolResults: toolResults,
          changedFilePaths: _latestTurnChangedFilePaths(),
        );
    if (completionAssessment.hasFailure ||
        completionAssessment.touchedTargetFiles.isEmpty ||
        completionAssessment.successfulValidationCommands.isNotEmpty ||
        completionAssessment.failedValidationCommands.isNotEmpty ||
        completionAssessment.unrelatedTouchedPaths.isNotEmpty ||
        completionAssessment.scaffoldCommands.isNotEmpty) {
      return false;
    }

    final preferValidationNow =
        completionAssessment.touchedAllTargetFiles ||
        completionAssessment.allowsLightValidationCompletion ||
        completionAssessment.untouchedTargetFiles.length <= 1;
    final targetCoverageLooksReady =
        completionAssessment.touchedTargetFiles.isNotEmpty &&
        (completionAssessment.touchedAllTargetFiles ||
            completionAssessment.touchedTargetFiles.length >=
                completionAssessment.untouchedTargetFiles.length);
    if (!preferValidationNow && !targetCoverageLooksReady) {
      return false;
    }

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    await chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildValidationFirstRecoveryPrompt(
        task: latestTask,
        touchedTargetFiles: completionAssessment.touchedTargetFiles,
        remainingTargetFiles: completionAssessment.untouchedTargetFiles,
        preferValidationNow: preferValidationNow,
      ),
      languageCode: languageCode,
    );

    final recoveryToolResults = chatNotifier.takeLatestToolResults();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: recoveryToolResults,
        );
    if (toolResultApplied || _taskReachedTerminalStatus(latestTask.id)) {
      return true;
    }

    final assistantResult =
        await _captureExecutionProgressFromLatestAssistantEvidence(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          isValidationRun: false,
          fallbackAssistantResponse: chatNotifier
              .takeLatestHiddenAssistantResponse(),
        );
    if (!assistantResult) {
      return false;
    }

    if (!mounted) {
      return false;
    }
    final refreshedConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (refreshedConversation == null) {
      return false;
    }
    final refreshedTask = refreshedConversation.projectedExecutionTasks
        .where((item) => item.id == latestTask.id)
        .firstOrNull;
    if (refreshedTask == null) {
      return false;
    }
    return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
        refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
  }

  Future<bool> _maybeRecoverFromToolLessExecution({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
    required bool assistantEvidenceApplied,
    String? fallbackAssistantResponse,
  }) async {
    if (!mounted) {
      return false;
    }
    if (toolResults.isNotEmpty) {
      return false;
    }

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed) {
      return false;
    }

    final progress = currentConversation.executionProgressForTask(
      latestTask.id,
    );
    final existingTargetFiles = _existingWorkspaceTargetFiles(latestTask);
    final fallbackAssistantEvidence = fallbackAssistantResponse?.trim() ?? '';
    final missingTargetFiles =
        ConversationPlanExecutionGuardrails.missingWorkspaceTargetFiles(
          task: latestTask,
          existingTargetPaths: existingTargetFiles,
        );
    final isScaffoldTask =
        ConversationPlanExecutionGuardrails.looksLikeScaffoldTask(latestTask);
    if (await _maybeFinalizeScaffoldFromWorkspaceTargets(task: latestTask)) {
      return true;
    }
    final latestAssistantResponse =
        _latestAssistantMessage(currentConversation)?.content.trim() ?? '';
    final assistantInference = ConversationExecutionProgressInference.infer(
      assistantResponse: latestAssistantResponse,
      task: latestTask,
      isValidationRun: false,
      fallbackAssistantResponse: fallbackAssistantEvidence,
    );
    final assistantResponses =
        [latestAssistantResponse, fallbackAssistantEvidence]
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
    final completionEvidence =
        ConversationPlanExecutionGuardrails.assistantMentionsTaskCompletionInAnyResponse(
          task: latestTask,
          assistantResponses: assistantResponses,
        );
    if (latestTask.status == ConversationWorkflowTaskStatus.blocked &&
        missingTargetFiles.isEmpty) {
      if (completionEvidence &&
          ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceTargets(
            task: latestTask,
            existingTargetPaths: existingTargetFiles,
          )) {
        final summary = assistantInference.summary.isNotEmpty
            ? assistantInference.summary
            : progress?.normalizedValidationSummary ??
                  progress?.normalizedSummary ??
                  'Marked complete after the assistant confirmed the saved task and every current target file already existed in the workspace.';
        await ref
            .read(conversationsNotifierProvider.notifier)
            .updateCurrentExecutionTaskProgress(
              taskId: latestTask.id,
              status: ConversationWorkflowTaskStatus.completed,
              summary: summary,
              validationStatus:
                  progress?.validationStatus ==
                      ConversationExecutionValidationStatus.passed
                  ? ConversationExecutionValidationStatus.passed
                  : null,
              lastValidationAt:
                  progress?.validationStatus ==
                      ConversationExecutionValidationStatus.passed
                  ? DateTime.now()
                  : null,
              lastValidationCommand: progress?.normalizedValidationCommand,
              lastValidationSummary:
                  progress?.validationStatus ==
                      ConversationExecutionValidationStatus.passed
                  ? (progress?.normalizedValidationSummary ?? summary)
                  : null,
              eventType: ConversationExecutionTaskEventType.completed,
              eventSummary: summary,
            );
        return true;
      }
      return false;
    }
    if (isScaffoldTask && missingTargetFiles.isNotEmpty) {
      final previousAssistantMessageId = _latestAssistantMessageId(
        currentConversation,
      );
      final chatNotifier = ref.read(chatNotifierProvider.notifier);
      await chatNotifier.sendHiddenPrompt(
        existingTargetFiles.isEmpty
            ? ConversationPlanExecutionCoordinator.buildScaffoldMissingTargetRecoveryPrompt(
                task: latestTask,
                missingTargetFiles: missingTargetFiles,
              )
            : ConversationPlanExecutionCoordinator.buildScaffoldRemainingTargetRecoveryPrompt(
                task: latestTask,
                existingTargetFiles: existingTargetFiles,
                missingTargetFiles: missingTargetFiles,
              ),
        languageCode: languageCode,
      );

      final recoveryToolResults = chatNotifier.takeLatestToolResults();
      final toolResultApplied =
          await _captureExecutionProgressFromLatestToolResults(
            task: latestTask,
            previousAssistantMessageId: previousAssistantMessageId,
            toolResults: recoveryToolResults,
          );
      final recoveredFromValidation =
          !toolResultApplied &&
          await _maybeRecoverFromValidationFirstExecution(
            task: latestTask,
            languageCode: languageCode,
            toolResults: recoveryToolResults,
          );
      if (toolResultApplied || recoveredFromValidation) {
        return true;
      }

      return _captureExecutionProgressFromLatestAssistantEvidence(
        task: latestTask,
        previousAssistantMessageId: previousAssistantMessageId,
        isValidationRun: false,
        fallbackAssistantResponse: chatNotifier
            .takeLatestHiddenAssistantResponse(),
      );
    }
    if (!isScaffoldTask && missingTargetFiles.isNotEmpty) {
      final previousAssistantMessageId = _latestAssistantMessageId(
        currentConversation,
      );
      final chatNotifier = ref.read(chatNotifierProvider.notifier);
      await chatNotifier.sendHiddenPrompt(
        ConversationPlanExecutionCoordinator.buildMissingTargetFileRecoveryPrompt(
          task: latestTask,
          missingTargetFiles: missingTargetFiles,
          failedCommand: latestTask.validationCommand.trim(),
        ),
        languageCode: languageCode,
      );

      final recoveryToolResults = chatNotifier.takeLatestToolResults();
      final toolResultApplied =
          await _captureExecutionProgressFromLatestToolResults(
            task: latestTask,
            previousAssistantMessageId: previousAssistantMessageId,
            toolResults: recoveryToolResults,
          );
      if (toolResultApplied) {
        return true;
      }

      return _captureExecutionProgressFromLatestAssistantEvidence(
        task: latestTask,
        previousAssistantMessageId: previousAssistantMessageId,
        isValidationRun: false,
        fallbackAssistantResponse: chatNotifier
            .takeLatestHiddenAssistantResponse(),
      );
    }

    final isVerificationTask =
        ConversationPlanExecutionCoordinator.looksLikeVerificationTask(
          latestTask,
        );
    if (isVerificationTask &&
        latestTask.validationCommand.trim().isNotEmpty &&
        missingTargetFiles.isEmpty) {
      final previousAssistantMessageId = _latestAssistantMessageId(
        currentConversation,
      );
      final chatNotifier = ref.read(chatNotifierProvider.notifier);
      await chatNotifier.sendHiddenPrompt(
        ConversationPlanExecutionCoordinator.buildVerificationTaskRecoveryPrompt(
          task: latestTask,
        ),
        languageCode: languageCode,
      );

      final recoveryToolResults = chatNotifier.takeLatestToolResults();
      final toolResultApplied =
          await _captureExecutionProgressFromLatestToolResults(
            task: latestTask,
            previousAssistantMessageId: previousAssistantMessageId,
            toolResults: recoveryToolResults,
          );
      if (toolResultApplied || _taskReachedTerminalStatus(latestTask.id)) {
        return true;
      }

      final assistantResult =
          await _captureExecutionProgressFromLatestAssistantEvidence(
            task: latestTask,
            previousAssistantMessageId: previousAssistantMessageId,
            isValidationRun: false,
            fallbackAssistantResponse: chatNotifier
                .takeLatestHiddenAssistantResponse(),
          );
      if (!assistantResult) {
        return false;
      }

      if (!mounted) {
        return false;
      }
      final refreshedConversation = ref
          .read(conversationsNotifierProvider)
          .currentConversation;
      if (refreshedConversation == null) {
        return false;
      }
      final refreshedTask = refreshedConversation.projectedExecutionTasks
          .where((item) => item.id == latestTask.id)
          .firstOrNull;
      if (refreshedTask == null) {
        return false;
      }
      return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
          refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
    }

    if (assistantInference.status == ConversationWorkflowTaskStatus.completed &&
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceTargets(
          task: latestTask,
          existingTargetPaths: existingTargetFiles,
        )) {
      final summary = assistantInference.summary.isNotEmpty
          ? assistantInference.summary
          : progress?.normalizedValidationSummary ??
                progress?.normalizedSummary ??
                'Marked complete after the assistant confirmed the saved task and every current target file already existed in the workspace.';
      await ref
          .read(conversationsNotifierProvider.notifier)
          .updateCurrentExecutionTaskProgress(
            taskId: latestTask.id,
            status: ConversationWorkflowTaskStatus.completed,
            summary: summary,
            validationStatus:
                progress?.validationStatus ==
                    ConversationExecutionValidationStatus.passed
                ? ConversationExecutionValidationStatus.passed
                : null,
            lastValidationAt:
                progress?.validationStatus ==
                    ConversationExecutionValidationStatus.passed
                ? DateTime.now()
                : null,
            lastValidationCommand: progress?.normalizedValidationCommand,
            lastValidationSummary:
                progress?.validationStatus ==
                    ConversationExecutionValidationStatus.passed
                ? (progress?.normalizedValidationSummary ?? summary)
                : null,
            eventType: ConversationExecutionTaskEventType.completed,
            eventSummary: summary,
          );
      return true;
    }
    if (latestTask.status == ConversationWorkflowTaskStatus.blocked &&
        missingTargetFiles.isNotEmpty) {
      return false;
    }
    if (assistantInference.status == ConversationWorkflowTaskStatus.completed ||
        assistantInference.status == ConversationWorkflowTaskStatus.blocked) {
      return false;
    }
    if (assistantEvidenceApplied &&
        latestAssistantResponse.isEmpty &&
        fallbackAssistantEvidence.isEmpty) {
      return false;
    }

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    if (progress?.validationStatus ==
            ConversationExecutionValidationStatus.failed &&
        latestTask.validationCommand.trim().isNotEmpty &&
        missingTargetFiles.isEmpty) {
      await chatNotifier.sendHiddenPrompt(
        ConversationPlanExecutionCoordinator.buildFailedValidationRecoveryPrompt(
          task: latestTask,
          failedCommand:
              progress?.normalizedValidationCommand ??
              latestTask.validationCommand.trim(),
          failedValidationSummary:
              progress?.normalizedValidationSummary ??
              progress?.normalizedSummary,
        ),
        languageCode: languageCode,
      );

      final recoveryToolResults = chatNotifier.takeLatestToolResults();
      final toolResultApplied =
          await _captureExecutionProgressFromLatestToolResults(
            task: latestTask,
            previousAssistantMessageId: previousAssistantMessageId,
            toolResults: recoveryToolResults,
          );
      if (toolResultApplied) {
        return true;
      }

      final assistantResult =
          await _captureExecutionProgressFromLatestAssistantEvidence(
            task: latestTask,
            previousAssistantMessageId: previousAssistantMessageId,
            isValidationRun: false,
            fallbackAssistantResponse: chatNotifier
                .takeLatestHiddenAssistantResponse(),
          );
      if (!assistantResult) {
        return false;
      }

      if (!mounted) {
        return false;
      }
      final refreshedConversation = ref
          .read(conversationsNotifierProvider)
          .currentConversation;
      if (refreshedConversation == null) {
        return false;
      }
      final refreshedTask = refreshedConversation.projectedExecutionTasks
          .where((item) => item.id == latestTask.id)
          .firstOrNull;
      if (refreshedTask == null) {
        return false;
      }
      return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
          refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
    }

    await chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildToolLessExecutionRecoveryPrompt(
        task: latestTask,
      ),
      languageCode: languageCode,
    );

    final recoveryToolResults = chatNotifier.takeLatestToolResults();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: recoveryToolResults,
        );
    if (toolResultApplied) {
      return true;
    }

    final assistantResult =
        await _captureExecutionProgressFromLatestAssistantEvidence(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          isValidationRun: false,
          fallbackAssistantResponse: chatNotifier
              .takeLatestHiddenAssistantResponse(),
        );
    if (!assistantResult) {
      return false;
    }

    if (!mounted) {
      return false;
    }
    final refreshedConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (refreshedConversation == null) {
      return false;
    }
    final refreshedTask = refreshedConversation.projectedExecutionTasks
        .where((item) => item.id == latestTask.id)
        .firstOrNull;
    if (refreshedTask == null) {
      return false;
    }
    return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
        refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
  }

  Future<bool> _maybePromoteCompletionFromValidationToolResults({
    required ConversationWorkflowTask task,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!mounted) {
      return false;
    }
    if (toolResults.isEmpty) {
      return false;
    }

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed) {
      return false;
    }

    final completionAssessment =
        ConversationPlanExecutionGuardrails.assessTaskCompletion(
          task: latestTask,
          toolResults: toolResults,
          changedFilePaths: _latestTurnChangedFilePaths(),
        );
    final existingWorkspaceTargets = _existingWorkspaceTargetFiles(latestTask);
    final canPromote =
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceValidation(
          task: latestTask,
          toolResults: toolResults,
          existingTargetPaths: existingWorkspaceTargets,
        ) ||
        ConversationPlanExecutionGuardrails.canPromoteScaffoldCompletionFromWorkspaceValidation(
          task: latestTask,
          toolResults: toolResults,
          existingTargetPaths: existingWorkspaceTargets,
        );
    if (!canPromote) {
      return false;
    }

    final progress = currentConversation.executionProgressForTask(
      latestTask.id,
    );
    final summary =
        progress?.normalizedValidationSummary ??
        progress?.normalizedSummary ??
        'Marked complete after the saved validation succeeded and every target file existed in the workspace.';
    await _markTaskCompletedFromToolEvidence(
      task: latestTask,
      conversationsNotifier: ref.read(conversationsNotifierProvider.notifier),
      completionAssessment: completionAssessment,
      summary: summary,
    );
    return true;
  }

  Future<bool> _maybeRecoverFromPythonSrcLayoutValidationFailure({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!mounted) {
      return false;
    }
    if (toolResults.isEmpty || !_toolResultsContainFailure(toolResults)) {
      return false;
    }

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed ||
        latestTask.status == ConversationWorkflowTaskStatus.blocked) {
      return false;
    }

    final failedCommand =
        ConversationPlanExecutionGuardrails.failedPythonValidationCommand(
          task: latestTask,
          toolResults: toolResults,
        );
    if (failedCommand == null) {
      return false;
    }

    final retryCommand =
        ConversationPlanExecutionGuardrails.suggestPythonSrcLayoutRetryCommand(
          task: latestTask,
          failedCommand: failedCommand,
        );
    if (retryCommand == null) {
      return false;
    }

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    await chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildPythonSrcLayoutValidationRecoveryPrompt(
        task: latestTask,
        failedCommand: failedCommand,
        retryCommand: retryCommand,
        blockedModuleName:
            ConversationPlanExecutionGuardrails.blockedPythonImportModule(
              toolResults,
            ),
      ),
      languageCode: languageCode,
    );

    final recoveryToolResults = chatNotifier.takeLatestToolResults();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: recoveryToolResults,
        );
    if (toolResultApplied || _taskReachedTerminalStatus(latestTask.id)) {
      return true;
    }

    final assistantResult =
        await _captureExecutionProgressFromLatestAssistantEvidence(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          isValidationRun: false,
          fallbackAssistantResponse: chatNotifier
              .takeLatestHiddenAssistantResponse(),
        );
    if (!assistantResult) {
      return false;
    }

    if (!mounted) {
      return false;
    }
    final refreshedConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (refreshedConversation == null) {
      return false;
    }
    final refreshedTask = refreshedConversation.projectedExecutionTasks
        .where((item) => item.id == latestTask.id)
        .firstOrNull;
    if (refreshedTask == null) {
      return false;
    }
    return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
        refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
  }

  Future<bool> _captureExecutionProgressFromLatestAssistantEvidence({
    required ConversationWorkflowTask task,
    required String? previousAssistantMessageId,
    required bool isValidationRun,
    String? fallbackAssistantResponse,
  }) async {
    if (!mounted) {
      return false;
    }
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return false;
    }

    final latestAssistantMessage = _latestAssistantMessage(currentConversation);
    final latestAssistantResponse =
        latestAssistantMessage != null &&
            latestAssistantMessage.id != previousAssistantMessageId
        ? latestAssistantMessage.content
        : '';
    final fallback = fallbackAssistantResponse?.trim() ?? '';
    if (latestAssistantResponse.trim().isEmpty && fallback.isEmpty) {
      return false;
    }

    final assistantInference = ConversationExecutionProgressInference.infer(
      assistantResponse: latestAssistantResponse,
      task: task,
      isValidationRun: isValidationRun,
      fallbackAssistantResponse: fallback,
    );
    final futureTaskTitles = currentConversation.projectedExecutionTasks
        .where((item) => item.id != task.id)
        .where(
          (item) => item.status != ConversationWorkflowTaskStatus.completed,
        )
        .map((item) => item.title.trim())
        .where((title) => title.isNotEmpty)
        .toList(growable: false);
    final assistantResponses = [latestAssistantResponse, fallback]
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final completionEvidence =
        ConversationPlanExecutionGuardrails.assistantMentionsTaskCompletionInAnyResponse(
          task: task,
          assistantResponses: assistantResponses,
        );
    final handoffEvidence =
        ConversationPlanExecutionGuardrails.assistantMentionsTaskHandoffInAnyResponse(
          task: task,
          assistantResponses: assistantResponses,
          futureTaskTitles: futureTaskTitles,
        );
    if (!isValidationRun &&
        completionEvidence &&
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceTargets(
          task: task,
          existingTargetPaths: _existingWorkspaceTargetFiles(task),
        )) {
      final currentProgress = currentConversation.executionProgressForTask(
        task.id,
      );
      final summary =
          assistantInference.status == ConversationWorkflowTaskStatus.completed
          ? assistantInference.summary
          : 'Marked complete after the assistant confirmed the saved task and every current target file already existed in the workspace.';
      await conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: task.id,
        status: ConversationWorkflowTaskStatus.completed,
        summary: summary,
        validationStatus:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? ConversationExecutionValidationStatus.passed
            : null,
        lastValidationAt:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? DateTime.now()
            : null,
        lastValidationCommand:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? currentProgress?.normalizedValidationCommand
            : null,
        lastValidationSummary:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? currentProgress?.normalizedValidationSummary
            : null,
        eventType: ConversationExecutionTaskEventType.completed,
        eventSummary: summary,
      );
      return true;
    }
    if (!isValidationRun &&
        handoffEvidence &&
        assistantInference.status == ConversationWorkflowTaskStatus.completed &&
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceTargets(
          task: task,
          existingTargetPaths: _existingWorkspaceTargetFiles(task),
        )) {
      final currentProgress = currentConversation.executionProgressForTask(
        task.id,
      );
      await conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: task.id,
        status: ConversationWorkflowTaskStatus.completed,
        summary: assistantInference.summary,
        validationStatus:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? ConversationExecutionValidationStatus.passed
            : null,
        lastValidationAt:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? DateTime.now()
            : null,
        lastValidationCommand:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? currentProgress?.normalizedValidationCommand
            : null,
        lastValidationSummary:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? currentProgress?.normalizedValidationSummary
            : null,
        eventType: ConversationExecutionTaskEventType.completed,
        eventSummary: assistantInference.summary,
      );
      return true;
    }

    await conversationsNotifier
        .updateCurrentExecutionTaskProgressFromAssistantTurn(
          task: task,
          assistantResponse: latestAssistantResponse,
          isValidationRun: isValidationRun,
          fallbackAssistantResponse: fallback,
        );
    return true;
  }

  Future<bool> _captureExecutionProgressFromLatestToolResults({
    required ConversationWorkflowTask task,
    required String? previousAssistantMessageId,
    required List<ToolResultInfo> toolResults,
    String? fallbackAssistantResponse,
  }) async {
    if (!mounted) {
      return false;
    }
    if (toolResults.isEmpty) {
      return false;
    }

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return false;
    }

    final latestAssistantMessage = _latestAssistantMessage(currentConversation);
    final latestAssistantResponse =
        latestAssistantMessage == null ||
            latestAssistantMessage.id == previousAssistantMessageId
        ? ''
        : latestAssistantMessage.content;
    final fallbackAssistantEvidence = fallbackAssistantResponse?.trim() ?? '';
    final assistantInference = ConversationExecutionProgressInference.infer(
      assistantResponse: latestAssistantResponse,
      task: task,
      isValidationRun: false,
      fallbackAssistantResponse: fallbackAssistantEvidence,
    );
    final completionAssessment =
        ConversationPlanExecutionGuardrails.assessTaskCompletion(
          task: task,
          toolResults: toolResults,
          changedFilePaths: _latestTurnChangedFilePaths(),
        );
    final existingWorkspaceTargets = _existingWorkspaceTargetFiles(task);
    final futureTaskTitles = currentConversation.projectedExecutionTasks
        .where((item) => item.id != task.id)
        .where(
          (item) => item.status != ConversationWorkflowTaskStatus.completed,
        )
        .map((item) => item.title.trim())
        .where((title) => title.isNotEmpty)
        .toList(growable: false);
    final assistantResponses =
        [latestAssistantResponse, fallbackAssistantEvidence]
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
    final handoffAssistantResponse = assistantResponses.firstWhere(
      (response) =>
          ConversationPlanExecutionGuardrails.assistantMentionsTaskHandoff(
            task: task,
            assistantResponse: response,
            futureTaskTitles: futureTaskTitles,
          ),
      orElse: () => latestAssistantResponse.isNotEmpty
          ? latestAssistantResponse
          : fallbackAssistantEvidence,
    );
    final handoffEvidence =
        ConversationPlanExecutionGuardrails.assistantMentionsTaskHandoffInAnyResponse(
          task: task,
          assistantResponses: assistantResponses,
          futureTaskTitles: futureTaskTitles,
        );
    final currentProgress = currentConversation.executionProgressForTask(
      task.id,
    );
    final currentValidationHandoffEvidence =
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromCurrentValidationHandoff(
          task: task,
          toolResults: toolResults,
          assistantResponse: handoffAssistantResponse,
          futureTaskTitles: futureTaskTitles,
        );
    final historicalValidationHandoffEvidence =
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromHistoricalValidationHandoff(
          task: task,
          progress: currentProgress,
          assistantResponse: handoffAssistantResponse,
          futureTaskTitles: futureTaskTitles,
        );
    final onlyRecoverableMalformedFailures =
        ConversationPlanExecutionGuardrails.hasOnlyRecoverableMalformedFailures(
          toolResults,
        );
    final onlyUnavailableToolFailures =
        ConversationPlanExecutionGuardrails.hasOnlyUnavailableToolFailures(
          toolResults,
        );
    final recoverableMissingTargetFile =
        ConversationPlanExecutionGuardrails.missingTargetFileFromValidationFailure(
          task: task,
          toolResults: toolResults,
        );
    final validationToolInference =
        ConversationValidationToolResultInference.infer(
          task: task,
          toolResults: toolResults
              .map(
                (result) => ConversationValidationToolResultInput(
                  toolName: result.name,
                  rawResult: result.result,
                ),
              )
              .toList(growable: false),
        );
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    if (validationToolInference != null &&
        (validationToolInference.status ==
                ConversationWorkflowTaskStatus.completed ||
            validationToolInference.validationStatus ==
                ConversationExecutionValidationStatus.passed)) {
      final validationProgressUpdated = await conversationsNotifier
          .updateCurrentValidationProgressFromToolResults(
            task: task,
            toolResults: toolResults
                .map(
                  (result) => ConversationValidationToolResultInput(
                    toolName: result.name,
                    rawResult: result.result,
                  ),
                )
                .toList(growable: false),
          );
      if (validationProgressUpdated && _taskReachedTerminalStatus(task.id)) {
        return true;
      }
    }
    if (ConversationPlanExecutionCoordinator.looksLikeVerificationTask(task) &&
        completionAssessment.successfulValidationCommands.isNotEmpty) {
      final validationProgressUpdated = await conversationsNotifier
          .updateCurrentValidationProgressFromToolResults(
            task: task,
            toolResults: toolResults
                .map(
                  (result) => ConversationValidationToolResultInput(
                    toolName: result.name,
                    rawResult: result.result,
                  ),
                )
                .toList(growable: false),
          );
      if (validationProgressUpdated && _taskReachedTerminalStatus(task.id)) {
        return true;
      }
    }
    if (completionAssessment.hasCompletionEvidenceIgnoringFailures &&
        onlyRecoverableMalformedFailures) {
      final summary =
          assistantInference.status == ConversationWorkflowTaskStatus.completed
          ? assistantInference.summary
          : 'Ignored recoverable malformed tool failures after the saved task had already met its completion evidence.';
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: summary,
      );
      return true;
    }
    if (!_toolResultsContainFailure(toolResults) &&
        await _maybeFinalizeScaffoldFromWorkspaceTargets(task: task)) {
      return true;
    }
    if (ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceValidation(
      task: task,
      toolResults: toolResults,
      existingTargetPaths: existingWorkspaceTargets,
    )) {
      await conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: task.id,
        status: ConversationWorkflowTaskStatus.completed,
        summary:
            'Marked complete after the saved validation succeeded and every target file already existed in the workspace.',
        validationStatus: ConversationExecutionValidationStatus.passed,
        lastValidationAt: DateTime.now(),
        lastValidationCommand:
            completionAssessment.successfulValidationCommands.firstOrNull ??
            task.validationCommand,
        lastValidationSummary:
            'Marked complete after the saved validation succeeded and every target file already existed in the workspace.',
        eventType: ConversationExecutionTaskEventType.completed,
        eventSummary:
            'Marked complete after the saved validation succeeded and every target file already existed in the workspace.',
      );
      return true;
    }
    if (ConversationPlanExecutionGuardrails.canPromoteScaffoldCompletionFromWorkspaceValidation(
      task: task,
      toolResults: toolResults,
      existingTargetPaths: existingWorkspaceTargets,
    )) {
      await conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: task.id,
        status: ConversationWorkflowTaskStatus.completed,
        summary:
            'Marked complete after the saved validation succeeded and every scaffold target file already existed in the workspace.',
        validationStatus: ConversationExecutionValidationStatus.passed,
        lastValidationAt: DateTime.now(),
        lastValidationCommand:
            completionAssessment.successfulValidationCommands.firstOrNull ??
            task.validationCommand,
        lastValidationSummary:
            'Marked complete after the saved validation succeeded and every scaffold target file already existed in the workspace.',
        eventType: ConversationExecutionTaskEventType.completed,
        eventSummary:
            'Marked complete after the saved validation succeeded and every scaffold target file already existed in the workspace.',
      );
      return true;
    }
    if (ConversationPlanExecutionCoordinator.looksLikeVerificationTask(task) &&
        completionAssessment.successfulValidationCommands.isNotEmpty &&
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceTargets(
          task: task,
          existingTargetPaths: existingWorkspaceTargets,
        )) {
      final summary =
          assistantInference.status == ConversationWorkflowTaskStatus.completed
          ? assistantInference.summary
          : currentProgress?.normalizedValidationSummary ??
                'Marked complete after the saved verification command succeeded.';
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: summary,
      );
      return true;
    }
    if (completionAssessment.hasCompletionEvidenceIgnoringFailures &&
        completionAssessment.successfulValidationCommands.isNotEmpty &&
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceTargets(
          task: task,
          existingTargetPaths: existingWorkspaceTargets,
        )) {
      final summary =
          currentProgress?.normalizedValidationSummary ??
          currentProgress?.normalizedSummary;
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: summary == null || summary.isEmpty
            ? 'Marked complete after the saved validation succeeded and the current target files already existed in the workspace.'
            : summary,
      );
      return true;
    }
    if (currentValidationHandoffEvidence) {
      final validationSummary =
          currentProgress?.normalizedValidationSummary ?? '';
      final summary = validationSummary.isNotEmpty
          ? validationSummary
          : 'Marked complete after the saved validation succeeded before the assistant moved on to a later saved task.';
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: summary,
      );
      return true;
    }
    if (ConversationPlanExecutionGuardrails.canPromoteCompletionFromTaskHandoff(
      task: task,
      toolResults: toolResults,
      assistantResponse: handoffAssistantResponse,
      futureTaskTitles: futureTaskTitles,
    )) {
      final summary =
          assistantInference.status == ConversationWorkflowTaskStatus.completed
          ? assistantInference.summary
          : 'Marked complete after the assistant finished the current saved task and moved on to a later task in the same turn.';
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: summary,
      );
      return true;
    }
    if (handoffEvidence &&
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceTargets(
          task: task,
          existingTargetPaths: existingWorkspaceTargets,
        ) &&
        (!_toolResultsContainFailure(toolResults) ||
            onlyUnavailableToolFailures)) {
      final summary =
          assistantInference.status == ConversationWorkflowTaskStatus.completed
          ? assistantInference.summary
          : 'Marked complete after the assistant moved on to a later saved task and every current target file already existed in the workspace.';
      await conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: task.id,
        status: ConversationWorkflowTaskStatus.completed,
        summary: summary,
        eventType: ConversationExecutionTaskEventType.completed,
        eventSummary: summary,
      );
      return true;
    }
    if (historicalValidationHandoffEvidence) {
      final summary =
          currentProgress?.normalizedValidationSummary ??
          currentProgress?.normalizedSummary ??
          assistantInference.summary;
      await conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: task.id,
        status: ConversationWorkflowTaskStatus.completed,
        summary: summary.isEmpty
            ? 'Marked complete after a passed saved validation and a later saved-task handoff.'
            : summary,
        validationStatus: ConversationExecutionValidationStatus.passed,
        lastValidationAt: DateTime.now(),
        lastValidationCommand:
            currentProgress?.normalizedValidationCommand ??
            task.validationCommand,
        lastValidationSummary: summary.isEmpty
            ? 'Marked complete after a passed saved validation and a later saved-task handoff.'
            : summary,
        eventType: ConversationExecutionTaskEventType.completed,
        eventSummary: summary.isEmpty
            ? 'Marked complete after a passed saved validation and a later saved-task handoff.'
            : summary,
      );
      return true;
    }
    if (assistantInference.status == ConversationWorkflowTaskStatus.completed &&
        completionAssessment.hasCompletionEvidenceIgnoringFailures) {
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: assistantInference.summary,
      );
      return true;
    }
    if (!_toolResultsContainFailure(toolResults) &&
        completionAssessment.shouldMarkCompleted) {
      final summary = completionAssessment.completedFromSuccessfulValidation
          ? 'Marked complete from saved target file changes and a successful validation result.'
          : completionAssessment.touchedAllTargetFiles &&
                completionAssessment.hasTargetFiles
          ? 'Marked complete after covering every saved target file.'
          : 'Marked complete from saved target file changes.';
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: summary,
      );
      return true;
    }
    if (assistantInference.status == ConversationWorkflowTaskStatus.blocked &&
        recoverableMissingTargetFile == null) {
      await conversationsNotifier
          .updateCurrentExecutionTaskProgressFromAssistantTurn(
            task: task,
            assistantResponse: latestAssistantResponse,
            isValidationRun: false,
            fallbackAssistantResponse: fallbackAssistantEvidence,
          );
      return true;
    }
    final shouldLockCompletedTaskBeforeNextToolWork =
        assistantInference.status == ConversationWorkflowTaskStatus.completed &&
        !_toolResultsContainFailure(toolResults) &&
        completionAssessment.touchedTargetFiles.isNotEmpty &&
        completionAssessment.unrelatedTouchedPaths.isNotEmpty;
    if (shouldLockCompletedTaskBeforeNextToolWork) {
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: assistantInference.summary,
      );
      return true;
    }
    if (_toolResultsContainFailure(toolResults)) {
      return false;
    }
    return false;
  }

  Future<void> _markTaskCompletedFromToolEvidence({
    required ConversationWorkflowTask task,
    required ConversationsNotifier conversationsNotifier,
    required ConversationPlanExecutionCompletionAssessment completionAssessment,
    required String summary,
  }) async {
    final normalizedSummary = summary.trim().isEmpty
        ? 'Marked complete from saved task evidence.'
        : summary.trim();
    final successfulValidationCommand =
        completionAssessment.successfulValidationCommands.firstOrNull;
    await conversationsNotifier.updateCurrentExecutionTaskProgress(
      taskId: task.id,
      status: ConversationWorkflowTaskStatus.completed,
      summary: normalizedSummary,
      validationStatus: successfulValidationCommand == null
          ? null
          : ConversationExecutionValidationStatus.passed,
      lastValidationAt: successfulValidationCommand == null
          ? null
          : DateTime.now(),
      lastValidationCommand:
          successfulValidationCommand ?? task.validationCommand,
      lastValidationSummary: successfulValidationCommand == null
          ? null
          : normalizedSummary,
      eventType: ConversationExecutionTaskEventType.completed,
      eventSummary: normalizedSummary,
    );
  }

  bool _toolResultsContainFailure(List<ToolResultInfo> toolResults) {
    for (final toolResult in toolResults) {
      final normalized = toolResult.result.trim().toLowerCase();
      if (normalized.isEmpty) {
        continue;
      }
      Object? decoded;
      if (normalized.startsWith('{')) {
        try {
          decoded = jsonDecode(toolResult.result);
        } catch (_) {
          decoded = null;
        }
      }
      if (decoded is Map<String, dynamic>) {
        final exitCode = decoded['exit_code'];
        if (exitCode is num && exitCode != 0) {
          return true;
        }
        if (decoded['success'] == false || decoded['isSuccess'] == false) {
          return true;
        }
        final errorText = decoded['error']?.toString().trim() ?? '';
        final errorMessage = decoded['errorMessage']?.toString().trim() ?? '';
        if (errorText.isNotEmpty || errorMessage.isNotEmpty) {
          return true;
        }
        if (CodingCommandOutputGuardrailService.commandResultReportsOutputIssue(
          toolResult.result,
        )) {
          return true;
        }
      }
      if (normalized.startsWith('error:') ||
          normalized.contains('failed to') ||
          normalized.contains('no matching tool available') ||
          normalized.contains('"error":') ||
          normalized.contains('"issuccess":false') ||
          normalized.contains('"success":false') ||
          normalized.contains('"errormessage"')) {
        return true;
      }
    }
    return false;
  }

  Message? _latestAssistantMessage(Conversation conversation) {
    for (final message in conversation.messages.reversed) {
      if (message.role == MessageRole.assistant &&
          !message.isStreaming &&
          message.content.trim().isNotEmpty) {
        return message;
      }
    }
    return null;
  }

  String? _latestAssistantMessageId(Conversation conversation) =>
      _latestAssistantMessage(conversation)?.id;

  List<String> _latestTurnChangedFilePaths() {
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return const [];
    }
    final diff = currentConversation.effectiveTurnDiffs.lastOrNull;
    return diff?.changedFilePaths ?? const [];
  }

  bool _taskReachedTerminalStatus(String taskId) {
    if (!mounted) {
      return false;
    }
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    final latestTask = currentConversation?.projectedExecutionTasks
        .where((task) => task.id == taskId)
        .firstOrNull;
    if (latestTask == null) {
      return false;
    }
    return latestTask.status == ConversationWorkflowTaskStatus.completed ||
        latestTask.status == ConversationWorkflowTaskStatus.blocked;
  }

  String _workflowProjectionStatusLabelKey(Conversation currentConversation) {
    if (currentConversation.isWorkflowProjectionFresh) {
      return 'chat.plan_document_projection_fresh';
    }
    if (currentConversation.isWorkflowProjectionStale) {
      return 'chat.plan_document_projection_stale';
    }
    return 'chat.plan_document_projection_unavailable';
  }

  String _planDocumentEditLabelKey(
    Conversation currentConversation, {
    required bool isPlanMode,
  }) {
    final artifact = currentConversation.effectivePlanArtifact;
    if (isPlanMode || artifact.hasPendingEdits) {
      return 'chat.plan_document_edit_draft';
    }
    if (artifact.hasApproved) {
      return 'chat.plan_document_edit_approved';
    }
    return 'chat.plan_document_edit';
  }

  String _planDocumentHeaderEditTooltipKey(
    Conversation currentConversation, {
    required bool isPlanMode,
  }) {
    final artifact = currentConversation.effectivePlanArtifact;
    if (isPlanMode || artifact.hasPendingEdits) {
      return 'chat.plan_document_edit_draft';
    }
    if (artifact.hasApproved) {
      return 'chat.plan_document_edit_approved';
    }
    return 'chat.plan_document_edit';
  }

  Color _workflowProjectionStatusColor(
    BuildContext context,
    Conversation currentConversation,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (currentConversation.isWorkflowProjectionFresh) {
      return Colors.green.shade700;
    }
    if (currentConversation.isWorkflowProjectionStale) {
      return scheme.tertiary;
    }
    return scheme.error;
  }

  String _workflowStageLabel(ConversationWorkflowStage stage) {
    return switch (stage) {
      ConversationWorkflowStage.idle => 'chat.workflow_stage_idle'.tr(),
      ConversationWorkflowStage.clarify => 'chat.workflow_stage_clarify'.tr(),
      ConversationWorkflowStage.plan => 'chat.workflow_stage_plan'.tr(),
      ConversationWorkflowStage.tasks => 'chat.workflow_stage_tasks'.tr(),
      ConversationWorkflowStage.implement =>
        'chat.workflow_stage_implement'.tr(),
      ConversationWorkflowStage.review => 'chat.workflow_stage_review'.tr(),
    };
  }

  String _workflowTaskStatusLabel(ConversationWorkflowTaskStatus status) {
    return switch (status) {
      ConversationWorkflowTaskStatus.pending =>
        'chat.workflow_task_status_pending'.tr(),
      ConversationWorkflowTaskStatus.inProgress =>
        'chat.workflow_task_status_in_progress'.tr(),
      ConversationWorkflowTaskStatus.completed =>
        'chat.workflow_task_status_completed'.tr(),
      ConversationWorkflowTaskStatus.blocked =>
        'chat.workflow_task_status_blocked'.tr(),
    };
  }

  String _workflowValidationStatusLabel(
    ConversationExecutionValidationStatus status,
  ) {
    return switch (status) {
      ConversationExecutionValidationStatus.unknown =>
        'chat.workflow_task_validation_status_unknown'.tr(),
      ConversationExecutionValidationStatus.passed =>
        'chat.workflow_task_validation_status_passed'.tr(),
      ConversationExecutionValidationStatus.failed =>
        'chat.workflow_task_validation_status_failed'.tr(),
    };
  }

  String _workflowTaskEventLabel(ConversationExecutionTaskEventType type) {
    return switch (type) {
      ConversationExecutionTaskEventType.started =>
        'chat.workflow_task_event_started'.tr(),
      ConversationExecutionTaskEventType.validated =>
        'chat.workflow_task_event_validated'.tr(),
      ConversationExecutionTaskEventType.blocked =>
        'chat.workflow_task_event_blocked'.tr(),
      ConversationExecutionTaskEventType.unblocked =>
        'chat.workflow_task_event_unblocked'.tr(),
      ConversationExecutionTaskEventType.completed =>
        'chat.workflow_task_event_completed'.tr(),
      ConversationExecutionTaskEventType.replanned =>
        'chat.workflow_task_event_replanned'.tr(),
    };
  }

  String _workflowTaskEventSummary(
    BuildContext context,
    ConversationExecutionTaskEvent event,
  ) {
    final timestamp = DateFormat(
      'MM/dd HH:mm',
    ).format(event.createdAt.toLocal());
    final summary =
        event.normalizedSummary ??
        event.normalizedValidationSummary ??
        event.normalizedBlockedReason ??
        _workflowTaskStatusLabel(event.status);
    return '$timestamp · ${_workflowTaskEventLabel(event.type)} · $summary';
  }

  String _planDocumentDiffEntryLabel(
    BuildContext context,
    ConversationPlanTaskDiffEntry entry,
  ) {
    final prefix = switch (entry.type) {
      ConversationPlanTaskDiffType.added =>
        'chat.plan_document_diff_entry_added'.tr(),
      ConversationPlanTaskDiffType.removed =>
        'chat.plan_document_diff_entry_removed'.tr(),
      ConversationPlanTaskDiffType.changed =>
        'chat.plan_document_diff_entry_changed'.tr(),
    };
    final beforeTitle = entry.beforeTask?.title.trim();
    final afterTitle = entry.afterTask?.title.trim();

    if (entry.type == ConversationPlanTaskDiffType.changed &&
        beforeTitle != null &&
        afterTitle != null &&
        beforeTitle != afterTitle) {
      return '$prefix: $beforeTitle -> $afterTitle';
    }
    return '$prefix: ${entry.displayTitle}';
  }

  Color _workflowTaskStatusColor(
    BuildContext context,
    ConversationWorkflowTaskStatus status,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      ConversationWorkflowTaskStatus.pending => scheme.secondary,
      ConversationWorkflowTaskStatus.inProgress => scheme.primary,
      ConversationWorkflowTaskStatus.completed => Colors.green.shade700,
      ConversationWorkflowTaskStatus.blocked => scheme.error,
    };
  }

  ConversationWorkflowStage? _recommendedWorkflowStage(
    ConversationWorkflowStage stage,
  ) {
    return switch (stage) {
      ConversationWorkflowStage.idle => ConversationWorkflowStage.clarify,
      ConversationWorkflowStage.clarify => ConversationWorkflowStage.plan,
      ConversationWorkflowStage.plan => ConversationWorkflowStage.tasks,
      ConversationWorkflowStage.tasks => ConversationWorkflowStage.implement,
      ConversationWorkflowStage.implement => ConversationWorkflowStage.review,
      ConversationWorkflowStage.review => null,
    };
  }

  Future<void> _showSshConnectDialog(
    BuildContext context,
    PendingSshConnect pending,
  ) async {
    final hostController = TextEditingController(text: pending.host);
    final portController = TextEditingController(text: pending.port.toString());
    final usernameController = TextEditingController(text: pending.username);
    final passwordController = TextEditingController(
      text: pending.savedPassword ?? '',
    );
    var savePassword = pending.savedPassword != null;
    var obscure = true;
    final hasSavedHint = pending.savedPassword != null;

    final approval = await showModalBottomSheet<SshConnectApproval>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: DraggableScrollableSheet(
                initialChildSize: 0.65,
                minChildSize: 0.4,
                maxChildSize: 0.9,
                builder: (_, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 4),
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        // Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.terminal_rounded,
                                  color: theme.colorScheme.onPrimaryContainer,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SSH Connection',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    Text(
                                      'Authenticate to remote server',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    Navigator.pop(sheetContext, null),
                                icon: const Icon(Icons.close_rounded),
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      theme.colorScheme.surfaceContainerHighest,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 24),
                        // Form fields
                        Expanded(
                          child: ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            children: [
                              // Host & Port in a row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: hostController,
                                      decoration: InputDecoration(
                                        labelText: 'Host',
                                        prefixIcon: const Icon(
                                          Icons.dns_rounded,
                                          size: 20,
                                        ),
                                        filled: true,
                                        fillColor: theme
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.5),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: theme.colorScheme.outline
                                                .withValues(alpha: 0.2),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: theme.colorScheme.primary,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 1,
                                    child: TextField(
                                      controller: portController,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'Port',
                                        filled: true,
                                        fillColor: theme
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.5),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: theme.colorScheme.outline
                                                .withValues(alpha: 0.2),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: theme.colorScheme.primary,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: usernameController,
                                decoration: InputDecoration(
                                  labelText: 'Username',
                                  prefixIcon: const Icon(
                                    Icons.person_rounded,
                                    size: 20,
                                  ),
                                  filled: true,
                                  fillColor: theme
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.outline
                                          .withValues(alpha: 0.2),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.primary,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: passwordController,
                                obscureText: obscure,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  helperText: hasSavedHint ? '(saved)' : null,
                                  prefixIcon: const Icon(
                                    Icons.lock_rounded,
                                    size: 20,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      obscure
                                          ? Icons.visibility_rounded
                                          : Icons.visibility_off_rounded,
                                    ),
                                    onPressed: () =>
                                        setState(() => obscure = !obscure),
                                  ),
                                  filled: true,
                                  fillColor: theme
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.outline
                                          .withValues(alpha: 0.2),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.primary,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Save password toggle
                              Container(
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SwitchListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  secondary: Icon(
                                    Icons.save_rounded,
                                    size: 20,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  title: Text(
                                    'Save password',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  subtitle: Text(
                                    'Store in secure keychain',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  value: savePassword,
                                  onChanged: (v) =>
                                      setState(() => savePassword = v),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                        // Bottom action buttons
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            8,
                            24,
                            16 + MediaQuery.of(sheetContext).padding.bottom,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      Navigator.pop(sheetContext, null),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    side: BorderSide(
                                      color: theme.colorScheme.outline
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text('common.cancel'.tr()),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: FilledButton.icon(
                                  onPressed: () {
                                    final host = hostController.text.trim();
                                    final port =
                                        int.tryParse(
                                          portController.text.trim(),
                                        ) ??
                                        22;
                                    final username = usernameController.text
                                        .trim();
                                    final password = passwordController.text;
                                    if (host.isEmpty ||
                                        username.isEmpty ||
                                        password.isEmpty) {
                                      ScaffoldMessenger.of(
                                        sheetContext,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Host, username and password are required',
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      return;
                                    }
                                    Navigator.pop(
                                      sheetContext,
                                      SshConnectApproval(
                                        host: host,
                                        port: port,
                                        username: username,
                                        password: password,
                                        savePassword: savePassword,
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.login_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Connect'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );

    hostController.dispose();
    portController.dispose();
    usernameController.dispose();
    passwordController.dispose();

    ref
        .read(chatNotifierProvider.notifier)
        .resolveSshConnect(id: pending.id, approval: approval);
  }

  Future<void> _showSshCommandDialog(
    BuildContext context,
    PendingSshCommand pending,
  ) async {
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.shield_rounded,
                          color: theme.colorScheme.onErrorContainer,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Command Approval',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${pending.username}@${pending.host}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                const ToolPerimeterSummary(toolName: 'ssh_execute_command'),
                const SizedBox(height: 12),
                // Reason (if any)
                if (pending.reason != null && pending.reason!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pending.reason!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Command display
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(
                          alpha: 0.15,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '\$',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SelectableText(
                            pending.command,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              height: 1.5,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Bottom action buttons
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    0,
                    24,
                    16 + MediaQuery.of(sheetContext).padding.bottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          icon: const Icon(Icons.block_rounded, size: 18),
                          label: const Text('Deny'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('Approve & Run'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            backgroundColor: theme.colorScheme.error,
                            foregroundColor: theme.colorScheme.onError,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    ref
        .read(chatNotifierProvider.notifier)
        .resolveSshCommand(id: pending.id, approved: approved ?? false);
  }

  Future<void> _showGitCommandDialog(
    BuildContext context,
    PendingGitCommand pending,
  ) async {
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.merge_type_rounded,
                          color: theme.colorScheme.onErrorContainer,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Git Command Approval',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              pending.workingDirectory,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                const ToolPerimeterSummary(toolName: 'git_execute_command'),
                const SizedBox(height: 12),
                // Reason (if any)
                if (pending.reason != null && pending.reason!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pending.reason!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Command display
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(
                          alpha: 0.15,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '\$',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SelectableText(
                            _formatGitCommandForDisplay(pending.command),
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              height: 1.5,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Bottom action buttons
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    0,
                    24,
                    16 + MediaQuery.of(sheetContext).padding.bottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          icon: const Icon(Icons.block_rounded, size: 18),
                          label: const Text('Deny'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('Approve & Run'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            backgroundColor: theme.colorScheme.error,
                            foregroundColor: theme.colorScheme.onError,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    ref
        .read(chatNotifierProvider.notifier)
        .resolveGitCommand(id: pending.id, approved: approved ?? false);
  }

  Future<void> _showLocalCommandDialog(
    BuildContext context,
    PendingLocalCommand pending,
  ) async {
    final approval = await showModalBottomSheet<LocalCommandApproval>(
      context: context,
      isDismissible: false,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.terminal_rounded,
                          color: theme.colorScheme.onErrorContainer,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Local Command Approval',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              pending.workingDirectory,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                const ToolPerimeterSummary(toolName: 'local_execute_command'),
                const SizedBox(height: 12),
                if (pending.reason != null && pending.reason!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pending.reason!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (pending.warningTitle != null &&
                    pending.warningTitle!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withValues(
                          alpha: 0.45,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.error.withValues(
                            alpha: 0.25,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 20,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pending.warningTitle!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                                if (pending.warningMessage != null &&
                                    pending.warningMessage!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    pending.warningMessage!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(
                          alpha: 0.15,
                        ),
                      ),
                    ),
                    child: SelectableText(
                      pending.command,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        height: 1.5,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    0,
                    24,
                    16 + MediaQuery.of(sheetContext).padding.bottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(
                            sheetContext,
                            const LocalCommandApproval(approved: false),
                          ),
                          icon: const Icon(Icons.block_rounded, size: 18),
                          label: const Text('Deny'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(
                            sheetContext,
                            const LocalCommandApproval(
                              approved: false,
                              rememberedRuleAction:
                                  LocalCommandPermissionAction.deny,
                              rememberedRuleMatch:
                                  LocalCommandPermissionMatch.exact,
                            ),
                          ),
                          icon: const Icon(
                            Icons.lock_outline_rounded,
                            size: 18,
                          ),
                          label: const Text('Always Deny'),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    0,
                    24,
                    16 + MediaQuery.of(sheetContext).padding.bottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(
                            sheetContext,
                            const LocalCommandApproval(approved: true),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('Approve & Run'),
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                            foregroundColor: theme.colorScheme.onError,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(
                            sheetContext,
                            const LocalCommandApproval(
                              approved: true,
                              rememberedRuleAction:
                                  LocalCommandPermissionAction.allow,
                              rememberedRuleMatch:
                                  LocalCommandPermissionMatch.exact,
                            ),
                          ),
                          icon: const Icon(Icons.verified_user_outlined),
                          label: const Text('Always Allow'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

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
    var unsafeArmed = !pending.requiresSmokeArming;
    var stopInProgress = false;
    String? stopStatus;
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final riskStyle = _computerUseRiskStyle(
          theme,
          pending.riskCategory,
          pending.toolName,
        );
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.92,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: riskStyle.containerColor.withValues(
                                  alpha: 0.6,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                riskStyle.icon,
                                color: riskStyle.iconColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pending.title,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    pending.toolName,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontFamily: 'monospace',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Chip(
                                    avatar: Icon(
                                      riskStyle.icon,
                                      size: 16,
                                      color: riskStyle.accentColor,
                                    ),
                                    label: Text(pending.riskLabel),
                                    visualDensity: VisualDensity.compact,
                                    side: BorderSide(
                                      color: riskStyle.accentColor.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 24),
                      ToolPerimeterSummary(toolName: pending.toolName),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          key: const ValueKey('computer-use-approval-scroll'),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      riskStyle.warningIcon,
                                      size: 20,
                                      color: riskStyle.accentColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        pending.warningMessage,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (pending.reason != null &&
                                  pending.reason!.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 18,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          pending.reason!,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (pending.targetSummary != null ||
                                  pending.targetDetails.isNotEmpty ||
                                  pending.exactTextPreview != null) ...[
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme
                                          .secondaryContainer
                                          .withValues(alpha: 0.38),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: theme.colorScheme.secondary
                                            .withValues(alpha: 0.22),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.control_camera_outlined,
                                              size: 18,
                                              color:
                                                  theme.colorScheme.secondary,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Target review',
                                              style: theme.textTheme.labelLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        if (pending.targetSummary != null &&
                                            pending
                                                .targetSummary!
                                                .isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Text(
                                            pending.targetSummary!,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSecondaryContainer,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ],
                                        if (pending
                                            .targetDetails
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          for (final detail
                                              in pending.targetDetails)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 3,
                                              ),
                                              child: SelectableText(
                                                detail,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: theme
                                                          .colorScheme
                                                          .onSecondaryContainer
                                                          .withValues(
                                                            alpha: 0.86,
                                                          ),
                                                      fontFamily: 'monospace',
                                                    ),
                                              ),
                                            ),
                                        ],
                                        if (pending.exactTextPreview !=
                                            null) ...[
                                          const SizedBox(height: 12),
                                          Text(
                                            'Exact text (${pending.exactTextLength ?? pending.exactTextPreview!.length} characters)',
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSecondaryContainer,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 6),
                                          Container(
                                            width: double.infinity,
                                            constraints: const BoxConstraints(
                                              maxHeight: 140,
                                            ),
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.surface
                                                  .withValues(alpha: 0.7),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: theme.colorScheme.outline
                                                    .withValues(alpha: 0.14),
                                              ),
                                            ),
                                            child: SingleChildScrollView(
                                              child: SelectableText(
                                                pending.exactTextPreview!,
                                                style: TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 12,
                                                  height: 1.35,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              if (pending.approvalBoundaries.isNotEmpty ||
                                  pending.approvalBlockerCodes.isNotEmpty ||
                                  pending.actionProposalNextAction != null) ...[
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: theme.colorScheme.outline
                                            .withValues(alpha: 0.18),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.rule_folder_outlined,
                                              size: 18,
                                              color: theme.colorScheme.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Approval boundaries',
                                              style: theme.textTheme.labelLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        if (pending
                                            .approvalBoundaries
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              for (final boundary
                                                  in pending.approvalBoundaries)
                                                Chip(
                                                  label: Text(
                                                    _computerUseBoundaryLabel(
                                                      boundary,
                                                    ),
                                                  ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                            ],
                                          ),
                                        ],
                                        if (pending
                                            .approvalBlockerCodes
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Text(
                                            'Blocked until: ${pending.approvalBlockerCodes.map(_computerUseBlockerLabel).join(', ')}',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color:
                                                      theme.colorScheme.error,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ],
                                        if (pending.actionProposalNextAction !=
                                                null &&
                                            pending
                                                .actionProposalNextAction!
                                                .isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            pending.actionProposalNextAction!,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              if (pending.visionObservationSummary != null) ...[
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.2),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.visibility_outlined,
                                          size: 20,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Latest observation context',
                                                style: theme
                                                    .textTheme
                                                    .labelLarge
                                                    ?.copyWith(
                                                      color: theme
                                                          .colorScheme
                                                          .onPrimaryContainer,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                pending
                                                    .visionObservationSummary!,
                                                style: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: theme
                                                          .colorScheme
                                                          .onPrimaryContainer,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                              if (pending
                                                  .visionObservationDetails
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                for (final detail
                                                    in pending
                                                        .visionObservationDetails)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 2,
                                                        ),
                                                    child: Text(
                                                      detail,
                                                      style: theme
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: theme
                                                                .colorScheme
                                                                .onPrimaryContainer
                                                                .withValues(
                                                                  alpha: 0.8,
                                                                ),
                                                            fontFamily:
                                                                'monospace',
                                                          ),
                                                    ),
                                                  ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: theme.colorScheme.outline
                                          .withValues(alpha: 0.15),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SelectableText(
                                        pending.summary,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 14,
                                          height: 1.5,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      if (pending.details.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        for (final detail in pending.details)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '• ',
                                                  style: TextStyle(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                    height: 1.4,
                                                  ),
                                                ),
                                                Expanded(
                                                  child: SelectableText(
                                                    detail,
                                                    style: TextStyle(
                                                      fontFamily: 'monospace',
                                                      fontSize: 12,
                                                      height: 1.4,
                                                      color: theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              if (pending.requiresSmokeArming) ...[
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: CheckboxListTile(
                                      value: unsafeArmed,
                                      onChanged: (value) {
                                        setSheetState(() {
                                          unsafeArmed = value ?? false;
                                        });
                                      },
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Arm this Computer Use action',
                                      ),
                                      subtitle: const Text(
                                        'I understand this can control the Mac and should run now.',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (!pending.emergencyStop) ...[
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      onPressed: stopInProgress
                                          ? null
                                          : () async {
                                              setSheetState(() {
                                                stopInProgress = true;
                                                stopStatus = null;
                                              });
                                              try {
                                                final result = await ref
                                                    .read(
                                                      macosComputerUseServiceProvider,
                                                    )
                                                    .stopHelperWork();
                                                final decoded = jsonDecode(
                                                  result,
                                                );
                                                final ok =
                                                    decoded is Map &&
                                                    decoded['ok'] != false;
                                                if (!sheetContext.mounted) {
                                                  return;
                                                }
                                                setSheetState(() {
                                                  stopStatus = ok
                                                      ? 'Emergency stop sent.'
                                                      : 'Emergency stop returned an error.';
                                                });
                                              } catch (error) {
                                                if (!sheetContext.mounted) {
                                                  return;
                                                }
                                                setSheetState(() {
                                                  stopStatus =
                                                      'Emergency stop failed.';
                                                });
                                              } finally {
                                                if (sheetContext.mounted) {
                                                  setSheetState(() {
                                                    stopInProgress = false;
                                                  });
                                                }
                                              }
                                            },
                                      icon: stopInProgress
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.stop_circle_outlined,
                                              size: 18,
                                            ),
                                      label: const Text('Stop Computer Use'),
                                    ),
                                  ),
                                ),
                                if (stopStatus != null) ...[
                                  const SizedBox(height: 4),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        stopStatus!,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          0,
                          24,
                          16 + MediaQuery.of(sheetContext).padding.bottom,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: stopInProgress
                                    ? null
                                    : () => Navigator.pop(sheetContext, false),
                                icon: const Icon(Icons.block_rounded, size: 18),
                                label: const Text('Deny'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed: unsafeArmed && !stopInProgress
                                    ? () => Navigator.pop(sheetContext, true)
                                    : null,
                                icon: Icon(riskStyle.approveIcon, size: 20),
                                label: Text(pending.approveLabel),
                                style: FilledButton.styleFrom(
                                  backgroundColor: riskStyle.buttonColor,
                                  foregroundColor:
                                      riskStyle.buttonForegroundColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    ref
        .read(chatNotifierProvider.notifier)
        .resolveComputerUseAction(
          id: pending.id,
          approved: approved ?? false,
          armed: unsafeArmed,
        );
  }

  _ComputerUseRiskStyle _computerUseRiskStyle(
    ThemeData theme,
    String riskCategory,
    String toolName,
  ) {
    final scheme = theme.colorScheme;
    return switch (riskCategory) {
      'observe' => _ComputerUseRiskStyle(
        icon: Icons.visibility_outlined,
        warningIcon: Icons.visibility_outlined,
        approveIcon: Icons.visibility_rounded,
        containerColor: scheme.primaryContainer,
        iconColor: scheme.onPrimaryContainer,
        accentColor: scheme.primary,
        buttonColor: scheme.primary,
        buttonForegroundColor: scheme.onPrimary,
      ),
      'sensitive' => _ComputerUseRiskStyle(
        icon: Icons.graphic_eq_rounded,
        warningIcon: Icons.hearing_outlined,
        approveIcon: Icons.mic_rounded,
        containerColor: scheme.errorContainer,
        iconColor: scheme.onErrorContainer,
        accentColor: scheme.error,
        buttonColor: scheme.error,
        buttonForegroundColor: scheme.onError,
      ),
      'recovery' => _ComputerUseRiskStyle(
        icon: Icons.health_and_safety_outlined,
        warningIcon: Icons.shield_outlined,
        approveIcon: Icons.stop_circle_outlined,
        containerColor: scheme.tertiaryContainer,
        iconColor: scheme.onTertiaryContainer,
        accentColor: scheme.tertiary,
        buttonColor: scheme.tertiary,
        buttonForegroundColor: scheme.onTertiary,
      ),
      'setup' => _ComputerUseRiskStyle(
        icon: Icons.settings_suggest_outlined,
        warningIcon: Icons.info_outline_rounded,
        approveIcon: Icons.arrow_forward_rounded,
        containerColor: scheme.secondaryContainer,
        iconColor: scheme.onSecondaryContainer,
        accentColor: scheme.secondary,
        buttonColor: scheme.secondary,
        buttonForegroundColor: scheme.onSecondary,
      ),
      _ => _ComputerUseRiskStyle(
        icon: switch (toolName) {
          'computer_type_text' ||
          'computer_press_key' => Icons.keyboard_rounded,
          'computer_switch_space' => Icons.swap_horiz_rounded,
          _ => Icons.ads_click_rounded,
        },
        warningIcon: Icons.warning_amber_rounded,
        approveIcon: Icons.check_rounded,
        containerColor: scheme.errorContainer,
        iconColor: scheme.onErrorContainer,
        accentColor: scheme.error,
        buttonColor: scheme.error,
        buttonForegroundColor: scheme.onError,
      ),
    };
  }

  String _computerUseBoundaryLabel(String boundary) {
    return switch (boundary) {
      'target' => 'Target',
      'exactText' => 'Exact text',
      'publicAction' => 'Public action',
      'systemAudio' => 'System audio',
      'secureField' => 'Secure field',
      'credential' => 'Credential',
      'payment' => 'Payment',
      'destructive' => 'Destructive action',
      _ => boundary,
    };
  }

  String _computerUseBlockerLabel(String blockerCode) {
    return switch (blockerCode) {
      'target_missing' => 'target selection',
      'exact_text_missing' => 'exact text',
      'separate_public_action_approval_required' =>
        'separate public action approval',
      'secure_field_target_blocked' => 'secure field target',
      'credential_target_blocked' => 'credential target',
      'payment_target_blocked' => 'payment target',
      'destructive_target_blocked' => 'destructive target',
      'action_policy_blocked' => 'target safety policy',
      _ => blockerCode,
    };
  }

  Future<void> _showFileOperationDialog(
    BuildContext context,
    PendingFileOperation pending,
  ) async {
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final preview = pending.preview.length > 3000
            ? '${pending.preview.substring(0, 3000)}\n...'
            : pending.preview;
        final isDiffPreview =
            preview.startsWith('--- ') && preview.contains('\n+++ ');
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.edit_note_rounded,
                          color: theme.colorScheme.onErrorContainer,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pending.operation,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              pending.path,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                ToolPerimeterSummary(
                  toolName: pending.operation.toLowerCase().contains('edit')
                      ? 'edit_file'
                      : 'write_file',
                ),
                const SizedBox(height: 12),
                if (pending.reason != null && pending.reason!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pending.reason!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isDiffPreview
                            ? 'chat.diff_preview'.tr()
                            : 'chat.preview'.tr(),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 280),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            preview,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              height: 1.5,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    0,
                    24,
                    16 + MediaQuery.of(sheetContext).padding.bottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          icon: const Icon(Icons.block_rounded, size: 18),
                          label: const Text('Deny'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          icon: const Icon(Icons.save_rounded, size: 20),
                          label: const Text('Approve Change'),
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                            foregroundColor: theme.colorScheme.onError,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    ref
        .read(chatNotifierProvider.notifier)
        .resolveFileOperation(id: pending.id, approved: approved ?? false);
  }

  Future<void> _showParticipantToolApprovalDialog(
    BuildContext context,
    PendingParticipantToolApproval pending,
  ) async {
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final roleLabel = pending.participantRoleLabel.trim();
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                20 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.manage_search_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'chat.participant_tool_approval_title'.tr(),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'chat.participant_tool_approval_message'.tr(
                      namedArgs: {
                        'participant': pending.participantName,
                        'tool': pending.toolName,
                      },
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (roleLabel.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _participantToolApprovalRow(
                      theme,
                      Icons.badge_outlined,
                      roleLabel,
                    ),
                  ],
                  if (pending.reason?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    _participantToolApprovalRow(
                      theme,
                      Icons.help_outline,
                      pending.reason!.trim(),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _participantToolApprovalRow(
                    theme,
                    Icons.data_object,
                    _participantToolApprovalArgumentsPreview(pending),
                    monospace: true,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(false),
                          child: Text(
                            'chat.participant_tool_approval_deny'.tr(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(sheetContext).pop(true),
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(
                            'chat.participant_tool_approval_approve'.tr(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    ref
        .read(chatNotifierProvider.notifier)
        .resolveParticipantToolApproval(
          id: pending.id,
          approved: approved ?? false,
        );
  }

  Widget _participantToolApprovalRow(
    ThemeData theme,
    IconData icon,
    String text, {
    bool monospace = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: monospace
                ? theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')
                : theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  String _participantToolApprovalArgumentsPreview(
    PendingParticipantToolApproval pending,
  ) {
    const maxLength = 1200;
    final encoded = const JsonEncoder.withIndent(
      '  ',
    ).convert(pending.arguments);
    if (encoded.length <= maxLength) {
      return encoded;
    }
    return '${encoded.substring(0, maxLength).trimRight()}\n...';
  }

  Future<void> _showBleConnectDialog(
    BuildContext context,
    PendingBleConnect pending,
  ) async {
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.bluetooth_rounded,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BLE Connection',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Connect to Bluetooth device?',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                // Device info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(
                          alpha: 0.15,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (pending.deviceName != null) ...[
                          Text(
                            pending.deviceName!,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          pending.deviceId,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Bottom action buttons
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    0,
                    24,
                    16 + MediaQuery.of(sheetContext).padding.bottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          icon: const Icon(Icons.block_rounded, size: 18),
                          label: const Text('Deny'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          icon: const Icon(
                            Icons.bluetooth_connected_rounded,
                            size: 20,
                          ),
                          label: const Text('Connect'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    ref
        .read(chatNotifierProvider.notifier)
        .resolveBleConnect(id: pending.id, approved: approved ?? false);
  }

  Future<void> _showSerialOpenDialog(
    BuildContext context,
    PendingSerialOpen pending,
  ) async {
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.cable_rounded,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Serial Port',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Open this serial port for read & write?',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                // Port info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(
                          alpha: 0.15,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pending.portName,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${pending.baudRate} baud',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'The assistant will be able to read from and write '
                          'to this device until the port is closed.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Bottom action buttons
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    0,
                    24,
                    16 + MediaQuery.of(sheetContext).padding.bottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          icon: const Icon(Icons.block_rounded, size: 18),
                          label: const Text('Deny'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          icon: const Icon(Icons.cable_rounded, size: 20),
                          label: const Text('Open'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    ref
        .read(chatNotifierProvider.notifier)
        .resolveSerialOpen(id: pending.id, approved: approved ?? false);
  }
}
