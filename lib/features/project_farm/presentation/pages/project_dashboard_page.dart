import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/workspace_mode.dart';
import '../../../chat/presentation/providers/chat_notifier.dart';
import '../../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../../chat/presentation/providers/conversations_notifier.dart';
import '../../../chat/presentation/providers/worktree_agent_task_registry_notifier.dart';
import '../../application/project_task_starter.dart';
import '../../data/project_git_status_reader.dart';
import '../../domain/entities/roadmap_snapshot.dart';
import '../providers/roadmap_snapshot_providers.dart';
import '../widgets/project_dashboard_sections.dart';

/// Pushes the dashboard for [projectId]. Completes with the id of a thread the
/// user opened or started from it, for the caller to select.
Future<String?> openProjectDashboard(BuildContext context, String projectId) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ProjectDashboardPage(projectId: projectId),
      ),
    );

/// A project at a glance: the roadmap's next task, what is in progress or
/// blocked, the project's threads, worktree agents, and git state (FARM1).
///
/// Rendering never waits on a model: it shows the cached roadmap snapshot and
/// refreshes it in the background.
class ProjectDashboardPage extends ConsumerStatefulWidget {
  const ProjectDashboardPage({
    super.key,
    required this.projectId,
    this.gitReader = const ProjectGitStatusReader(),
  });

  final String projectId;
  final ProjectGitStatusReader gitReader;

  @override
  ConsumerState<ProjectDashboardPage> createState() =>
      _ProjectDashboardPageState();
}

class _ProjectDashboardPageState extends ConsumerState<ProjectDashboardPage> {
  RoadmapSnapshot? _snapshot;
  ProjectGitStatus? _git;
  bool _refreshing = false;
  bool _hasRoadmap = true;

  @override
  void initState() {
    super.initState();
    _snapshot = ref
        .read(roadmapSnapshotServiceProvider)
        .cachedSnapshot(widget.projectId);
    unawaited(_refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    final project = ref
        .read(codingProjectsNotifierProvider)
        .findById(widget.projectId);
    if (project == null) return;
    setState(() => _refreshing = true);
    final service = ref.read(roadmapSnapshotServiceProvider);
    final results = await Future.wait<Object?>([
      service.refresh(
        projectId: project.id,
        projectRoot: project.rootPath,
        force: force,
      ),
      widget.gitReader.read(project.rootPath),
    ]);
    if (!mounted) return;
    setState(() {
      _snapshot = results[0] as RoadmapSnapshot? ?? _snapshot;
      _hasRoadmap = results[0] != null || _snapshot != null;
      _git = results[1] as ProjectGitStatus?;
      _refreshing = false;
    });
  }

  Future<void> _startWork(RoadmapSnapshot snapshot) async {
    final item = snapshot.recommended;
    if (item == null) return;
    final conversationId = await startProjectTask(
      conversations: ref.read(conversationsNotifierProvider.notifier),
      readConversations: () => ref.read(conversationsNotifierProvider),
      projectId: widget.projectId,
      item: item,
      roadmapPath: snapshot.roadmapPath,
    );
    if (!mounted || conversationId == null) return;
    Navigator.of(context).pop(conversationId);
  }

  void _openConsole() {
    ref
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(workspaceMode: WorkspaceMode.chat);
    final id = ref.read(conversationsNotifierProvider).currentConversationId;
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(
      codingProjectsNotifierProvider.select(
        (state) => state.findById(widget.projectId),
      ),
    );
    if (project == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('project_dashboard.project_missing'.tr())),
      );
    }
    final threads = ref
        .watch(conversationsNotifierProvider)
        .conversations
        .where(
          (conversation) =>
              conversation.workspaceMode == WorkspaceMode.coding &&
              conversation.normalizedProjectId == project.id,
        )
        .toList(growable: false);
    // Rebuild on the per-thread signals the rows read.
    ref.watch(
      chatNotifierProvider.select(
        (state) => (state.approvalRequiredConversationIds, state.isLoading),
      ),
    );
    final chat = ref.read(chatNotifierProvider.notifier);
    final agents = ref
        .watch(worktreeAgentTaskRegistryNotifierProvider)
        .tasks
        .where((task) => task.codingProjectId == project.id)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        actions: [
          IconButton(
            key: const ValueKey('project-dashboard-refresh'),
            tooltip: 'project_dashboard.refresh'.tr(),
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _refreshing ? null : () => _refresh(force: true),
          ),
          TextButton.icon(
            key: const ValueKey('project-dashboard-console'),
            icon: const Icon(Icons.chat_bubble_outline),
            label: Text('project_dashboard.open_console'.tr()),
            onPressed: _openConsole,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NextTaskCard(
            snapshot: _snapshot,
            hasRoadmap: _hasRoadmap,
            refreshing: _refreshing,
            onStartWork: _startWork,
          ),
          const SizedBox(height: 12),
          if (_snapshot != null) ...[
            RoadmapItemsCard(snapshot: _snapshot!),
            const SizedBox(height: 12),
          ],
          ProjectThreadsCard(
            threads: threads,
            isBusy: chat.isConversationBusy,
            needsApproval: chat.isConversationAwaitingApproval,
            onOpen: (id) => Navigator.of(context).pop(id),
          ),
          const SizedBox(height: 12),
          ProjectStatusRow(agents: agents, git: _git),
        ],
      ),
    );
  }
}
