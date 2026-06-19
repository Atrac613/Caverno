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
    @Default('main') String baseBranch,
    required String branchName,
    required String worktreePath,
    @Default('') String checkpointLineageId,
    @Default('') String endpointId,
    @Default('') String verificationCommand,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? startedAt,
    DateTime? finishedAt,
    @Default('') String resultSummary,
    @Default(false) bool verifiedGreen,
    @Default('') String verificationSummary,
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
