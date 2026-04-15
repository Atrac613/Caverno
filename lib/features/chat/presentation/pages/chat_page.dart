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
import '../../data/datasources/git_tools.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../providers/chat_notifier.dart';
import '../providers/chat_state.dart';
import '../providers/conversations_notifier.dart';
import '../widgets/conversation_drawer.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  final Set<String> _activeApprovalDialogIds = <String>{};
  final _uuid = const Uuid();
  late final TabController _workspaceTabController;

  @override
  void initState() {
    super.initState();
    _workspaceTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _workspaceTabController.dispose();
    _scrollController.dispose();
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
    await settingsNotifier.updateAssistantMode(AssistantMode.coding);
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
    await ref
        .read(settingsNotifierProvider.notifier)
        .updateAssistantMode(AssistantMode.coding);
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
          if (isCodingWorkspace &&
              activeProject != null &&
              currentConversation != null)
            _buildWorkflowPanel(context, currentConversation, chatState),
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
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(
                        message: chatState.messages[index],
                        onReselectProject: isCodingWorkspace
                            ? () => _pickAndActivateProject(context)
                            : null,
                      );
                    },
                  ),
          ),
          // Token usage indicator
          if (canCompose && chatState.totalTokens > 0)
            _buildTokenUsageBar(context, chatState),
          // Input area
          if (canCompose)
            MessageInput(
              onSend: (message, imageBase64, imageMimeType) =>
                  chatNotifier.sendMessage(
                    message,
                    imageBase64: imageBase64,
                    imageMimeType: imageMimeType,
                    languageCode: context.locale.languageCode,
                  ),
              onCancel: () => chatNotifier.cancelStreaming(),
              isLoading: chatState.isLoading,
              inputHintKey: isCodingWorkspace
                  ? 'message.input_hint_coding'
                  : 'message.input_hint',
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

  Widget _buildWorkflowPanel(
    BuildContext context,
    Conversation currentConversation,
    ChatState chatState,
  ) {
    final theme = Theme.of(context);
    final spec = currentConversation.effectiveWorkflowSpec;
    final hasContext = currentConversation.hasWorkflowContext;
    final isBusy = chatState.isLoading;

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
                      'chat.workflow_title'.tr(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasContext
                          ? 'chat.workflow_subtitle'.tr()
                          : 'chat.workflow_empty'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (chatState.isGeneratingWorkflowProposal)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
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
              Chip(
                label: Text(
                  _workflowStageLabel(currentConversation.workflowStage),
                ),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () =>
                    _showWorkflowEditor(context, currentConversation),
                icon: Icon(hasContext ? Icons.edit_outlined : Icons.add),
                tooltip: hasContext
                    ? 'chat.workflow_edit'.tr()
                    : 'chat.workflow_add'.tr(),
              ),
            ],
          ),
          if (chatState.workflowProposalDraft != null) ...[
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
          if (hasContext) ...[
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
          const SizedBox(height: 16),
          _buildWorkflowTasksSection(
            context,
            currentConversation: currentConversation,
            chatState: chatState,
          ),
          const SizedBox(height: 16),
          _buildWorkflowQuickActions(
            context,
            currentConversation: currentConversation,
            isBusy: isBusy,
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowTasksSection(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
  }) {
    final theme = Theme.of(context);
    final tasks = currentConversation.effectiveWorkflowSpec.tasks;
    final isBusy = chatState.isLoading;
    final canGenerateTasks =
        currentConversation.effectiveWorkflowSpec.hasContent;

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
            if (chatState.isGeneratingTaskProposal)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
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
            const SizedBox(width: 4),
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
        if (chatState.taskProposalDraft != null) ...[
          _buildWorkflowTaskProposalCard(
            context,
            currentConversation: currentConversation,
            proposal: chatState.taskProposalDraft!,
            isGenerating: chatState.isGeneratingTaskProposal,
          ),
          const SizedBox(height: 8),
        ] else if (chatState.taskProposalError != null) ...[
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
              'chat.workflow_tasks_empty'.tr(),
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
                onPressed: () => _showWorkflowEditor(
                  context,
                  currentConversation,
                  initialWorkflowStage: proposal.workflowStage,
                  initialWorkflowSpec: proposal.workflowSpec,
                  dismissWorkflowProposalOnSave: true,
                ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text('chat.workflow_edit'.tr()),
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
    final normalizedFiles = task.targetFiles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

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
                  PopupMenuItem(
                    value: _WorkflowTaskMenuAction.edit,
                    child: Text('chat.workflow_task_edit'.tr()),
                  ),
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
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: isBusy
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
              const SizedBox(width: 8),
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
        await _updateWorkflowTaskStatus(
          currentConversation: currentConversation,
          taskId: task.id,
          status: ConversationWorkflowTaskStatus.pending,
        );
      case _WorkflowTaskMenuAction.markInProgress:
        await _updateWorkflowTaskStatus(
          currentConversation: currentConversation,
          taskId: task.id,
          status: ConversationWorkflowTaskStatus.inProgress,
        );
      case _WorkflowTaskMenuAction.markCompleted:
        await _updateWorkflowTaskStatus(
          currentConversation: currentConversation,
          taskId: task.id,
          status: ConversationWorkflowTaskStatus.completed,
        );
      case _WorkflowTaskMenuAction.markBlocked:
        await _updateWorkflowTaskStatus(
          currentConversation: currentConversation,
          taskId: task.id,
          status: ConversationWorkflowTaskStatus.blocked,
        );
      case _WorkflowTaskMenuAction.edit:
        await _showWorkflowTaskEditor(
          context,
          currentConversation: currentConversation,
          task: task,
        );
      case _WorkflowTaskMenuAction.delete:
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

  Future<void> _updateWorkflowTaskStatus({
    required Conversation currentConversation,
    required String taskId,
    required ConversationWorkflowTaskStatus status,
  }) async {
    final tasks = currentConversation.effectiveWorkflowSpec.tasks
        .map((task) => task.id == taskId ? task.copyWith(status: status) : task)
        .toList(growable: false);
    await _replaceWorkflowTasks(
      currentConversation: currentConversation,
      tasks: tasks,
      workflowStage: status == ConversationWorkflowTaskStatus.completed
          ? ConversationWorkflowStage.review
          : ConversationWorkflowStage.implement,
    );
  }

  Future<void> _runWorkflowTask(
    BuildContext context, {
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
  }) async {
    final chatNotifier = ref.read(chatNotifierProvider.notifier);

    await _updateWorkflowTaskStatus(
      currentConversation: currentConversation,
      taskId: task.id,
      status: task.status == ConversationWorkflowTaskStatus.completed
          ? ConversationWorkflowTaskStatus.completed
          : ConversationWorkflowTaskStatus.inProgress,
    );
    if (!context.mounted) {
      return;
    }

    final promptLines = <String>[
      'chat.workflow_task_use_prompt_intro'.tr(
        namedArgs: {'title': task.title},
      ),
    ];
    final targetFiles = task.targetFiles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(', ');
    if (targetFiles.isNotEmpty) {
      promptLines.add(
        '${'chat.workflow_task_target_files'.tr()}: $targetFiles',
      );
    }
    final validationCommand = task.validationCommand.trim();
    if (validationCommand.isNotEmpty) {
      promptLines.add(
        '${'chat.workflow_task_validation'.tr()}: $validationCommand',
      );
    }
    final notes = task.notes.trim();
    if (notes.isNotEmpty) {
      promptLines.add('${'chat.workflow_task_notes'.tr()}: $notes');
    }
    promptLines.add(
      task.status == ConversationWorkflowTaskStatus.completed
          ? 'chat.workflow_task_review_prompt_outro'.tr()
          : 'chat.workflow_task_use_prompt_outro'.tr(),
    );

    await chatNotifier.sendMessage(
      promptLines.join('\n'),
      languageCode: context.locale.languageCode,
    );
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
        child: Column(
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
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
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
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
          ],
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
