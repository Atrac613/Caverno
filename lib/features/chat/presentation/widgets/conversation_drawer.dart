import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/workspace_mode.dart';
import '../../../../core/utils/logger.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/conversation_repository_api.dart';
import '../../data/repositories/semantic_search_service.dart';
import '../../../routines/domain/entities/routine.dart';
import '../../../routines/domain/services/routine_schedule_service.dart';
import '../../../routines/presentation/providers/routines_notifier.dart';
import '../../../routines/presentation/widgets/routine_editor_launcher.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../../settings/presentation/widgets/settings_modal.dart';
import 'conversation_search_delegate.dart';
import '../../domain/entities/coding_project.dart';
import '../../domain/entities/conversation.dart';
import '../providers/chat_notifier.dart';
import '../providers/coding_projects_notifier.dart';
import '../providers/conversations_notifier.dart';
import '../providers/semantic_search_provider.dart';

const _collapsedCodingProjectIdsPrefsKey =
    'conversationDrawer.collapsedCodingProjectIds';
const _codingProjectSortOrderPrefsKey =
    'conversationDrawer.codingProjectSortOrder';
// Inset for rounded ListTile hover/selection so the fill does not touch the
// drawer edge, plus a gap between neighboring rows.
const _drawerRowMargin = 8.0;
const _drawerRowGap = 4.0;

enum _CodingProjectSortOrder {
  newestFirst,
  oldestFirst,
  recentlyActiveFirst,
  leastRecentlyActiveFirst,
}

enum _CodingSortAction {
  projectsNewestFirst,
  projectsOldestFirst,
  projectsRecentlyActiveFirst,
  projectsLeastRecentlyActiveFirst,
}

typedef CodingWorkspaceDrawerBuilder =
    Widget Function(BuildContext context, VoidCallback closeDrawer);

class ConversationDrawer extends ConsumerStatefulWidget {
  const ConversationDrawer({
    super.key,
    required this.onWorkspaceModeSelected,
    required this.onCodingProjectSelected,
    required this.onConversationSelected,
    required this.onAddCodingProject,
    required this.onOpenDashboard,
    required this.onCreateChatConversation,
    required this.onCreateCodingThread,
    this.onOpenCodingProjectDirectory,
    this.isDashboardSelected = false,
    this.codingWorkspaceDrawerBuilder,
    this.closeOnAction = true,
    this.width,
  });

  final Future<void> Function(WorkspaceMode workspaceMode)
  onWorkspaceModeSelected;
  final Future<void> Function(String projectId) onCodingProjectSelected;
  final Future<void> Function(String conversationId) onConversationSelected;
  final Future<void> Function() onAddCodingProject;
  final VoidCallback onOpenDashboard;
  final VoidCallback onCreateChatConversation;
  final ValueChanged<String> onCreateCodingThread;
  final Future<void> Function(String rootPath)? onOpenCodingProjectDirectory;
  final bool isDashboardSelected;
  final CodingWorkspaceDrawerBuilder? codingWorkspaceDrawerBuilder;
  final bool closeOnAction;
  final double? width;

  @override
  ConsumerState<ConversationDrawer> createState() => _ConversationDrawerState();
}

class _ConversationDrawerState extends ConsumerState<ConversationDrawer> {
  static const int _collapsedProjectThreadLimit = 5;

  final Set<String> _expandedProjectIds = <String>{};
  final Set<String> _collapsedProjectIds = <String>{};
  _CodingProjectSortOrder _projectSortOrder =
      _CodingProjectSortOrder.newestFirst;

  @override
  void initState() {
    super.initState();
    _loadCollapsedProjectIds();
    _loadSortOrders();
  }

