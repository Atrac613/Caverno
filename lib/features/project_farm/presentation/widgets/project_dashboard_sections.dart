import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../chat/domain/entities/conversation.dart';
import '../../../chat/domain/entities/conversation_goal.dart';
import '../../../chat/domain/entities/worktree_agent_task.dart';
import '../../data/project_git_status_reader.dart';
import '../../domain/entities/roadmap_snapshot.dart';

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.labelLarge)),
                ?action,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

/// The roadmap's next task, labeled by what the verifier made of it.
class NextTaskCard extends StatelessWidget {
  const NextTaskCard({
    super.key,
    required this.snapshot,
    required this.hasRoadmap,
    required this.refreshing,
    required this.onStartWork,
    this.onChangeRoadmap,
    this.onPinTask,
    this.onClearPin,
  });

  final VoidCallback? onChangeRoadmap;
  final VoidCallback? onPinTask;
  final VoidCallback? onClearPin;

  final RoadmapSnapshot? snapshot;
  final bool hasRoadmap;
  final bool refreshing;
  final ValueChanged<RoadmapSnapshot> onStartWork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = snapshot;
    final Widget body;
    if (current == null) {
      body = Text(
        hasRoadmap || refreshing
            ? 'project_dashboard.extracting'.tr()
            : 'project_dashboard.no_roadmap'.tr(),
        key: const ValueKey('project-dashboard-next-empty'),
      );
    } else if (current.status == RoadmapSnapshotStatus.failed) {
      body = Text(
        'project_dashboard.extraction_failed'.tr(),
        key: const ValueKey('project-dashboard-next-failed'),
      );
    } else if (current.recommended == null) {
      body = Text(
        'project_dashboard.no_recommendation'.tr(),
        key: const ValueKey('project-dashboard-next-none'),
      );
    } else {
      final item = current.recommended!;
      final verified = current.status == RoadmapSnapshotStatus.verified;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (current.pinned)
                Chip(
                  key: const ValueKey('project-dashboard-pinned'),
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.push_pin_outlined, size: 16),
                  label: Text('project_dashboard.pinned'.tr()),
                ),
              Chip(
                key: ValueKey(
                  verified
                      ? 'project-dashboard-verified'
                      : 'project-dashboard-unverified',
                ),
                visualDensity: VisualDensity.compact,
                avatar: Icon(
                  verified ? Icons.check : Icons.help_outline,
                  size: 16,
                ),
                label: Text(
                  verified
                      ? 'project_dashboard.verified'.tr()
                      : 'project_dashboard.unverified'.tr(),
                ),
              ),
              Text(
                item.line == null
                    ? current.roadmapPath
                    : '${current.roadmapPath}:${item.line}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [item.id, item.title].where((part) => part.isNotEmpty).join(' · '),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '"${item.quote}"',
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              key: const ValueKey('project-dashboard-start-work'),
              icon: const Icon(Icons.play_arrow),
              label: Text('project_dashboard.start_work'.tr()),
              onPressed: () => onStartWork(current),
            ),
          ),
        ],
      );
    }
    return _SectionCard(
      title: 'project_dashboard.next_task'.tr(),
      action: PopupMenuButton<String>(
        key: const ValueKey('project-dashboard-next-menu'),
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (value) => switch (value) {
          'roadmap' => onChangeRoadmap?.call(),
          'pin' => onPinTask?.call(),
          _ => onClearPin?.call(),
        },
        itemBuilder: (_) => [
          if (onChangeRoadmap != null)
            PopupMenuItem(
              value: 'roadmap',
              child: Text('project_dashboard.change_roadmap'.tr()),
            ),
          if (onPinTask != null)
            PopupMenuItem(
              value: 'pin',
              child: Text('project_dashboard.pin_task'.tr()),
            ),
          if (current?.pinned == true && onClearPin != null)
            PopupMenuItem(
              value: 'clear',
              child: Text('project_dashboard.clear_pin'.tr()),
            ),
        ],
      ),
      child: body,
    );
  }
}

/// Current and blocked items the verifier kept.
class RoadmapItemsCard extends StatelessWidget {
  const RoadmapItemsCard({super.key, required this.snapshot});

  final RoadmapSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    List<Widget> rows(List<RoadmapItemSnapshot> items) => [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            [item.id, item.title].where((part) => part.isNotEmpty).join(' · '),
          ),
        ),
    ];
    return _SectionCard(
      title: 'project_dashboard.in_progress'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (snapshot.current.isEmpty)
            Text(
              'project_dashboard.none'.tr(),
              style: theme.textTheme.bodySmall,
            )
          else
            ...rows(snapshot.current),
          const SizedBox(height: 8),
          Text(
            'project_dashboard.blocked'.tr(),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          if (snapshot.blocked.isEmpty)
            Text(
              'project_dashboard.none'.tr(),
              style: theme.textTheme.bodySmall,
            )
          else
            ...rows(snapshot.blocked),
        ],
      ),
    );
  }
}

