import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../../../core/types/workspace_mode.dart';
import '../providers/coding_projects_notifier.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/chat_remote_datasource.dart';
import '../../data/datasources/git_tools.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_plan_artifact.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/entities/message.dart';
import '../../domain/services/conversation_plan_diff_service.dart';
import '../../domain/services/conversation_plan_document_builder.dart';
import '../../domain/services/conversation_execution_progress_inference.dart';
import '../../domain/services/conversation_execution_recovery_service.dart';
import '../../domain/services/conversation_plan_execution_coordinator.dart';
import '../../domain/services/conversation_plan_execution_guardrails.dart';
import '../../domain/services/conversation_plan_projection_service.dart';
import '../../domain/services/conversation_validation_tool_result_inference.dart';
import '../providers/chat_notifier.dart';
import '../providers/chat_state.dart';
import '../providers/conversations_notifier.dart';
import '../widgets/conversation_drawer.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../widgets/plan/compact_plan_footer_card.dart';
import '../widgets/plan/plan_document_approval_sheet.dart';
import '../widgets/plan/plan_document_editor_sheet.dart';
import '../widgets/plan/plan_hydrated_task_row.dart';
import '../widgets/plan/plan_markdown_preview.dart';
import '../widgets/plan/plan_open_question_section.dart';
import '../widgets/plan/plan_review_sheet.dart';
import '../widgets/plan/plan_revision_history_sheet.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _workflowPanelScrollController = ScrollController();
  final Set<String> _activeApprovalDialogIds = <String>{};
  final _uuid = const Uuid();
  late final TabController _workspaceTabController;
  String? _workflowPanelConversationId;
  bool _isApprovedPlanExpanded = false;
  bool _isPresentingPlanReviewSheet = false;
  String? _trackedPlanGenerationConversationId;
  bool _wasGeneratingPlanForTrackedConversation = false;
  bool _wasShowingPlanDraft = false;
  String _composerPrefillText = '';
  int _composerPrefillVersion = 0;

  @override
  void initState() {
    super.initState();
    _workspaceTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _workspaceTabController.dispose();
    _scrollController.dispose();
    _workflowPanelScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
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
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final projectsState = ref.read(codingProjectsNotifierProvider);
    final projectsNotifier = ref.read(codingProjectsNotifierProvider.notifier);
    final settingsNotifier = ref.read(settingsNotifierProvider.notifier);
    final currentAssistantMode = ref
        .read(settingsNotifierProvider)
        .assistantMode;

    if (workspaceMode == WorkspaceMode.chat) {
      conversationsNotifier.activateWorkspace(
        workspaceMode: WorkspaceMode.chat,
        createIfMissing: true,
      );
      await settingsNotifier.updateAssistantMode(AssistantMode.general);
      return;
    }

    final projectId =
        ref.read(conversationsNotifierProvider).activeProjectId ??
        projectsState.selectedProjectId;
    if (projectId != null) {
      projectsNotifier.selectProject(projectId);
    }

    conversationsNotifier.activateWorkspace(
      workspaceMode: WorkspaceMode.coding,
      projectId: projectId,
      createIfMissing: projectId != null,
    );
    await settingsNotifier.updateAssistantMode(
      currentAssistantMode == AssistantMode.general
          ? AssistantMode.coding
          : currentAssistantMode,
    );
  }

  Future<void> _pickAndActivateProject(BuildContext context) async {
    final selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory == null || !context.mounted) return;

    final project = await ref
        .read(codingProjectsNotifierProvider.notifier)
        .addProject(selectedDirectory);
    if (project == null || !context.mounted) return;

    ref.read(codingProjectsNotifierProvider.notifier).selectProject(project.id);
    ref
        .read(conversationsNotifierProvider.notifier)
        .activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
          createIfMissing: true,
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

  Future<void> _showDeleteConversationDialog(
    BuildContext context,
    ConversationsNotifier conversationsNotifier,
    String conversationId,
    String conversationTitle,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('chat.delete_title'.tr()),
        content: Text(
          'chat.delete_confirm'.tr(namedArgs: {'title': conversationTitle}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) return;

    await conversationsNotifier.deleteConversation(conversationId);
    if (!context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('chat.deleted'.tr())));
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

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatNotifierProvider);
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    final conversationsState = ref.watch(conversationsNotifierProvider);
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final codingProjectsState = ref.watch(codingProjectsNotifierProvider);

    // Scroll when the message list changes.
    ref.listen(chatNotifierProvider, (previous, next) {
      if (previous?.messages.length != next.messages.length ||
          (next.messages.isNotEmpty && next.messages.last.isStreaming)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
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
        if (next != null && prev?.id != next.id) {
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
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showLocalCommandDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingFileOperation?>(
      chatNotifierProvider.select((s) => s.pendingFileOperation),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
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

    final settings = ref.watch(settingsNotifierProvider);
    final isCodingWorkspace =
        conversationsState.activeWorkspaceMode == WorkspaceMode.coding;
    final activeProject = codingProjectsState.findById(
      conversationsState.activeProjectId,
    );
    final currentConversation = conversationsState.currentConversation;
    final isPlanMode = currentConversation?.isPlanningSession ?? false;
    final effectiveAssistantMode = isPlanMode
        ? AssistantMode.plan
        : switch (settings.assistantMode) {
            AssistantMode.plan =>
              isCodingWorkspace ? AssistantMode.coding : AssistantMode.general,
            final mode => mode,
          };
    final rawTitle = currentConversation?.title ?? 'Caverno';
    final currentTitle = rawTitle == defaultConversationTitle
        ? (isCodingWorkspace
              ? 'chat.new_thread'.tr()
              : 'chat.new_conversation'.tr())
        : rawTitle;
    final workspaceIndex = isCodingWorkspace ? 1 : 0;
    if (_workspaceTabController.index != workspaceIndex) {
      _workspaceTabController.index = workspaceIndex;
    }
    final canCompose = !isCodingWorkspace || activeProject != null;
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
    _maybePresentPlanReviewSheet(
      context,
      currentConversation: currentConversation,
      chatState: chatState,
      isPlanMode: isPlanMode,
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: isCodingWorkspace
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activeProject?.name ?? 'chat.workspace_coding'.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          activeProject == null
                              ? 'chat.coding_no_project_short'.tr()
                              : currentTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    )
                  : Text(
                      currentTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            if (settings.demoMode) ...[
              const SizedBox(width: 8),
              Chip(
                label: Text('chat.demo_banner'.tr()),
                labelStyle: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                ),
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.tertiaryContainer,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
        bottom: TabBar(
          controller: _workspaceTabController,
          onTap: (index) {
            _switchWorkspaceMode(
              index == 0 ? WorkspaceMode.chat : WorkspaceMode.coding,
            );
          },
          tabs: [
            Tab(
              text: 'chat.workspace_chat'.tr(),
              icon: const Icon(Icons.chat_bubble_outline),
            ),
            Tab(
              text: 'chat.workspace_coding'.tr(),
              icon: const Icon(Icons.code),
            ),
          ],
        ),
        actions: [
          if (isCodingWorkspace)
            IconButton(
              onPressed: () => _pickAndActivateProject(context),
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: 'chat.add_project'.tr(),
            ),
          IconButton(
            onPressed: canCompose
                ? () => conversationsNotifier.createNewConversation(
                    workspaceMode: conversationsState.activeWorkspaceMode,
                    projectId: activeProject?.id,
                  )
                : null,
            icon: const Icon(Icons.add),
            tooltip: isCodingWorkspace
                ? 'chat.new_thread'.tr()
                : 'chat.new_conversation'.tr(),
          ),
          if (currentConversation != null)
            IconButton(
              onPressed: () => _showDeleteConversationDialog(
                context,
                conversationsNotifier,
                currentConversation.id,
                currentConversation.title,
              ),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'chat.delete_current'.tr(),
            ),
          IconButton(
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
            },
            icon: const Icon(Icons.settings),
            tooltip: 'chat.settings'.tr(),
          ),
        ],
      ),
      drawer: const ConversationDrawer(),
      body: Column(
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
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      chatState.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (currentConversation?.hasCompactionArtifact ?? false)
            _buildConversationCompactionBanner(context, currentConversation!),
          // Message list
          Expanded(
            child: !canCompose
                ? _buildCodingProjectEmptyState(context)
                : chatState.messages.isEmpty
                ? _buildEmptyState(
                    context,
                    isCodingWorkspace: isCodingWorkspace,
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount:
                        chatState.messages.length +
                        (shouldShowPlanStatusMessage ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= chatState.messages.length) {
                        return MessageBubble(
                          message: _buildPlanStatusMessage(
                            context,
                            chatState: chatState,
                          ),
                          onReselectProject: isCodingWorkspace
                              ? () => _pickAndActivateProject(context)
                              : null,
                        );
                      }
                      return MessageBubble(
                        message: chatState.messages[index],
                        onReselectProject: isCodingWorkspace
                            ? () => _pickAndActivateProject(context)
                            : null,
                      );
                    },
                  ),
          ),
          if (canCompose && shouldShowPlanFooterCard)
            _buildFooterPlanCard(
              context,
              currentConversation: currentConversation,
              chatState: chatState,
              isPlanMode: isPlanMode,
            ),
          // Token usage indicator
          if (canCompose && chatState.totalTokens > 0)
            _buildTokenUsageBar(context, chatState),
          // Input area
          if (canCompose)
            MessageInput(
              onSend: (message, imageBase64, imageMimeType) {
                setState(() {
                  _composerPrefillText = '';
                  _composerPrefillVersion++;
                });
                chatNotifier.sendMessage(
                  message,
                  imageBase64: imageBase64,
                  imageMimeType: imageMimeType,
                  languageCode: context.locale.languageCode,
                );
              },
              onCancel: () => chatNotifier.cancelStreaming(),
              isLoading: chatState.isLoading,
              assistantMode: effectiveAssistantMode,
              onAssistantModeSelected: (mode) async {
                final settingsNotifier = ref.read(
                  settingsNotifierProvider.notifier,
                );
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
              },
              isCodingWorkspace: isCodingWorkspace,
              inputHintKey: isCodingWorkspace
                  ? (isPlanMode
                        ? 'message.input_hint_plan'
                        : 'message.input_hint_coding')
                  : 'message.input_hint',
              composerPrefillText: _composerPrefillText,
              composerPrefillVersion: _composerPrefillVersion,
            ),
        ],
      ),
    );
  }

  Widget _buildTokenUsageBar(BuildContext context, ChatState chatState) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(
            Icons.token_outlined,
            size: 14,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 4),
          Text(
            'chat.token_usage'.tr(
              namedArgs: {
                'prompt': _formatTokenCount(chatState.promptTokens),
                'completion': _formatTokenCount(chatState.completionTokens),
                'total': _formatTokenCount(chatState.totalTokens),
              },
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterPlanCard(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
    required bool isPlanMode,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: CompactPlanFooterCard(
        currentConversation: currentConversation,
        isPlanMode: isPlanMode,
        onOpen: () {
          _openPlanReviewSheet(
            context,
            currentConversation: currentConversation,
            chatState: chatState,
            isPlanMode: isPlanMode,
          );
        },
        onApprove: () {
          _approveCurrentPlanAndStart(
            context,
            currentConversation: currentConversation,
          );
        },
        onEdit: () {
          _editPlanInChat(context, currentConversation: currentConversation);
        },
        onCancel: () {
          _cancelPlanReview(context, currentConversation: currentConversation);
        },
      ),
    );
  }

  Message _buildPlanStatusMessage(
    BuildContext context, {
    required ChatState chatState,
  }) {
    final hasError =
        chatState.workflowProposalError != null ||
        chatState.taskProposalError != null;
    return Message(
      id: 'plan_progress_message',
      content: hasError
          ? 'chat.workflow_generate_error'.tr()
          : 'chat.plan_proposal_generating'.tr(),
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isStreaming: !hasError,
    );
  }

  bool _shouldAutoPresentPlanReviewSheet(
    Conversation? currentConversation,
    ChatState chatState, {
    required bool isPlanMode,
  }) {
    if (currentConversation == null) {
      _trackedPlanGenerationConversationId = null;
      _wasGeneratingPlanForTrackedConversation = false;
      return false;
    }

    final conversationId = currentConversation.id;
    final isGenerating =
        chatState.isGeneratingWorkflowProposal ||
        chatState.isGeneratingTaskProposal;
    if (_trackedPlanGenerationConversationId != conversationId) {
      _trackedPlanGenerationConversationId = conversationId;
      _wasGeneratingPlanForTrackedConversation = isGenerating;
      return false;
    }

    if (isGenerating) {
      _wasGeneratingPlanForTrackedConversation = true;
      return false;
    }

    final artifact = currentConversation.effectivePlanArtifact;
    final requiresReview =
        isPlanMode || artifact.hasPendingEdits || !artifact.hasApproved;
    final shouldPresent =
        _wasGeneratingPlanForTrackedConversation &&
        requiresReview &&
        artifact.normalizedDraftMarkdown != null &&
        chatState.workflowProposalError == null &&
        chatState.taskProposalError == null;
    _wasGeneratingPlanForTrackedConversation = false;
    return shouldPresent;
  }

  void _maybePresentPlanReviewSheet(
    BuildContext context, {
    required Conversation? currentConversation,
    required ChatState chatState,
    required bool isPlanMode,
  }) {
    if (currentConversation == null || _isPresentingPlanReviewSheet) {
      return;
    }

    final shouldPresent = _shouldAutoPresentPlanReviewSheet(
      currentConversation,
      chatState,
      isPlanMode: isPlanMode,
    );
    if (!shouldPresent) {
      return;
    }

    _isPresentingPlanReviewSheet = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _isPresentingPlanReviewSheet = false;
        return;
      }
      await _openPlanReviewSheet(
        context,
        currentConversation: currentConversation,
        chatState: chatState,
        isPlanMode: isPlanMode,
      );
      _isPresentingPlanReviewSheet = false;
    });
  }

  Future<void> _openPlanReviewSheet(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
    required bool isPlanMode,
  }) async {
    final latestConversation =
        ref.read(conversationsNotifierProvider).currentConversation ??
        currentConversation;
    final artifact = latestConversation.effectivePlanArtifact;
    if (!artifact.hasContent) {
      return;
    }

    final isDraftState =
        isPlanMode || artifact.hasPendingEdits || !artifact.hasApproved;
    final action = await showModalBottomSheet<PlanReviewSheetAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.96,
        child: PlanReviewSheet(
          planArtifact: artifact,
          isPlanMode: isPlanMode,
          canApprove: isDraftState,
          canCancel: isDraftState,
        ),
      ),
    );
    if (!mounted || !context.mounted) {
      return;
    }
    setState(() {});

    if (action == PlanReviewSheetAction.approve) {
      await _approveCurrentPlanAndStart(
        context,
        currentConversation: latestConversation,
      );
      return;
    }
    if (action == PlanReviewSheetAction.edit) {
      _editPlanInChat(context, currentConversation: latestConversation);
      return;
    }
    if (action == PlanReviewSheetAction.cancel) {
      await _cancelPlanReview(context, currentConversation: latestConversation);
    }
  }

  Widget _buildConversationCompactionBanner(
    BuildContext context,
    Conversation currentConversation,
  ) {
    final theme = Theme.of(context);
    final artifact = currentConversation.effectiveCompactionArtifact;
    final summary = artifact.normalizedSummary;
    if (summary == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.compress_outlined,
                size: 18,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Conversation compaction is active',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh summary',
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await ref
                      .read(conversationsNotifierProvider.notifier)
                      .rebuildCurrentConversationCompaction();
                  if (!mounted) {
                    return;
                  }
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Compacted summary refreshed'),
                    ),
                  );
                },
                icon: const Icon(Icons.refresh_outlined, size: 18),
              ),
              TextButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Compacted summary'),
                      content: SingleChildScrollView(child: Text(summary)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('View summary'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Older turns are summarized before they are sent to the model. '
            'Recent turns still remain verbatim.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Compacted turns: ${artifact.compactedMessageCount} • '
            'Source messages: ${artifact.sourceMessageCount} • '
            'Estimated prompt tokens: ${artifact.estimatedPromptTokens} • '
            'v${artifact.version}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTokenCount(int count) {
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

  String _buildPlanEditSeed(Conversation currentConversation) {
    final planArtifact = currentConversation.effectivePlanArtifact;
    if (planArtifact.hasApproved) {
      return 'Please revise the saved plan for this thread based on the following adjustment:\n- ';
    }
    return 'Please adjust the current draft plan for this thread as follows:\n- ';
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
    final nextTask = ConversationPlanExecutionCoordinator.nextTask(
      executionConversation,
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

  // ignore: unused_element
  Widget _buildWorkflowPanel(
    BuildContext context,
    Conversation currentConversation,
    ChatState chatState, {
    required bool isPlanMode,
  }) {
    final theme = Theme.of(context);
    final spec = currentConversation.effectiveWorkflowSpec;
    final planArtifact = currentConversation.effectivePlanArtifact;
    final hasContext = currentConversation.hasWorkflowContext;
    final shouldPreferPlanDocument =
        currentConversation.shouldPreferPlanDocument;
    final isBusy = chatState.isLoading;
    final hasPlanDraft =
        chatState.workflowProposalDraft != null ||
        chatState.taskProposalDraft != null ||
        chatState.workflowProposalError != null ||
        chatState.taskProposalError != null ||
        chatState.isGeneratingWorkflowProposal ||
        chatState.isGeneratingTaskProposal;
    final showCombinedPlanCard = isPlanMode && hasPlanDraft;
    final conversationId = currentConversation.id;
    if (_workflowPanelConversationId != conversationId) {
      _workflowPanelConversationId = conversationId;
      _isApprovedPlanExpanded = false;
      _wasShowingPlanDraft = hasPlanDraft;
    } else if (_wasShowingPlanDraft &&
        !hasPlanDraft &&
        isPlanMode &&
        hasContext) {
      _isApprovedPlanExpanded = false;
      _wasShowingPlanDraft = false;
    } else {
      _wasShowingPlanDraft = hasPlanDraft;
    }
    final showCompactApprovedPlan =
        isPlanMode && hasContext && !hasPlanDraft && !_isApprovedPlanExpanded;
    final showCompactPlanSupport =
        hasContext &&
        shouldPreferPlanDocument &&
        (!isPlanMode || showCompactApprovedPlan);
    final showWorkflowStageChip =
        currentConversation.workflowStage != ConversationWorkflowStage.idle;
    final workflowPanelMaxHeight =
        (MediaQuery.sizeOf(context).height *
                (showCompactApprovedPlan ? 0.22 : (isPlanMode ? 0.52 : 0.4)))
            .clamp(showCompactApprovedPlan ? 120.0 : 220.0, 480.0)
            .toDouble();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: workflowPanelMaxHeight),
        child: Scrollbar(
          controller: _workflowPanelScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _workflowPanelScrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPlanMode
                                ? 'chat.plan_mode_title'.tr()
                                : 'chat.workflow_title'.tr(),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isPlanMode
                                ? (hasContext
                                      ? 'chat.plan_mode_ready'.tr()
                                      : 'chat.plan_mode_subtitle'.tr())
                                : (hasContext
                                      ? 'chat.workflow_subtitle'.tr()
                                      : 'chat.workflow_empty'.tr()),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (!isPlanMode && !shouldPreferPlanDocument)
                      IconButton(
                        onPressed: isBusy
                            ? null
                            : () => ref
                                  .read(chatNotifierProvider.notifier)
                                  .generateWorkflowProposal(
                                    languageCode: context.locale.languageCode,
                                  ),
                        icon: const Icon(Icons.auto_awesome_outlined),
                        tooltip: 'chat.workflow_generate'.tr(),
                      ),
                    if (showWorkflowStageChip) ...[
                      Chip(
                        label: Text(
                          _workflowStageLabel(
                            currentConversation.workflowStage,
                          ),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if ((!isPlanMode || hasContext) &&
                        !shouldPreferPlanDocument)
                      IconButton(
                        onPressed: () =>
                            _showWorkflowEditor(context, currentConversation),
                        icon: Icon(
                          hasContext ? Icons.edit_outlined : Icons.add,
                        ),
                        tooltip: hasContext
                            ? 'chat.workflow_edit'.tr()
                            : 'chat.workflow_add'.tr(),
                      ),
                    if (shouldPreferPlanDocument)
                      IconButton(
                        onPressed: isBusy
                            ? null
                            : () => _showPlanDocumentEditor(
                                context,
                                currentConversation,
                                preferDraft: isPlanMode,
                              ),
                        icon: const Icon(Icons.description_outlined),
                        tooltip: _planDocumentHeaderEditTooltipKey(
                          currentConversation,
                          isPlanMode: isPlanMode,
                        ).tr(),
                      ),
                    if (isPlanMode && hasContext && !hasPlanDraft)
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isApprovedPlanExpanded = !_isApprovedPlanExpanded;
                          });
                        },
                        icon: Icon(
                          _isApprovedPlanExpanded
                              ? Icons.unfold_less
                              : Icons.unfold_more,
                        ),
                        tooltip: _isApprovedPlanExpanded
                            ? 'chat.workflow_collapse'.tr()
                            : 'chat.workflow_expand'.tr(),
                      ),
                  ],
                ),
                if (showCombinedPlanCard) ...[
                  const SizedBox(height: 12),
                  _buildPlanProposalCard(
                    context,
                    currentConversation: currentConversation,
                    chatState: chatState,
                  ),
                ] else if (chatState.workflowProposalDraft != null) ...[
                  const SizedBox(height: 12),
                  _buildWorkflowProposalCard(
                    context,
                    currentConversation: currentConversation,
                    proposal: chatState.workflowProposalDraft!,
                    isGenerating: chatState.isGeneratingWorkflowProposal,
                  ),
                ] else if (chatState.workflowProposalError != null) ...[
                  const SizedBox(height: 12),
                  _buildWorkflowProposalErrorCard(
                    context,
                    error: chatState.workflowProposalError!,
                  ),
                ],
                if (!showCombinedPlanCard && planArtifact.hasContent) ...[
                  const SizedBox(height: 12),
                  _buildPlanDocumentCard(
                    context,
                    currentConversation: currentConversation,
                    chatState: chatState,
                    isPlanMode: isPlanMode,
                  ),
                ],
                if (showCompactPlanSupport) ...[
                  const SizedBox(height: 12),
                  _buildCompactWorkflowSummary(
                    context,
                    currentConversation: currentConversation,
                  ),
                ] else if (hasContext && !shouldPreferPlanDocument) ...[
                  if (spec.goal.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildWorkflowTextSection(
                      context,
                      label: 'chat.workflow_goal'.tr(),
                      value: spec.goal.trim(),
                    ),
                  ],
                  _buildWorkflowListSection(
                    context,
                    label: 'chat.workflow_constraints'.tr(),
                    items: spec.constraints,
                  ),
                  _buildWorkflowListSection(
                    context,
                    label: 'chat.workflow_acceptance'.tr(),
                    items: spec.acceptanceCriteria,
                  ),
                  _buildWorkflowListSection(
                    context,
                    label: 'chat.workflow_open_questions'.tr(),
                    items: spec.openQuestions,
                  ),
                ],
                if (hasContext) ...[
                  const SizedBox(height: 16),
                  _buildWorkflowTasksSection(
                    context,
                    currentConversation: currentConversation,
                    chatState: chatState,
                    isPlanMode: isPlanMode,
                  ),
                  if (!isPlanMode) ...[
                    const SizedBox(height: 16),
                    _buildWorkflowQuickActions(
                      context,
                      currentConversation: currentConversation,
                      isBusy: isBusy,
                    ),
                  ],
                ] else if (isPlanMode && !hasPlanDraft) ...[
                  const SizedBox(height: 12),
                  Text(
                    'chat.plan_mode_empty'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkflowTasksSection(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
    required bool isPlanMode,
  }) {
    final theme = Theme.of(context);
    final tasks = currentConversation.projectedExecutionTasks;
    final isBusy = chatState.isLoading;
    final canGenerateTasks =
        currentConversation.effectiveWorkflowSpec.hasContent &&
        !currentConversation.shouldPreferPlanDocument;
    final canEditTasks = !currentConversation.shouldPreferPlanDocument;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'chat.workflow_tasks'.tr(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (tasks.isNotEmpty)
              Chip(
                label: Text(
                  'chat.workflow_tasks_count'.tr(
                    namedArgs: {'count': tasks.length.toString()},
                  ),
                ),
                visualDensity: VisualDensity.compact,
              ),
            const SizedBox(width: 8),
            if (!isPlanMode && chatState.isGeneratingTaskProposal)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (!isPlanMode &&
                !currentConversation.shouldPreferPlanDocument)
              IconButton(
                onPressed: !canGenerateTasks || isBusy
                    ? null
                    : () => ref
                          .read(chatNotifierProvider.notifier)
                          .generateTaskProposal(
                            languageCode: context.locale.languageCode,
                          ),
                icon: const Icon(Icons.auto_awesome_outlined),
                tooltip: 'chat.workflow_tasks_generate'.tr(),
              ),
            if (canEditTasks)
              IconButton(
                onPressed: () => _showWorkflowTaskEditor(
                  context,
                  currentConversation: currentConversation,
                ),
                icon: const Icon(Icons.add_task_outlined),
                tooltip: 'chat.workflow_task_add'.tr(),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (!isPlanMode && currentConversation.shouldPreferPlanDocument) ...[
          _buildWorkflowProjectionBanner(
            context,
            currentConversation: currentConversation,
            isBusy: isBusy,
          ),
          const SizedBox(height: 8),
        ],
        if (!isPlanMode && chatState.taskProposalDraft != null) ...[
          _buildWorkflowTaskProposalCard(
            context,
            currentConversation: currentConversation,
            proposal: chatState.taskProposalDraft!,
            isGenerating: chatState.isGeneratingTaskProposal,
          ),
          const SizedBox(height: 8),
        ] else if (!isPlanMode && chatState.taskProposalError != null) ...[
          _buildWorkflowTaskProposalErrorCard(
            context,
            error: chatState.taskProposalError!,
          ),
          const SizedBox(height: 8),
        ],
        if (tasks.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
              ),
            ),
            child: Text(
              currentConversation.shouldPreferPlanDocument &&
                      currentConversation.needsWorkflowProjectionRefresh
                  ? 'chat.workflow_tasks_refresh_required'.tr()
                  : 'chat.workflow_tasks_empty'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Column(
            children: tasks
                .map(
                  (task) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildWorkflowTaskCard(
                      context,
                      currentConversation: currentConversation,
                      task: task,
                      isBusy: isBusy,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }

  Widget _buildWorkflowProjectionBanner(
    BuildContext context, {
    required Conversation currentConversation,
    required bool isBusy,
  }) {
    final theme = Theme.of(context);
    final labelKey = _workflowProjectionStatusLabelKey(currentConversation);
    final color = _workflowProjectionStatusColor(context, currentConversation);
    final messageKey = currentConversation.isWorkflowProjectionFresh
        ? 'chat.workflow_tasks_projection_fresh'
        : currentConversation.isWorkflowProjectionStale
        ? 'chat.workflow_tasks_projection_stale'
        : 'chat.workflow_tasks_projection_unavailable';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.assignment_turned_in_outlined, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  labelKey.tr(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  messageKey.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => _refreshExecutionTasksFromPlan(context),
            icon: const Icon(Icons.sync_outlined, size: 18),
            label: Text('chat.plan_document_refresh_tasks'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactWorkflowSummary(
    BuildContext context, {
    required Conversation currentConversation,
  }) {
    final theme = Theme.of(context);
    final spec = currentConversation.effectiveWorkflowSpec;
    final tasks = currentConversation.projectedExecutionTasks;
    final completedCount = tasks
        .where(
          (task) => task.status == ConversationWorkflowTaskStatus.completed,
        )
        .length;
    final remainingCount = tasks.length - completedCount;
    final nextTask = tasks.firstWhere(
      (task) => task.status != ConversationWorkflowTaskStatus.completed,
      orElse: () =>
          tasks.firstOrNull ??
          const ConversationWorkflowTask(id: '', title: ''),
    );
    final hasNextTask = nextTask.title.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surface.withValues(alpha: 0.45),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (spec.goal.trim().isNotEmpty)
            Text(
              spec.goal.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          if (spec.goal.trim().isNotEmpty) const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text(
                  'chat.workflow_tasks_count'.tr(
                    namedArgs: {'count': tasks.length.toString()},
                  ),
                ),
                visualDensity: VisualDensity.compact,
              ),
              Chip(
                label: Text(
                  '$remainingCount ${'chat.workflow_tasks_remaining'.tr()}',
                ),
                visualDensity: VisualDensity.compact,
              ),
              Chip(
                label: Text(
                  '$completedCount ${'chat.workflow_task_status_completed'.tr()}',
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (hasNextTask) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    nextTask.title.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanProposalCard(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
  }) {
    final theme = Theme.of(context);
    final planArtifact = currentConversation.effectivePlanArtifact;
    final workflowDraft = chatState.workflowProposalDraft;
    final taskDraft = chatState.taskProposalDraft;
    final workflowSpec = workflowDraft?.workflowSpec;
    final isGenerating =
        chatState.isGeneratingWorkflowProposal ||
        chatState.isGeneratingTaskProposal;
    final canApprove = workflowDraft != null && taskDraft != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.route_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'chat.plan_proposal_title'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (workflowDraft != null)
                Chip(
                  label: Text(_workflowStageLabel(workflowDraft.workflowStage)),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'chat.plan_proposal_subtitle'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (isGenerating) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'chat.plan_proposal_generating'.tr(),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          if (workflowSpec != null) ...[
            if (workflowSpec.goal.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildWorkflowTextSection(
                context,
                label: 'chat.workflow_goal'.tr(),
                value: workflowSpec.goal.trim(),
              ),
            ],
            _buildWorkflowListSection(
              context,
              label: 'chat.workflow_constraints'.tr(),
              items: workflowSpec.constraints,
            ),
            _buildWorkflowListSection(
              context,
              label: 'chat.workflow_acceptance'.tr(),
              items: workflowSpec.acceptanceCriteria,
            ),
            _buildWorkflowListSection(
              context,
              label: 'chat.workflow_open_questions'.tr(),
              items: workflowSpec.openQuestions,
            ),
          ],
          if (taskDraft != null) ...[
            const SizedBox(height: 12),
            Text(
              'chat.workflow_tasks'.tr(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final task in taskDraft.tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• ${task.title}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
          ],
          if (planArtifact.hasContent) ...[
            const SizedBox(height: 12),
            _buildPlanDocumentCard(
              context,
              currentConversation: currentConversation,
              chatState: chatState,
              isPlanMode: true,
              showActionBar: false,
            ),
          ],
          if (chatState.workflowProposalError != null) ...[
            const SizedBox(height: 10),
            Text(
              chatState.workflowProposalError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (chatState.taskProposalError != null) ...[
            const SizedBox(height: 10),
            Text(
              chatState.taskProposalError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: canApprove
                    ? () => _approvePlanAndStart(
                        context,
                        currentConversation: currentConversation,
                        workflowDraft: workflowDraft,
                        taskDraft: taskDraft,
                      )
                    : null,
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: Text('chat.plan_proposal_approve_start'.tr()),
              ),
              OutlinedButton.icon(
                onPressed: isGenerating
                    ? null
                    : () => ref
                          .read(chatNotifierProvider.notifier)
                          .generatePlanProposal(
                            languageCode: context.locale.languageCode,
                          ),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text('chat.plan_proposal_regenerate'.tr()),
              ),
              if (workflowDraft != null && !currentConversation.hasPlanArtifact)
                OutlinedButton.icon(
                  onPressed: () => _showWorkflowEditor(
                    context,
                    currentConversation,
                    initialWorkflowStage: workflowDraft.workflowStage,
                    initialWorkflowSpec: workflowDraft.workflowSpec,
                    dismissWorkflowProposalOnSave: true,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text('chat.workflow_edit'.tr()),
                ),
              OutlinedButton.icon(
                onPressed: () => _showPlanDocumentEditor(
                  context,
                  currentConversation,
                  preferDraft: true,
                ),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: Text('chat.plan_document_edit_draft'.tr()),
              ),
              TextButton(
                onPressed: () => ref
                    .read(chatNotifierProvider.notifier)
                    .dismissPlanProposal(),
                child: Text('chat.workflow_dismiss'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _approvePlanAndStart(
    BuildContext context, {
    required Conversation currentConversation,
    required WorkflowProposalDraft workflowDraft,
    required WorkflowTaskProposalDraft taskDraft,
  }) async {
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final nextTasks = taskDraft.tasks.isEmpty
        ? const <ConversationWorkflowTask>[]
        : taskDraft.tasks.indexed
              .map((entry) {
                final index = entry.$1;
                final task = entry.$2;
                return index == 0
                    ? task.copyWith(
                        status:
                            task.status ==
                                ConversationWorkflowTaskStatus.completed
                            ? task.status
                            : ConversationWorkflowTaskStatus.inProgress,
                      )
                    : task;
              })
              .toList(growable: false);
    final nextSpec = workflowDraft.workflowSpec.copyWith(tasks: nextTasks);
    final initialTask = nextTasks.firstOrNull;
    final approvedWorkflowStage = initialTask == null
        ? ConversationWorkflowStage.tasks
        : ConversationWorkflowStage.implement;
    await _snapshotApprovedPlanDocument(
      workflowDraft: workflowDraft,
      taskDraft: taskDraft.copyWith(tasks: nextTasks),
      approvedWorkflowStage: approvedWorkflowStage,
    );

    final refreshed = await conversationsNotifier
        .refreshCurrentWorkflowProjectionFromApprovedPlan();
    if (!refreshed) {
      await conversationsNotifier.updateCurrentWorkflow(
        workflowStage: approvedWorkflowStage,
        workflowSpec: nextSpec,
      );
    }
    await conversationsNotifier.exitPlanningSession();
    ref.read(chatNotifierProvider.notifier).dismissPlanProposal();

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('chat.plan_proposal_started'.tr())));

    final latestConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (initialTask == null || latestConversation == null) {
      await ref
          .read(chatNotifierProvider.notifier)
          .sendMessage(
            'chat.plan_proposal_execute_prompt'.tr(),
            languageCode: context.locale.languageCode,
            bypassPlanMode: true,
          );
      return;
    }

    final latestTask =
        latestConversation.projectedExecutionTasks
            .where((task) => task.id == initialTask.id)
            .firstOrNull ??
        initialTask;
    await _runWorkflowTask(
      context,
      currentConversation: latestConversation,
      task: latestTask,
    );
  }

  Widget _buildPlanDocumentCard(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
    required bool isPlanMode,
    bool showActionBar = true,
  }) {
    final theme = Theme.of(context);
    final planArtifact = currentConversation.effectivePlanArtifact;
    final markdown = currentConversation.displayPlanDocument(
      isPlanning: isPlanMode,
    );
    if (markdown == null) {
      return const SizedBox.shrink();
    }

    final statusKey = isPlanMode || !planArtifact.hasApproved
        ? 'chat.plan_document_status_draft'
        : planArtifact.hasPendingEdits
        ? 'chat.plan_document_status_pending'
        : 'chat.plan_document_status_approved';
    final subtitleKey = isPlanMode || !planArtifact.hasApproved
        ? 'chat.plan_document_draft_subtitle'
        : planArtifact.hasPendingEdits
        ? 'chat.plan_document_pending_subtitle'
        : 'chat.plan_document_approved_subtitle';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'chat.plan_document_title'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Chip(
                label: Text(statusKey.tr()),
                visualDensity: VisualDensity.compact,
              ),
              if (!isPlanMode && planArtifact.hasExecutionDocument) ...[
                const SizedBox(width: 6),
                Chip(
                  label: Text(
                    _workflowProjectionStatusLabelKey(currentConversation).tr(),
                  ),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                  backgroundColor: _workflowProjectionStatusColor(
                    context,
                    currentConversation,
                  ).withValues(alpha: 0.14),
                  labelStyle: theme.textTheme.labelSmall?.copyWith(
                    color: _workflowProjectionStatusColor(
                      context,
                      currentConversation,
                    ),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitleKey.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          PlanMarkdownPreview(
            markdown: markdown,
            maxHeight: isPlanMode ? 320 : 240,
          ),
          if (!isPlanMode &&
              currentConversation.shouldPreferPlanDocument &&
              currentConversation.effectiveWorkflowSpec.openQuestions
                  .where((item) => item.trim().isNotEmpty)
                  .isNotEmpty) ...[
            const SizedBox(height: 10),
            PlanOpenQuestionSection(
              currentConversation: currentConversation,
              onStatusSelected: (question, status) => _setOpenQuestionStatus(
                context,
                question: question,
                status: status,
              ),
              onAnswerPressed: (question, existingNote) => _answerOpenQuestion(
                context,
                question: question,
                existingNote: existingNote,
              ),
            ),
          ],
          if (!isPlanMode &&
              currentConversation.shouldPreferPlanDocument &&
              currentConversation.projectedExecutionTasks.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildHydratedPlanView(
              context,
              currentConversation: currentConversation,
            ),
          ],
          if (!isPlanMode &&
              planArtifact.hasApproved &&
              planArtifact.hasPendingEdits) ...[
            const SizedBox(height: 10),
            _buildPlanDocumentDiffPreview(
              context,
              currentConversation: currentConversation,
            ),
          ],
          const SizedBox(height: 8),
          if (showActionBar)
            _buildPlanDocumentActions(
              context,
              currentConversation: currentConversation,
              chatState: chatState,
              isPlanMode: isPlanMode,
            ),
        ],
      ),
    );
  }

  Widget _buildPlanDocumentDiffPreview(
    BuildContext context, {
    required Conversation currentConversation,
  }) {
    final theme = Theme.of(context);
    final artifact = currentConversation.effectivePlanArtifact;
    final approvedMarkdown = artifact.normalizedApprovedMarkdown;
    final draftMarkdown = artifact.normalizedDraftMarkdown;
    if (approvedMarkdown == null || draftMarkdown == null) {
      return const SizedBox.shrink();
    }

    final diff = ConversationPlanDiffService.buildTaskDiff(
      approvedMarkdown: approvedMarkdown,
      draftMarkdown: draftMarkdown,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat.plan_document_diff_title'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            diff.isValid
                ? 'chat.plan_document_diff_subtitle'.tr()
                : 'chat.plan_document_diff_invalid'.tr(
                    namedArgs: {
                      'error':
                          diff.errorMessage ??
                          'draft plan document could not be parsed',
                    },
                  ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (diff.isValid) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    'chat.plan_document_diff_added'.tr(
                      namedArgs: {
                        'count': diff
                            .countByType(ConversationPlanTaskDiffType.added)
                            .toString(),
                      },
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  label: Text(
                    'chat.plan_document_diff_changed'.tr(
                      namedArgs: {
                        'count': diff
                            .countByType(ConversationPlanTaskDiffType.changed)
                            .toString(),
                      },
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  label: Text(
                    'chat.plan_document_diff_removed'.tr(
                      namedArgs: {
                        'count': diff
                            .countByType(ConversationPlanTaskDiffType.removed)
                            .toString(),
                      },
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (diff.entries.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'chat.plan_document_diff_no_changes'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              for (final entry in diff.entries.take(6)) ...[
                Text(
                  _planDocumentDiffEntryLabel(context, entry),
                  style: theme.textTheme.bodySmall,
                ),
                if (entry != diff.entries.take(6).last)
                  const SizedBox(height: 4),
              ],
              if (diff.entries.length > 6) ...[
                const SizedBox(height: 4),
                Text(
                  'chat.plan_document_diff_more'.tr(
                    namedArgs: {'count': (diff.entries.length - 6).toString()},
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPlanDocumentActions(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
    required bool isPlanMode,
  }) {
    final planArtifact = currentConversation.effectivePlanArtifact;
    final isBusy = chatState.isLoading;
    final canUseProjection =
        !currentConversation.shouldPreferPlanDocument ||
        currentConversation.isWorkflowProjectionFresh;
    final blockedTask = ConversationPlanExecutionCoordinator.blockedTask(
      currentConversation,
    );
    final nextTask = ConversationPlanExecutionCoordinator.nextTask(
      currentConversation,
    );
    final activeTask = ConversationPlanExecutionCoordinator.activeTask(
      currentConversation,
    );
    final validationTask = ConversationPlanExecutionCoordinator.validationTask(
      currentConversation,
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: isBusy
              ? null
              : () => _showPlanDocumentEditor(
                  context,
                  currentConversation,
                  preferDraft: isPlanMode,
                ),
          icon: const Icon(Icons.edit_note_outlined, size: 18),
          label: Text(
            _planDocumentEditLabelKey(
              currentConversation,
              isPlanMode: isPlanMode,
            ).tr(),
          ),
        ),
        if (planArtifact.historyEntries.isNotEmpty)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => _showPlanRevisionHistory(
                    context,
                    currentConversation: currentConversation,
                  ),
            icon: const Icon(Icons.history_outlined, size: 18),
            label: Text('chat.plan_document_history'.tr()),
          ),
        if (planArtifact.hasPendingEdits)
          FilledButton.tonalIcon(
            onPressed: isBusy
                ? null
                : () => _approveDraftPlanDocument(
                    context,
                    currentConversation: currentConversation,
                  ),
            icon: const Icon(Icons.verified_outlined, size: 18),
            label: Text('chat.plan_document_review_draft'.tr()),
          ),
        if (planArtifact.hasApproved && planArtifact.hasPendingEdits)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => _revertDraftPlanDocument(
                    context,
                    currentConversation: currentConversation,
                  ),
            icon: const Icon(Icons.restore_outlined, size: 18),
            label: Text('chat.plan_document_revert'.tr()),
          ),
        if (!isPlanMode && planArtifact.hasExecutionDocument)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => _regenerateDraftPlan(
                    context,
                    currentConversation: currentConversation,
                  ),
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: Text('chat.plan_document_regenerate_draft'.tr()),
          ),
        if (!isPlanMode && planArtifact.hasExecutionDocument)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => _refreshExecutionTasksFromPlan(context),
            icon: const Icon(Icons.sync_outlined, size: 18),
            label: Text('chat.plan_document_refresh_tasks'.tr()),
          ),
        if (!isPlanMode && blockedTask != null)
          OutlinedButton.icon(
            onPressed: isBusy || !canUseProjection
                ? null
                : () => _markWorkflowTaskUnblocked(
                    context,
                    currentConversation: currentConversation,
                    task: blockedTask,
                  ),
            icon: const Icon(Icons.lock_open_outlined, size: 18),
            label: Text('chat.workflow_task_mark_unblocked'.tr()),
          ),
        if (!isPlanMode && blockedTask != null)
          OutlinedButton.icon(
            onPressed: isBusy || !canUseProjection
                ? null
                : () => _editWorkflowTaskBlockedReason(
                    context,
                    currentConversation: currentConversation,
                    task: blockedTask,
                  ),
            icon: const Icon(Icons.edit_note_outlined, size: 18),
            label: Text('chat.workflow_task_edit_blocked_reason'.tr()),
          ),
        if (!isPlanMode && blockedTask != null)
          FilledButton.tonalIcon(
            onPressed: isBusy
                ? null
                : () => _replanFromBlockedTask(
                    context,
                    currentConversation: currentConversation,
                    task: blockedTask,
                  ),
            icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
            label: Text('chat.workflow_task_replan_from_blocker'.tr()),
          ),
        if (!isPlanMode && activeTask != null)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => _replanCurrentTask(
                    context,
                    currentConversation: currentConversation,
                    task: activeTask,
                  ),
            icon: const Icon(Icons.alt_route_outlined, size: 18),
            label: Text('chat.plan_document_replan_current_task'.tr()),
          ),
        if (!isPlanMode &&
            validationTask != null &&
            validationTask.validationCommand.trim().isNotEmpty)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => _replanValidationPath(
                    context,
                    currentConversation: currentConversation,
                    task: validationTask,
                  ),
            icon: const Icon(Icons.route_outlined, size: 18),
            label: Text('chat.plan_document_replan_validation'.tr()),
          ),
        if (!isPlanMode && nextTask != null)
          FilledButton.tonalIcon(
            onPressed: isBusy || !canUseProjection
                ? null
                : () => _runWorkflowTask(
                    context,
                    currentConversation: currentConversation,
                    task: nextTask,
                  ),
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: Text('chat.plan_document_start_next_task'.tr()),
          ),
        if (!isPlanMode && activeTask != null)
          OutlinedButton.icon(
            onPressed: isBusy || !canUseProjection
                ? null
                : () => _setWorkflowTaskStatus(
                    currentConversation: currentConversation,
                    task: activeTask,
                    status: ConversationWorkflowTaskStatus.completed,
                    summary: 'Marked complete from the approved plan document.',
                    eventType: ConversationExecutionTaskEventType.completed,
                  ),
            icon: const Icon(Icons.task_alt_outlined, size: 18),
            label: Text('chat.plan_document_mark_current_complete'.tr()),
          ),
        if (!isPlanMode && validationTask != null)
          OutlinedButton.icon(
            onPressed: isBusy || !canUseProjection
                ? null
                : () => _runWorkflowTaskValidation(
                    context,
                    currentConversation: currentConversation,
                    task: validationTask,
                  ),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: Text('chat.plan_document_run_validation'.tr()),
          ),
        if (isPlanMode)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => ref
                      .read(chatNotifierProvider.notifier)
                      .generatePlanProposal(
                        languageCode: context.locale.languageCode,
                      ),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text('chat.plan_proposal_regenerate'.tr()),
          ),
      ],
    );
  }

  Widget _buildHydratedPlanView(
    BuildContext context, {
    required Conversation currentConversation,
  }) {
    final theme = Theme.of(context);
    final tasks = currentConversation.projectedExecutionTasks;
    final projectionIsCurrent = currentConversation.isWorkflowProjectionFresh;
    final subtitleKey = projectionIsCurrent
        ? 'chat.plan_document_hydrated_subtitle'
        : 'chat.plan_document_hydrated_stale_subtitle';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat.plan_document_hydrated_title'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitleKey.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          for (final task in tasks) ...[
            PlanHydratedTaskRow(
              task: task,
              progress: currentConversation.executionProgressForTask(task.id),
            ),
            if (task != tasks.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Future<void> _answerOpenQuestion(
    BuildContext context, {
    required String question,
    String? existingNote,
  }) async {
    final pending = PendingWorkflowDecision(
      id: 'open-question-${_uuid.v4()}',
      decision: WorkflowPlanningDecision(
        id: Conversation.openQuestionIdFor(question),
        question: question.trim(),
        help: 'chat.open_question_answer_subtitle'.tr(),
        allowFreeText: true,
        freeTextPlaceholder: 'chat.open_question_answer_placeholder'.tr(),
        options: const [],
      ),
      completer: Completer<WorkflowPlanningDecisionAnswer?>(),
    );
    final answer = await showModalBottomSheet<WorkflowPlanningDecisionAnswer>(
      context: context,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _WorkflowDecisionSheet(
        pending: pending,
        initialFreeText: existingNote,
        titleText: 'chat.open_question_answer_title'.tr(),
      ),
    );
    if (answer == null || !context.mounted) {
      return;
    }

    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentOpenQuestionProgress(
          question: question,
          status: ConversationOpenQuestionStatus.resolved,
          note: answer.optionLabel,
        );

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('chat.open_question_answer_saved'.tr())),
    );
  }

  Future<void> _setOpenQuestionStatus(
    BuildContext context, {
    required String question,
    required ConversationOpenQuestionStatus status,
  }) async {
    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentOpenQuestionProgress(question: question, status: status);

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'chat.plan_document_open_question_status_changed'.tr(
            namedArgs: {
              'status': switch (status) {
                ConversationOpenQuestionStatus.unresolved =>
                  'chat.open_question_status_unresolved'.tr(),
                ConversationOpenQuestionStatus.needsUserInput =>
                  'chat.open_question_status_needs_user_input'.tr(),
                ConversationOpenQuestionStatus.resolved =>
                  'chat.open_question_status_resolved'.tr(),
                ConversationOpenQuestionStatus.deferred =>
                  'chat.open_question_status_deferred'.tr(),
              },
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showPlanDocumentEditor(
    BuildContext context,
    Conversation currentConversation, {
    required bool preferDraft,
  }) async {
    final latestConversation =
        ref.read(conversationsNotifierProvider).currentConversation ??
        currentConversation;
    final planArtifact = latestConversation.effectivePlanArtifact;
    final result = await showModalBottomSheet<PlanDocumentEditorSubmission>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => PlanDocumentEditorSheet(
        planArtifact: planArtifact,
        preferDraft: preferDraft,
      ),
    );
    if (result == null) {
      return;
    }

    final normalizedDraft = result.markdown.trim().isEmpty
        ? (planArtifact.normalizedApprovedMarkdown ?? '')
        : result.markdown.trimRight();
    final updatedAt = DateTime.now();
    final nextArtifact = planArtifact
        .copyWith(draftMarkdown: normalizedDraft, updatedAt: updatedAt)
        .recordRevision(
          markdown: normalizedDraft,
          kind: ConversationPlanRevisionKind.draft,
          label: 'Saved draft plan document',
          createdAt: updatedAt,
        );

    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentPlanArtifact(
          planArtifact: nextArtifact.hasContent ? nextArtifact : null,
          clearPlanArtifact: !nextArtifact.hasContent,
        );

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.validation.isValid
              ? 'chat.plan_document_saved'.tr()
              : 'chat.plan_document_saved_with_issues'.tr(
                  namedArgs: {
                    'error':
                        result.validation.errorMessage ??
                        'plan document could not be parsed',
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _approveDraftPlanDocument(
    BuildContext context, {
    required Conversation currentConversation,
  }) async {
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final latestConversation =
        ref.read(conversationsNotifierProvider).currentConversation ??
        currentConversation;
    final currentArtifact = latestConversation.effectivePlanArtifact;
    final draftMarkdown = currentArtifact.normalizedDraftMarkdown;
    if (draftMarkdown == null) {
      return;
    }

    final validation = ConversationPlanProjectionService.validateDocument(
      markdown: draftMarkdown,
      requireTasks: true,
    );
    if (!validation.isValid) {
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

    final shouldApprove =
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (sheetContext) => PlanDocumentApprovalSheet(
            markdown: draftMarkdown,
            validation: validation,
          ),
        ) ??
        false;
    if (!shouldApprove) {
      return;
    }

    final approvedMarkdown =
        ConversationPlanProjectionService.replaceWorkflowStage(
          markdown: draftMarkdown,
          workflowStage: _preferredApprovedWorkflowStage(latestConversation),
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
          label: 'Approved draft plan document',
          createdAt: updatedAt,
        );

    await conversationsNotifier.updateCurrentPlanArtifact(
      planArtifact: nextArtifact.hasContent ? nextArtifact : null,
      clearPlanArtifact: !nextArtifact.hasContent,
    );
    final refreshed = await conversationsNotifier
        .refreshCurrentWorkflowProjectionFromApprovedPlan();

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          refreshed
              ? 'chat.plan_document_approved'.tr()
              : 'chat.plan_document_approved_refresh_failed'.tr(),
        ),
      ),
    );
  }

  Future<void> _revertDraftPlanDocument(
    BuildContext context, {
    required Conversation currentConversation,
  }) async {
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final latestConversation =
        ref.read(conversationsNotifierProvider).currentConversation ??
        currentConversation;
    final currentArtifact = latestConversation.effectivePlanArtifact;
    if (!currentArtifact.hasApproved) {
      return;
    }

    final approvedMarkdown = currentArtifact.normalizedApprovedMarkdown ?? '';
    final updatedAt = DateTime.now();
    final nextArtifact = currentArtifact
        .copyWith(draftMarkdown: approvedMarkdown, updatedAt: updatedAt)
        .recordRevision(
          markdown: approvedMarkdown,
          kind: ConversationPlanRevisionKind.restored,
          label: 'Restored draft from approved plan document',
          createdAt: updatedAt,
        );
    await conversationsNotifier.updateCurrentPlanArtifact(
      planArtifact: nextArtifact.hasContent ? nextArtifact : null,
      clearPlanArtifact: !nextArtifact.hasContent,
    );

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('chat.plan_document_reverted'.tr())));
  }

  Future<void> _refreshExecutionTasksFromPlan(BuildContext context) async {
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final refreshed = await conversationsNotifier
        .refreshCurrentWorkflowProjectionFromApprovedPlan();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          refreshed
              ? 'chat.plan_document_tasks_refreshed'.tr()
              : 'chat.plan_document_tasks_refresh_failed'.tr(),
        ),
      ),
    );
  }

  Future<void> _regenerateDraftPlan(
    BuildContext context, {
    required Conversation currentConversation,
  }) async {
    final languageCode = context.locale.languageCode;
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    if (!currentConversation.isPlanningSession) {
      await conversationsNotifier.enterPlanningSession();
    }
    await chatNotifier.generatePlanProposal(languageCode: languageCode);

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('chat.plan_document_regeneration_started'.tr())),
    );
  }

  Future<void> _snapshotApprovedPlanDocument({
    required WorkflowProposalDraft workflowDraft,
    required WorkflowTaskProposalDraft taskDraft,
    required ConversationWorkflowStage approvedWorkflowStage,
  }) async {
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return;
    }

    final currentArtifact = currentConversation.effectivePlanArtifact;
    final approvedMarkdown = currentArtifact.normalizedDraftMarkdown != null
        ? ConversationPlanProjectionService.replaceWorkflowStage(
            markdown: currentArtifact.normalizedDraftMarkdown!,
            workflowStage: approvedWorkflowStage,
          )
        : ConversationPlanDocumentBuilder.build(
            workflowStage: approvedWorkflowStage,
            workflowSpec: workflowDraft.workflowSpec,
            tasks: taskDraft.tasks,
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
          label: 'Captured approved plan document snapshot',
          createdAt: updatedAt,
        );

    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentPlanArtifact(
          planArtifact: nextArtifact.hasContent ? nextArtifact : null,
          clearPlanArtifact: !nextArtifact.hasContent,
        );
  }

  ConversationWorkflowStage _preferredApprovedWorkflowStage(
    Conversation currentConversation,
  ) {
    return switch (currentConversation.workflowStage) {
      ConversationWorkflowStage.tasks ||
      ConversationWorkflowStage.implement ||
      ConversationWorkflowStage.review => currentConversation.workflowStage,
      _ =>
        currentConversation.effectiveWorkflowSpec.tasks.isEmpty
            ? ConversationWorkflowStage.tasks
            : ConversationWorkflowStage.implement,
    };
  }

  Future<void> _showPlanRevisionHistory(
    BuildContext context, {
    required Conversation currentConversation,
  }) async {
    final artifact = currentConversation.effectivePlanArtifact;
    if (artifact.historyEntries.isEmpty) {
      return;
    }
    final selectedRevision =
        await showModalBottomSheet<ConversationPlanRevision>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (sheetContext) =>
              PlanRevisionHistorySheet(planArtifact: artifact),
        );
    if (selectedRevision == null) {
      return;
    }

    final updatedAt = DateTime.now();
    final nextArtifact = artifact
        .copyWith(
          draftMarkdown: selectedRevision.normalizedMarkdown ?? '',
          updatedAt: updatedAt,
        )
        .recordRevision(
          markdown: selectedRevision.normalizedMarkdown ?? '',
          kind: ConversationPlanRevisionKind.restored,
          label: 'Restored draft from revision history',
          createdAt: updatedAt,
        );
    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentPlanArtifact(
          planArtifact: nextArtifact.hasContent ? nextArtifact : null,
          clearPlanArtifact: !nextArtifact.hasContent,
        );

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('chat.plan_document_history_restored'.tr())),
    );
  }

  Widget _buildWorkflowProposalCard(
    BuildContext context, {
    required Conversation currentConversation,
    required WorkflowProposalDraft proposal,
    required bool isGenerating,
  }) {
    final theme = Theme.of(context);
    final spec = proposal.workflowSpec;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'chat.workflow_proposal_title'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Chip(
                label: Text(_workflowStageLabel(proposal.workflowStage)),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'chat.workflow_proposal_subtitle'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (spec.goal.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildWorkflowTextSection(
              context,
              label: 'chat.workflow_goal'.tr(),
              value: spec.goal.trim(),
            ),
          ],
          _buildWorkflowListSection(
            context,
            label: 'chat.workflow_constraints'.tr(),
            items: spec.constraints,
          ),
          _buildWorkflowListSection(
            context,
            label: 'chat.workflow_acceptance'.tr(),
            items: spec.acceptanceCriteria,
          ),
          _buildWorkflowListSection(
            context,
            label: 'chat.workflow_open_questions'.tr(),
            items: spec.openQuestions,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _applyWorkflowProposal(
                  context,
                  currentConversation: currentConversation,
                  proposal: proposal,
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text('chat.workflow_proposal_apply'.tr()),
              ),
              OutlinedButton.icon(
                onPressed: isGenerating
                    ? null
                    : () => ref
                          .read(chatNotifierProvider.notifier)
                          .generateWorkflowProposal(
                            languageCode: context.locale.languageCode,
                          ),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text('chat.workflow_regenerate'.tr()),
              ),
              OutlinedButton.icon(
                onPressed: () => currentConversation.shouldPreferPlanDocument
                    ? _showPlanDocumentEditor(
                        context,
                        currentConversation,
                        preferDraft: true,
                      )
                    : _showWorkflowEditor(
                        context,
                        currentConversation,
                        initialWorkflowStage: proposal.workflowStage,
                        initialWorkflowSpec: proposal.workflowSpec,
                        dismissWorkflowProposalOnSave: true,
                      ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(
                  currentConversation.shouldPreferPlanDocument
                      ? 'chat.plan_document_edit_draft'.tr()
                      : 'chat.workflow_edit'.tr(),
                ),
              ),
              TextButton(
                onPressed: () => ref
                    .read(chatNotifierProvider.notifier)
                    .dismissWorkflowProposal(),
                child: Text('chat.workflow_dismiss'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowProposalErrorCard(
    BuildContext context, {
    required String error,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat.workflow_generate_error'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onErrorContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowTaskProposalCard(
    BuildContext context, {
    required Conversation currentConversation,
    required WorkflowTaskProposalDraft proposal,
    required bool isGenerating,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'chat.workflow_tasks_proposal_title'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'chat.workflow_tasks_proposal_subtitle'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          for (final task in proposal.tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• ${task.title}', style: theme.textTheme.bodyMedium),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _applyTaskProposal(
                  context,
                  currentConversation: currentConversation,
                  proposal: proposal,
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text('chat.workflow_tasks_apply'.tr()),
              ),
              OutlinedButton.icon(
                onPressed: isGenerating
                    ? null
                    : () => ref
                          .read(chatNotifierProvider.notifier)
                          .generateTaskProposal(
                            languageCode: context.locale.languageCode,
                          ),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text('chat.workflow_tasks_regenerate'.tr()),
              ),
              TextButton(
                onPressed: () => ref
                    .read(chatNotifierProvider.notifier)
                    .dismissTaskProposal(),
                child: Text('chat.workflow_dismiss'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowTaskProposalErrorCard(
    BuildContext context, {
    required String error,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat.workflow_tasks_generate_error'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onErrorContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowTaskCard(
    BuildContext context, {
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
    required bool isBusy,
  }) {
    final theme = Theme.of(context);
    final progress = currentConversation.executionProgressForTask(task.id);
    final canEditTask = !currentConversation.shouldPreferPlanDocument;
    final canRunTask =
        !isBusy &&
        (!currentConversation.shouldPreferPlanDocument ||
            currentConversation.isWorkflowProjectionFresh);
    final normalizedFiles = task.targetFiles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final recoverySuggestions = ConversationExecutionRecoveryService.suggest(
      task: task,
      progress: progress,
    );
    final showValidationRecoveryActions =
        currentConversation.shouldPreferPlanDocument &&
        progress?.validationStatus ==
            ConversationExecutionValidationStatus.failed &&
        task.validationCommand.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _workflowTaskStatusColor(
            context,
            task.status,
          ).withValues(alpha: 0.35),
        ),
        color: _workflowTaskStatusColor(
          context,
          task.status,
        ).withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title.trim(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Chip(
                      label: Text(_workflowTaskStatusLabel(task.status)),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide.none,
                      backgroundColor: _workflowTaskStatusColor(
                        context,
                        task.status,
                      ).withValues(alpha: 0.18),
                      labelStyle: theme.textTheme.labelSmall?.copyWith(
                        color: _workflowTaskStatusColor(context, task.status),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_WorkflowTaskMenuAction>(
                enabled: canEditTask || canRunTask,
                onSelected: (action) => _handleWorkflowTaskMenuAction(
                  context,
                  currentConversation: currentConversation,
                  task: task,
                  action: action,
                ),
                itemBuilder: (context) => [
                  if (task.status != ConversationWorkflowTaskStatus.pending)
                    PopupMenuItem(
                      value: _WorkflowTaskMenuAction.markPending,
                      child: Text('chat.workflow_task_mark_pending'.tr()),
                    ),
                  if (task.status != ConversationWorkflowTaskStatus.inProgress)
                    PopupMenuItem(
                      value: _WorkflowTaskMenuAction.markInProgress,
                      child: Text('chat.workflow_task_mark_in_progress'.tr()),
                    ),
                  if (task.status != ConversationWorkflowTaskStatus.completed)
                    PopupMenuItem(
                      value: _WorkflowTaskMenuAction.markCompleted,
                      child: Text('chat.workflow_task_mark_completed'.tr()),
                    ),
                  if (task.status != ConversationWorkflowTaskStatus.blocked)
                    PopupMenuItem(
                      value: _WorkflowTaskMenuAction.markBlocked,
                      child: Text('chat.workflow_task_mark_blocked'.tr()),
                    ),
                  if (currentConversation.shouldPreferPlanDocument &&
                      task.status == ConversationWorkflowTaskStatus.blocked)
                    PopupMenuItem(
                      value: _WorkflowTaskMenuAction.markUnblocked,
                      child: Text('chat.workflow_task_mark_unblocked'.tr()),
                    ),
                  if (currentConversation.shouldPreferPlanDocument &&
                      task.status == ConversationWorkflowTaskStatus.blocked)
                    PopupMenuItem(
                      value: _WorkflowTaskMenuAction.editBlockedReason,
                      child: Text(
                        'chat.workflow_task_edit_blocked_reason'.tr(),
                      ),
                    ),
                  if (currentConversation.shouldPreferPlanDocument &&
                      task.status == ConversationWorkflowTaskStatus.blocked)
                    PopupMenuItem(
                      value: _WorkflowTaskMenuAction.replanFromBlocker,
                      child: Text(
                        'chat.workflow_task_replan_from_blocker'.tr(),
                      ),
                    ),
                  if (canEditTask)
                    PopupMenuItem(
                      value: _WorkflowTaskMenuAction.edit,
                      child: Text('chat.workflow_task_edit'.tr()),
                    ),
                  if (canEditTask)
                    PopupMenuItem(
                      value: _WorkflowTaskMenuAction.delete,
                      child: Text('chat.workflow_task_delete'.tr()),
                    ),
                ],
              ),
            ],
          ),
          if (normalizedFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_target_files'.tr(),
              value: normalizedFiles.join(', '),
            ),
          ],
          if (task.validationCommand.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_validation'.tr(),
              value: task.validationCommand.trim(),
              monospace: true,
            ),
          ],
          if (task.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_notes'.tr(),
              value: task.notes.trim(),
            ),
          ],
          if (progress?.normalizedSummary != null) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_progress_summary'.tr(),
              value: progress!.normalizedSummary!,
            ),
          ],
          if (progress?.normalizedBlockedReason != null) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_blocked_reason'.tr(),
              value: progress!.normalizedBlockedReason!,
            ),
          ],
          if (progress?.validationStatus != null &&
              progress!.validationStatus !=
                  ConversationExecutionValidationStatus.unknown) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_validation_status'.tr(),
              value: _workflowValidationStatusLabel(progress.validationStatus),
            ),
          ],
          if (progress?.normalizedValidationCommand != null) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_last_validation_command'.tr(),
              value: progress!.normalizedValidationCommand!,
              monospace: true,
            ),
          ],
          if (progress?.normalizedValidationSummary != null) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_validation_summary'.tr(),
              value: progress!.normalizedValidationSummary!,
            ),
          ],
          if (progress != null && progress.recentEvents.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskTimeline(context, events: progress.recentEvents),
          ],
          if (recoverySuggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildWorkflowTaskRecoverySuggestions(
              context,
              suggestions: recoverySuggestions,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: !canRunTask
                    ? null
                    : () => _runWorkflowTask(
                        context,
                        currentConversation: currentConversation,
                        task: task,
                      ),
                icon: Icon(
                  task.status == ConversationWorkflowTaskStatus.completed
                      ? Icons.fact_check_outlined
                      : Icons.play_circle_outline,
                  size: 18,
                ),
                label: Text(
                  task.status == ConversationWorkflowTaskStatus.completed
                      ? 'chat.workflow_task_review'.tr()
                      : 'chat.workflow_task_use'.tr(),
                ),
              ),
              if (showValidationRecoveryActions)
                OutlinedButton.icon(
                  onPressed: !canRunTask
                      ? null
                      : () => _runWorkflowTaskValidation(
                          context,
                          currentConversation: currentConversation,
                          task: task,
                        ),
                  icon: const Icon(Icons.refresh_outlined, size: 18),
                  label: Text('chat.workflow_task_retry_validation'.tr()),
                ),
              if (showValidationRecoveryActions)
                FilledButton.icon(
                  onPressed: isBusy
                      ? null
                      : () => _replanValidationPath(
                          context,
                          currentConversation: currentConversation,
                          task: task,
                        ),
                  icon: const Icon(Icons.rule_folder_outlined, size: 18),
                  label: Text('chat.plan_document_replan_validation'.tr()),
                ),
              if (currentConversation.shouldPreferPlanDocument &&
                  task.status == ConversationWorkflowTaskStatus.blocked)
                OutlinedButton.icon(
                  onPressed: !canRunTask
                      ? null
                      : () => _markWorkflowTaskUnblocked(
                          context,
                          currentConversation: currentConversation,
                          task: task,
                        ),
                  icon: const Icon(Icons.lock_open_outlined, size: 18),
                  label: Text('chat.workflow_task_mark_unblocked'.tr()),
                ),
              if (currentConversation.shouldPreferPlanDocument &&
                  task.status == ConversationWorkflowTaskStatus.blocked)
                OutlinedButton.icon(
                  onPressed: !canRunTask
                      ? null
                      : () => _editWorkflowTaskBlockedReason(
                          context,
                          currentConversation: currentConversation,
                          task: task,
                        ),
                  icon: const Icon(Icons.edit_note_outlined, size: 18),
                  label: Text('chat.workflow_task_edit_blocked_reason'.tr()),
                ),
              if (currentConversation.shouldPreferPlanDocument &&
                  task.status == ConversationWorkflowTaskStatus.blocked)
                FilledButton.icon(
                  onPressed: isBusy
                      ? null
                      : () => _replanFromBlockedTask(
                          context,
                          currentConversation: currentConversation,
                          task: task,
                        ),
                  icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                  label: Text('chat.workflow_task_replan_from_blocker'.tr()),
                ),
              if (canEditTask)
                OutlinedButton.icon(
                  onPressed: () => _showWorkflowTaskEditor(
                    context,
                    currentConversation: currentConversation,
                    task: task,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text('chat.workflow_task_edit'.tr()),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowTaskRecoverySuggestions(
    BuildContext context, {
    required List<ConversationExecutionRecoverySuggestion> suggestions,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.32),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat.workflow_task_recovery_title'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final suggestion in suggestions) ...[
            Text(
              '• ${suggestion.reason}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (suggestion != suggestions.last) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkflowQuickActions(
    BuildContext context, {
    required Conversation currentConversation,
    required bool isBusy,
  }) {
    final theme = Theme.of(context);
    final recommendedStage = _recommendedWorkflowStage(
      currentConversation.workflowStage,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'chat.workflow_quick_actions'.tr(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _workflowQuickActions
              .map((action) {
                final isRecommended = action.targetStage == recommendedStage;
                return isRecommended
                    ? FilledButton.tonalIcon(
                        onPressed: isBusy
                            ? null
                            : () => _runWorkflowQuickAction(
                                context,
                                action: action,
                              ),
                        icon: Icon(action.icon, size: 18),
                        label: Text(action.labelKey.tr()),
                      )
                    : OutlinedButton.icon(
                        onPressed: isBusy
                            ? null
                            : () => _runWorkflowQuickAction(
                                context,
                                action: action,
                              ),
                        icon: Icon(action.icon, size: 18),
                        label: Text(action.labelKey.tr()),
                      );
              })
              .toList(growable: false),
        ),
        const SizedBox(height: 6),
        Text(
          isBusy
              ? 'chat.workflow_quick_actions_busy'.tr()
              : 'chat.workflow_quick_actions_hint'.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildWorkflowTaskDetail(
    BuildContext context, {
    required String label,
    required String value,
    bool monospace = false,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: monospace
              ? theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')
              : theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildWorkflowTaskTimeline(
    BuildContext context, {
    required List<ConversationExecutionTaskEvent> events,
  }) {
    final theme = Theme.of(context);
    final recentEvents = events.reversed.take(4).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'chat.workflow_task_recent_events'.tr(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        for (final event in recentEvents) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '• ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Text(
                  _workflowTaskEventSummary(context, event),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (event != recentEvents.last) const SizedBox(height: 2),
        ],
      ],
    );
  }

  Widget _buildWorkflowTextSection(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildWorkflowListSection(
    BuildContext context, {
    required String label,
    required List<String> items,
  }) {
    final normalizedItems = items
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (normalizedItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          for (final item in normalizedItems)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• $item', style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
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
    final toolResults = chatNotifier.takeLatestToolResults();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: task,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: toolResults,
        );
    final recoveredFromDrift =
        !toolResultApplied &&
        await _maybeRecoverFromTaskDrift(
          task: task,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    if (!toolResultApplied && !recoveredFromDrift) {
      await _captureExecutionProgressFromLatestAssistantTurn(
        task: task,
        previousAssistantMessageId: previousAssistantMessageId,
        isValidationRun: false,
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
    final toolResultApplied = await conversationsNotifier
        .updateCurrentValidationProgressFromToolResults(
          task: task,
          toolResults: chatNotifier
              .takeLatestToolResults()
              .map(
                (result) => ConversationValidationToolResultInput(
                  toolName: result.name,
                  rawResult: result.result,
                ),
              )
              .toList(growable: false),
        );
    if (!toolResultApplied) {
      await _captureExecutionProgressFromLatestAssistantTurn(
        task: task,
        previousAssistantMessageId: previousAssistantMessageId,
        isValidationRun: true,
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
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: nextTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: toolResults,
        );
    final recoveredFromDrift =
        !toolResultApplied &&
        await _maybeRecoverFromTaskDrift(
          task: nextTask,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    if (!toolResultApplied && !recoveredFromDrift) {
      await _captureExecutionProgressFromLatestAssistantTurn(
        task: nextTask,
        previousAssistantMessageId: previousAssistantMessageId,
        isValidationRun: false,
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

  Future<bool> _maybeRecoverFromTaskDrift({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (toolResults.isEmpty || _toolResultsContainFailure(toolResults)) {
      return false;
    }

    final assessment = ConversationPlanExecutionGuardrails.assessTaskDrift(
      task: task,
      toolResults: toolResults,
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
        latestTask.status == ConversationWorkflowTaskStatus.completed ||
        latestTask.status == ConversationWorkflowTaskStatus.blocked) {
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
      ),
      languageCode: languageCode,
    );

    return _captureExecutionProgressFromLatestToolResults(
      task: latestTask,
      previousAssistantMessageId: previousAssistantMessageId,
      toolResults: chatNotifier.takeLatestToolResults(),
    );
  }

  Future<void> _captureExecutionProgressFromLatestAssistantTurn({
    required ConversationWorkflowTask task,
    required String? previousAssistantMessageId,
    required bool isValidationRun,
  }) async {
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return;
    }

    final latestAssistantMessage = _latestAssistantMessage(currentConversation);
    if (latestAssistantMessage == null ||
        latestAssistantMessage.id == previousAssistantMessageId) {
      return;
    }

    await conversationsNotifier
        .updateCurrentExecutionTaskProgressFromAssistantTurn(
          task: task,
          assistantResponse: latestAssistantMessage.content,
          isValidationRun: isValidationRun,
        );
  }

  Future<bool> _captureExecutionProgressFromLatestToolResults({
    required ConversationWorkflowTask task,
    required String? previousAssistantMessageId,
    required List<ToolResultInfo> toolResults,
  }) async {
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
    final assistantInference = ConversationExecutionProgressInference.infer(
      assistantResponse: latestAssistantResponse,
      task: task,
      isValidationRun: false,
    );
    if (assistantInference.status == ConversationWorkflowTaskStatus.blocked ||
        assistantInference.status == ConversationWorkflowTaskStatus.completed) {
      return false;
    }

    if (_toolResultsContainFailure(toolResults)) {
      return false;
    }

    final completionAssessment =
        ConversationPlanExecutionGuardrails.assessTaskCompletion(
          task: task,
          toolResults: toolResults,
        );
    if (!completionAssessment.shouldMarkCompleted) {
      return false;
    }

    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final summary = completionAssessment.requiresValidation
        ? 'Marked complete from saved target file changes and a successful validation result.'
        : 'Marked complete from saved target file changes.';
    await conversationsNotifier.updateCurrentExecutionTaskProgress(
      taskId: task.id,
      status: ConversationWorkflowTaskStatus.completed,
      summary: summary,
      eventType: ConversationExecutionTaskEventType.completed,
      eventSummary: summary,
    );
    return true;
  }

  bool _toolResultsContainFailure(List<ToolResultInfo> toolResults) {
    for (final toolResult in toolResults) {
      final normalized = toolResult.result.trim().toLowerCase();
      if (normalized.isEmpty) {
        continue;
      }
      if (normalized.startsWith('error:') ||
          normalized.contains('failed to') ||
          normalized.contains('no matching tool available') ||
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
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('Approve & Run'),
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
        .resolveLocalCommand(id: pending.id, approved: approved ?? false);
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

  Widget _buildCodingProjectEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'chat.coding_no_project_title'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'chat.coding_no_project_message'.tr(),
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _pickAndActivateProject(context),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text('chat.add_project'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required bool isCodingWorkspace,
  }) {
    final emptySettings = ref.watch(settingsNotifierProvider);
    final isDefault =
        emptySettings.baseUrl == ApiConstants.defaultBaseUrl &&
        !emptySettings.demoMode;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isDefault ? Icons.settings_suggest : Icons.chat_bubble_outline,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              if (isDefault && !isCodingWorkspace) ...[
                Text(
                  'chat.setup_title'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'chat.setup_message'.tr(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    ref
                        .read(settingsNotifierProvider.notifier)
                        .updateDemoMode(true);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: Text('chat.try_demo'.tr()),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                  },
                  icon: const Icon(Icons.settings),
                  label: Text('chat.setup_button'.tr()),
                ),
              ] else
                Text(
                  isCodingWorkspace
                      ? 'chat.coding_empty_state'.tr()
                      : 'chat.empty_state'.tr(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _WorkflowEditorAction { save, clear }

class _WorkflowEditorSubmission {
  const _WorkflowEditorSubmission.save({
    required this.workflowStage,
    required this.workflowSpec,
  }) : action = _WorkflowEditorAction.save;

  const _WorkflowEditorSubmission.clear()
    : action = _WorkflowEditorAction.clear,
      workflowStage = ConversationWorkflowStage.idle,
      workflowSpec = const ConversationWorkflowSpec();

  final _WorkflowEditorAction action;
  final ConversationWorkflowStage workflowStage;
  final ConversationWorkflowSpec workflowSpec;
}

class _WorkflowEditorSheet extends StatefulWidget {
  const _WorkflowEditorSheet({
    required this.currentConversation,
    this.initialWorkflowStage,
    this.initialWorkflowSpec,
    required this.workflowStageLabelBuilder,
  });

  final Conversation currentConversation;
  final ConversationWorkflowStage? initialWorkflowStage;
  final ConversationWorkflowSpec? initialWorkflowSpec;
  final String Function(ConversationWorkflowStage stage)
  workflowStageLabelBuilder;

  @override
  State<_WorkflowEditorSheet> createState() => _WorkflowEditorSheetState();
}

class _WorkflowEditorSheetState extends State<_WorkflowEditorSheet> {
  late final TextEditingController _goalController;
  late final TextEditingController _constraintsController;
  late final TextEditingController _acceptanceController;
  late final TextEditingController _openQuestionsController;
  late ConversationWorkflowStage _selectedStage;

  @override
  void initState() {
    super.initState();
    final spec =
        widget.initialWorkflowSpec ??
        widget.currentConversation.effectiveWorkflowSpec;
    _selectedStage =
        widget.initialWorkflowStage ?? widget.currentConversation.workflowStage;
    _goalController = TextEditingController(text: spec.goal);
    _constraintsController = TextEditingController(
      text: spec.constraints.join('\n'),
    );
    _acceptanceController = TextEditingController(
      text: spec.acceptanceCriteria.join('\n'),
    );
    _openQuestionsController = TextEditingController(
      text: spec.openQuestions.join('\n'),
    );
  }

  @override
  void dispose() {
    _goalController.dispose();
    _constraintsController.dispose();
    _acceptanceController.dispose();
    _openQuestionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'chat.workflow_edit'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'chat.workflow_sheet_subtitle'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<ConversationWorkflowStage>(
                initialValue: _selectedStage,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_stage'.tr(),
                  border: const OutlineInputBorder(),
                ),
                items: ConversationWorkflowStage.values
                    .map(
                      (stage) => DropdownMenuItem(
                        value: stage,
                        child: Text(widget.workflowStageLabelBuilder(stage)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedStage = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _goalController,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_goal'.tr(),
                  hintText: 'chat.workflow_goal_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _constraintsController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_constraints'.tr(),
                  hintText: 'chat.workflow_constraints_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _acceptanceController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_acceptance'.tr(),
                  hintText: 'chat.workflow_acceptance_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _openQuestionsController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_open_questions'.tr(),
                  hintText: 'chat.workflow_open_questions_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pop(const _WorkflowEditorSubmission.clear());
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: Text('chat.workflow_clear'.tr()),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('common.cancel'.tr()),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _WorkflowEditorSubmission.save(
                          workflowStage: _selectedStage,
                          workflowSpec: ConversationWorkflowSpec(
                            goal: _goalController.text.trim(),
                            constraints: _workflowLinesFromText(
                              _constraintsController.text,
                            ),
                            acceptanceCriteria: _workflowLinesFromText(
                              _acceptanceController.text,
                            ),
                            openQuestions: _workflowLinesFromText(
                              _openQuestionsController.text,
                            ),
                            tasks: widget
                                .currentConversation
                                .effectiveWorkflowSpec
                                .tasks,
                          ),
                        ),
                      );
                    },
                    child: Text('common.save'.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _WorkflowTaskMenuAction {
  markPending,
  markInProgress,
  markCompleted,
  markBlocked,
  markUnblocked,
  editBlockedReason,
  replanFromBlocker,
  edit,
  delete,
}

enum _WorkflowTaskEditorAction { save, delete }

class _WorkflowTaskEditorSubmission {
  const _WorkflowTaskEditorSubmission.save({required this.task})
    : action = _WorkflowTaskEditorAction.save;

  const _WorkflowTaskEditorSubmission.delete({required this.task})
    : action = _WorkflowTaskEditorAction.delete;

  final _WorkflowTaskEditorAction action;
  final ConversationWorkflowTask task;
}

class _WorkflowTaskEditorSheet extends StatefulWidget {
  const _WorkflowTaskEditorSheet({
    required this.task,
    required this.statusLabelBuilder,
  });

  final ConversationWorkflowTask? task;
  final String Function(ConversationWorkflowTaskStatus status)
  statusLabelBuilder;

  @override
  State<_WorkflowTaskEditorSheet> createState() =>
      _WorkflowTaskEditorSheetState();
}

class _WorkflowTaskEditorSheetState extends State<_WorkflowTaskEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _targetFilesController;
  late final TextEditingController _validationController;
  late final TextEditingController _notesController;
  late ConversationWorkflowTaskStatus _selectedStatus;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _selectedStatus = task?.status ?? ConversationWorkflowTaskStatus.pending;
    _titleController = TextEditingController(text: task?.title ?? '');
    _targetFilesController = TextEditingController(
      text: task?.targetFiles.join('\n') ?? '',
    );
    _validationController = TextEditingController(
      text: task?.validationCommand ?? '',
    );
    _notesController = TextEditingController(text: task?.notes ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _targetFilesController.dispose();
    _validationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existingTask = widget.task;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                existingTask == null
                    ? 'chat.workflow_task_add'.tr()
                    : 'chat.workflow_task_edit'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'chat.workflow_task_sheet_subtitle'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _titleController,
                maxLines: 2,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_task_title'.tr(),
                  hintText: 'chat.workflow_task_title_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ConversationWorkflowTaskStatus>(
                initialValue: _selectedStatus,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_task_status'.tr(),
                  border: const OutlineInputBorder(),
                ),
                items: ConversationWorkflowTaskStatus.values
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(widget.statusLabelBuilder(status)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedStatus = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _targetFilesController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_task_target_files'.tr(),
                  hintText: 'chat.workflow_task_target_files_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _validationController,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_task_validation'.tr(),
                  hintText: 'chat.workflow_task_validation_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_task_notes'.tr(),
                  hintText: 'chat.workflow_task_notes_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (existingTask != null)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(
                          _WorkflowTaskEditorSubmission.delete(
                            task: existingTask,
                          ),
                        );
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: Text('chat.workflow_task_delete'.tr()),
                    ),
                  if (existingTask != null) const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('common.cancel'.tr()),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _WorkflowTaskEditorSubmission.save(
                          task: ConversationWorkflowTask(
                            id: existingTask?.id ?? '',
                            title: _titleController.text.trim(),
                            status: _selectedStatus,
                            targetFiles: _workflowLinesFromText(
                              _targetFilesController.text,
                            ),
                            validationCommand: _validationController.text
                                .trim(),
                            notes: _notesController.text.trim(),
                          ),
                        ),
                      );
                    },
                    child: Text('common.save'.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkflowDecisionSheet extends StatefulWidget {
  const _WorkflowDecisionSheet({
    required this.pending,
    this.initialFreeText,
    this.titleText,
  });

  final PendingWorkflowDecision pending;
  final String? initialFreeText;
  final String? titleText;

  @override
  State<_WorkflowDecisionSheet> createState() => _WorkflowDecisionSheetState();
}

class _WorkflowDecisionSheetState extends State<_WorkflowDecisionSheet> {
  late final TextEditingController _textController;
  WorkflowPlanningDecisionOption? _selectedOption;

  bool get _isFreeTextDecision =>
      widget.pending.decision.allowFreeText ||
      widget.pending.decision.options.isEmpty;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialFreeText ?? '');
    _selectedOption = _isFreeTextDecision
        ? null
        : widget.pending.decision.options.firstOrNull;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submit() {
    final answer = _buildAnswer();
    if (answer == null) return;
    Navigator.pop(context, answer);
  }

  WorkflowPlanningDecisionAnswer? _buildAnswer() {
    if (_isFreeTextDecision) {
      final answerText = _textController.text.trim();
      if (answerText.isEmpty) {
        return null;
      }
      return WorkflowPlanningDecisionAnswer(
        decisionId: widget.pending.decision.id,
        question: widget.pending.decision.question,
        optionId: 'free_text',
        optionLabel: answerText,
      );
    }

    final selectedOption = _selectedOption;
    if (selectedOption == null) {
      return null;
    }
    return WorkflowPlanningDecisionAnswer(
      decisionId: widget.pending.decision.id,
      question: widget.pending.decision.question,
      optionId: selectedOption.id,
      optionLabel: selectedOption.label,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final helpText = widget.pending.decision.help.trim().isNotEmpty
        ? widget.pending.decision.help.trim()
        : 'chat.workflow_decision_subtitle'.tr();
    final submitEnabled = _buildAnswer() != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
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
                          color: theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.8,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.alt_route_rounded,
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
                              widget.titleText?.trim().isNotEmpty == true
                                  ? widget.titleText!.trim()
                                  : 'chat.workflow_decision_title'.tr(),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              helpText,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context, null),
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
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.12,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.pending.decision.question,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (widget.pending.decision.help
                                  .trim()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(
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
                                        widget.pending.decision.help.trim(),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_isFreeTextDecision)
                          TextField(
                            controller: _textController,
                            autofocus: true,
                            minLines: 2,
                            maxLines: 5,
                            decoration: InputDecoration(
                              hintText:
                                  widget.pending.decision.freeTextPlaceholder
                                      .trim()
                                      .isEmpty
                                  ? 'chat.workflow_decision_input_placeholder'
                                        .tr()
                                  : widget.pending.decision.freeTextPlaceholder
                                        .trim(),
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
                                  color: theme.colorScheme.outline.withValues(
                                    alpha: 0.2,
                                  ),
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
                            onChanged: (_) => setState(() {}),
                          )
                        else
                          ...widget.pending.decision.options.map(
                            (option) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Material(
                                color: _selectedOption?.id == option.id
                                    ? theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.65)
                                    : theme.colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    setState(() {
                                      _selectedOption = option;
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          _selectedOption?.id == option.id
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_off,
                                          size: 20,
                                          color:
                                              _selectedOption?.id == option.id
                                              ? theme.colorScheme.primary
                                              : theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(option.label),
                                              if (option.description
                                                  .trim()
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  option.description.trim(),
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
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
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    8,
                    24,
                    16 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, null),
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
                          child: Text('common.cancel'.tr()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: submitEnabled ? _submit : null,
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                          ),
                          label: Text('chat.workflow_decision_confirm'.tr()),
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
        ),
      ),
    );
  }
}

List<String> _workflowLinesFromText(String rawValue) {
  return rawValue
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

class _WorkflowQuickAction {
  const _WorkflowQuickAction({
    required this.labelKey,
    required this.icon,
    required this.targetStage,
    required this.promptKey,
  });

  final String labelKey;
  final IconData icon;
  final ConversationWorkflowStage targetStage;
  final String promptKey;
}

const List<_WorkflowQuickAction> _workflowQuickActions = [
  _WorkflowQuickAction(
    labelKey: 'chat.workflow_quick_clarify',
    icon: Icons.help_outline,
    targetStage: ConversationWorkflowStage.clarify,
    promptKey: 'chat.workflow_quick_clarify_prompt',
  ),
  _WorkflowQuickAction(
    labelKey: 'chat.workflow_quick_plan',
    icon: Icons.route_outlined,
    targetStage: ConversationWorkflowStage.plan,
    promptKey: 'chat.workflow_quick_plan_prompt',
  ),
  _WorkflowQuickAction(
    labelKey: 'chat.workflow_quick_tasks',
    icon: Icons.checklist_rtl,
    targetStage: ConversationWorkflowStage.tasks,
    promptKey: 'chat.workflow_quick_tasks_prompt',
  ),
  _WorkflowQuickAction(
    labelKey: 'chat.workflow_quick_implement',
    icon: Icons.play_circle_outline,
    targetStage: ConversationWorkflowStage.implement,
    promptKey: 'chat.workflow_quick_implement_prompt',
  ),
  _WorkflowQuickAction(
    labelKey: 'chat.workflow_quick_review',
    icon: Icons.fact_check_outlined,
    targetStage: ConversationWorkflowStage.review,
    promptKey: 'chat.workflow_quick_review_prompt',
  ),
];
