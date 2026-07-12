// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_workflow.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ConversationOpenQuestionProgress _$ConversationOpenQuestionProgressFromJson(
  Map<String, dynamic> json,
) => _ConversationOpenQuestionProgress(
  questionId: json['questionId'] as String,
  question: json['question'] as String,
  status:
      $enumDecodeNullable(
        _$ConversationOpenQuestionStatusEnumMap,
        json['status'],
      ) ??
      ConversationOpenQuestionStatus.unresolved,
  note: json['note'] as String? ?? '',
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$ConversationOpenQuestionProgressToJson(
  _ConversationOpenQuestionProgress instance,
) => <String, dynamic>{
  'questionId': instance.questionId,
  'question': instance.question,
  'status': _$ConversationOpenQuestionStatusEnumMap[instance.status]!,
  'note': instance.note,
  'updatedAt': instance.updatedAt?.toIso8601String(),
};

const _$ConversationOpenQuestionStatusEnumMap = {
  ConversationOpenQuestionStatus.unresolved: 'unresolved',
  ConversationOpenQuestionStatus.needsUserInput: 'needsUserInput',
  ConversationOpenQuestionStatus.resolved: 'resolved',
  ConversationOpenQuestionStatus.deferred: 'deferred',
};

_ConversationWorkflowTask _$ConversationWorkflowTaskFromJson(
  Map<String, dynamic> json,
) => _ConversationWorkflowTask(
  id: json['id'] as String,
  title: json['title'] as String,
  status:
      $enumDecodeNullable(
        _$ConversationWorkflowTaskStatusEnumMap,
        json['status'],
      ) ??
      ConversationWorkflowTaskStatus.pending,
  targetFiles:
      (json['targetFiles'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  validationCommand: json['validationCommand'] as String? ?? '',
  notes: json['notes'] as String? ?? '',
);

Map<String, dynamic> _$ConversationWorkflowTaskToJson(
  _ConversationWorkflowTask instance,
) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'status': _$ConversationWorkflowTaskStatusEnumMap[instance.status]!,
  'targetFiles': instance.targetFiles,
  'validationCommand': instance.validationCommand,
  'notes': instance.notes,
};

const _$ConversationWorkflowTaskStatusEnumMap = {
  ConversationWorkflowTaskStatus.pending: 'pending',
  ConversationWorkflowTaskStatus.inProgress: 'inProgress',
  ConversationWorkflowTaskStatus.completed: 'completed',
  ConversationWorkflowTaskStatus.blocked: 'blocked',
};

_ConversationExecutionTaskProgress _$ConversationExecutionTaskProgressFromJson(
  Map<String, dynamic> json,
) => _ConversationExecutionTaskProgress(
  taskId: json['taskId'] as String,
  status:
      $enumDecodeNullable(
        _$ConversationWorkflowTaskStatusEnumMap,
        json['status'],
      ) ??
      ConversationWorkflowTaskStatus.pending,
  validationStatus:
      $enumDecodeNullable(
        _$ConversationExecutionValidationStatusEnumMap,
        json['validationStatus'],
      ) ??
      ConversationExecutionValidationStatus.unknown,
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
  lastRunAt: json['lastRunAt'] == null
      ? null
      : DateTime.parse(json['lastRunAt'] as String),
  lastValidationAt: json['lastValidationAt'] == null
      ? null
      : DateTime.parse(json['lastValidationAt'] as String),
  summary: json['summary'] as String? ?? '',
  blockedReason: json['blockedReason'] as String? ?? '',
  lastValidationCommand: json['lastValidationCommand'] as String? ?? '',
  lastValidationSummary: json['lastValidationSummary'] as String? ?? '',
  events: json['events'] == null
      ? const <ConversationExecutionTaskEvent>[]
      : _executionEventsFromJson(json['events'] as List?),
);

Map<String, dynamic> _$ConversationExecutionTaskProgressToJson(
  _ConversationExecutionTaskProgress instance,
) => <String, dynamic>{
  'taskId': instance.taskId,
  'status': _$ConversationWorkflowTaskStatusEnumMap[instance.status]!,
  'validationStatus':
      _$ConversationExecutionValidationStatusEnumMap[instance
          .validationStatus]!,
  'updatedAt': instance.updatedAt?.toIso8601String(),
  'lastRunAt': instance.lastRunAt?.toIso8601String(),
  'lastValidationAt': instance.lastValidationAt?.toIso8601String(),
  'summary': instance.summary,
  'blockedReason': instance.blockedReason,
  'lastValidationCommand': instance.lastValidationCommand,
  'lastValidationSummary': instance.lastValidationSummary,
  'events': _executionEventsToJson(instance.events),
};

const _$ConversationExecutionValidationStatusEnumMap = {
  ConversationExecutionValidationStatus.unknown: 'unknown',
  ConversationExecutionValidationStatus.passed: 'passed',
  ConversationExecutionValidationStatus.failed: 'failed',
};

_ConversationExecutionTaskEvent _$ConversationExecutionTaskEventFromJson(
  Map<String, dynamic> json,
) => _ConversationExecutionTaskEvent(
  type: $enumDecode(_$ConversationExecutionTaskEventTypeEnumMap, json['type']),
  createdAt: DateTime.parse(json['createdAt'] as String),
  summary: json['summary'] as String? ?? '',
  status:
      $enumDecodeNullable(
        _$ConversationWorkflowTaskStatusEnumMap,
        json['status'],
      ) ??
      ConversationWorkflowTaskStatus.pending,
  validationStatus:
      $enumDecodeNullable(
        _$ConversationExecutionValidationStatusEnumMap,
        json['validationStatus'],
      ) ??
      ConversationExecutionValidationStatus.unknown,
  blockedReason: json['blockedReason'] as String? ?? '',
  validationCommand: json['validationCommand'] as String? ?? '',
  validationSummary: json['validationSummary'] as String? ?? '',
);

Map<String, dynamic> _$ConversationExecutionTaskEventToJson(
  _ConversationExecutionTaskEvent instance,
) => <String, dynamic>{
  'type': _$ConversationExecutionTaskEventTypeEnumMap[instance.type]!,
  'createdAt': instance.createdAt.toIso8601String(),
  'summary': instance.summary,
  'status': _$ConversationWorkflowTaskStatusEnumMap[instance.status]!,
  'validationStatus':
      _$ConversationExecutionValidationStatusEnumMap[instance
          .validationStatus]!,
  'blockedReason': instance.blockedReason,
  'validationCommand': instance.validationCommand,
  'validationSummary': instance.validationSummary,
};

const _$ConversationExecutionTaskEventTypeEnumMap = {
  ConversationExecutionTaskEventType.started: 'started',
  ConversationExecutionTaskEventType.validated: 'validated',
  ConversationExecutionTaskEventType.blocked: 'blocked',
  ConversationExecutionTaskEventType.unblocked: 'unblocked',
  ConversationExecutionTaskEventType.completed: 'completed',
  ConversationExecutionTaskEventType.replanned: 'replanned',
};

_ConversationContractSourceReference
_$ConversationContractSourceReferenceFromJson(Map<String, dynamic> json) =>
    _ConversationContractSourceReference(
      id: json['id'] as String,
      kind: $enumDecode(_$ConversationContractSourceKindEnumMap, json['kind']),
      locator: json['locator'] as String? ?? '',
      contentHash: json['contentHash'] as String? ?? '',
      section: json['section'] as String? ?? '',
      toolCallId: json['toolCallId'] as String? ?? '',
    );

Map<String, dynamic> _$ConversationContractSourceReferenceToJson(
  _ConversationContractSourceReference instance,
) => <String, dynamic>{
  'id': instance.id,
  'kind': _$ConversationContractSourceKindEnumMap[instance.kind]!,
  'locator': instance.locator,
  'contentHash': instance.contentHash,
  'section': instance.section,
  'toolCallId': instance.toolCallId,
};

const _$ConversationContractSourceKindEnumMap = {
  ConversationContractSourceKind.userMessage: 'userMessage',
  ConversationContractSourceKind.specificationFile: 'specificationFile',
  ConversationContractSourceKind.approvedPlan: 'approvedPlan',
  ConversationContractSourceKind.workspaceObservation: 'workspaceObservation',
  ConversationContractSourceKind.userConfirmedAssumption:
      'userConfirmedAssumption',
  ConversationContractSourceKind.legacy: 'legacy',
};

_ConversationContractItemProvenance
_$ConversationContractItemProvenanceFromJson(Map<String, dynamic> json) =>
    _ConversationContractItemProvenance(
      itemId: json['itemId'] as String,
      kind: $enumDecode(_$ConversationContractItemKindEnumMap, json['kind']),
      sourceIds:
          (json['sourceIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      assumption: json['assumption'] as bool? ?? false,
      material: json['material'] as bool? ?? false,
      confirmed: json['confirmed'] as bool? ?? false,
      clarificationQuestion: json['clarificationQuestion'] as String? ?? '',
    );

Map<String, dynamic> _$ConversationContractItemProvenanceToJson(
  _ConversationContractItemProvenance instance,
) => <String, dynamic>{
  'itemId': instance.itemId,
  'kind': _$ConversationContractItemKindEnumMap[instance.kind]!,
  'sourceIds': instance.sourceIds,
  'assumption': instance.assumption,
  'material': instance.material,
  'confirmed': instance.confirmed,
  'clarificationQuestion': instance.clarificationQuestion,
};

const _$ConversationContractItemKindEnumMap = {
  ConversationContractItemKind.goal: 'goal',
  ConversationContractItemKind.constraint: 'constraint',
  ConversationContractItemKind.acceptanceCriterion: 'acceptanceCriterion',
  ConversationContractItemKind.openQuestion: 'openQuestion',
  ConversationContractItemKind.task: 'task',
};

_ConversationWorkflowSpec _$ConversationWorkflowSpecFromJson(
  Map<String, dynamic> json,
) => _ConversationWorkflowSpec(
  goal: json['goal'] as String? ?? '',
  constraints:
      (json['constraints'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  acceptanceCriteria:
      (json['acceptanceCriteria'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  openQuestions:
      (json['openQuestions'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  tasks: json['tasks'] == null
      ? const <ConversationWorkflowTask>[]
      : _workflowTasksFromJson(json['tasks'] as List?),
  sources: json['sources'] == null
      ? const <ConversationContractSourceReference>[]
      : _contractSourcesFromJson(json['sources'] as List?),
  provenance: json['provenance'] == null
      ? const <ConversationContractItemProvenance>[]
      : _contractProvenanceFromJson(json['provenance'] as List?),
);

Map<String, dynamic> _$ConversationWorkflowSpecToJson(
  _ConversationWorkflowSpec instance,
) => <String, dynamic>{
  'goal': instance.goal,
  'constraints': instance.constraints,
  'acceptanceCriteria': instance.acceptanceCriteria,
  'openQuestions': instance.openQuestions,
  'tasks': _workflowTasksToJson(instance.tasks),
  'sources': _contractSourcesToJson(instance.sources),
  'provenance': _contractProvenanceToJson(instance.provenance),
};
