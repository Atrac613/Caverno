import 'package:freezed_annotation/freezed_annotation.dart';

part 'conversation_workflow.freezed.dart';
part 'conversation_workflow.g.dart';

enum ConversationExecutionMode { normal, planning }

enum ConversationWorkflowStage { idle, clarify, plan, tasks, implement, review }

enum ConversationWorkflowTaskStatus { pending, inProgress, completed, blocked }

enum ConversationExecutionValidationStatus { unknown, passed, failed }

enum ConversationExecutionTaskEventType {
  started,
  validated,
  blocked,
  unblocked,
  completed,
  replanned,
}

List<ConversationWorkflowTask> _workflowTasksFromJson(List<dynamic>? json) {
  if (json == null) {
    return const [];
  }
  return json
      .map(
        (item) =>
            ConversationWorkflowTask.fromJson(item as Map<String, dynamic>),
      )
      .toList(growable: false);
}

List<Map<String, dynamic>> _workflowTasksToJson(
  List<ConversationWorkflowTask> tasks,
) {
  return tasks.map((task) => task.toJson()).toList(growable: false);
}

List<ConversationExecutionTaskEvent> _executionEventsFromJson(
  List<dynamic>? json,
) {
  if (json == null) {
    return const [];
  }
  return json
      .map(
        (item) => ConversationExecutionTaskEvent.fromJson(
          item as Map<String, dynamic>,
        ),
      )
      .toList(growable: false);
}

List<Map<String, dynamic>> _executionEventsToJson(
  List<ConversationExecutionTaskEvent> events,
) {
  return events.map((event) => event.toJson()).toList(growable: false);
}

@freezed
abstract class ConversationWorkflowTask with _$ConversationWorkflowTask {
  const ConversationWorkflowTask._();

  const factory ConversationWorkflowTask({
    required String id,
    required String title,
    @Default(ConversationWorkflowTaskStatus.pending)
    ConversationWorkflowTaskStatus status,
    @Default(<String>[]) List<String> targetFiles,
    @Default('') String validationCommand,
    @Default('') String notes,
  }) = _ConversationWorkflowTask;

  factory ConversationWorkflowTask.fromJson(Map<String, dynamic> json) =>
      _$ConversationWorkflowTaskFromJson(json);

  bool get hasMetadata =>
      targetFiles.any((item) => item.trim().isNotEmpty) ||
      validationCommand.trim().isNotEmpty ||
      notes.trim().isNotEmpty;
}

@freezed
abstract class ConversationExecutionTaskProgress
    with _$ConversationExecutionTaskProgress {
  const ConversationExecutionTaskProgress._();

  const factory ConversationExecutionTaskProgress({
    required String taskId,
    @Default(ConversationWorkflowTaskStatus.pending)
    ConversationWorkflowTaskStatus status,
    @Default(ConversationExecutionValidationStatus.unknown)
    ConversationExecutionValidationStatus validationStatus,
    DateTime? updatedAt,
    DateTime? lastRunAt,
    DateTime? lastValidationAt,
    @Default('') String summary,
    @Default('') String blockedReason,
    @Default('') String lastValidationCommand,
    @Default('') String lastValidationSummary,
    @JsonKey(fromJson: _executionEventsFromJson, toJson: _executionEventsToJson)
    @Default(<ConversationExecutionTaskEvent>[])
    List<ConversationExecutionTaskEvent> events,
  }) = _ConversationExecutionTaskProgress;

  factory ConversationExecutionTaskProgress.fromJson(
    Map<String, dynamic> json,
  ) => _$ConversationExecutionTaskProgressFromJson(json);

  String? get normalizedSummary {
    final trimmed = summary.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get normalizedBlockedReason {
    final trimmed = blockedReason.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get normalizedValidationCommand {
    final trimmed = lastValidationCommand.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get normalizedValidationSummary {
    final trimmed = lastValidationSummary.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  List<ConversationExecutionTaskEvent> get recentEvents =>
      events.toList(growable: false);

  bool get hasMeaningfulState =>
      status != ConversationWorkflowTaskStatus.pending ||
      lastRunAt != null ||
      lastValidationAt != null ||
      validationStatus != ConversationExecutionValidationStatus.unknown ||
      normalizedSummary != null ||
      normalizedBlockedReason != null ||
      normalizedValidationCommand != null ||
      normalizedValidationSummary != null ||
      events.isNotEmpty;
}

@freezed
abstract class ConversationExecutionTaskEvent
    with _$ConversationExecutionTaskEvent {
  const ConversationExecutionTaskEvent._();

  const factory ConversationExecutionTaskEvent({
    required ConversationExecutionTaskEventType type,
    required DateTime createdAt,
    @Default('') String summary,
    @Default(ConversationWorkflowTaskStatus.pending)
    ConversationWorkflowTaskStatus status,
    @Default(ConversationExecutionValidationStatus.unknown)
    ConversationExecutionValidationStatus validationStatus,
    @Default('') String blockedReason,
    @Default('') String validationCommand,
    @Default('') String validationSummary,
  }) = _ConversationExecutionTaskEvent;

  factory ConversationExecutionTaskEvent.fromJson(Map<String, dynamic> json) =>
      _$ConversationExecutionTaskEventFromJson(json);

  String? get normalizedSummary {
    final trimmed = summary.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get normalizedBlockedReason {
    final trimmed = blockedReason.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get normalizedValidationCommand {
    final trimmed = validationCommand.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get normalizedValidationSummary {
    final trimmed = validationSummary.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

@freezed
abstract class ConversationWorkflowSpec with _$ConversationWorkflowSpec {
  const ConversationWorkflowSpec._();

  const factory ConversationWorkflowSpec({
    @Default('') String goal,
    @Default(<String>[]) List<String> constraints,
    @Default(<String>[]) List<String> acceptanceCriteria,
    @Default(<String>[]) List<String> openQuestions,
    @JsonKey(fromJson: _workflowTasksFromJson, toJson: _workflowTasksToJson)
    @Default(<ConversationWorkflowTask>[])
    List<ConversationWorkflowTask> tasks,
  }) = _ConversationWorkflowSpec;

  factory ConversationWorkflowSpec.fromJson(Map<String, dynamic> json) =>
      _$ConversationWorkflowSpecFromJson(json);

  bool get hasContent =>
      goal.trim().isNotEmpty ||
      constraints.any((item) => item.trim().isNotEmpty) ||
      acceptanceCriteria.any((item) => item.trim().isNotEmpty) ||
      openQuestions.any((item) => item.trim().isNotEmpty) ||
      tasks.any((task) => task.title.trim().isNotEmpty || task.hasMetadata);
}