  @override
  Widget build(BuildContext context) {
    final conversationsState = ref.watch(conversationsNotifierProvider);
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final projectsState = ref.watch(codingProjectsNotifierProvider);
    final projectsNotifier = ref.read(codingProjectsNotifierProvider.notifier);
    ref.watch(
      chatNotifierProvider.select(
        (state) => (
          isLoading: state.isLoading,
          isGeneratingWorkflowProposal: state.isGeneratingWorkflowProposal,
          isGeneratingTaskProposal: state.isGeneratingTaskProposal,
          // A background thread finishing changes only this set, and the
          // finished state for the visible thread is emitted before it — so
          // without watching it the spinner never stops.
          busyConversationIds: state.busyConversationIds,
        ),
      ),
    );
    final chatNotifier = ref.read(chatNotifierProvider.notifier);

    return Drawer(
      width: widget.width,
      child: SafeArea(
        child: Column(
          children: [
            _WorkspaceSwitcher(
              activeWorkspaceMode: conversationsState.activeWorkspaceMode,
              isDashboardSelected: widget.isDashboardSelected,
              onDashboardSelected: () => _openDashboard(context),
              onSelected: (workspaceMode) =>
                  _selectWorkspace(context, workspaceMode),
            ),
            const Divider(height: 1),
            Expanded(
              child: widget.isDashboardSelected
                  ? const SizedBox.shrink()
                  : switch (conversationsState.activeWorkspaceMode) {
                      WorkspaceMode.chat => _ChatConversationSection(
                        conversationsState: conversationsState,
                        onCreateConversation: () {
                          widget.onCreateChatConversation();
                          _closeDrawerIfNeeded(context);
                        },
                        onConversationSelected: (conversationId) =>
                            _selectConversation(context, conversationId),
                        onDeleteConversation: (conversation) =>
                            _showDeleteDialog(
                              context,
                              conversationsNotifier,
                              conversation,
                            ),
                        onDeleteAll: () => _showDeleteScopedDialog(
                          context,
                          conversationsNotifier,
                          isCodingWorkspace: false,
                        ),
                      ),
                      WorkspaceMode.coding =>
                        widget.codingWorkspaceDrawerBuilder?.call(
                              context,
                              () => _closeDrawerIfNeeded(context),
                            ) ??
                            _CodingProjectsSection(
                              projectsState: projectsState,
                              conversationsState: conversationsState,
                              isConversationBusy:
                                  chatNotifier.isConversationBusy,
                              isConversationAwaitingApproval:
                                  chatNotifier.isConversationAwaitingApproval,
                              expandedProjectIds: _expandedProjectIds,
                              collapsedProjectIds: _collapsedProjectIds,
                              collapsedThreadLimit:
                                  _collapsedProjectThreadLimit,
                              onAddProject: widget.onAddCodingProject,
                              onProjectSelected: (projectId) async {
                                setState(() {
                                  _collapsedProjectIds.remove(projectId);
                                });
                                _persistCollapsedProjectIds();
                                await widget.onCodingProjectSelected(projectId);
                              },
                              onConversationSelected: (conversationId) =>
                                  _selectConversation(context, conversationId),
                              onCreateThread: (projectId) {
                                widget.onCreateCodingThread(projectId);
                                _closeDrawerIfNeeded(context);
                              },
                              onDeleteConversation: (conversation) =>
                                  _showDeleteDialog(
                                    context,
                                    conversationsNotifier,
                                    conversation,
                                  ),
                              onDeleteAllThreads: () => _showDeleteScopedDialog(
                                context,
                                conversationsNotifier,
                                isCodingWorkspace: true,
                              ),
                              onDeleteProject: (project) =>
                                  _showDeleteProjectDialog(
                                    context,
                                    conversationsNotifier,
                                    projectsNotifier,
                                    project,
                                  ),
                              onOpenProject: (project) =>
                                  _openProjectInFinder(context, project),
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
                              projectSortOrder: _projectSortOrder,
                              onSortSelected: _selectSortAction,
                            ),
                      WorkspaceMode.routines => _RoutinesSection(
                        closeDrawer: () => _closeDrawerIfNeeded(context),
                      ),
                    },
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _drawerRowMargin),
              child: Column(
                spacing: _drawerRowGap,
                children: [
                  _SearchDrawerTile(onTap: () => _openSearch(context)),
                  _SettingsDrawerTile(onTap: () => _openSettings(context)),
                ],
              ),
            ),
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

  Future<void> _openSearch(BuildContext context) async {
    final repository = ref.read(conversationRepositoryProvider);
    final selectedId = await showSearch<String?>(
      context: context,
      delegate: ConversationSearchDelegate(search: _historySearch(repository)),
    );
    if (selectedId == null || !context.mounted) return;
    await _selectConversation(context, selectedId);
  }

  void _openDashboard(BuildContext context) {
    widget.onOpenDashboard();
    _closeDrawerIfNeeded(context);
  }

  /// LL5: when semantic search is enabled, rank history by embedding similarity
  /// (the service falls back to lexical FTS internally) and hydrate the ranked
  /// ids into conversations. Otherwise search the repository (FTS5) directly.
  Future<List<Conversation>> Function(String query) _historySearch(
    ConversationRepositoryApi repository,
  ) {
    SemanticSearchService? semantic;
    try {
      semantic = ref.read(semanticSearchServiceProvider);
    } catch (_) {
      semantic = null;
    }
    if (semantic == null) return repository.search;

    final service = semantic;
    return (String query) async {
      final result = await service.search(query);
      return [for (final id in result.conversationIds) ?repository.getById(id)];
    };
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

  Future<void> _openProjectInFinder(
    BuildContext context,
    CodingProject project,
  ) async {
    try {
      final customOpener = widget.onOpenCodingProjectDirectory;
      if (customOpener != null) {
        await customOpener(project.rootPath);
      } else {
        final result = await Process.run('/usr/bin/open', [project.rootPath]);
        if (result.exitCode != 0) {
          throw ProcessException(
            '/usr/bin/open',
            [project.rootPath],
            result.stderr.toString(),
            result.exitCode,
          );
        }
      }
    } catch (error) {
      appDebugPrint('Failed to open coding project in Finder: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('drawer.open_in_finder_failed'.tr())),
      );
    }
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
      appDebugPrint('Failed to load collapsed coding projects: $e');
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
      appDebugPrint('Failed to persist collapsed coding projects: $e');
    }
  }

  void _loadSortOrders() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final storedProjectOrder = prefs.getString(
        _codingProjectSortOrderPrefsKey,
      );
      _projectSortOrder = _CodingProjectSortOrder.values.firstWhere(
        (order) => order.name == storedProjectOrder,
        orElse: () => _CodingProjectSortOrder.newestFirst,
      );
    } catch (e) {
      appDebugPrint('Failed to load coding drawer sort order: $e');
    }
  }

  void _selectSortAction(_CodingSortAction action) {
    setState(() {
      switch (action) {
        case _CodingSortAction.projectsNewestFirst:
          _projectSortOrder = _CodingProjectSortOrder.newestFirst;
        case _CodingSortAction.projectsOldestFirst:
          _projectSortOrder = _CodingProjectSortOrder.oldestFirst;
        case _CodingSortAction.projectsRecentlyActiveFirst:
          _projectSortOrder = _CodingProjectSortOrder.recentlyActiveFirst;
        case _CodingSortAction.projectsLeastRecentlyActiveFirst:
          _projectSortOrder = _CodingProjectSortOrder.leastRecentlyActiveFirst;
      }
    });
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      unawaited(
        prefs.setString(
          _codingProjectSortOrderPrefsKey,
          _projectSortOrder.name,
        ),
      );
    } catch (e) {
      appDebugPrint('Failed to persist coding drawer sort order: $e');
    }
  }
}

class _WorkspaceSwitcher extends StatelessWidget {
  const _WorkspaceSwitcher({
    required this.activeWorkspaceMode,
    required this.isDashboardSelected,
    required this.onDashboardSelected,
    required this.onSelected,
  });

