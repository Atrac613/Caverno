import 'package:freezed_annotation/freezed_annotation.dart';

part 'routine.freezed.dart';
part 'routine.g.dart';

enum RoutineIntervalUnit { minutes, hours, days }

enum RoutineRunStatus { completed, failed }

enum RoutineRunTrigger { manual, scheduled }

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
    @Default(0) int durationMs,
    @Default(false) bool usedTools,
    @Default(0) int toolCallCount,
    @Default(<String>[]) List<String> toolNames,
    @Default('') String preview,
    @Default('') String output,
    @Default('') String error,
  }) = _RoutineRunRecord;

  factory RoutineRunRecord.fromJson(Map<String, dynamic> json) =>
      _$RoutineRunRecordFromJson(json);

  bool get isSuccessful => status == RoutineRunStatus.completed;

  int get effectiveDurationMs {
    final measured = finishedAt.difference(startedAt).inMilliseconds;
    if (durationMs > 0) {
      return durationMs;
    }
    return measured < 0 ? 0 : measured;
  }
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
    @Default(1) int intervalValue,
    @JsonKey(unknownEnumValue: RoutineIntervalUnit.hours)
    @Default(RoutineIntervalUnit.hours)
    RoutineIntervalUnit intervalUnit,
    DateTime? nextRunAt,
    DateTime? lastRunAt,
    @Default(<RoutineRunRecord>[]) List<RoutineRunRecord> runs,
  }) = _Routine;

  factory Routine.fromJson(Map<String, dynamic> json) =>
      _$RoutineFromJson(json);

  String get trimmedName => name.trim();

  String get trimmedPrompt => prompt.trim();

  bool get hasPrompt => trimmedPrompt.isNotEmpty;

  RoutineRunRecord? get latestRun => runs.isEmpty ? null : runs.first;
}
