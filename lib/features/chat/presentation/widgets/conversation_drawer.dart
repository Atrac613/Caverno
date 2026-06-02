import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/workspace_mode.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../../settings/presentation/widgets/settings_modal.dart';
import '../../domain/entities/coding_project.dart';
import '../../domain/entities/conversation.dart';
import '../providers/coding_projects_notifier.dart';
import '../providers/conversations_notifier.dart';

const _collapsedCodingProjectIdsPrefsKey =
    'conversationDrawer.collapsedCodingProjectIds';

class ConversationDrawer extends ConsumerStatefulWidget {
  const ConversationDrawer({
    super.key,
    required this.onWorkspaceModeSelected,
    required this.onCodingProjectSelected,
    required this.onConversationSelected,
    required this.onAddCodingProject,
    this.closeOnAction = true,
    this.width,
  });

  final Future<void> Function(WorkspaceMode workspaceMode)
  onWorkspaceModeSelected;
  final Future<void> Function(String projectId) onCodingProjectSelected;
  final Future<void> Function(String conversationId) onConversationSelected;
  final Future<void> Function(BuildContext context) onAddCodingProject;
  final bool closeOnAction;
  final double? width;

  @override
  ConsumerState<ConversationDrawer> createState() => _ConversationDrawerState();
}

class _ConversationDrawerState extends ConsumerState<ConversationDrawer> {
  static const int _collapsedProjectThreadLimit = 5;

