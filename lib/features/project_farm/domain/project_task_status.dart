import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/conversation_goal.dart';
import '../../chat/domain/entities/conversation_workflow.dart';
import '../../chat/domain/entities/turn_diff.dart';
import 'entities/project_task_git_state.dart';
import 'project_task_progress.dart';

/// Where a roadmap task stands, read from what is saved rather than from the
/// workflow that last ran it.
///
/// The workflow's own progress lives in memory and only the workflow writes
/// it, so a task finished by hand after a stop (a manual fix, a suggestion
/// button, a commit from the terminal) kept showing the stage the run had
/// stopped in. The sidebar and the workflow's resume both read this instead, so what the
/// sidebar shows is where Resume continues.
abstract final class ProjectTaskStatus {
  /// The files this task changed: those recorded on its goal (an earlier
  /// run's and this run's earlier turns') and those its file tools captured.
  static List<String> taskPaths(Conversation task) => {
    ...?task.goal?.projectTaskInheritedPaths,
    for (final diff in task.turnDiffs)
      if (diff.source == TurnDiffSource.tool)
        for (final file in diff.files) file.filePath,
  }.toList();

  /// A stable digest of the changed [files], independent of their order, so
  /// a review verdict can be matched to the patch it covered.
  static String fingerprint(Iterable<TurnDiffFile> files) {
    final entries = [
      for (final file in files)
        if (file.hasChanges)
          '${file.filePath}\u0000${file.isBinary}${file.isLargeFile}'
              '\u0000${file.unifiedPatch}',
    ]..sort();
    return sha256.convert(utf8.encode(entries.join('\u0001'))).toString();
  }

  /// The index of the first unfinished subtask, or null when implementation
  /// is finished. A task saved without subtasks is finished once its goal is.
  static int? nextSubtask(Conversation task) {
    final subtasks = task.workflowSpec?.tasks ?? const [];
    if (subtasks.isEmpty) {
      return task.goal?.status == ConversationGoalStatus.completed ? null : 0;
    }
    final done = {
      for (final progress in task.executionProgress)
        if (progress.status == ConversationWorkflowTaskStatus.completed)
          progress.taskId,
    };
    final next = subtasks.indexWhere((subtask) => !done.contains(subtask.id));
    return next < 0 ? null : next;
  }

  /// The task's state, or null for a thread that is not a started roadmap
  /// task. [git] is the state of [taskPaths] and [patch] the fingerprint of
  /// their current change; either is null when git cannot be read, and the
  /// task then reads as unreviewed rather than committed or reviewed.
  static ProjectTaskProgress? derive(
    Conversation task, {
    ProjectTaskGitState? git,
    String? patch,
  }) {
    final goal = task.goal;
    if (goal == null || !goal.projectTaskAutoReview || task.messages.isEmpty) {
      return null;
    }
    return stage(task, git: git, patch: patch);
  }

  /// [derive] for any thread with a goal, started or not: the stage the
  /// saved state puts the task in.
  static ProjectTaskProgress stage(
    Conversation task, {
    ProjectTaskGitState? git,
    String? patch,
  }) {
    final review = task.goal?.projectTaskReview ?? ProjectTaskReviewState.none;
    final subtaskCount = task.workflowSpec?.tasks.length ?? 0;
    final next = nextSubtask(task);
    if (next != null) {
      return ProjectTaskProgress(
        phase: ProjectTaskPhase.implement,
        outcome: ProjectTaskOutcome.paused,
        subtaskIndex: next,
        subtaskCount: subtaskCount,
      );
    }
    ProjectTaskProgress at(
      ProjectTaskPhase phase,
      ProjectTaskOutcome outcome,
    ) => ProjectTaskProgress(
      phase: phase,
      outcome: outcome,
      subtaskIndex: subtaskCount,
      subtaskCount: subtaskCount,
    );
    if (git != null && git.dirtyPaths.isEmpty && taskPaths(task).isNotEmpty) {
      return at(ProjectTaskPhase.commit, ProjectTaskOutcome.committed);
    }
    final reviewed =
        patch != null &&
        review != ProjectTaskReviewState.none &&
        task.goal?.projectTaskReviewedPatch == patch;
    if (!reviewed) {
      return at(ProjectTaskPhase.review, ProjectTaskOutcome.unreviewed);
    }
    return review == ProjectTaskReviewState.clean
        ? at(ProjectTaskPhase.commit, ProjectTaskOutcome.readyToCommit)
        : at(ProjectTaskPhase.review, ProjectTaskOutcome.findingsRemain);
  }
}
