import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/presentation/providers/coding_environment_snapshot_provider.dart';
import '../../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../../chat/presentation/providers/conversations_notifier.dart';
import '../../data/project_git_status_reader.dart';
import '../../domain/project_task_progress.dart';
import '../../domain/project_task_status.dart';
import 'project_task_progress_provider.dart';

final projectTaskGitReaderProvider = Provider<ProjectGitStatusReader>(
  (ref) => const ProjectGitStatusReader(),
);

/// A project task's state derived from its saved thread and git, keyed by
/// conversation id; null for a thread that is not a started roadmap task.
///
/// Recomputed when the thread's turns, captured changes, subtask progress or
/// goal change, and when the sidebar's Changes section is refreshed, so work
/// done by hand after a stop (a manual fix, a suggestion button, a commit)
/// moves the task on. Skipped while a workflow run is reporting live.
final projectTaskStatusProvider = FutureProvider.autoDispose
    .family<ProjectTaskProgress?, String>((ref, conversationId) async {
      final running = ref.watch(
        projectTaskProgressProvider.select(
          (all) => all[conversationId]?.outcome == ProjectTaskOutcome.running,
        ),
      );
      if (running) return null;
      ref.watch(
        conversationsNotifierProvider.select((state) {
          final task = state.conversationForId(conversationId);
          return (
            task?.messages.length,
            task?.turnDiffs.length,
            task?.goal,
            task?.executionProgress,
            task?.workflowSpec,
          );
        }),
      );
      final task = ref
          .read(conversationsNotifierProvider)
          .conversationForId(conversationId);
      if (task == null || ProjectTaskStatus.derive(task) == null) return null;
      final root = ref
          .read(codingProjectsNotifierProvider)
          .findById(task.projectId)
          ?.rootPath
          .trim();
      if (root == null || root.isEmpty) return ProjectTaskStatus.derive(task);
      // Follows the Changes section's refresh button and rollbacks.
      ref.watch(codingWorktreeDiffProvider(root));
      final reader = ref.read(projectTaskGitReaderProvider);
      final paths = ProjectTaskStatus.taskPaths(task);
      final files = await reader.readTaskPatch(root, paths);
      return ProjectTaskStatus.derive(
        task,
        git: await reader.readTaskState(root, paths),
        patch: files == null ? null : ProjectTaskStatus.fingerprint(files),
      );
    });
