import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'routine.freezed.dart';
part 'routine.g.dart';

enum RoutineIntervalUnit { minutes, hours, days }

enum RoutineScheduleMode { interval, dailyTime }

enum RoutineRunStatus { completed, failed }

enum RoutineRunTrigger { manual, scheduled }

enum RoutineCompletionAction { none, googleChat, promptGoogleChat }

enum RoutineGoogleChatRule { onSuccess, onFailure, always }

enum RoutineDeliveryStatus { notRequested, skipped, delivered, failed }

enum RoutinePlanRevisionKind { draft, approved, restored }

@freezed
abstract class RoutinePlanRevision with _$RoutinePlanRevision {
  const RoutinePlanRevision._();

  const factory RoutinePlanRevision({
    required String markdown,
    required DateTime createdAt,
    @JsonKey(unknownEnumValue: RoutinePlanRevisionKind.draft)
    @Default(RoutinePlanRevisionKind.draft)
    RoutinePlanRevisionKind kind,
    @Default('') String label,
  }) = _RoutinePlanRevision;

  factory RoutinePlanRevision.fromJson(Map<String, dynamic> json) =>
      _$RoutinePlanRevisionFromJson(json);

  String? get normalizedMarkdown {
    final trimmed = markdown.trimRight();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get normalizedLabel {
    final trimmed = label.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

@freezed
abstract class RoutinePlanArtifact with _$RoutinePlanArtifact {
  const RoutinePlanArtifact._();

  const factory RoutinePlanArtifact({
    @Default('') String draftMarkdown,
    @Default('') String approvedMarkdown,
    @Default('') String approvedSourceHash,
    DateTime? approvedAt,
    DateTime? updatedAt,
    @JsonKey(
      fromJson: _routinePlanRevisionsFromJson,
      toJson: _routinePlanRevisionsToJson,
    )
    @Default(<RoutinePlanRevision>[])
    List<RoutinePlanRevision> revisions,
  }) = _RoutinePlanArtifact;

  factory RoutinePlanArtifact.fromJson(Map<String, dynamic> json) =>
      _$RoutinePlanArtifactFromJson(json);

  String? get normalizedDraftMarkdown {
    final trimmed = draftMarkdown.trimRight();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get normalizedApprovedMarkdown {
    final trimmed = approvedMarkdown.trimRight();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get normalizedApprovedSourceHash {
    final trimmed = approvedSourceHash.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool get hasDraft => normalizedDraftMarkdown != null;

  bool get hasApproved => normalizedApprovedMarkdown != null;

  bool get hasContent => hasDraft || hasApproved;

  bool get hasPendingEdits =>
      normalizedDraftMarkdown != null &&
      normalizedDraftMarkdown != normalizedApprovedMarkdown;

  List<RoutinePlanRevision> get historyEntries => revisions
      .where((entry) => entry.normalizedMarkdown != null)
      .toList(growable: false);

  bool isApprovedForSource(String sourceHash) {
    final normalizedSourceHash = sourceHash.trim();
    return normalizedSourceHash.isNotEmpty &&
        normalizedApprovedMarkdown != null &&
        normalizedApprovedSourceHash == normalizedSourceHash;
  }

  RoutinePlanArtifact recordRevision({
    required String markdown,
    required RoutinePlanRevisionKind kind,
    String label = '',
    DateTime? createdAt,
    int maxEntries = 12,
  }) {
    final normalizedMarkdown = markdown.trimRight();
    if (normalizedMarkdown.isEmpty) {
      return this;
    }

    final revision = RoutinePlanRevision(
      markdown: normalizedMarkdown,
      createdAt: createdAt ?? DateTime.now(),
      kind: kind,
      label: label.trim(),
    );
    final nextHistory = <RoutinePlanRevision>[
      revision,
      ...historyEntries.where(
        (entry) =>
            entry.normalizedMarkdown != normalizedMarkdown ||
            entry.kind != kind,
      ),
    ];
    final trimmedHistory = nextHistory.length <= maxEntries
        ? nextHistory
        : nextHistory.sublist(0, maxEntries);
    return copyWith(revisions: trimmedHistory);
  }
}

List<RoutinePlanRevision> _routinePlanRevisionsFromJson(List<dynamic>? json) {
  if (json == null) {
    return const <RoutinePlanRevision>[];
  }
  return json
      .map((item) {
        if (item is RoutinePlanRevision) {
          return item;
        }
        return RoutinePlanRevision.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> _routinePlanRevisionsToJson(
  List<RoutinePlanRevision> revisions,
) {
  return revisions.map((revision) => revision.toJson()).toList(growable: false);
}

RoutinePlanArtifact? _routinePlanArtifactFromJson(Map<String, dynamic>? json) {
  if (json == null) {
    return null;
  }
  return RoutinePlanArtifact.fromJson(json);
}

Map<String, dynamic>? _routinePlanArtifactToJson(
  RoutinePlanArtifact? artifact,
) {
  return artifact?.toJson();
}

@freezed
abstract class RoutineRunRecord with _$RoutineRunRecord {
  const RoutineRunRecord._();

  const factory RoutineRunRecord({
    required String id,
    required DateTime startedAt,
    required DateTime finishedAt,
    @JsonKey(unknownEnumValue: RoutineRunStatus.completed)
    @Default(RoutineRunStatus.completed)
    RoutineRunStatus status,
    @JsonKey(unknownEnumValue: RoutineRunTrigger.manual)
    @Default(RoutineRunTrigger.manual)
    RoutineRunTrigger trigger,
    @Default(false) bool usedPlan,
    @Default('') String planSourceHash,
    @Default(0) int durationMs,
    @Default(false) bool usedTools,
    @Default(0) int toolCallCount,
    @Default(<String>[]) List<String> toolNames,
    @JsonKey(
      fromJson: _routineRunToolCallsFromJson,
      toJson: _routineRunToolCallsToJson,
    )
    @Default(<RoutineRunToolCall>[])
    List<RoutineRunToolCall> toolCalls,
    @Default(<String, String>{}) Map<String, String> toolSourceLabels,
    @JsonKey(unknownEnumValue: RoutineDeliveryStatus.notRequested)
    @Default(RoutineDeliveryStatus.notRequested)
    RoutineDeliveryStatus deliveryStatus,
    DateTime? deliveredAt,
    @Default('') String deliveryMessage,
    @Default('') String preview,
    @Default('') String output,
    @Default('') String error,
    @Default(false) bool failureAcknowledged,
  }) = _RoutineRunRecord;

  factory RoutineRunRecord.fromJson(Map<String, dynamic> json) =>
      _$RoutineRunRecordFromJson(json);

  bool get isSuccessful => status == RoutineRunStatus.completed;

  bool get requiresAttention =>
      status == RoutineRunStatus.failed && !failureAcknowledged;

  bool get wasDelivered => deliveryStatus == RoutineDeliveryStatus.delivered;

  List<String> get toolDisplayNames {
    return toolNames
        .map((name) {
          final sourceLabel = toolSourceLabels[name]?.trim();
          if (sourceLabel == null || sourceLabel.isEmpty) {
            return name;
          }
          return '$name ($sourceLabel)';
        })
        .toList(growable: false);
  }

  int get effectiveDurationMs {
    final measured = finishedAt.difference(startedAt).inMilliseconds;
    if (durationMs > 0) {
      return durationMs;
    }
    return measured < 0 ? 0 : measured;
  }
}

List<RoutineRunToolCall> _routineRunToolCallsFromJson(List<dynamic>? json) {
  if (json == null) {
    return const <RoutineRunToolCall>[];
  }
  return json
      .map((item) {
        if (item is RoutineRunToolCall) {
          return item;
        }
        return RoutineRunToolCall.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> _routineRunToolCallsToJson(
  List<RoutineRunToolCall> toolCalls,
) {
  return toolCalls.map((toolCall) => toolCall.toJson()).toList(growable: false);
}

@freezed
abstract class RoutineRunToolCall with _$RoutineRunToolCall {
  const RoutineRunToolCall._();

  const factory RoutineRunToolCall({
    required String id,
    required String name,
    @Default('') String arguments,
    @Default('') String result,
  }) = _RoutineRunToolCall;

  factory RoutineRunToolCall.fromJson(Map<String, dynamic> json) =>
      _$RoutineRunToolCallFromJson(json);
}

@freezed
abstract class Routine with _$Routine {
  const Routine._();

  const factory Routine({
    required String id,
    required String name,
    required String prompt,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default(true) bool enabled,
    @Default(true) bool notifyOnCompletion,
    @Default(false) bool toolsEnabled,
    @JsonKey(unknownEnumValue: RoutineCompletionAction.none)
    @Default(RoutineCompletionAction.none)
    RoutineCompletionAction completionAction,
    @JsonKey(unknownEnumValue: RoutineGoogleChatRule.onFailure)
    @Default(RoutineGoogleChatRule.onFailure)
    RoutineGoogleChatRule googleChatRule,
    @Default('') String workspaceDirectory,
    @Default(false) bool allowWorkspaceWrites,
    @JsonKey(
      fromJson: _routinePlanArtifactFromJson,
      toJson: _routinePlanArtifactToJson,
    )
    RoutinePlanArtifact? planArtifact,
    @Default(1) int intervalValue,
    @JsonKey(unknownEnumValue: RoutineIntervalUnit.hours)
    @Default(RoutineIntervalUnit.hours)
    RoutineIntervalUnit intervalUnit,
    @JsonKey(unknownEnumValue: RoutineScheduleMode.interval)
    @Default(RoutineScheduleMode.interval)
    RoutineScheduleMode scheduleMode,
    @Default(480) int timeOfDayMinutes,
    DateTime? nextRunAt,
    DateTime? lastRunAt,
    @Default(<RoutineRunRecord>[]) List<RoutineRunRecord> runs,
  }) = _Routine;

  factory Routine.fromJson(Map<String, dynamic> json) =>
      _$RoutineFromJson(json);

  String get trimmedName => name.trim();

  String get trimmedPrompt => prompt.trim();

  String get trimmedWorkspaceDirectory => workspaceDirectory.trim();

  bool get hasPrompt => trimmedPrompt.isNotEmpty;

  bool get hasWorkspaceDirectory => trimmedWorkspaceDirectory.isNotEmpty;

  bool get hasWorkspaceWriteAccess =>
      toolsEnabled && allowWorkspaceWrites && hasWorkspaceDirectory;

  RoutinePlanArtifact get effectivePlanArtifact =>
      planArtifact ?? const RoutinePlanArtifact();

  String get planSourceHash => _computeRoutinePlanSourceHash(
    prompt: trimmedPrompt,
    toolsEnabled: toolsEnabled,
    completionAction: completionAction.name,
    googleChatRule: googleChatRule.name,
    workspaceDirectory: trimmedWorkspaceDirectory,
    allowWorkspaceWrites: allowWorkspaceWrites,
    intervalValue: intervalValue,
    intervalUnit: intervalUnit.name,
    scheduleMode: scheduleMode.name,
    timeOfDayMinutes: timeOfDayMinutes,
  );

  String? get freshApprovedPlanMarkdown {
    final artifact = effectivePlanArtifact;
    if (!artifact.isApprovedForSource(planSourceHash)) {
      return null;
    }
    return artifact.normalizedApprovedMarkdown;
  }

  bool get hasApprovedPlan => effectivePlanArtifact.hasApproved;

  bool get hasPlanDraft => effectivePlanArtifact.hasDraft;

  bool get hasPendingPlanEdits => effectivePlanArtifact.hasPendingEdits;

  bool get isApprovedPlanFresh => freshApprovedPlanMarkdown != null;

  bool get hasStaleApprovedPlan => hasApprovedPlan && !isApprovedPlanFresh;

  bool get needsPlanAttention => hasStaleApprovedPlan || hasPendingPlanEdits;

  RoutineRunRecord? get latestRun => runs.isEmpty ? null : runs.first;

  int get consecutiveFailureCount {
    var count = 0;
    for (final run in runs) {
      if (run.isSuccessful) {
        break;
      }
      count += 1;
    }
    return count;
  }

  bool get postsToGoogleChat =>
      completionAction == RoutineCompletionAction.googleChat;

  bool get allowsPromptGoogleChatPost =>
      completionAction == RoutineCompletionAction.promptGoogleChat;
}

String _computeRoutinePlanSourceHash({
  required String prompt,
  required bool toolsEnabled,
  required String completionAction,
  required String googleChatRule,
  required String workspaceDirectory,
  required bool allowWorkspaceWrites,
  required int intervalValue,
  required String intervalUnit,
  required String scheduleMode,
  required int timeOfDayMinutes,
}) {
  final sourcePayload = jsonEncode(<String, Object?>{
    'prompt': prompt.trim(),
    'toolsEnabled': toolsEnabled,
    'completionAction': completionAction,
    'googleChatRule': googleChatRule,
    'workspaceDirectory': workspaceDirectory.trim(),
    'allowWorkspaceWrites': allowWorkspaceWrites,
    'intervalValue': intervalValue,
    'intervalUnit': intervalUnit,
    'scheduleMode': scheduleMode,
    'timeOfDayMinutes': timeOfDayMinutes,
  });
  return _computeStableRoutineHash(sourcePayload);
}

String _computeStableRoutineHash(String value) {
  const int offsetBasis = 0x811c9dc5;
  const int prime = 0x01000193;
  var hash = offsetBasis;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * prime) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
