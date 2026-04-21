import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/google_chat_delivery_service.dart';
import '../../../../core/services/notification_providers.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/routine_execution_service.dart';
import '../../data/routine_repository.dart';
import '../../domain/entities/routine.dart';
import '../../domain/services/routine_completion_action_service.dart';
import '../../domain/services/routine_schedule_service.dart';

class RoutinesState {
  const RoutinesState({
    required this.routines,
    this.runningRoutineIds = const <String>{},
  });

  final List<Routine> routines;
  final Set<String> runningRoutineIds;

  RoutinesState copyWith({
    List<Routine>? routines,
    Set<String>? runningRoutineIds,
  }) {
    return RoutinesState(
      routines: routines ?? this.routines,
      runningRoutineIds: runningRoutineIds ?? this.runningRoutineIds,
    );
  }

  bool isRunning(String routineId) => runningRoutineIds.contains(routineId);
}

final routinesNotifierProvider =
    NotifierProvider<RoutinesNotifier, RoutinesState>(RoutinesNotifier.new);

class RoutinesNotifier extends Notifier<RoutinesState> {
  final Uuid _uuid = const Uuid();
  static const int _maxStoredRuns = 8;

  late RoutineRepository _repository;

  @override
  RoutinesState build() {
    _repository = ref.read(routineRepositoryProvider);
    final routines = _orderedRoutines(_repository.loadAll());
    return RoutinesState(routines: routines);
  }

  Future<void> createRoutine({
    required String name,
    required String prompt,
    required int intervalValue,
    required RoutineIntervalUnit intervalUnit,
    required bool enabled,
    required bool notifyOnCompletion,
    required bool toolsEnabled,
    required RoutineCompletionAction completionAction,
    required RoutineGoogleChatRule googleChatRule,
  }) async {
    final now = DateTime.now();
    final routine = Routine(
      id: _uuid.v4(),
      name: name.trim(),
      prompt: prompt.trim(),
      createdAt: now,
      updatedAt: now,
      enabled: enabled,
      notifyOnCompletion: notifyOnCompletion,
      toolsEnabled: toolsEnabled,
      completionAction: completionAction,
      googleChatRule: googleChatRule,
      intervalValue: RoutineScheduleService.normalizeIntervalValue(
        intervalValue,
      ),
      intervalUnit: intervalUnit,
    );

    final prepared = _prepareRoutineForPersistence(routine, previous: null);
    await _persistRoutines([...state.routines, prepared]);
  }

  Future<void> updateRoutine({
    required String routineId,
    required String name,
    required String prompt,
    required int intervalValue,
    required RoutineIntervalUnit intervalUnit,
    required bool enabled,
    required bool notifyOnCompletion,
    required bool toolsEnabled,
    required RoutineCompletionAction completionAction,
    required RoutineGoogleChatRule googleChatRule,
  }) async {
    final existing = _findRoutine(routineId);
    if (existing == null) {
      return;
    }

    final updated = existing.copyWith(
      name: name.trim(),
      prompt: prompt.trim(),
      enabled: enabled,
      notifyOnCompletion: notifyOnCompletion,
      toolsEnabled: toolsEnabled,
      completionAction: completionAction,
      googleChatRule: googleChatRule,
      intervalValue: RoutineScheduleService.normalizeIntervalValue(
        intervalValue,
      ),
      intervalUnit: intervalUnit,
      updatedAt: DateTime.now(),
    );

    final prepared = _prepareRoutineForPersistence(updated, previous: existing);
    await _persistRoutine(prepared);
  }

  Future<void> toggleRoutine(String routineId, bool enabled) async {
    final existing = _findRoutine(routineId);
    if (existing == null) {
      return;
    }

    final updated = _prepareRoutineForPersistence(
      existing.copyWith(enabled: enabled, updatedAt: DateTime.now()),
      previous: existing,
    );
    await _persistRoutine(updated);
  }

  Future<void> deleteRoutine(String routineId) async {
    final updated = state.routines
        .where((routine) => routine.id != routineId)
        .toList(growable: false);
    await _persistRoutines(
      updated,
      runningRoutineIds: {
        ...state.runningRoutineIds.where((id) => id != routineId),
      },
    );
  }

