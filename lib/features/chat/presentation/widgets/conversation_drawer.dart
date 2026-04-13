import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/workspace_mode.dart';
import '../../domain/entities/coding_project.dart';
import '../../domain/entities/conversation.dart';
import '../providers/coding_projects_notifier.dart';
import '../providers/conversations_notifier.dart';

class ConversationDrawer extends ConsumerWidget {
  const ConversationDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsState = ref.watch(conversationsNotifierProvider);
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final projectsState = ref.watch(codingProjectsNotifierProvider);
    final projectsNotifier = ref.read(codingProjectsNotifierProvider.notifier);
    final isCodingWorkspace =
        conversationsState.activeWorkspaceMode == WorkspaceMode.coding;
    final activeProject = projectsState.findById(
      conversationsState.activeProjectId,
    );
    final visibleConversations = conversationsState.visibleConversations;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isCodingWorkspace
                          ? 'drawer.coding_title'.tr()
                          : 'drawer.title'.tr(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (visibleConversations.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined),
                      tooltip: isCodingWorkspace
                          ? 'drawer.delete_all_threads_tooltip'.tr()
                          : 'drawer.delete_all_tooltip'.tr(),
                      onPressed: () {
                        _showDeleteScopedDialog(
                          context,
                          conversationsNotifier,
                          isCodingWorkspace: isCodingWorkspace,
                        );
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: isCodingWorkspace
                        ? 'drawer.new_thread'.tr()
                        : 'drawer.new_conversation'.tr(),
                    onPressed: isCodingWorkspace && activeProject == null
                        ? null
                        : () {
                            conversationsNotifier.createNewConversation(
                              workspaceMode:
                                  conversationsState.activeWorkspaceMode,
                              projectId: activeProject?.id,
                            );
                            Navigator.pop(context);
                          },
                  ),
                ],
              ),
            ),
            if (isCodingWorkspace) ...[
              const Divider(height: 1),
              Expanded(
                flex: 4,
                child: _CodingProjectsSection(
                  projectsState: projectsState,
                  projectsNotifier: projectsNotifier,
                  conversationsNotifier: conversationsNotifier,
                  selectedProjectId: activeProject?.id,
                ),
              ),
            ],
            const Divider(height: 1),
            Expanded(
              flex: isCodingWorkspace ? 5 : 1,
              child: visibleConversations.isEmpty
                  ? Center(
                      child: Text(
                        isCodingWorkspace
                            ? 'drawer.no_threads'.tr()
                            : 'drawer.no_conversations'.tr(),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: visibleConversations.length,
                      itemBuilder: (context, index) {
                        final conversation = visibleConversations[index];
                        final isSelected =
                            conversation.id ==
                            conversationsState.currentConversationId;

                        return _ConversationTile(
                          conversation: conversation,
                          isSelected: isSelected,
                          isCodingWorkspace: isCodingWorkspace,
                          onTap: () {
                            conversationsNotifier.selectConversation(
                              conversation.id,
                            );
                            Navigator.pop(context);
                          },
                          onDelete: () {
                            _showDeleteDialog(
                              context,
                              conversationsNotifier,
                              conversation,
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
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
}

class _CodingProjectsSection extends ConsumerWidget {
  const _CodingProjectsSection({
    required this.projectsState,
    required this.projectsNotifier,
    required this.conversationsNotifier,
    required this.selectedProjectId,
  });

  final CodingProjectsState projectsState;
  final CodingProjectsNotifier projectsNotifier;
  final ConversationsNotifier conversationsNotifier;
  final String? selectedProjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        ListTile(
          title: Text(
            'drawer.projects'.tr(),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'chat.add_project'.tr(),
            onPressed: () => _pickProject(context, ref),
          ),
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
                  itemCount: projectsState.projects.length,
                  itemBuilder: (context, index) {
                    final project = projectsState.projects[index];
                    final isSelected = project.id == selectedProjectId;
                    return ListTile(
                      selected: isSelected,
                      selectedTileColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      leading: Icon(
                        Icons.folder_outlined,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        project.rootPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        tooltip: 'drawer.delete_tooltip'.tr(),
                        onPressed: () =>
                            _showDeleteProjectDialog(context, ref, project),
                      ),
                      onTap: () {
                        projectsNotifier.selectProject(project.id);
                        conversationsNotifier.activateWorkspace(
                          workspaceMode: WorkspaceMode.coding,
                          projectId: project.id,
                          createIfMissing: true,
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _pickProject(BuildContext context, WidgetRef ref) async {
    final selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory == null || !context.mounted) return;

    final project = await ref
        .read(codingProjectsNotifierProvider.notifier)
        .addProject(selectedDirectory);
    if (project == null || !context.mounted) return;

    projectsNotifier.selectProject(project.id);
    conversationsNotifier.activateWorkspace(
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
      createIfMissing: true,
    );
  }

  Future<void> _showDeleteProjectDialog(
    BuildContext context,
    WidgetRef ref,
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

    final fallbackProjectId = ref
        .read(codingProjectsNotifierProvider)
        .selectedProjectId;
    conversationsNotifier.activateWorkspace(
      workspaceMode: WorkspaceMode.coding,
      projectId: fallbackProjectId,
      createIfMissing: fallbackProjectId != null,
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.isSelected,
    required this.isCodingWorkspace,
    required this.onTap,
    required this.onDelete,
  });

  final Conversation conversation;
  final bool isSelected;
  final bool isCodingWorkspace;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.3,
      ),
      leading: Icon(
        isCodingWorkspace ? Icons.code : Icons.chat_bubble_outline,
        color: isSelected ? theme.colorScheme.primary : null,
      ),
      title: Text(
        conversation.title == defaultConversationTitle
            ? (isCodingWorkspace
                  ? 'drawer.new_thread'.tr()
                  : 'drawer.new_conversation'.tr())
            : conversation.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        _formatDate(conversation.updatedAt),
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

  String _formatDate(DateTime date) {
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
}
