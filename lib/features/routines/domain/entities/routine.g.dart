// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'routine.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RoutinePlanRevision _$RoutinePlanRevisionFromJson(Map<String, dynamic> json) =>
    _RoutinePlanRevision(
      markdown: json['markdown'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      kind:
          $enumDecodeNullable(
            _$RoutinePlanRevisionKindEnumMap,
            json['kind'],
            unknownValue: RoutinePlanRevisionKind.draft,
          ) ??
          RoutinePlanRevisionKind.draft,
      label: json['label'] as String? ?? '',
    );

Map<String, dynamic> _$RoutinePlanRevisionToJson(
  _RoutinePlanRevision instance,
) => <String, dynamic>{
  'markdown': instance.markdown,
  'createdAt': instance.createdAt.toIso8601String(),
  'kind': _$RoutinePlanRevisionKindEnumMap[instance.kind]!,
  'label': instance.label,
};

const _$RoutinePlanRevisionKindEnumMap = {
  RoutinePlanRevisionKind.draft: 'draft',
  RoutinePlanRevisionKind.approved: 'approved',
  RoutinePlanRevisionKind.restored: 'restored',
};

_RoutinePlanArtifact _$RoutinePlanArtifactFromJson(Map<String, dynamic> json) =>
    _RoutinePlanArtifact(
      draftMarkdown: json['draftMarkdown'] as String? ?? '',
      approvedMarkdown: json['approvedMarkdown'] as String? ?? '',
      approvedSourceHash: json['approvedSourceHash'] as String? ?? '',
      approvedAt: json['approvedAt'] == null
          ? null
          : DateTime.parse(json['approvedAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
      revisions: json['revisions'] == null
          ? const <RoutinePlanRevision>[]
          : _routinePlanRevisionsFromJson(json['revisions'] as List?),
    );

Map<String, dynamic> _$RoutinePlanArtifactToJson(
  _RoutinePlanArtifact instance,
) => <String, dynamic>{
  'draftMarkdown': instance.draftMarkdown,
  'approvedMarkdown': instance.approvedMarkdown,
  'approvedSourceHash': instance.approvedSourceHash,
  'approvedAt': instance.approvedAt?.toIso8601String(),
  'updatedAt': instance.updatedAt?.toIso8601String(),
  'revisions': _routinePlanRevisionsToJson(instance.revisions),
};

_RoutineRunRecord _$RoutineRunRecordFromJson(Map<String, dynamic> json) =>
    _RoutineRunRecord(
      id: json['id'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      finishedAt: DateTime.parse(json['finishedAt'] as String),
      status:
          $enumDecodeNullable(
            _$RoutineRunStatusEnumMap,
            json['status'],
            unknownValue: RoutineRunStatus.completed,
          ) ??
          RoutineRunStatus.completed,
      trigger:
          $enumDecodeNullable(
            _$RoutineRunTriggerEnumMap,
            json['trigger'],
            unknownValue: RoutineRunTrigger.manual,
          ) ??
          RoutineRunTrigger.manual,
      usedPlan: json['usedPlan'] as bool? ?? false,
      planSourceHash: json['planSourceHash'] as String? ?? '',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      usedTools: json['usedTools'] as bool? ?? false,
      toolCallCount: (json['toolCallCount'] as num?)?.toInt() ?? 0,
      toolNames:
          (json['toolNames'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      toolCalls: json['toolCalls'] == null
          ? const <RoutineRunToolCall>[]
          : _routineRunToolCallsFromJson(json['toolCalls'] as List?),
      toolSourceLabels:
          (json['toolSourceLabels'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          const <String, String>{},
      deliveryStatus:
          $enumDecodeNullable(
            _$RoutineDeliveryStatusEnumMap,
            json['deliveryStatus'],
            unknownValue: RoutineDeliveryStatus.notRequested,
          ) ??
          RoutineDeliveryStatus.notRequested,
      deliveredAt: json['deliveredAt'] == null
          ? null
          : DateTime.parse(json['deliveredAt'] as String),
      deliveryMessage: json['deliveryMessage'] as String? ?? '',
      preview: json['preview'] as String? ?? '',
      output: json['output'] as String? ?? '',
      error: json['error'] as String? ?? '',
      failureAcknowledged: json['failureAcknowledged'] as bool? ?? false,
    );

Map<String, dynamic> _$RoutineRunRecordToJson(
  _RoutineRunRecord instance,
) => <String, dynamic>{
  'id': instance.id,
  'startedAt': instance.startedAt.toIso8601String(),
  'finishedAt': instance.finishedAt.toIso8601String(),
  'status': _$RoutineRunStatusEnumMap[instance.status]!,
  'trigger': _$RoutineRunTriggerEnumMap[instance.trigger]!,
  'usedPlan': instance.usedPlan,
  'planSourceHash': instance.planSourceHash,
  'durationMs': instance.durationMs,
  'usedTools': instance.usedTools,
  'toolCallCount': instance.toolCallCount,
  'toolNames': instance.toolNames,
  'toolCalls': _routineRunToolCallsToJson(instance.toolCalls),
  'toolSourceLabels': instance.toolSourceLabels,
  'deliveryStatus': _$RoutineDeliveryStatusEnumMap[instance.deliveryStatus]!,
  'deliveredAt': instance.deliveredAt?.toIso8601String(),
  'deliveryMessage': instance.deliveryMessage,
  'preview': instance.preview,
  'output': instance.output,
  'error': instance.error,
  'failureAcknowledged': instance.failureAcknowledged,
};

const _$RoutineRunStatusEnumMap = {
  RoutineRunStatus.completed: 'completed',
  RoutineRunStatus.failed: 'failed',
};

const _$RoutineRunTriggerEnumMap = {
  RoutineRunTrigger.manual: 'manual',
  RoutineRunTrigger.scheduled: 'scheduled',
};

const _$RoutineDeliveryStatusEnumMap = {
  RoutineDeliveryStatus.notRequested: 'notRequested',
  RoutineDeliveryStatus.skipped: 'skipped',
  RoutineDeliveryStatus.delivered: 'delivered',
  RoutineDeliveryStatus.failed: 'failed',
};

_RoutineRunToolCall _$RoutineRunToolCallFromJson(Map<String, dynamic> json) =>
    _RoutineRunToolCall(
      id: json['id'] as String,
      name: json['name'] as String,
      arguments: json['arguments'] as String? ?? '',
      result: json['result'] as String? ?? '',
    );

Map<String, dynamic> _$RoutineRunToolCallToJson(_RoutineRunToolCall instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'arguments': instance.arguments,
      'result': instance.result,
    };

_Routine _$RoutineFromJson(Map<String, dynamic> json) => _Routine(
  id: json['id'] as String,
  name: json['name'] as String,
  prompt: json['prompt'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  enabled: json['enabled'] as bool? ?? true,
  notifyOnCompletion: json['notifyOnCompletion'] as bool? ?? true,
  toolsEnabled: json['toolsEnabled'] as bool? ?? false,
  completionAction:
      $enumDecodeNullable(
        _$RoutineCompletionActionEnumMap,
        json['completionAction'],
        unknownValue: RoutineCompletionAction.none,
      ) ??
      RoutineCompletionAction.none,
  googleChatRule:
      $enumDecodeNullable(
        _$RoutineGoogleChatRuleEnumMap,
        json['googleChatRule'],
        unknownValue: RoutineGoogleChatRule.onFailure,
      ) ??
      RoutineGoogleChatRule.onFailure,
  workspaceDirectory: json['workspaceDirectory'] as String? ?? '',
  allowWorkspaceWrites: json['allowWorkspaceWrites'] as bool? ?? false,
  planArtifact: _routinePlanArtifactFromJson(
    json['planArtifact'] as Map<String, dynamic>?,
  ),
  intervalValue: (json['intervalValue'] as num?)?.toInt() ?? 1,
  intervalUnit:
      $enumDecodeNullable(
        _$RoutineIntervalUnitEnumMap,
        json['intervalUnit'],
        unknownValue: RoutineIntervalUnit.hours,
      ) ??
      RoutineIntervalUnit.hours,
  scheduleMode:
      $enumDecodeNullable(
        _$RoutineScheduleModeEnumMap,
        json['scheduleMode'],
        unknownValue: RoutineScheduleMode.interval,
      ) ??
      RoutineScheduleMode.interval,
  timeOfDayMinutes: (json['timeOfDayMinutes'] as num?)?.toInt() ?? 480,
  nextRunAt: json['nextRunAt'] == null
      ? null
      : DateTime.parse(json['nextRunAt'] as String),
  lastRunAt: json['lastRunAt'] == null
      ? null
      : DateTime.parse(json['lastRunAt'] as String),
  runs:
      (json['runs'] as List<dynamic>?)
          ?.map((e) => RoutineRunRecord.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <RoutineRunRecord>[],
);

Map<String, dynamic> _$RoutineToJson(_Routine instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'prompt': instance.prompt,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'enabled': instance.enabled,
  'notifyOnCompletion': instance.notifyOnCompletion,
  'toolsEnabled': instance.toolsEnabled,
  'completionAction':
      _$RoutineCompletionActionEnumMap[instance.completionAction]!,
  'googleChatRule': _$RoutineGoogleChatRuleEnumMap[instance.googleChatRule]!,
  'workspaceDirectory': instance.workspaceDirectory,
  'allowWorkspaceWrites': instance.allowWorkspaceWrites,
  'planArtifact': _routinePlanArtifactToJson(instance.planArtifact),
  'intervalValue': instance.intervalValue,
  'intervalUnit': _$RoutineIntervalUnitEnumMap[instance.intervalUnit]!,
  'scheduleMode': _$RoutineScheduleModeEnumMap[instance.scheduleMode]!,
  'timeOfDayMinutes': instance.timeOfDayMinutes,
  'nextRunAt': instance.nextRunAt?.toIso8601String(),
  'lastRunAt': instance.lastRunAt?.toIso8601String(),
  'runs': instance.runs,
};

const _$RoutineCompletionActionEnumMap = {
  RoutineCompletionAction.none: 'none',
  RoutineCompletionAction.googleChat: 'googleChat',
  RoutineCompletionAction.promptGoogleChat: 'promptGoogleChat',
};

const _$RoutineGoogleChatRuleEnumMap = {
  RoutineGoogleChatRule.onSuccess: 'onSuccess',
  RoutineGoogleChatRule.onFailure: 'onFailure',
  RoutineGoogleChatRule.always: 'always',
};

const _$RoutineIntervalUnitEnumMap = {
  RoutineIntervalUnit.minutes: 'minutes',
  RoutineIntervalUnit.hours: 'hours',
  RoutineIntervalUnit.days: 'days',
};

const _$RoutineScheduleModeEnumMap = {
  RoutineScheduleMode.interval: 'interval',
  RoutineScheduleMode.dailyTime: 'dailyTime',
};