  Future<Routine?> duplicateRoutine({
    required String routineId,
    required String duplicatedName,
  }) async {
    final source = _findRoutine(routineId);
    if (source == null) {
      return null;
    }

    final now = DateTime.now();
    final duplicate = Routine(
      id: _uuid.v4(),
      name: duplicatedName.trim(),
      prompt: source.trimmedPrompt,
      createdAt: now,
      updatedAt: now,
      enabled: source.enabled,
      notifyOnCompletion: source.notifyOnCompletion,
      toolsEnabled: source.toolsEnabled,
      completionAction: source.completionAction,
      googleChatRule: source.googleChatRule,
      intervalValue: source.intervalValue,
      intervalUnit: source.intervalUnit,
    );
    final prepared = _prepareRoutineForPersistence(duplicate, previous: null);
    await _persistRoutines([...state.routines, prepared]);
    return prepared;
  }

  Future<void> clearRunHistory(String routineId) async {
    final existing = _findRoutine(routineId);
    if (existing == null) {
      return;
    }

    final updated = existing.copyWith(
      runs: const [],
      lastRunAt: null,
      updatedAt: DateTime.now(),
    );
    await _persistRoutine(updated);
  }

  Future<RoutineRunRecord?> runRoutineNow(
    String routineId, {
    RoutineRunTrigger trigger = RoutineRunTrigger.manual,
  }) async {
    final routine = _findRoutine(routineId);
    if (routine == null || state.isRunning(routineId)) {
      return null;
    }

    state = state.copyWith(
      runningRoutineIds: {...state.runningRoutineIds, routineId},
    );

    final executionService = ref.read(routineExecutionServiceProvider);
    final runRecord = await executionService.execute(routine, trigger: trigger);
    final latestRoutine = _findRoutine(routineId);

    if (latestRoutine == null) {
      state = state.copyWith(
        runningRoutineIds: {
          ...state.runningRoutineIds.where((id) => id != routineId),
        },
      );
      return runRecord;
    }

    final finalizedRunRecord = await _finalizeCompletionActions(
      routine: latestRoutine,
      runRecord: runRecord,
    );

    final nextRunAt = latestRoutine.enabled
        ? RoutineScheduleService.computeNextRunAt(
            routine: latestRoutine,
            from: finalizedRunRecord.finishedAt,
          )
        : null;

    final updatedRoutine = latestRoutine.copyWith(
      updatedAt: finalizedRunRecord.finishedAt,
      lastRunAt: finalizedRunRecord.finishedAt,
      nextRunAt: nextRunAt,
      runs: [
        finalizedRunRecord,
        ...latestRoutine.runs,
      ].take(_maxStoredRuns).toList(growable: false),
    );

    await _persistRoutine(
      updatedRoutine,
      runningRoutineIds: {
        ...state.runningRoutineIds.where((id) => id != routineId),
      },
    );

    if (trigger == RoutineRunTrigger.scheduled &&
        updatedRoutine.notifyOnCompletion) {
      _maybeNotifyRoutineResult(updatedRoutine, finalizedRunRecord);
    }

    return finalizedRunRecord;
  }

  Future<int> runDueRoutines({
    RoutineRunTrigger trigger = RoutineRunTrigger.scheduled,
  }) async {
    final due = RoutineScheduleService.dueRoutines(
      state.routines,
    ).where((routine) => !state.isRunning(routine.id)).toList(growable: false);
    var executedCount = 0;

    for (final routine in due) {
      final runRecord = await runRoutineNow(routine.id, trigger: trigger);
      if (runRecord != null) {
        executedCount += 1;
      }
    }

    return executedCount;
  }

  Routine? findRoutine(String routineId) => _findRoutine(routineId);

