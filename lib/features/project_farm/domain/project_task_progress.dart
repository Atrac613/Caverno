/// The stages a dashboard-started roadmap task moves through, in order.
/// [repair] repeats with [review] until the review is clean or the repair
/// rounds run out.
enum ProjectTaskPhase { decompose, implement, review, repair, commit }

/// How the workflow run ended, or [running] while it has not.
///
/// [paused], [unreviewed] and [readyToCommit] are derived from the saved
/// thread and git when no run is live: a task stopped part-way through its
/// subtasks, one whose changes are newer than its last review, and one whose
/// current changes passed review but are not committed.
enum ProjectTaskOutcome {
  running,
  committed,
  findingsRemain,
  stopped,
  paused,
  unreviewed,
  readyToCommit,
}

/// Where a project task's workflow stands, for the sidebar.
///
/// Subtask completion itself lives in the conversation's execution progress,
/// which the Plan Mode progress rows already render; this only says which
/// stage is running and how far the implementation has got.
final class ProjectTaskProgress {
  const ProjectTaskProgress({
    required this.phase,
    this.outcome = ProjectTaskOutcome.running,
    this.subtaskIndex = 0,
    this.subtaskCount = 0,
    this.repairRound = 0,
    this.stopReason,
  });

  final ProjectTaskPhase phase;
  final ProjectTaskOutcome outcome;

  /// Zero-based index of the subtask being implemented.
  final int subtaskIndex;

  /// Subtasks the task was split into; zero until decomposition finishes.
  final int subtaskCount;

  /// Repair rounds started so far.
  final int repairRound;
  final String? stopReason;

  /// Subtasks finished so far: all of them once implementation is behind the
  /// workflow, otherwise the ones before the running subtask.
  int get completedSubtasks => phase == ProjectTaskPhase.decompose
      ? 0
      : phase == ProjectTaskPhase.implement &&
            outcome != ProjectTaskOutcome.committed
      ? subtaskIndex.clamp(0, subtaskCount)
      : subtaskCount;

  ProjectTaskProgress copyWith({
    ProjectTaskPhase? phase,
    ProjectTaskOutcome? outcome,
    int? subtaskIndex,
    int? subtaskCount,
    int? repairRound,
    String? stopReason,
  }) => ProjectTaskProgress(
    phase: phase ?? this.phase,
    outcome: outcome ?? this.outcome,
    subtaskIndex: subtaskIndex ?? this.subtaskIndex,
    subtaskCount: subtaskCount ?? this.subtaskCount,
    repairRound: repairRound ?? this.repairRound,
    stopReason: stopReason ?? this.stopReason,
  );
}
