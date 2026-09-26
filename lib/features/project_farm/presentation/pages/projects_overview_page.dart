import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/workspace_mode.dart';
import '../../../chat/domain/entities/coding_project.dart';
import '../../../chat/presentation/providers/chat_notifier.dart';
import '../../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../../chat/presentation/providers/conversations_notifier.dart';
import '../../application/project_task_starter.dart';
import '../../domain/entities/project_proposal.dart';
import '../../domain/entities/roadmap_snapshot.dart';
import '../../domain/next_step_proposal_contract.dart';
import '../providers/roadmap_snapshot_providers.dart';
import 'project_dashboard_page.dart';

/// Pushes the cross-project overview. Completes with the id of a thread the
/// user opened or started from it, for the caller to select.
Future<String?> openProjectsOverview(BuildContext context) => Navigator.of(
  context,
).push<String>(MaterialPageRoute(builder: (_) => const ProjectsOverviewPage()));

/// Every coding project at a glance: its next task and what needs the user
/// (FARM3, first slice).
///
/// Shows cached snapshots only. Refresh all re-reads roadmaps one project at a
/// time, so the model is never asked for several extractions at once.
class ProjectsOverviewPage extends ConsumerStatefulWidget {
  const ProjectsOverviewPage({super.key});

  @override
  ConsumerState<ProjectsOverviewPage> createState() =>
      _ProjectsOverviewPageState();
}

class _ProjectsOverviewPageState extends ConsumerState<ProjectsOverviewPage> {
  final Map<String, RoadmapSnapshot?> _snapshots = {};
  final Map<String, ProjectProposal?> _proposals = {};
  String? _refreshingProjectId;
  bool _refreshingAll = false;

  RoadmapSnapshot? _snapshotFor(String projectId) =>
      _snapshots.containsKey(projectId)
      ? _snapshots[projectId]
      : ref.read(roadmapSnapshotServiceProvider).cachedSnapshot(projectId);

  ProjectProposal? _proposalFor(String projectId) =>
      _proposals.containsKey(projectId)
      ? _proposals[projectId]
      : ref.read(projectProposalServiceProvider).cachedProposal(projectId);

  List<ProposalThread> _threadsFor(String projectId) {
    final chat = ref.read(chatNotifierProvider.notifier);
    return [
      for (final thread
          in ref.read(conversationsNotifierProvider).conversations)
        if (thread.workspaceMode == WorkspaceMode.coding &&
            thread.normalizedProjectId == projectId)
          ProposalThread(
            title: thread.title,
            state: chat.isConversationAwaitingApproval(thread.id)
                ? 'needs_approval'
                : chat.isConversationBusy(thread.id)
                ? 'running'
                : 'idle',
            goal: thread.goal?.objective.split('\n').first,
            goalStatus: thread.goal?.status.name,
          ),
    ];
  }

  Future<void> _refreshAll(List<CodingProject> projects) async {
    setState(() => _refreshingAll = true);
    final service = ref.read(roadmapSnapshotServiceProvider);
    for (final project in projects) {
      if (!mounted) return;
      setState(() => _refreshingProjectId = project.id);
      final snapshot = await service.refresh(
        projectId: project.id,
        projectRoot: project.rootPath,
      );
      if (!mounted) return;
      final current = snapshot ?? _snapshotFor(project.id);
      setState(() => _snapshots[project.id] = current);
      // One at a time, like the roadmap reads, so calls never overlap.
      final proposal = await ref
          .read(projectProposalServiceProvider)
          .refresh(
            project: project,
            snapshot: current,
            threads: _threadsFor(project.id),
          );
      if (!mounted) return;
      setState(() => _proposals[project.id] = proposal);
    }
    if (!mounted) return;
    setState(() {
      _refreshingAll = false;
      _refreshingProjectId = null;
    });
  }

  Future<void> _openDashboard(CodingProject project) async {
    final id = await openProjectDashboard(context, project.id);
    if (!mounted) return;
    if (id != null) {
      Navigator.of(context).pop(id);
      return;
    }
    // The dashboard may have refreshed the snapshot.
    setState(() => _snapshots.remove(project.id));
  }