  final Set<String> _expandedProjectIds = <String>{};
  final Set<String> _collapsedProjectIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadCollapsedProjectIds();
  }

  @override
  Widget build(BuildContext context) {
    final conversationsState = ref.watch(conversationsNotifierProvider);
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final projectsState = ref.watch(codingProjectsNotifierProvider);
    final projectsNotifier = ref.read(codingProjectsNotifierProvider.notifier);

    return Drawer(
      width: widget.width,
      child: SafeArea(
        child: Column(
          children: [
            _WorkspaceSwitcher(
              activeWorkspaceMode: conversationsState.activeWorkspaceMode,
              onSelected: (workspaceMode) =>
                  _selectWorkspace(context, workspaceMode),
            ),
            const Divider(height: 1),
            Expanded(
              child: switch (conversationsState.activeWorkspaceMode) {
                WorkspaceMode.chat => _ChatConversationSection(
                  conversationsState: conversationsState,
                  conversationsNotifier: conversationsNotifier,
                  onConversationSelected: (conversationId) =>
                      _selectConversation(context, conversationId),
                  onDeleteConversation: (conversation) => _showDeleteDialog(
                    context,
                    conversationsNotifier,
                    conversation,
                  ),
                  onDeleteAll: () => _showDeleteScopedDialog(
                    context,
                    conversationsNotifier,
                    isCodingWorkspace: false,
                  ),
                  closeDrawer: () => _closeDrawerIfNeeded(context),
                ),
                WorkspaceMode.coding => _CodingProjectsSection(
                  projectsState: projectsState,
                  conversationsState: conversationsState,
                  conversationsNotifier: conversationsNotifier,
                  expandedProjectIds: _expandedProjectIds,
                  collapsedProjectIds: _collapsedProjectIds,
                  collapsedThreadLimit: _collapsedProjectThreadLimit,
                  onAddProject: () => widget.onAddCodingProject(context),
                  onProjectSelected: (projectId) async {
                    setState(() {
                      _collapsedProjectIds.remove(projectId);
                    });
                    _persistCollapsedProjectIds();
                    await widget.onCodingProjectSelected(projectId);
                  },
                  onConversationSelected: (conversationId) =>
                      _selectConversation(context, conversationId),
                  onDeleteConversation: (conversation) => _showDeleteDialog(
                    context,
                    conversationsNotifier,
                    conversation,
                  ),
                  onDeleteAllThreads: () => _showDeleteScopedDialog(
                    context,
                    conversationsNotifier,
                    isCodingWorkspace: true,
                  ),
                  onDeleteProject: (project) => _showDeleteProjectDialog(
                    context,
                    conversationsNotifier,
                    projectsNotifier,
                    project,
                  ),
                  onToggleProjectExpanded: (projectId) {
                    setState(() {
                      if (!_expandedProjectIds.add(projectId)) {
                        _expandedProjectIds.remove(projectId);
                      }
                    });
                  },
                  onToggleProjectCollapsed: (projectId) {
                    setState(() {
                      if (!_collapsedProjectIds.add(projectId)) {
                        _collapsedProjectIds.remove(projectId);
                      }
                    });
                    _persistCollapsedProjectIds();
                  },
                  closeDrawer: () => _closeDrawerIfNeeded(context),
                ),
                WorkspaceMode.routines => const SizedBox.expand(),
              },
            ),
            const Divider(height: 1),
            _SettingsDrawerTile(onTap: () => _openSettings(context)),
          ],
        ),
      ),
    );
  }

  Future<void> _selectWorkspace(
    BuildContext context,
    WorkspaceMode workspaceMode,
  ) async {
    await widget.onWorkspaceModeSelected(workspaceMode);
    if (!context.mounted) return;
    _closeDrawerIfNeeded(context);
  }

  Future<void> _selectConversation(
    BuildContext context,
    String conversationId,
  ) async {
    await widget.onConversationSelected(conversationId);
    if (!context.mounted) return;
    _closeDrawerIfNeeded(context);
  }

  void _openSettings(BuildContext context) {
    final navigator = Navigator.of(context);
    if (widget.closeOnAction) {
      navigator.pop();
    }
    // Desktop opens the same sidebar modal the macOS app menu uses; mobile keeps
    // the full-screen pushed page.
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      showSettingsModal(navigator.context);
      return;
    }
    navigator.push(MaterialPageRoute(builder: (_) => const SettingsPage()));
  }

  void _closeDrawerIfNeeded(BuildContext context) {
    if (!widget.closeOnAction) {
      return;
    }
    Navigator.pop(context);
  }

  void _showDeleteDialog(
    BuildContext context,
    ConversationsNotifier notifier,
    Conversation conversation,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('drawer.delete_title'.tr()),
        content: Text(
          'drawer.delete_confirm'.tr(namedArgs: {'title': conversation.title}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () {
              notifier.deleteConversation(conversation.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteScopedDialog(
    BuildContext context,
    ConversationsNotifier notifier, {
    required bool isCodingWorkspace,
  }) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isCodingWorkspace
              ? 'drawer.delete_all_threads_title'.tr()
              : 'drawer.delete_all_title'.tr(),
        ),
        content: Text(
          isCodingWorkspace
              ? 'drawer.delete_all_threads_confirm'.tr()
              : 'drawer.delete_all_confirm'.tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('common.delete_all'.tr()),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) return;

    await notifier.deleteScopedConversations();
    if (!context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('drawer.delete_all_done'.tr())));
  }

  Future<void> _showDeleteProjectDialog(
    BuildContext context,
    ConversationsNotifier conversationsNotifier,
    CodingProjectsNotifier projectsNotifier,
    CodingProject project,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('drawer.project_delete_title'.tr()),
        content: Text(
          'drawer.project_delete_confirm'.tr(namedArgs: {'name': project.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) return;

    await conversationsNotifier.deleteConversationsForProject(project.id);
    await projectsNotifier.removeProject(project.id);
    _expandedProjectIds.remove(project.id);
    _collapsedProjectIds.remove(project.id);
    _persistCollapsedProjectIds();

    final fallbackProjectId = ref
        .read(codingProjectsNotifierProvider)
        .selectedProjectId;
    if (fallbackProjectId == null) {
      conversationsNotifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: null,
        createIfMissing: false,
      );
      return;
    }

    await widget.onCodingProjectSelected(fallbackProjectId);
  }

  void _loadCollapsedProjectIds() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final stored = prefs.getStringList(_collapsedCodingProjectIdsPrefsKey);
      if (stored == null || stored.isEmpty) {
        return;
      }
      _collapsedProjectIds
        ..clear()
        ..addAll(stored.where((id) => id.trim().isNotEmpty));
    } catch (e) {
      debugPrint('Failed to load collapsed coding projects: $e');
    }
  }

  void _persistCollapsedProjectIds() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final projectIds = _collapsedProjectIds.toList()..sort();
      unawaited(
        prefs.setStringList(_collapsedCodingProjectIdsPrefsKey, projectIds),
      );
    } catch (e) {
      debugPrint('Failed to persist collapsed coding projects: $e');
    }
  }
}