  final WorkspaceMode activeWorkspaceMode;
  final bool isDashboardSelected;
  final VoidCallback onDashboardSelected;
  final ValueChanged<WorkspaceMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _drawerRowMargin,
        _drawerRowMargin,
        _drawerRowMargin,
        6,
      ),
      child: Column(
        spacing: _drawerRowGap,
        children: [
          _WorkspaceTile(
            key: const ValueKey('drawer-workspace-dashboard'),
            icon: Icons.insights_outlined,
            label: 'chat.workspace_dashboard'.tr(),
            selected: isDashboardSelected,
            onTap: onDashboardSelected,
          ),
          _WorkspaceTile(
            key: const ValueKey('drawer-workspace-chat'),
            icon: Icons.chat_bubble_outline,
            label: 'chat.workspace_chat'.tr(),
            selected:
                !isDashboardSelected &&
                activeWorkspaceMode == WorkspaceMode.chat,
            onTap: () => onSelected(WorkspaceMode.chat),
          ),
          _WorkspaceTile(
            key: const ValueKey('drawer-workspace-coding'),
            icon: Icons.code,
            label: 'chat.workspace_coding'.tr(),
            selected:
                !isDashboardSelected &&
                activeWorkspaceMode == WorkspaceMode.coding,
            onTap: () => onSelected(WorkspaceMode.coding),
          ),
          _WorkspaceTile(
            key: const ValueKey('drawer-workspace-routines'),
            icon: Icons.schedule_outlined,
            label: 'chat.workspace_routines'.tr(),
            selected:
                !isDashboardSelected &&
                activeWorkspaceMode == WorkspaceMode.routines,
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
      // Selected background matches the hover state layer; the accent is
      // carried by the foreground (icon) instead of a tinted fill.
      selectedTileColor: theme.hoverColor,
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
    required this.onCreateConversation,
    required this.onConversationSelected,
    required this.onDeleteConversation,
    required this.onDeleteAll,
  });

  final ConversationsState conversationsState;
  final VoidCallback onCreateConversation;
  final Future<void> Function(String conversationId) onConversationSelected;
  final ValueChanged<Conversation> onDeleteConversation;
  final VoidCallback onDeleteAll;

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
              onPressed: onCreateConversation,
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
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    _drawerRowMargin,
                    0,
                    _drawerRowMargin,
                    8,
                  ),
                  itemCount: conversations.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: _drawerRowGap),
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
    required this.isConversationBusy,
    required this.isConversationAwaitingApproval,
    required this.expandedProjectIds,
    required this.collapsedProjectIds,
    required this.collapsedThreadLimit,
    required this.onAddProject,
    required this.onProjectSelected,
    required this.onCreateThread,
    required this.onConversationSelected,
    required this.onDeleteConversation,
    required this.onDeleteAllThreads,
    required this.onDeleteProject,
    required this.onOpenProject,
    required this.onToggleProjectExpanded,
    required this.onToggleProjectCollapsed,
    required this.projectSortOrder,
    required this.onSortSelected,
  });

  final CodingProjectsState projectsState;
  final ConversationsState conversationsState;
  final bool Function(String conversationId) isConversationBusy;
  final bool Function(String conversationId) isConversationAwaitingApproval;
  final Set<String> expandedProjectIds;
  final Set<String> collapsedProjectIds;
  final int collapsedThreadLimit;
  final Future<void> Function() onAddProject;
  final Future<void> Function(String projectId) onProjectSelected;
  final ValueChanged<String> onCreateThread;
  final Future<void> Function(String conversationId) onConversationSelected;
  final ValueChanged<Conversation> onDeleteConversation;
  final VoidCallback onDeleteAllThreads;
  final ValueChanged<CodingProject> onDeleteProject;
  final ValueChanged<CodingProject> onOpenProject;
  final ValueChanged<String> onToggleProjectExpanded;
  final ValueChanged<String> onToggleProjectCollapsed;
  final _CodingProjectSortOrder projectSortOrder;
  final ValueChanged<_CodingSortAction> onSortSelected;

  @override
  Widget build(BuildContext context) {
    final activeThreads = conversationsState.visibleConversations;
    final latestThreadUpdates = <String, DateTime>{};
    for (final conversation in conversationsState.conversations) {
      if (conversation.workspaceMode != WorkspaceMode.coding) continue;
      final projectId = conversation.normalizedProjectId;
      if (projectId == null) continue;
      final previous = latestThreadUpdates[projectId];
      if (previous == null || conversation.updatedAt.isAfter(previous)) {
        latestThreadUpdates[projectId] = conversation.updatedAt;
      }
    }
    final projects = projectsState.projects.toList(growable: false)
      ..sort((left, right) {
        final byPrimarySort = switch (projectSortOrder) {
          _CodingProjectSortOrder.newestFirst => right.createdAt.compareTo(
            left.createdAt,
          ),
          _CodingProjectSortOrder.oldestFirst => left.createdAt.compareTo(
            right.createdAt,
          ),
          _CodingProjectSortOrder.recentlyActiveFirst =>
            _compareLatestThreadUpdates(
              latestThreadUpdates[left.id],
              latestThreadUpdates[right.id],
              newestFirst: true,
            ),
          _CodingProjectSortOrder.leastRecentlyActiveFirst =>
            _compareLatestThreadUpdates(
              latestThreadUpdates[left.id],
              latestThreadUpdates[right.id],
              newestFirst: false,
            ),
        };
        if (byPrimarySort != 0) return byPrimarySort;
        final byCreatedAt = right.createdAt.compareTo(left.createdAt);
        if (byCreatedAt != 0) return byCreatedAt;
        return left.id.compareTo(right.id);
      });

    return Column(
      children: [
        _DrawerSectionHeader(
          title: 'drawer.projects'.tr(),
          actions: [
            _CodingSortMenuButton(
              projectSortOrder: projectSortOrder,
              onSelected: onSortSelected,
            ),
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
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    _drawerRowMargin,
                    0,
                    _drawerRowMargin,
                    8,
                  ),
                  itemCount: projects.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: _drawerRowGap),
                  itemBuilder: (context, index) {
                    final project = projects[index];
                    final threads = _threadsForProject(project.id);
                    return _ProjectThreadGroup(
                      project: project,
                      threads: threads,
                      isSelected:
                          project.id == conversationsState.activeProjectId,
                      selectedConversationId:
                          conversationsState.currentConversationId,
                      isConversationBusy: isConversationBusy,
                      isConversationAwaitingApproval:
                          isConversationAwaitingApproval,
                      isExpanded: expandedProjectIds.contains(project.id),
                      isCollapsed: collapsedProjectIds.contains(project.id),
                      collapsedThreadLimit: collapsedThreadLimit,
                      onProjectSelected: () => onProjectSelected(project.id),
                      onCreateThread: () => onCreateThread(project.id),
                      onDeleteProject: () => onDeleteProject(project),
                      onOpenProject: () => onOpenProject(project),
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
    final threads = conversationsState.conversations
        .where(
          (conversation) =>
              conversation.workspaceMode == WorkspaceMode.coding &&
              conversation.normalizedProjectId == projectId,
        )
        .toList(growable: false);
    threads.sort((left, right) {
      final byUpdatedAt = right.updatedAt.compareTo(left.updatedAt);
      if (byUpdatedAt != 0) return byUpdatedAt;
      return left.id.compareTo(right.id);
    });
    return threads;
  }

  int _compareLatestThreadUpdates(
    DateTime? left,
    DateTime? right, {
    required bool newestFirst,
  }) {
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return newestFirst ? right.compareTo(left) : left.compareTo(right);
  }
}

class _ProjectThreadGroup extends StatelessWidget {
  const _ProjectThreadGroup({
    required this.project,
    required this.threads,
    required this.isSelected,
    required this.selectedConversationId,
    required this.isConversationBusy,
    required this.isConversationAwaitingApproval,
    required this.isExpanded,
    required this.isCollapsed,
    required this.collapsedThreadLimit,
    required this.onProjectSelected,
    required this.onCreateThread,
    required this.onDeleteProject,
    required this.onOpenProject,
    required this.onConversationSelected,
    required this.onDeleteConversation,
    required this.onToggleExpanded,
    required this.onToggleCollapsed,
  });

  final CodingProject project;
  final List<Conversation> threads;
  final bool isSelected;
  final String? selectedConversationId;
  final bool Function(String conversationId) isConversationBusy;
  final bool Function(String conversationId) isConversationAwaitingApproval;
  final bool isExpanded;
  final bool isCollapsed;
  final int collapsedThreadLimit;
  final VoidCallback onProjectSelected;
  final VoidCallback onCreateThread;
  final VoidCallback onDeleteProject;
  final VoidCallback onOpenProject;
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
      spacing: _drawerRowGap,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProjectTile(
          project: project,
          isSelected: isSelected,
          isCollapsed: isCollapsed,
          onTap: onProjectSelected,
          onCreateThread: onCreateThread,
          onDelete: onDeleteProject,
          onOpenProject: onOpenProject,
          onToggleCollapsed: onToggleCollapsed,
        ),
        for (final thread in visibleThreads)
          _ProjectThreadTile(
            conversation: thread,
            isSelected: thread.id == selectedConversationId,
            isWorking: isConversationBusy(thread.id),
            needsApproval: isConversationAwaitingApproval(thread.id),
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

class _RoutinesSection extends ConsumerWidget {
  const _RoutinesSection({required this.closeDrawer});

  final VoidCallback closeDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routinesState = ref.watch(routinesNotifierProvider);
    final routines = routinesState.routines;
    final selectedId = routinesState.selectedRoutineId;

    return Column(
      children: [
        _DrawerSectionHeader(
          title: 'routines.title'.tr(),
          actions: [
            _HeaderIconButton(
              icon: Icons.add,
              tooltip: 'routines.create_cta'.tr(),
              onPressed: () => _createRoutine(context, ref),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _drawerRowMargin),
          child: _RoutineHomeTile(
            isSelected: selectedId == null,
            onTap: () {
              ref.read(routinesNotifierProvider.notifier).selectRoutine(null);
              closeDrawer();
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: routines.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'routines.empty_title'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    _drawerRowMargin,
                    0,
                    _drawerRowMargin,
                    8,
                  ),
                  itemCount: routines.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: _drawerRowGap),
                  itemBuilder: (context, index) {
                    final routine = routines[index];
                    return _RoutineDrawerTile(
                      routine: routine,
                      isSelected: routine.id == selectedId,
                      isRunning: routinesState.isRunning(routine.id),
                      onTap: () {
                        ref
                            .read(routinesNotifierProvider.notifier)
                            .selectRoutine(routine.id);
                        closeDrawer();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _createRoutine(BuildContext context, WidgetRef ref) async {
    final createdId = await showRoutineEditor(context, ref);
    if (createdId == null) {
      return;
    }
    ref.read(routinesNotifierProvider.notifier).selectRoutine(createdId);
    closeDrawer();
  }
}

class _RoutineHomeTile extends StatelessWidget {
  const _RoutineHomeTile({required this.isSelected, required this.onTap});

  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: const ValueKey('drawer-routines-home'),
      dense: true,
      visualDensity: VisualDensity.compact,
      selected: isSelected,
      selectedTileColor: theme.hoverColor,
      leading: Icon(
        Icons.home_outlined,
        size: 20,
        color: isSelected ? theme.colorScheme.primary : null,
      ),
      title: Text(
        'routines.home'.tr(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _RoutineDrawerTile extends StatelessWidget {
  const _RoutineDrawerTile({
    required this.routine,
    required this.isSelected,
    required this.isRunning,
    required this.onTap,
  });

  final Routine routine;
  final bool isSelected;
  final bool isRunning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDue = RoutineScheduleService.isDue(routine);
    final statusLabel = isRunning
        ? 'routines.running_badge'.tr()
        : !routine.enabled
        ? 'routines.disabled_badge'.tr()
        : isDue
        ? 'routines.due_badge'.tr()
        : 'routines.enabled_badge'.tr();

    return ListTile(
      key: ValueKey('drawer-routine-${routine.id}'),
      dense: true,
      visualDensity: VisualDensity.compact,
      selected: isSelected,
      selectedTileColor: theme.hoverColor,
      leading: Icon(
        routine.enabled ? Icons.schedule_outlined : Icons.pause_circle_outline,
        size: 20,
        color: isSelected ? theme.colorScheme.primary : null,
      ),
      title: Text(
        routine.trimmedName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        statusLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
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

class _CodingSortMenuButton extends StatelessWidget {
  const _CodingSortMenuButton({
    required this.projectSortOrder,
    required this.onSelected,
  });

  final _CodingProjectSortOrder projectSortOrder;
  final ValueChanged<_CodingSortAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_CodingSortAction>(
      key: const ValueKey('drawer-coding-sort-menu'),
      icon: const Icon(Icons.sort, size: 20),
      tooltip: 'drawer.sort_tooltip'.tr(),
      onSelected: onSelected,
      itemBuilder: (context) => [
        _sortMenuItem(
          action: _CodingSortAction.projectsNewestFirst,
          label: 'drawer.sort_projects_newest'.tr(),
          selected: projectSortOrder == _CodingProjectSortOrder.newestFirst,
        ),
        _sortMenuItem(
          action: _CodingSortAction.projectsOldestFirst,
          label: 'drawer.sort_projects_oldest'.tr(),
          selected: projectSortOrder == _CodingProjectSortOrder.oldestFirst,
        ),
        _sortMenuItem(
          action: _CodingSortAction.projectsRecentlyActiveFirst,
          label: 'drawer.sort_projects_recent_thread'.tr(),
          selected:
              projectSortOrder == _CodingProjectSortOrder.recentlyActiveFirst,
        ),
        _sortMenuItem(
          action: _CodingSortAction.projectsLeastRecentlyActiveFirst,
          label: 'drawer.sort_projects_oldest_thread'.tr(),
          selected:
              projectSortOrder ==
              _CodingProjectSortOrder.leastRecentlyActiveFirst,
        ),
      ],
    );
  }

  PopupMenuItem<_CodingSortAction> _sortMenuItem({
    required _CodingSortAction action,
    required String label,
    required bool selected,
  }) {
    return PopupMenuItem<_CodingSortAction>(
      value: action,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: selected ? const Icon(Icons.check, size: 18) : null,
          ),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _ProjectTile extends StatefulWidget {
  const _ProjectTile({
    required this.project,
    required this.isSelected,
    required this.isCollapsed,
    required this.onTap,
    required this.onCreateThread,
    required this.onDelete,
    required this.onOpenProject,
    required this.onToggleCollapsed,
  });

  final CodingProject project;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onTap;
  final VoidCallback onCreateThread;
  final VoidCallback onDelete;
  final VoidCallback onOpenProject;
  final VoidCallback onToggleCollapsed;

  @override
  State<_ProjectTile> createState() => _ProjectTileState();
}

class _ProjectTileState extends State<_ProjectTile> {
  bool _isHovering = false;
  bool _isMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = widget.project;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: ListTile(
        key: ValueKey('drawer-project-${project.id}'),
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 6),
        selected: widget.isSelected,
        selectedTileColor: theme.hoverColor,
        leading: IconButton(
          key: ValueKey('drawer-project-${project.id}-toggle'),
          icon: Icon(
            widget.isCollapsed ? Icons.chevron_right : Icons.expand_more,
            size: 20,
          ),
          tooltip: widget.isCollapsed
              ? 'drawer.expand_project'.tr()
              : 'drawer.collapse_project'.tr(),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          onPressed: widget.onToggleCollapsed,
        ),
        minLeadingWidth: 36,
        title: Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: 20,
              color: widget.isSelected ? theme.colorScheme.primary : null,
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
        trailing: _isHovering || _isMenuOpen
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: ValueKey(
                      'drawer-project-${project.id}-new-thread-button',
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: 'drawer.new_thread'.tr(),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    onPressed: widget.onCreateThread,
                  ),
                  PopupMenuButton<_ProjectMenuAction>(
                    key: ValueKey('drawer-project-${project.id}-menu'),
                    icon: const Icon(Icons.more_vert, size: 18),
                    tooltip: 'drawer.project_actions_tooltip'.tr(),
                    onOpened: () => setState(() => _isMenuOpen = true),
                    onCanceled: () => setState(() => _isMenuOpen = false),
                    onSelected: (action) {
                      setState(() => _isMenuOpen = false);
                      switch (action) {
                        case _ProjectMenuAction.openInFinder:
                          widget.onOpenProject();
                          return;
                        case _ProjectMenuAction.delete:
                          widget.onDelete();
                          return;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _ProjectMenuAction.openInFinder,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.folder_open_outlined),
                          title: Text('drawer.open_in_finder'.tr()),
                        ),
                      ),
                      PopupMenuItem(
                        value: _ProjectMenuAction.delete,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                          ),
                          title: Text(
                            'drawer.project_delete_action'.tr(),
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : null,
        onTap: widget.onTap,
      ),
    );
  }
}

enum _ProjectMenuAction { openInFinder, delete }

class _ProjectThreadTile extends StatefulWidget {
  const _ProjectThreadTile({
    required this.conversation,
    required this.isSelected,
    required this.isWorking,
    required this.needsApproval,
    required this.onTap,
    required this.onDelete,
  });

  final Conversation conversation;
  final bool isSelected;
  final bool isWorking;
  final bool needsApproval;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_ProjectThreadTile> createState() => _ProjectThreadTileState();
}

class _ProjectThreadTileState extends State<_ProjectThreadTile> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversation = widget.conversation;
    final showDeleteAction = _isHovering;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: ListTile(
        key: ValueKey('drawer-thread-${conversation.id}'),
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.only(left: 44, right: 8),
        selected: widget.isSelected,
        selectedTileColor: theme.hoverColor,
        title: Text(
          _conversationTitle(conversation),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        trailing: SizedBox(
          width: 64,
          child: Align(
            alignment: widget.isWorking && !showDeleteAction
                ? AlignmentDirectional.center
                : AlignmentDirectional.centerEnd,
            child: showDeleteAction
                ? IconButton(
                    key: ValueKey(
                      'drawer-thread-${conversation.id}-delete-button',
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'drawer.delete_tooltip'.tr(),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    onPressed: widget.onDelete,
                  )
                : widget.needsApproval
                ? Tooltip(
                    message: 'drawer.thread_approval_required_tooltip'.tr(),
                    child: Text(
                      key: ValueKey(
                        'drawer-thread-${conversation.id}-approval-label',
                      ),
                      'drawer.thread_approval_required'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  )
                : widget.isWorking
                ? Tooltip(
                    message: 'drawer.thread_working_tooltip'.tr(),
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        key: ValueKey(
                          'drawer-thread-${conversation.id}-working-indicator',
                        ),
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                        semanticsLabel: 'drawer.thread_working_tooltip'.tr(),
                      ),
                    ),
                  )
                : Text(
                    key: ValueKey(
                      'drawer-thread-${conversation.id}-date-label',
                    ),
                    _formatConversationDate(conversation.updatedAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
        onTap: widget.onTap,
      ),
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
      selectedTileColor: theme.hoverColor,
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

class _SearchDrawerTile extends StatelessWidget {
  const _SearchDrawerTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const ValueKey('drawer-search'),
      dense: true,
      leading: const Icon(Icons.search),
      title: Text('drawer.search_tooltip'.tr()),
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
