import 'package:freezed_annotation/freezed_annotation.dart';

part 'subagent_task.freezed.dart';
part 'subagent_task.g.dart';

/// Lifecycle states for a delegated subagent run.
///
/// Mirrors the terminal-state semantics used by the CC task system: a task
/// settles into exactly one of [completed], [failed], or [cancelled] and never
/// transitions afterwards.
enum SubagentTaskStatus { pending, running, completed, failed, cancelled }

/// A single subagent delegation spawned from the main chat loop.
///
/// The parent LLM triggers one of these via the `spawn_subagent` tool. The
/// child runs its own tool-calling loop with the parent's inherited tools
/// (minus `spawn_subagent` itself, to keep delegation depth at 1) and returns a
/// summary to the parent. Background tasks (PR-B) keep the same shape but run
/// asynchronously and surface progress through the UI.
@freezed
abstract class SubagentTask with _$SubagentTask {
  const SubagentTask._();

  const factory SubagentTask({
    required String id,
    @Default(SubagentTaskStatus.pending) SubagentTaskStatus status,
    @Default('') String description,
    String? parentToolUseId,
    @Default('') String prompt,
    @Default('') String output,
    @Default('') String resultSummary,
    DateTime? startedAt,
    DateTime? finishedAt,
    @Default(false) bool isBackground,
    @Default(false) bool notified,
    String? error,
  }) = _SubagentTask;

  factory SubagentTask.fromJson(Map<String, dynamic> json) =>
      _$SubagentTaskFromJson(json);

  /// True once the task has settled and will not transition further.
  bool get isTerminal =>
      status == SubagentTaskStatus.completed ||
      status == SubagentTaskStatus.failed ||
      status == SubagentTaskStatus.cancelled;

  /// True while the task is still occupying a delegation slot.
  bool get isActive =>
      status == SubagentTaskStatus.pending ||
      status == SubagentTaskStatus.running;
}