class _WorkspaceSwitcher extends StatelessWidget {
  const _WorkspaceSwitcher({
    required this.activeWorkspaceMode,
    required this.onSelected,
  });

  final WorkspaceMode activeWorkspaceMode;
  final ValueChanged<WorkspaceMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Column(
        children: [
          _WorkspaceTile(
            key: const ValueKey('drawer-workspace-chat'),
            icon: Icons.chat_bubble_outline,
            label: 'chat.workspace_chat'.tr(),
            selected: activeWorkspaceMode == WorkspaceMode.chat,
            onTap: () => onSelected(WorkspaceMode.chat),
          ),
          _WorkspaceTile(
            key: const ValueKey('drawer-workspace-coding'),
            icon: Icons.code,
            label: 'chat.workspace_coding'.tr(),
            selected: activeWorkspaceMode == WorkspaceMode.coding,
            onTap: () => onSelected(WorkspaceMode.coding),
          ),
          _WorkspaceTile(
            key: const ValueKey('drawer-workspace-routines'),
            icon: Icons.schedule_outlined,
            label: 'chat.workspace_routines'.tr(),
            selected: activeWorkspaceMode == WorkspaceMode.routines,
            onTap: () => onSelected(WorkspaceMode.routines),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.3,
      ),
      leading: Icon(
        icon,
        size: 20,
        color: selected ? theme.colorScheme.primary : null,
      ),
      minLeadingWidth: 24,
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}

class _ChatConversationSection extends StatelessWidget {
  const _ChatConversationSection({
    required this.conversationsState,
    required this.conversationsNotifier,
    required this.onConversationSelected,
    required this.onDeleteConversation,
    required this.onDeleteAll,
    required this.closeDrawer,
  });

  final ConversationsState conversationsState;
  final ConversationsNotifier conversationsNotifier;
  final Future<void> Function(String conversationId) onConversationSelected;
  final ValueChanged<Conversation> onDeleteConversation;
  final VoidCallback onDeleteAll;
  final VoidCallback closeDrawer;

  @override
  Widget build(BuildContext context) {
    final conversations = conversationsState.conversations
        .where(
          (conversation) => conversation.workspaceMode == WorkspaceMode.chat,
        )
        .toList(growable: false);

    return Column(
      children: [
        _DrawerSectionHeader(
          title: 'drawer.title'.tr(),
          actions: [
            if (conversations.isNotEmpty)
              _HeaderIconButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: 'drawer.delete_all_tooltip'.tr(),
                onPressed: onDeleteAll,
              ),
            _HeaderIconButton(
              icon: Icons.add,
              tooltip: 'drawer.new_conversation'.tr(),
              onPressed: () {
                conversationsNotifier.createNewConversation(
                  workspaceMode: WorkspaceMode.chat,
                );
                closeDrawer();
              },
            ),
          ],
        ),
        Expanded(
          child: conversations.isEmpty
              ? Center(
                  child: Text(
                    'drawer.no_conversations'.tr(),
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = conversations[index];
                    return _ConversationTile(
                      conversation: conversation,
                      isSelected:
                          conversation.id ==
                          conversationsState.currentConversationId,
                      onTap: () => onConversationSelected(conversation.id),
                      onDelete: () => onDeleteConversation(conversation),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CodingProjectsSection extends StatelessWidget {
  const _CodingProjectsSection({
    required this.projectsState,
    required this.conversationsState,
    required this.conversationsNotifier,
    required this.expandedProjectIds,
    required this.collapsedProjectIds,
    required this.collapsedThreadLimit,
    required this.onAddProject,
    required this.onProjectSelected,
    required this.onConversationSelected,
    required this.onDeleteConversation,
    required this.onDeleteAllThreads,
    required this.onDeleteProject,
    required this.onToggleProjectExpanded,
    required this.onToggleProjectCollapsed,
    required this.closeDrawer,
  });

  final CodingProjectsState projectsState;
  final ConversationsState conversationsState;
  final ConversationsNotifier conversationsNotifier;
  final Set<String> expandedProjectIds;
  final Set<String> collapsedProjectIds;
  final int collapsedThreadLimit;
  final Future<void> Function() onAddProject;
  final Future<void> Function(String projectId) onProjectSelected;
  final Future<void> Function(String conversationId) onConversationSelected;
  final ValueChanged<Conversation> onDeleteConversation;
  final VoidCallback onDeleteAllThreads;
  final ValueChanged<CodingProject> onDeleteProject;
  final ValueChanged<String> onToggleProjectExpanded;
  final ValueChanged<String> onToggleProjectCollapsed;
  final VoidCallback closeDrawer;

  @override
  Widget build(BuildContext context) {
    final activeThreads = conversationsState.visibleConversations;

    return Column(
      children: [
        _DrawerSectionHeader(
          title: 'drawer.projects'.tr(),
          actions: [
            _HeaderIconButton(
              icon: Icons.create_new_folder_outlined,
              tooltip: 'chat.add_project'.tr(),
              onPressed: onAddProject,
            ),
            if (activeThreads.isNotEmpty)
              _HeaderIconButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: 'drawer.delete_all_threads_tooltip'.tr(),
                onPressed: onDeleteAllThreads,
              ),
          ],
        ),
        Expanded(
          child: projectsState.projects.isEmpty
              ? Center(
                  child: Text(
                    'drawer.no_projects'.tr(),
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: projectsState.projects.length,
                  itemBuilder: (context, index) {
                    final project = projectsState.projects[index];
                    final threads = _threadsForProject(project.id);
                    return _ProjectThreadGroup(
                      project: project,
                      threads: threads,
                      isSelected:
                          project.id == conversationsState.activeProjectId,
                      selectedConversationId:
                          conversationsState.currentConversationId,
                      isExpanded: expandedProjectIds.contains(project.id),
                      isCollapsed: collapsedProjectIds.contains(project.id),
                      collapsedThreadLimit: collapsedThreadLimit,
                      onProjectSelected: () => onProjectSelected(project.id),
                      onCreateThread: () {
                        conversationsNotifier.createNewConversation(
                          workspaceMode: WorkspaceMode.coding,
                          projectId: project.id,
                        );
                        closeDrawer();
                      },
                      onDeleteProject: () => onDeleteProject(project),
                      onConversationSelected: onConversationSelected,
                      onDeleteConversation: onDeleteConversation,
                      onToggleExpanded: () =>
                          onToggleProjectExpanded(project.id),
                      onToggleCollapsed: () =>
                          onToggleProjectCollapsed(project.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<Conversation> _threadsForProject(String projectId) {
    return conversationsState.conversations
        .where(
          (conversation) =>
              conversation.workspaceMode == WorkspaceMode.coding &&
              conversation.normalizedProjectId == projectId,
        )
        .toList(growable: false);
  }
}

class _ProjectThreadGroup extends StatelessWidget {
  const _ProjectThreadGroup({
    required this.project,
    required this.threads,
    required this.isSelected,
    required this.selectedConversationId,
    required this.isExpanded,
    required this.isCollapsed,
    required this.collapsedThreadLimit,
    required this.onProjectSelected,
    required this.onCreateThread,
    required this.onDeleteProject,
    required this.onConversationSelected,
    required this.onDeleteConversation,
    required this.onToggleExpanded,
    required this.onToggleCollapsed,
  });

  final CodingProject project;
  final List<Conversation> threads;
  final bool isSelected;
  final String? selectedConversationId;
  final bool isExpanded;
  final bool isCollapsed;
  final int collapsedThreadLimit;
  final VoidCallback onProjectSelected;
  final VoidCallback onCreateThread;
  final VoidCallback onDeleteProject;
  final Future<void> Function(String conversationId) onConversationSelected;
  final ValueChanged<Conversation> onDeleteConversation;
  final VoidCallback onToggleExpanded;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final visibleThreads = isExpanded && !isCollapsed
        ? threads
        : isCollapsed
        ? const <Conversation>[]
        : threads.take(collapsedThreadLimit).toList(growable: false);
    final hiddenThreadCount = threads.length - collapsedThreadLimit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProjectTile(
          project: project,
          isSelected: isSelected,
          isCollapsed: isCollapsed,
          onTap: onProjectSelected,
          onCreateThread: onCreateThread,
          onDelete: onDeleteProject,
          onToggleCollapsed: onToggleCollapsed,
        ),
        for (final thread in visibleThreads)
          _ProjectThreadTile(
            conversation: thread,
            isSelected: thread.id == selectedConversationId,
            onTap: () => onConversationSelected(thread.id),
            onDelete: () => onDeleteConversation(thread),
          ),
        if (!isCollapsed && hiddenThreadCount > 0)
          _ShowMoreThreadsTile(
            projectId: project.id,
            isExpanded: isExpanded,
            onTap: onToggleExpanded,
          ),
      ],
    );
  }
}

class _DrawerSectionHeader extends StatelessWidget {
  const _DrawerSectionHeader({required this.title, required this.actions});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      onPressed: onPressed,
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({
    required this.project,
    required this.isSelected,
    required this.isCollapsed,
    required this.onTap,
    required this.onCreateThread,
    required this.onDelete,
    required this.onToggleCollapsed,
  });

  final CodingProject project;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onTap;
  final VoidCallback onCreateThread;
  final VoidCallback onDelete;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: ValueKey('drawer-project-${project.id}'),
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 6),
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.3,
      ),
      leading: IconButton(
        key: ValueKey('drawer-project-${project.id}-toggle'),
        icon: Icon(
          isCollapsed ? Icons.chevron_right : Icons.expand_more,
          size: 20,
        ),
        tooltip: isCollapsed
            ? 'drawer.expand_project'.tr()
            : 'drawer.collapse_project'.tr(),
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        onPressed: onToggleCollapsed,
      ),
      minLeadingWidth: 36,
      title: Row(
        children: [
          Icon(
            Icons.folder_outlined,
            size: 20,
            color: isSelected ? theme.colorScheme.primary : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            tooltip: 'drawer.new_thread'.tr(),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            onPressed: onCreateThread,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'drawer.delete_tooltip'.tr(),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            onPressed: onDelete,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _ProjectThreadTile extends StatelessWidget {
  const _ProjectThreadTile({
    required this.conversation,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  final Conversation conversation;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: ValueKey('drawer-thread-${conversation.id}'),
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.only(left: 44, right: 8),
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.3,
      ),
      title: Text(
        _conversationTitle(conversation),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatConversationDate(conversation.updatedAt),
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'drawer.delete_tooltip'.tr(),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            onPressed: onDelete,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _ShowMoreThreadsTile extends StatelessWidget {
  const _ShowMoreThreadsTile({
    required this.projectId,
    required this.isExpanded,
    required this.onTap,
  });

  final String projectId;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('drawer-project-$projectId-show-more'),
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.only(left: 44, right: 16),
      title: Text(
        isExpanded ? 'drawer.show_less'.tr() : 'drawer.show_more'.tr(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
      ),
      onTap: onTap,
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  final Conversation conversation;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      key: ValueKey('drawer-conversation-${conversation.id}'),
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.3,
      ),
      leading: Icon(
        Icons.chat_bubble_outline,
        color: isSelected ? theme.colorScheme.primary : null,
      ),
      title: Text(
        _conversationTitle(conversation),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        _formatConversationDate(conversation.updatedAt),
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: onDelete,
        tooltip: 'drawer.delete_tooltip'.tr(),
      ),
      onTap: onTap,
    );
  }
}

class _SettingsDrawerTile extends StatelessWidget {
  const _SettingsDrawerTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const ValueKey('drawer-settings'),
      dense: true,
      leading: const Icon(Icons.settings_outlined),
      title: Text('chat.settings'.tr()),
      onTap: onTap,
    );
  }
}

String _conversationTitle(Conversation conversation) {
  if (conversation.title != defaultConversationTitle) {
    return conversation.title;
  }
  return switch (conversation.workspaceMode) {
    WorkspaceMode.coding => 'drawer.new_thread'.tr(),
    _ => 'drawer.new_conversation'.tr(),
  };
}

String _formatConversationDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);

  if (diff.inDays == 0) {
    final time =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return 'drawer.date_today'.tr(namedArgs: {'time': time});
  } else if (diff.inDays == 1) {
    return 'drawer.date_yesterday'.tr();
  } else if (diff.inDays < 7) {
    return 'drawer.days_ago'.tr(namedArgs: {'days': diff.inDays.toString()});
  } else {
    return '${date.month}/${date.day}';
  }
}