  void _startWork(
    CodingProject project,
    RoadmapSnapshot snapshot,
    RoadmapItemSnapshot item,
  ) {
    final id = startProjectTask(
      conversations: ref.read(conversationsNotifierProvider.notifier),
      projectId: project.id,
      item: item,
      roadmapPath: snapshot.roadmapPath,
    );
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(codingProjectsNotifierProvider).projects;
    final conversations = ref
        .watch(conversationsNotifierProvider)
        .conversations;
    ref.watch(
      chatNotifierProvider.select(
        (state) => (state.approvalRequiredConversationIds, state.isLoading),
      ),
    );
    final chat = ref.read(chatNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('project_overview.title'.tr()),
        actions: [
          TextButton.icon(
            key: const ValueKey('projects-overview-refresh-all'),
            icon: _refreshingAll
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text('project_overview.refresh_all'.tr()),
            onPressed: _refreshingAll ? null : () => _refreshAll(projects),
          ),
        ],
      ),
      body: projects.isEmpty
          ? Center(child: Text('drawer.no_projects'.tr()))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: projects.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final project = projects[index];
                final threads = conversations.where(
                  (c) =>
                      c.workspaceMode == WorkspaceMode.coding &&
                      c.normalizedProjectId == project.id,
                );
                return ProjectOverviewTile(
                  project: project,
                  snapshot: _snapshotFor(project.id),
                  refreshing: _refreshingProjectId == project.id,
                  running: threads
                      .where((t) => chat.isConversationBusy(t.id))
                      .length,
                  needsApproval: threads
                      .where((t) => chat.isConversationAwaitingApproval(t.id))
                      .length,
                  onOpenDashboard: () => _openDashboard(project),
                  proposal: _proposalFor(project.id),
                  onStartWork: (snapshot, item) =>
                      _startWork(project, snapshot, item),
                );
              },
            ),
    );
  }
}

/// One project row in the overview.
class ProjectOverviewTile extends StatelessWidget {
  const ProjectOverviewTile({
    super.key,
    required this.project,
    required this.snapshot,
    required this.refreshing,
    required this.running,
    required this.needsApproval,
    required this.onOpenDashboard,
    required this.onStartWork,
    this.proposal,
  });

  final CodingProject project;
  final RoadmapSnapshot? snapshot;
  final ProjectProposal? proposal;
  final bool refreshing;
  final int running;
  final int needsApproval;
  final VoidCallback onOpenDashboard;
  final void Function(RoadmapSnapshot snapshot, RoadmapItemSnapshot item)
  onStartWork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = snapshot;
    final item = current?.recommended;
    final verified = current?.status == RoadmapSnapshotStatus.verified;
    final startable = startableItem(current, proposal);
    final proposed = proposal;
    final String nextLabel;
    if (refreshing) {
      nextLabel = 'project_dashboard.extracting'.tr();
    } else if (current == null) {
      nextLabel = 'project_overview.not_read'.tr();
    } else if (item == null) {
      nextLabel = 'project_dashboard.no_recommendation'.tr();
    } else {
      nextLabel =
          '${[item.id, item.title].where((p) => p.isNotEmpty).join(' · ')}'
          '${verified ? '' : ' (${'project_dashboard.unverified'.tr()})'}';
    }
    return Card(
      key: ValueKey('projects-overview-${project.id}'),
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpenDashboard,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      nextLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (proposed != null &&
                        proposed.error == null &&
                        proposed.taskId.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Chip(
                            key: ValueKey(
                              'projects-overview-${project.id}-'
                              '${proposed.automatability}',
                            ),
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              'project_overview.automatability.'
                                      '${proposed.automatability}'
                                  .tr(),
                            ),
                          ),
                          Text(
                            'project_overview.proposal'.tr(
                              args: [proposed.taskId, proposed.rationale],
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'project_overview.thread_counts'.tr(
                        args: ['$running', '$needsApproval'],
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: needsApproval > 0
                            ? theme.colorScheme.error
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (startable != null) ...[
                const SizedBox(width: 12),
                FilledButton.tonal(
                  key: ValueKey('projects-overview-${project.id}-start'),
                  onPressed: () => onStartWork(current!, startable),
                  child: Text('project_dashboard.start_work'.tr()),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The item Start work would begin: the proposed one when it is a verified
/// next or in-progress item, otherwise the verified next task. Blocked items
/// and unverified ones are never startable.
RoadmapItemSnapshot? startableItem(
  RoadmapSnapshot? snapshot,
  ProjectProposal? proposal,
) {
  if (snapshot == null) return null;
  final verifiedNext = snapshot.status == RoadmapSnapshotStatus.verified
      ? snapshot.recommended
      : null;
  final startable = [
    ?verifiedNext,
    ...snapshot.current.where((item) => item.verified),
  ];
  final proposedId = proposal?.error == null ? proposal?.taskId ?? '' : '';
  if (proposedId.isNotEmpty) {
    final match = startable.where((item) => item.id == proposedId).firstOrNull;
    if (match != null) return match;
  }
  return verifiedNext;
}
