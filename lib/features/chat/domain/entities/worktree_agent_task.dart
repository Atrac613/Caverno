import 'package:freezed_annotation/freezed_annotation.dart';

part 'worktree_agent_task.freezed.dart';
part 'worktree_agent_task.g.dart';

enum WorktreeAgentTaskStatus {
  queued,
  running,
  needsRecovery,
  completed,
  failed,
  cancelled,
}

@freezed
abstract class WorktreeAgentChangedFileEvidence
    with _$WorktreeAgentChangedFileEvidence {
  const factory WorktreeAgentChangedFileEvidence({
    required String path,
    @Default('') String content,
    String? contentHash,
    @Default(0) int byteSize,
    @Default(false) bool deleted,
    @Default(false) bool truncated,
  }) = _WorktreeAgentChangedFileEvidence;

  factory WorktreeAgentChangedFileEvidence.fromJson(
    Map<String, dynamic> json,
  ) => _$WorktreeAgentChangedFileEvidenceFromJson(json);
}

@freezed
abstract class WorktreeAgentTask with _$WorktreeAgentTask {
  const WorktreeAgentTask._();

  const factory WorktreeAgentTask({
    required String id,
    @JsonKey(unknownEnumValue: WorktreeAgentTaskStatus.needsRecovery)
    @Default(WorktreeAgentTaskStatus.queued)
    WorktreeAgentTaskStatus status,
    @Default('') String title,
    @Default('') String prompt,
    @Default('') String codingProjectId,

    /// The saved plan task this worktree child was admitted against.
    ///
    /// Empty for the two entry points that predate parent delegation -- the UI
    /// and LL37's approved repairs -- which have no plan task to bind to. The
    /// acceptance audit needs it for the same reason `SubagentTask` does: without
    /// the binding there is no way to tell which result is the one being
    /// accepted.
    @Default('') String workflowTaskId,
    @Default('main') String baseBranch,
    required String branchName,
    required String worktreePath,
    @Default('') String checkpointLineageId,
    @Default('') String endpointId,
    @Default('') String verificationCommand,

    /// The files the saved task said it would change.
    ///
    /// Carried so the audit can tell "changed nothing, as expected" from
    /// "changed nothing, and said it would": a task that declares no target
    /// files owes no changed-file evidence, which is the rule the subagent side
    /// already had for an inspecting child.
    @Default(<String>[]) List<String> expectedTargetFiles,
    @Default(<String>[]) List<String> objectiveAcceptanceCriteria,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? startedAt,
    DateTime? finishedAt,
    @Default('') String resultSummary,
    @Default(false) bool verifiedGreen,
    @Default('') String verificationSummary,
    @Default(<WorktreeAgentChangedFileEvidence>[])
    List<WorktreeAgentChangedFileEvidence> changedFiles,
    @Default(false) bool changedFileEvidenceTruncated,
    @Default('') String recoveryNote,
    @Default('') String error,
  }) = _WorktreeAgentTask;

  factory WorktreeAgentTask.fromJson(Map<String, dynamic> json) =>
      _$WorktreeAgentTaskFromJson(json);

  static String normalizeWorktreePath(String path) {
    final trimmed = path.trim();
    if (trimmed.length <= 1) return trimmed;
    var end = trimmed.length;
    while (end > 1) {
      final codeUnit = trimmed.codeUnitAt(end - 1);
      if (codeUnit != 47 && codeUnit != 92) break;
      end--;
    }
    return trimmed.substring(0, end);
  }

  String get normalizedWorktreePath => normalizeWorktreePath(worktreePath);

  bool get isTerminal =>
      status == WorktreeAgentTaskStatus.completed ||
      status == WorktreeAgentTaskStatus.failed ||
      status == WorktreeAgentTaskStatus.cancelled;

  bool get isRecoverable => status == WorktreeAgentTaskStatus.needsRecovery;

  bool get occupiesWorktree =>
      status == WorktreeAgentTaskStatus.queued ||
      status == WorktreeAgentTaskStatus.running ||
      status == WorktreeAgentTaskStatus.needsRecovery;
}