  void _maybeNotifyRoutineResult(Routine routine, RoutineRunRecord runRecord) {
    final notificationService = ref.read(notificationServiceProvider);
    final body = runRecord.preview.isEmpty
        ? (runRecord.isSuccessful
              ? 'Scheduled routine finished.'
              : 'Scheduled routine failed.')
        : runRecord.preview;

    notificationService.showRoutineCompletionNotification(
      routineId: routine.id,
      routineName: routine.trimmedName,
      isSuccessful: runRecord.isSuccessful,
      body: body,
    );
  }

  Future<RoutineRunRecord> _finalizeCompletionActions({
    required Routine routine,
    required RoutineRunRecord runRecord,
  }) async {
    final settings = ref.read(settingsNotifierProvider);
    final completionActionService = ref.read(
      routineCompletionActionServiceProvider,
    );
    final decision = completionActionService.planGoogleChatDelivery(
      routine: routine,
      runRecord: runRecord,
      settings: settings,
    );

    if (!decision.shouldDeliver) {
      return runRecord.copyWith(
        deliveryStatus: decision.status,
        deliveryMessage: decision.message,
      );
    }

    final deliveryService = ref.read(googleChatDeliveryServiceProvider);
    final deliveryResult = await deliveryService.sendMessage(
      webhookUrl: settings.normalizedGoogleChatWebhookUrl,
      text: decision.payload!,
    );

    return runRecord.copyWith(
      deliveryStatus: deliveryResult.isSuccessful
          ? RoutineDeliveryStatus.delivered
          : RoutineDeliveryStatus.failed,
      deliveredAt: deliveryResult.deliveredAt,
      deliveryMessage: deliveryResult.message,
    );
  }

  Routine? _findRoutine(String routineId) {
    for (final routine in state.routines) {
      if (routine.id == routineId) {
        return routine;
      }
    }
    return null;
  }

  Routine _prepareRoutineForPersistence(
    Routine routine, {
    required Routine? previous,
  }) {
    final now = DateTime.now();
    final shouldReschedule =
        previous == null ||
        previous.enabled != routine.enabled ||
        previous.intervalValue != routine.intervalValue ||
        previous.intervalUnit != routine.intervalUnit ||
        previous.nextRunAt == null ||
        !(previous.nextRunAt!.isAfter(now));

    final nextRunAt = !routine.enabled
        ? null
        : shouldReschedule
        ? RoutineScheduleService.computeNextRunAt(routine: routine, from: now)
        : previous.nextRunAt;

    return routine.copyWith(
      name: routine.trimmedName,
      prompt: routine.trimmedPrompt,
      intervalValue: RoutineScheduleService.normalizeIntervalValue(
        routine.intervalValue,
      ),
      nextRunAt: nextRunAt,
      updatedAt: now,
    );
  }

  Future<void> _persistRoutine(
    Routine routine, {
    Set<String>? runningRoutineIds,
  }) async {
    final updated = state.routines
        .map((item) => item.id == routine.id ? routine : item)
        .toList(growable: false);
    await _persistRoutines(updated, runningRoutineIds: runningRoutineIds);
  }

  Future<void> _persistRoutines(
    List<Routine> routines, {
    Set<String>? runningRoutineIds,
  }) async {
    final ordered = _orderedRoutines(routines);
    state = state.copyWith(
      routines: ordered,
      runningRoutineIds: runningRoutineIds,
    );
    await _repository.saveAll(ordered);
  }

  List<Routine> _orderedRoutines(List<Routine> routines) {
    final ordered = [...routines];
    ordered.sort((left, right) {
      final leftDue = RoutineScheduleService.isDue(left);
      final rightDue = RoutineScheduleService.isDue(right);
      if (leftDue != rightDue) {
        return leftDue ? -1 : 1;
      }

      final leftNext = left.nextRunAt;
      final rightNext = right.nextRunAt;
      if (leftNext != null && rightNext != null) {
        final byNextRun = leftNext.compareTo(rightNext);
        if (byNextRun != 0) {
          return byNextRun;
        }
      } else if (leftNext != null || rightNext != null) {
        return leftNext == null ? 1 : -1;
      }

      return right.updatedAt.compareTo(left.updatedAt);
    });
    return ordered;
  }
}