/// The project's coding threads with their run and goal state.
class ProjectThreadsCard extends StatefulWidget {
  const ProjectThreadsCard({
    super.key,
    required this.threads,
    required this.isBusy,
    required this.needsApproval,
    required this.onOpen,
    this.pageSize = defaultPageSize,
  });

  static const int defaultPageSize = 10;

  final List<Conversation> threads;
  final bool Function(String conversationId) isBusy;
  final bool Function(String conversationId) needsApproval;
  final ValueChanged<String> onOpen;
  final int pageSize;

  @override
  State<ProjectThreadsCard> createState() => _ProjectThreadsCardState();
}

class _ProjectThreadsCardState extends State<ProjectThreadsCard> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = sortThreadsForDashboard(
      widget.threads,
      isBusy: widget.isBusy,
      needsApproval: widget.needsApproval,
    );
    final pageCount = (sorted.length / widget.pageSize).ceil();
    // A thread list that shrank (a delete, a move) must not strand the user
    // on a page that no longer exists.
    final page = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
    final start = page * widget.pageSize;
    final end = (start + widget.pageSize).clamp(0, sorted.length);
    return _SectionCard(
      title: 'project_dashboard.threads'.tr(),
      child: sorted.isEmpty
          ? Text('project_dashboard.no_threads'.tr())
          : Column(
              children: [
                for (final thread in sorted.sublist(start, end))
                  ListTile(
                    key: ValueKey('project-dashboard-thread-${thread.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      thread.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: thread.goal == null
                        ? null
                        : Text(
                            'project_dashboard.goal_status'.tr(
                              args: [_goalLabel(thread.goal!.status)],
                            ),
                          ),
                    trailing: Text(
                      widget.needsApproval(thread.id)
                          ? 'project_dashboard.thread_needs_approval'.tr()
                          : widget.isBusy(thread.id)
                          ? 'project_dashboard.thread_running'.tr()
                          : 'project_dashboard.thread_idle'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: widget.needsApproval(thread.id)
                            ? theme.colorScheme.error
                            : null,
                      ),
                    ),
                    onTap: () => widget.onOpen(thread.id),
                  ),
                if (pageCount > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'project_dashboard.thread_range'.tr(
                          args: ['${start + 1}', '$end', '${sorted.length}'],
                        ),
                        key: const ValueKey('project-dashboard-thread-range'),
                        style: theme.textTheme.bodySmall,
                      ),
                      IconButton(
                        key: const ValueKey('project-dashboard-thread-prev'),
                        tooltip: 'project_dashboard.previous_page'.tr(),
                        icon: const Icon(Icons.chevron_left),
                        onPressed: page > 0
                            ? () => setState(() => _page = page - 1)
                            : null,
                      ),
                      IconButton(
                        key: const ValueKey('project-dashboard-thread-next'),
                        tooltip: 'project_dashboard.next_page'.tr(),
                        icon: const Icon(Icons.chevron_right),
                        onPressed: page < pageCount - 1
                            ? () => setState(() => _page = page + 1)
                            : null,
                      ),
                    ],
                  ),
              ],
            ),
    );
  }

  static String _goalLabel(ConversationGoalStatus status) =>
      'project_dashboard.goal.${status.name}'.tr();
}

/// Dashboard order: threads waiting on the user first, then running ones,
/// then the rest, each group newest first. Paging never hides a thread that
/// needs the user behind the first page.
List<Conversation> sortThreadsForDashboard(
  Iterable<Conversation> threads, {
  required bool Function(String conversationId) isBusy,
  required bool Function(String conversationId) needsApproval,
}) {
  int rank(Conversation thread) => needsApproval(thread.id)
      ? 0
      : isBusy(thread.id)
      ? 1
      : 2;
  return threads.toList()..sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : b.updatedAt.compareTo(a.updatedAt);
  });
}

/// Worktree agents and git state.
class ProjectStatusRow extends StatelessWidget {
  const ProjectStatusRow({super.key, required this.agents, required this.git});

  final List<WorktreeAgentTask> agents;
  final ProjectGitStatus? git;

  @override
  Widget build(BuildContext context) {
    final running = agents
        .where((task) => task.status == WorktreeAgentTaskStatus.running)
        .length;
    final completed = agents
        .where((task) => task.status == WorktreeAgentTaskStatus.completed)
        .length;
    final status = git;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 320,
          child: _SectionCard(
            title: 'project_dashboard.worktree_agents'.tr(),
            child: Text(
              'project_dashboard.agents_summary'.tr(
                args: ['$running', '$completed'],
              ),
            ),
          ),
        ),
        SizedBox(
          width: 320,
          child: _SectionCard(
            title: 'project_dashboard.git'.tr(),
            child: status == null
                ? Text('project_dashboard.git_unavailable'.tr())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          status.branch,
                          if (status.ahead != null)
                            'project_dashboard.ahead'.tr(
                              args: ['${status.ahead}'],
                            ),
                          status.changedFiles == 0
                              ? 'project_dashboard.clean'.tr()
                              : 'project_dashboard.changed'.tr(
                                  args: ['${status.changedFiles}'],
                                ),
                        ].join(' · '),
                      ),
                      Text(
                        status.lastCommit,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
