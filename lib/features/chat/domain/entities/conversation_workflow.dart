import 'package:freezed_annotation/freezed_annotation.dart';

part 'conversation_workflow.freezed.dart';
part 'conversation_workflow.g.dart';

enum ConversationExecutionMode { normal, planning }

enum ConversationWorkflowStage { idle, clarify, plan, tasks, implement, review }

enum ConversationWorkflowTaskStatus { pending, inProgress, completed, blocked }

enum ConversationExecutionValidationStatus { unknown, passed, failed }

enum ConversationOpenQuestionStatus {
  unresolved,
  needsUserInput,
  resolved,
  deferred,
}

enum ConversationExecutionTaskEventType {
  started,
  validated,
  blocked,
  unblocked,
  completed,
  replanned,
}

enum ConversationContractSourceKind {
  userMessage,
  specificationFile,
  approvedPlan,
  workspaceObservation,
  userConfirmedAssumption,
  legacy,
}

enum ConversationContractItemKind {
  goal,
  constraint,
  acceptanceCriterion,
  openQuestion,
  task,
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

List<ConversationContractSourceReference> _contractSourcesFromJson(
  List<dynamic>? json,
) {
  if (json == null) return const [];
  return json
      .map(
        (item) => ConversationContractSourceReference.fromJson(
          item as Map<String, dynamic>,
        ),
      )
      .toList(growable: false);
}

List<Map<String, dynamic>> _contractSourcesToJson(
  List<ConversationContractSourceReference> sources,
) => sources.map((source) => source.toJson()).toList(growable: false);

List<ConversationTaskPrecondition> _taskPreconditionsFromJson(
  List<dynamic>? json,
) {
  if (json == null) return const [];
  return json
      .map(
        (item) =>
            ConversationTaskPrecondition.fromJson(item as Map<String, dynamic>),
      )
      .toList(growable: false);
}

List<Map<String, dynamic>> _taskPreconditionsToJson(
  List<ConversationTaskPrecondition> preconditions,
) => preconditions.map((item) => item.toJson()).toList(growable: false);

List<ConversationContractItemProvenance> _contractProvenanceFromJson(
  List<dynamic>? json,
) {
  if (json == null) return const [];
  return json
      .map(
        (item) => ConversationContractItemProvenance.fromJson(
          item as Map<String, dynamic>,
        ),
      )
      .toList(growable: false);
}

List<Map<String, dynamic>> _contractProvenanceToJson(
  List<ConversationContractItemProvenance> provenance,
) => provenance.map((item) => item.toJson()).toList(growable: false);

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
abstract class ConversationOpenQuestionProgress
    with _$ConversationOpenQuestionProgress {
  const ConversationOpenQuestionProgress._();

  const factory ConversationOpenQuestionProgress({
    required String questionId,
    required String question,
    @Default(ConversationOpenQuestionStatus.unresolved)
    ConversationOpenQuestionStatus status,
    @Default('') String note,
    DateTime? updatedAt,
  }) = _ConversationOpenQuestionProgress;

  factory ConversationOpenQuestionProgress.fromJson(
    Map<String, dynamic> json,
  ) => _$ConversationOpenQuestionProgressFromJson(json);

  String? get normalizedNote {
    final trimmed = note.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// The Anabasis parent's record that a task's result was accepted.
///
/// **One writer, by design.** The acceptance model has four levels: the
/// mechanical and evidence ones are derived from what the runners record, and
/// the semantic one is the parent's own judgement — the reason Anabasis
/// exists. Nothing derives a judgement, so it has to be written, and §10 of
/// the design gives it exactly one author. `ConversationExecutionValidationStatus`
/// is the cautionary tale: three writers, one of them judging prose, and a
/// fourth added and reverted after the investigation found stderr outranking a
/// clean exit 0.
///
/// [premises] is what makes an acceptance revisitable. ANA2's contradiction
/// policy bars a result whose premise has lapsed, and it can only tell that if
/// the premises in force at acceptance time were written down.
@freezed
abstract class ConversationTaskAcceptance with _$ConversationTaskAcceptance {
  const ConversationTaskAcceptance._();

  const factory ConversationTaskAcceptance({
    required String taskId,
    required DateTime acceptedAt,

    /// Why the parent judged this to satisfy the goal, in its own words.
    @Default('') String rationale,

    /// What the mechanical and evidence levels rested on: the verification
    /// command that passed, the files the child changed.
    @Default(<String>[]) List<String> evidence,

    /// The confirmed assumptions in force when this was accepted.
    @Default(<String>[]) List<String> premises,
  }) = _ConversationTaskAcceptance;

  factory ConversationTaskAcceptance.fromJson(Map<String, dynamic> json) =>
      _$ConversationTaskAcceptanceFromJson(json);

  bool get isValid => taskId.trim().isNotEmpty;
}

/// What kind of state a precondition points at.
enum ConversationTaskPreconditionKind {
  /// Another task in the same contract, by task id.
  task,

  /// A contract item marked as an assumption, by its provenance item id.
  assumption,

  /// An open question, by its text — the same key
  /// `ConversationOpenQuestionProgress` is tracked under.
  question,
}

/// One edge in the decomposition graph: this task waits on [ref].
///
/// Readiness is never stored. Storing it would add a second writer for
/// something the graph already determines, which is the failure mode this
/// codebase has paid for before.
@freezed
abstract class ConversationTaskPrecondition
    with _$ConversationTaskPrecondition {
  const ConversationTaskPrecondition._();

  const factory ConversationTaskPrecondition({
    required ConversationTaskPreconditionKind kind,
    required String ref,
  }) = _ConversationTaskPrecondition;

  factory ConversationTaskPrecondition.fromJson(Map<String, dynamic> json) =>
      _$ConversationTaskPreconditionFromJson(json);

  bool get isValid => ref.trim().isNotEmpty;
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

    /// What has to hold before this task can start (ANA1).
    ///
    /// A plain dependency list would only cover one of the three shapes real
    /// blocking takes here. Each kind points at state that already exists, so
    /// the new structure is the edge and the predicate, never new state on
    /// either end.
    @JsonKey(
      fromJson: _taskPreconditionsFromJson,
      toJson: _taskPreconditionsToJson,
    )
    @Default(<ConversationTaskPrecondition>[])
    List<ConversationTaskPrecondition> preconditions,
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

final class ExecutionTaskView {
  const ExecutionTaskView({required this.task, this.progress});

  final ConversationWorkflowTask task;
  final ConversationExecutionTaskProgress? progress;

  ConversationWorkflowTaskStatus get status =>
      progress?.status ?? ConversationWorkflowTaskStatus.pending;

  bool get hasLegacyAuthoredExecutionState =>
      progress == null && task.status != ConversationWorkflowTaskStatus.pending;

  ConversationWorkflowTask get legacyProjectedTask {
    final currentProgress = progress;
    if (currentProgress == null) {
      return task;
    }
    return task.copyWith(status: currentProgress.status);
  }
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
abstract class ConversationContractSourceReference
    with _$ConversationContractSourceReference {
  const ConversationContractSourceReference._();

  const factory ConversationContractSourceReference({
    required String id,
    required ConversationContractSourceKind kind,
    @Default('') String locator,
    @Default('') String contentHash,
    @Default('') String section,
    @Default('') String toolCallId,
  }) = _ConversationContractSourceReference;

  factory ConversationContractSourceReference.fromJson(
    Map<String, dynamic> json,
  ) => _$ConversationContractSourceReferenceFromJson(json);
}

@freezed
abstract class ConversationContractItemProvenance
    with _$ConversationContractItemProvenance {
  const ConversationContractItemProvenance._();

  const factory ConversationContractItemProvenance({
    required String itemId,
    required ConversationContractItemKind kind,
    @Default(<String>[]) List<String> sourceIds,
    @Default(false) bool assumption,
    @Default(false) bool material,
    @Default(false) bool confirmed,
    @Default('') String clarificationQuestion,
  }) = _ConversationContractItemProvenance;

  factory ConversationContractItemProvenance.fromJson(
    Map<String, dynamic> json,
  ) => _$ConversationContractItemProvenanceFromJson(json);

  bool get blocksExecution => assumption && material && !confirmed;

  String? get normalizedClarificationQuestion {
    final value = clarificationQuestion.trim();
    return value.isEmpty ? null : value;
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
    @JsonKey(fromJson: _contractSourcesFromJson, toJson: _contractSourcesToJson)
    @Default(<ConversationContractSourceReference>[])
    List<ConversationContractSourceReference> sources,
    @JsonKey(
      fromJson: _contractProvenanceFromJson,
      toJson: _contractProvenanceToJson,
    )
    @Default(<ConversationContractItemProvenance>[])
    List<ConversationContractItemProvenance> provenance,
  }) = _ConversationWorkflowSpec;

  factory ConversationWorkflowSpec.fromJson(Map<String, dynamic> json) =>
      _$ConversationWorkflowSpecFromJson(json);

  bool get hasContent =>
      goal.trim().isNotEmpty ||
      constraints.any((item) => item.trim().isNotEmpty) ||
      acceptanceCriteria.any((item) => item.trim().isNotEmpty) ||
      openQuestions.any((item) => item.trim().isNotEmpty) ||
      tasks.any((task) => task.title.trim().isNotEmpty || task.hasMetadata);

  List<ConversationContractItemProvenance> get blockingAssumptions =>
      provenance.where((item) => item.blocksExecution).toList(growable: false);
}
