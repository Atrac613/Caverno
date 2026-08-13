import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/google_chat_delivery_service.dart';
import '../../../../core/services/notification_providers.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/routine_execution_service.dart';
import '../../data/routine_retry_until_green_service.dart';
import '../../data/routine_repository.dart';
import '../../domain/entities/routine.dart';
import '../../domain/services/routine_completion_action_service.dart';
import '../../domain/services/routine_schedule_service.dart';
import 'routine_catalog_reconciliation.dart';
import 'routine_creation_receipt.dart';
import 'routine_creation_receipt_ledger.dart';

export 'routine_creation_receipt.dart';

/// Sentinel used so [RoutinesState.copyWith] can distinguish "leave unchanged"
/// from an explicit `null` (needed to clear the selected routine).
const Object _unsetSelectedRoutine = Object();

class RoutinesState {
  const RoutinesState({
    required this.routines,
    this.runningRoutineIds = const <String>{},
    this.generatingPlanRoutineIds = const <String>{},
    this.selectedRoutineId,
  });

  final List<Routine> routines;
  final Set<String> runningRoutineIds;
  final Set<String> generatingPlanRoutineIds;

  /// Routine shown in the workspace detail pane, or `null` for the home view.
  final String? selectedRoutineId;

  RoutinesState copyWith({
    List<Routine>? routines,
    Set<String>? runningRoutineIds,
    Set<String>? generatingPlanRoutineIds,
    Object? selectedRoutineId = _unsetSelectedRoutine,
  }) {
    return RoutinesState(
      routines: routines ?? this.routines,
      runningRoutineIds: runningRoutineIds ?? this.runningRoutineIds,
      generatingPlanRoutineIds:
          generatingPlanRoutineIds ?? this.generatingPlanRoutineIds,
      selectedRoutineId: identical(selectedRoutineId, _unsetSelectedRoutine)
          ? this.selectedRoutineId
          : selectedRoutineId as String?,
    );
  }

  bool isRunning(String routineId) => runningRoutineIds.contains(routineId);

  bool isGeneratingPlan(String routineId) =>
      generatingPlanRoutineIds.contains(routineId);
}

final routinesNotifierProvider =
    NotifierProvider<RoutinesNotifier, RoutinesState>(RoutinesNotifier.new);

class RoutinesNotifier extends Notifier<RoutinesState> {
  final Uuid _uuid = const Uuid();
  static const int _maxStoredRuns = 8;
  static const int maxPendingCreationReceipts = 64;
  static const int maxCreationReceiptTombstones = 64;

  late RoutineRepositoryApi _repository;
  final RoutineCreationReceiptLedger _creationReceipts =
      RoutineCreationReceiptLedger(
        maxPendingReceipts: maxPendingCreationReceipts,
        maxTombstones: maxCreationReceiptTombstones,
      );
  Future<void> _routineMutationTail = Future<void>.value();

  @override
  RoutinesState build() {
    _repository = ref.read(routineRepositoryProvider);
    final routines = _orderedRoutines(_repository.loadAll());
    return RoutinesState(routines: routines);
  }

  List<Routine> get routinesSnapshot =>
      List<Routine>.unmodifiable(state.routines);
  int get pendingCreationReceiptCount => _creationReceipts.pendingCount;
  int get creationReceiptTombstoneCount => _creationReceipts.tombstoneCount;

  RoutineCreationReceipt? pendingCreationReceipt(
    RoutineCreationReceiptClaim claim,
  ) => _creationReceipts.pending(claim);

  RoutineCreationReceiptTombstone? terminalCreationReceipt(
    RoutineCreationReceiptClaim claim,
  ) => _creationReceipts.terminal(claim);

  RoutineCreationReceipt? releasedCreationReceipt(
    RoutineCreationReceiptClaim claim,
  ) {
    final tombstone = terminalCreationReceipt(claim);
    return tombstone?.disposition == RoutineCreationTerminalDisposition.released
        ? tombstone!.receipt
        : null;
  }

  Future<void> createRoutine({
    required String name,
    required String prompt,
    required int intervalValue,
    required RoutineIntervalUnit intervalUnit,
    required RoutineScheduleMode scheduleMode,
    required int timeOfDayMinutes,
    required bool enabled,
    required bool notifyOnCompletion,
    required bool toolsEnabled,
    required RoutineCompletionAction completionAction,
    required RoutineGoogleChatRule googleChatRule,
    String workspaceDirectory = '',
    bool allowWorkspaceWrites = false,
    RoutineObjectiveEvidenceContract? objectiveEvidenceContract,
    RoutineRetryUntilGreenConfig? retryUntilGreenConfig,
  }) async {
    final prepared = _newRoutine(
      name: name,
      prompt: prompt,
      intervalValue: intervalValue,
      intervalUnit: intervalUnit,
      scheduleMode: scheduleMode,
      timeOfDayMinutes: timeOfDayMinutes,
      enabled: enabled,
      notifyOnCompletion: notifyOnCompletion,
      toolsEnabled: toolsEnabled,
      completionAction: completionAction,
      googleChatRule: googleChatRule,
      workspaceDirectory: workspaceDirectory,
      allowWorkspaceWrites: allowWorkspaceWrites,
      objectiveEvidenceContract: objectiveEvidenceContract,
      retryUntilGreenConfig: retryUntilGreenConfig,
    );
    await _withRoutineMutation(() => _persistLocalRoutine(prepared));
  }

  /// Preallocates a compensable receipt before any repository side effect.
  Future<RoutineCreationAttempt> attemptRoutineCreationWithReceipt({
    required RoutineCreationReceiptBinding binding,
    required RoutineCreationPreEffectGuard preEffectOwnerIsCurrent,
    required String name,
    required String prompt,
    required int intervalValue,
    required RoutineIntervalUnit intervalUnit,
    required RoutineScheduleMode scheduleMode,
    required int timeOfDayMinutes,
    required bool enabled,
    required bool notifyOnCompletion,
    required bool toolsEnabled,
    required RoutineCompletionAction completionAction,
    required RoutineGoogleChatRule googleChatRule,
    String workspaceDirectory = '',
    bool allowWorkspaceWrites = false,
  }) async {
    final priorTerminal = _creationReceipts.terminalWithBinding(binding);
    if (priorTerminal != null) {
      if (priorTerminal.disposition ==
          RoutineCreationTerminalDisposition.released) {
        return RoutineCreationAttempt(
          receipt: priorTerminal.receipt,
          disposition: RoutineCreationCommitDisposition.committed,
        );
      }
      throw const RoutineCreationPreEffectRejection(
        'This exact routine creation call was already compensated.',
      );
    }
    late final RoutineCreationReceipt receipt;
    try {
      final prepared = _newRoutine(
        name: name,
        prompt: prompt,
        intervalValue: intervalValue,
        intervalUnit: intervalUnit,
        scheduleMode: scheduleMode,
        timeOfDayMinutes: timeOfDayMinutes,
        enabled: enabled,
        notifyOnCompletion: notifyOnCompletion,
        toolsEnabled: toolsEnabled,
        completionAction: completionAction,
        googleChatRule: googleChatRule,
        workspaceDirectory: workspaceDirectory,
        allowWorkspaceWrites: allowWorkspaceWrites,
      );
      receipt = RoutineCreationReceipt(
        token: _uuid.v4(),
        binding: binding,
        routine: prepared,
        routineDigest: routineCreationDigest(prepared),
        phase: RoutineCreationReceiptPhase.prepared,
      );
    } catch (error) {
      throw RoutineCreationPreEffectRejection(
        'Routine creation could not be prepared: $error',
      );
    }
    _rememberCreationReceipt(receipt);
    return _withRoutineMutation(
      () => _commitRoutineCreation(
        receipt.claim,
        preEffectOwnerIsCurrent: preEffectOwnerIsCurrent,
      ),
    );
  }

  /// Removes only the unchanged routine named by an exact creation receipt.
  Future<RoutineCreationCompensationDisposition> compensateRoutineCreation(
    RoutineCreationReceiptClaim claim,
  ) => _withRoutineMutation(() => _compensateRoutineCreation(claim));

  Future<RoutineCreationSettlementDisposition> prepareRoutineCreationSettlement(
    RoutineCreationReceiptClaim claim, {
    bool Function()? isStillValid,
  }) => _withRoutineMutation(() {
    final terminal = terminalCreationReceipt(claim);
    if (terminal != null) {
      return terminal.disposition == RoutineCreationTerminalDisposition.released
          ? RoutineCreationSettlementDisposition.released
          : RoutineCreationSettlementDisposition.conflict;
    }
    final bool ownerCurrent;
    try {
      ownerCurrent = isStillValid?.call() ?? true;
    } catch (_) {
      return RoutineCreationSettlementDisposition.effectUncertain;
    }
    if (!ownerCurrent) {
      return RoutineCreationSettlementDisposition.ownerExpired;
    }
    final receipt = pendingCreationReceipt(claim);
    if (receipt == null) {
      return _creationReceipts.containsToken(claim.token)
          ? RoutineCreationSettlementDisposition.conflict
          : RoutineCreationSettlementDisposition.unknownToken;
    }
    if (receipt.phase == RoutineCreationReceiptPhase.settlementPrepared) {
      return RoutineCreationSettlementDisposition.prepared;
    }
    if (receipt.phase != RoutineCreationReceiptPhase.committed) {
      return RoutineCreationSettlementDisposition.conflict;
    }
    late final List<Routine> persisted;
    try {
      persisted = _repository.loadAll();
    } catch (_) {
      return RoutineCreationSettlementDisposition.effectUncertain;
    }
    if (!sameExactRoutineCatalog(persisted, state.routines) ||
        !containsUniqueExactRoutine(state.routines, receipt.routine) ||
        !containsUniqueExactRoutine(persisted, receipt.routine)) {
      return RoutineCreationSettlementDisposition.conflict;
    }
    _replaceReceiptPhase(
      receipt,
      RoutineCreationReceiptPhase.settlementPrepared,
    );
    return RoutineCreationSettlementDisposition.prepared;
  });

  Future<bool> releaseRoutineCreationSettlement(
    RoutineCreationReceiptClaim claim,
  ) => _withRoutineMutation(() {
    final terminal = terminalCreationReceipt(claim);
    if (terminal != null) {
      return terminal.disposition ==
          RoutineCreationTerminalDisposition.released;
    }
    final receipt = pendingCreationReceipt(claim);
    if (receipt == null ||
        receipt.phase != RoutineCreationReceiptPhase.settlementPrepared) {
      return false;
    }
    _creationReceipts.rememberReleased(receipt);
    return true;
  });

  Future<void> updateRoutine({
    required String routineId,
    required String name,
    required String prompt,
    required int intervalValue,
    required RoutineIntervalUnit intervalUnit,
    required RoutineScheduleMode scheduleMode,
    required int timeOfDayMinutes,
    required bool enabled,
    required bool notifyOnCompletion,
    required bool toolsEnabled,
    required RoutineCompletionAction completionAction,
    required RoutineGoogleChatRule googleChatRule,
    String? workspaceDirectory,
    bool? allowWorkspaceWrites,
    RoutineObjectiveEvidenceContract? objectiveEvidenceContract,
    RoutineRetryUntilGreenConfig? retryUntilGreenConfig,
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
      workspaceDirectory: workspaceDirectory ?? existing.workspaceDirectory,
      allowWorkspaceWrites:
          allowWorkspaceWrites ?? existing.allowWorkspaceWrites,
      objectiveEvidenceContract: objectiveEvidenceContract,
      retryUntilGreenConfig: retryUntilGreenConfig,
      intervalValue: RoutineScheduleService.normalizeIntervalValue(
        intervalValue,
      ),
      intervalUnit: intervalUnit,
      scheduleMode: scheduleMode,
      timeOfDayMinutes: RoutineScheduleService.normalizeTimeOfDayMinutes(
        timeOfDayMinutes,
      ),
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

  /// Selects the routine shown in the workspace detail pane. Pass `null` to
  /// return to the routines home view.
  void selectRoutine(String? routineId) {
    if (state.selectedRoutineId == routineId) {
      return;
    }
    state = state.copyWith(selectedRoutineId: routineId);
  }

  Future<void> deleteRoutine(String routineId) async {
    await _withRoutineMutation(
      () => _persistRoutinesUnlocked(
        state.routines
            .where((routine) => routine.id != routineId)
            .toList(growable: false),
        runningRoutineIds: {
          ...state.runningRoutineIds.where((id) => id != routineId),
        },
      ),
    );
    if (state.selectedRoutineId == routineId) {
      state = state.copyWith(selectedRoutineId: null);
    }
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
      workspaceDirectory: source.workspaceDirectory,
      allowWorkspaceWrites: source.allowWorkspaceWrites,
      planArtifact: source.planArtifact,
      intervalValue: source.intervalValue,
      intervalUnit: source.intervalUnit,
      scheduleMode: source.scheduleMode,
      timeOfDayMinutes: source.timeOfDayMinutes,
    );
    final prepared = _prepareRoutineForPersistence(duplicate, previous: null);
    await _withRoutineMutation(
      () => _persistRoutinesUnlocked([...state.routines, prepared]),
    );
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

  Future<void> savePlanDraft({
    required String routineId,
    required String markdown,
  }) async {
    await _savePlanDraft(
      routineId: routineId,
      markdown: markdown,
      revisionLabel: 'Saved routine plan draft',
    );
  }

  Future<String?> generatePlanDraft(String routineId) async {
    final existing = _findRoutine(routineId);
    if (existing == null) {
      return null;
    }
    if (state.isGeneratingPlan(routineId)) {
      return null;
    }

    state = state.copyWith(
      generatingPlanRoutineIds: {...state.generatingPlanRoutineIds, routineId},
    );

    try {
      final markdown = await ref
          .read(routineExecutionServiceProvider)
          .generatePlanDraft(existing);
      await _savePlanDraft(
        routineId: routineId,
        markdown: markdown,
        revisionLabel: 'Generated routine plan draft',
      );
      return markdown;
    } finally {
      state = state.copyWith(
        generatingPlanRoutineIds: {
          ...state.generatingPlanRoutineIds.where((id) => id != routineId),
        },
      );
    }
  }

  Future<void> _savePlanDraft({
    required String routineId,
    required String markdown,
    required String revisionLabel,
  }) async {
    final existing = _findRoutine(routineId);
    if (existing == null) {
      return;
    }
    final normalizedMarkdown = markdown.trimRight();
    final now = DateTime.now();
    final nextArtifact = existing.effectivePlanArtifact
        .copyWith(draftMarkdown: normalizedMarkdown, updatedAt: now)
        .recordRevision(
          markdown: normalizedMarkdown,
          kind: RoutinePlanRevisionKind.draft,
          label: revisionLabel,
          createdAt: now,
        );
    await _persistRoutine(
      existing.copyWith(planArtifact: nextArtifact, updatedAt: now),
    );
  }

  Future<void> approvePlanDraft(String routineId) async {
    final existing = _findRoutine(routineId);
    if (existing == null) {
      return;
    }

    final currentArtifact = existing.effectivePlanArtifact;
    final markdown =
        currentArtifact.normalizedDraftMarkdown ??
        currentArtifact.normalizedApprovedMarkdown;
    if (markdown == null) {
      return;
    }

    final now = DateTime.now();
    final nextArtifact = currentArtifact
        .copyWith(
          draftMarkdown: markdown,
          approvedMarkdown: markdown,
          approvedSourceHash: existing.planSourceHash,
          approvedAt: now,
          updatedAt: now,
        )
        .recordRevision(
          markdown: markdown,
          kind: RoutinePlanRevisionKind.approved,
          label: 'Approved routine plan',
          createdAt: now,
        );
    await _persistRoutine(
      existing.copyWith(planArtifact: nextArtifact, updatedAt: now),
    );
  }

  Future<void> acknowledgeLatestFailure(String routineId) async {
    final existing = _findRoutine(routineId);
    final latestRun = existing?.latestRun;
    if (existing == null ||
        latestRun == null ||
        latestRun.isSuccessful ||
        latestRun.failureAcknowledged) {
      return;
    }

    final updatedRuns = [
      latestRun.copyWith(failureAcknowledged: true),
      ...existing.runs.skip(1),
    ];
    final updated = existing.copyWith(
      runs: updatedRuns,
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

    final retryConfig = routine.retryUntilGreenConfig;
    final shouldRetry =
        trigger == RoutineRunTrigger.scheduled && retryConfig?.enabled == true;
    final retryService = shouldRetry
        ? ref.read(routineRetryUntilGreenServiceProvider)
        : null;
    final runRecord = shouldRetry && retryService == null
        ? _retryUnavailableRunRecord(trigger)
        : retryService != null
        ? (await retryService.run(routine)).runRecord
        : await ref
              .read(routineExecutionServiceProvider)
              .execute(routine, trigger: trigger);
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

  RoutineRunRecord _retryUnavailableRunRecord(RoutineRunTrigger trigger) {
    final now = DateTime.now();
    const message =
        'Routine retry-until-green requires available workspace tools.';
    return RoutineRunRecord(
      id: _uuid.v4(),
      startedAt: now,
      finishedAt: now,
      status: RoutineRunStatus.failed,
      trigger: trigger,
      preview: message,
      error: message,
    );
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

  Routine? _findRoutine(String routineId) =>
      _findRoutineIn(state.routines, routineId);

  Routine? _findRoutineIn(Iterable<Routine> routines, String routineId) {
    for (final routine in routines) {
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
        previous.scheduleMode != routine.scheduleMode ||
        previous.timeOfDayMinutes != routine.timeOfDayMinutes ||
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
      workspaceDirectory: routine.trimmedWorkspaceDirectory,
      allowWorkspaceWrites:
          routine.toolsEnabled &&
          routine.allowWorkspaceWrites &&
          routine.hasWorkspaceDirectory,
      intervalValue: RoutineScheduleService.normalizeIntervalValue(
        routine.intervalValue,
      ),
      timeOfDayMinutes: RoutineScheduleService.normalizeTimeOfDayMinutes(
        routine.timeOfDayMinutes,
      ),
      nextRunAt: nextRunAt,
      updatedAt: now,
    );
  }

  Routine _newRoutine({
    required String name,
    required String prompt,
    required int intervalValue,
    required RoutineIntervalUnit intervalUnit,
    required RoutineScheduleMode scheduleMode,
    required int timeOfDayMinutes,
    required bool enabled,
    required bool notifyOnCompletion,
    required bool toolsEnabled,
    required RoutineCompletionAction completionAction,
    required RoutineGoogleChatRule googleChatRule,
    required String workspaceDirectory,
    required bool allowWorkspaceWrites,
    RoutineObjectiveEvidenceContract? objectiveEvidenceContract,
    RoutineRetryUntilGreenConfig? retryUntilGreenConfig,
  }) {
    final now = DateTime.now();
    return _prepareRoutineForPersistence(
      Routine(
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
        workspaceDirectory: workspaceDirectory,
        allowWorkspaceWrites: allowWorkspaceWrites,
        objectiveEvidenceContract: objectiveEvidenceContract,
        retryUntilGreenConfig: retryUntilGreenConfig,
        intervalValue: RoutineScheduleService.normalizeIntervalValue(
          intervalValue,
        ),
        intervalUnit: intervalUnit,
        scheduleMode: scheduleMode,
        timeOfDayMinutes: RoutineScheduleService.normalizeTimeOfDayMinutes(
          timeOfDayMinutes,
        ),
      ),
      previous: null,
    );
  }

  Future<void> _persistRoutine(
    Routine routine, {
    Set<String>? runningRoutineIds,
  }) => _withRoutineMutation(() async {
    final updated = state.routines
        .map((item) => item.id == routine.id ? routine : item)
        .toList(growable: false);
    await _persistRoutinesUnlocked(
      updated,
      runningRoutineIds: runningRoutineIds,
    );
  });

  Future<void> _persistRoutinesUnlocked(
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

  Future<void> _persistLocalRoutine(Routine routine) async {
    if (_findRoutine(routine.id) != null) {
      throw StateError('A routine with the generated ID already exists.');
    }
    final runningBefore = Set<String>.of(state.runningRoutineIds);
    late final List<Routine> baseline;
    try {
      baseline = _repository.loadAll();
    } catch (error) {
      throw StateError('Routine catalog could not be refreshed: $error');
    }
    if (!sameExactRoutineCatalog(baseline, state.routines)) {
      _adoptRoutineCatalog(baseline, runningBefore: runningBefore);
      throw StateError('Routine catalog changed before local creation.');
    }

    final intended = _orderedRoutines([...baseline, routine]);
    Object? persistenceError;
    try {
      await _persistRoutinesUnlocked(intended);
    } catch (error) {
      persistenceError = error;
    }

    List<Routine>? persisted;
    try {
      persisted = _repository.loadAll();
    } catch (error) {
      persistenceError ??= error;
    }
    final readback = persisted;
    if (readback != null) {
      _adoptRoutineCatalog(readback, runningBefore: runningBefore);
      if (sameExactRoutineCatalog(readback, intended) &&
          containsUniqueExactRoutine(readback, routine)) {
        return;
      }
      if (containsUniqueExactRoutine(readback, routine) &&
          isCompatibleCatalogProjection(readback, intended)) {
        try {
          await _persistRoutinesUnlocked(intended);
        } catch (error) {
          persistenceError ??= error;
        }
        try {
          final repaired = _repository.loadAll();
          _adoptRoutineCatalog(repaired, runningBefore: runningBefore);
          if (sameExactRoutineCatalog(repaired, intended) &&
              containsUniqueExactRoutine(repaired, routine)) {
            return;
          }
        } catch (error) {
          persistenceError ??= error;
        }
      }
    }
    throw persistenceError ??
        StateError('The persisted routine did not match the local creation.');
  }

  Future<RoutineCreationAttempt> _commitRoutineCreation(
    RoutineCreationReceiptClaim claim, {
    required RoutineCreationPreEffectGuard preEffectOwnerIsCurrent,
  }) async {
    final receipt = pendingCreationReceipt(claim);
    if (receipt == null) {
      throw StateError('Routine creation receipt identity mismatch.');
    }
    if (receipt.phase == RoutineCreationReceiptPhase.committed) {
      return RoutineCreationAttempt(
        receipt: receipt,
        disposition: RoutineCreationCommitDisposition.committed,
      );
    }
    var ownerIsCurrent = false;
    try {
      ownerIsCurrent = preEffectOwnerIsCurrent(receipt.binding);
    } catch (_) {
      ownerIsCurrent = false;
    }
    if (!ownerIsCurrent) {
      _creationReceipts.removePending(claim);
      return RoutineCreationAttempt(
        receipt: receipt,
        disposition: RoutineCreationCommitDisposition.ownerExpiredBeforeEffect,
      );
    }

    final runningBefore = Set<String>.of(state.runningRoutineIds);
    late final List<Routine> baseline;
    try {
      baseline = _repository.loadAll();
    } catch (error) {
      _creationReceipts.removePending(claim);
      return RoutineCreationAttempt(
        receipt: receipt,
        disposition: RoutineCreationCommitDisposition.rejectedBeforeEffect,
        error: StateError('Routine catalog could not be refreshed: $error'),
      );
    }
    if (!sameExactRoutineCatalog(baseline, state.routines)) {
      _adoptRoutineCatalog(baseline, runningBefore: runningBefore);
      _creationReceipts.removePending(claim);
      return RoutineCreationAttempt(
        receipt: receipt,
        disposition: RoutineCreationCommitDisposition.rejectedBeforeEffect,
        error: StateError('Routine catalog changed before creation.'),
      );
    }

    final existing = _findRoutine(receipt.routine.id);
    if (existing != null && existing != receipt.routine) {
      _creationReceipts.removePending(claim);
      return RoutineCreationAttempt(
        receipt: receipt,
        disposition: RoutineCreationCommitDisposition.rejectedBeforeEffect,
        error: StateError('A routine with the generated ID already exists.'),
      );
    }

    final candidate = existing == null
        ? [...baseline, receipt.routine]
        : baseline;
    Object? persistenceError;
    try {
      await _persistRoutinesUnlocked(candidate);
    } catch (error) {
      persistenceError = error;
    }

    List<Routine>? persisted;
    try {
      persisted = _repository.loadAll();
    } catch (error) {
      persistenceError ??= error;
    }
    if (persisted != null &&
        sameExactRoutineCatalog(persisted, state.routines) &&
        containsUniqueExactRoutine(persisted, receipt.routine) &&
        containsUniqueExactRoutine(state.routines, receipt.routine)) {
      final committed = _replaceReceiptPhase(
        receipt,
        RoutineCreationReceiptPhase.committed,
      );
      return RoutineCreationAttempt(
        receipt: committed,
        disposition: RoutineCreationCommitDisposition.committed,
        error: persistenceError,
      );
    }

    if (persisted != null) {
      _adoptRoutineCatalog(persisted, runningBefore: runningBefore);
    }
    final uncertain = _replaceReceiptPhase(
      receipt,
      RoutineCreationReceiptPhase.effectUncertain,
    );
    return RoutineCreationAttempt(
      receipt: uncertain,
      disposition: RoutineCreationCommitDisposition.effectUncertain,
      error:
          persistenceError ??
          StateError(
            'The persisted routine did not match the creation receipt.',
          ),
    );
  }

  Future<RoutineCreationCompensationDisposition> _compensateRoutineCreation(
    RoutineCreationReceiptClaim claim,
  ) async {
    final terminal = terminalCreationReceipt(claim);
    if (terminal != null) {
      if (terminal.disposition ==
          RoutineCreationTerminalDisposition.compensated) {
        return terminal.compensationDisposition!;
      }
      return RoutineCreationCompensationDisposition.conflict;
    }
    final receipt = pendingCreationReceipt(claim);
    if (receipt == null) {
      return _creationReceipts.containsToken(claim.token)
          ? RoutineCreationCompensationDisposition.conflict
          : RoutineCreationCompensationDisposition.unknownToken;
    }

    late final List<Routine> persisted;
    try {
      persisted = _repository.loadAll();
    } catch (_) {
      _replaceReceiptPhase(
        receipt,
        RoutineCreationReceiptPhase.effectUncertain,
      );
      return RoutineCreationCompensationDisposition.effectUncertain;
    }
    final stateBefore = List<Routine>.of(state.routines);
    final runningBefore = Set<String>.of(state.runningRoutineIds);
    if (!hasUniqueRoutineIds(stateBefore) ||
        !hasOnlyExactTargetMatches(stateBefore, receipt.routine) ||
        !hasUniqueRoutineIds(persisted) ||
        !hasOnlyExactTargetMatches(persisted, receipt.routine) ||
        persisted.where((routine) => routine.id == receipt.routine.id).length >
            1) {
      return RoutineCreationCompensationDisposition.conflict;
    }

    final runningWithout = {
      ...state.runningRoutineIds.where((id) => id != receipt.routine.id),
    };
    final targetWasPersisted = persisted.any(
      (routine) => routine.id == receipt.routine.id,
    );
    if (!targetWasPersisted) {
      _adoptRoutineCatalog(persisted, runningBefore: runningWithout);
      _creationReceipts.rememberCompensated(
        receipt,
        RoutineCreationCompensationDisposition.alreadyAbsent,
      );
      return RoutineCreationCompensationDisposition.alreadyAbsent;
    }

    final desired = _orderedRoutines(
      persisted
          .where((routine) => routine.id != receipt.routine.id)
          .toList(growable: false),
    );
    List<Routine>? readback = await _persistCompensationCandidate(
      desired,
      runningRoutineIds: runningWithout,
    );
    if (readback == null) {
      _replaceReceiptPhase(
        receipt,
        RoutineCreationReceiptPhase.effectUncertain,
      );
      return RoutineCreationCompensationDisposition.effectUncertain;
    }
    var reconciled = collapseExactRoutineDuplicates(readback);
    if (reconciled == null ||
        !hasOnlyExactTargetMatches(reconciled, receipt.routine)) {
      _replaceReceiptPhase(
        receipt,
        RoutineCreationReceiptPhase.effectUncertain,
      );
      return RoutineCreationCompensationDisposition.effectUncertain;
    }
    if (reconciled.length != readback.length ||
        reconciled.any((routine) => routine.id == receipt.routine.id)) {
      if (!isCompatibleCatalogProjection(reconciled, desired)) {
        _replaceReceiptPhase(
          receipt,
          RoutineCreationReceiptPhase.effectUncertain,
        );
        return RoutineCreationCompensationDisposition.effectUncertain;
      }
      readback = await _persistCompensationCandidate(
        desired,
        runningRoutineIds: runningWithout,
      );
      if (readback == null) {
        _replaceReceiptPhase(
          receipt,
          RoutineCreationReceiptPhase.effectUncertain,
        );
        return RoutineCreationCompensationDisposition.effectUncertain;
      }
      reconciled = collapseExactRoutineDuplicates(readback);
    }
    if (reconciled != null &&
        hasOnlyExactTargetMatches(reconciled, receipt.routine) &&
        !reconciled.any((routine) => routine.id == receipt.routine.id)) {
      _adoptRoutineCatalog(reconciled, runningBefore: runningWithout);
      _creationReceipts.rememberCompensated(
        receipt,
        RoutineCreationCompensationDisposition.reverted,
      );
      return RoutineCreationCompensationDisposition.reverted;
    }
    _adoptRoutineCatalog(readback, runningBefore: runningBefore);
    _replaceReceiptPhase(receipt, RoutineCreationReceiptPhase.effectUncertain);
    return RoutineCreationCompensationDisposition.effectUncertain;
  }

  Future<List<Routine>?> _persistCompensationCandidate(
    List<Routine> routines, {
    required Set<String> runningRoutineIds,
  }) async {
    try {
      await _persistRoutinesUnlocked(
        routines,
        runningRoutineIds: runningRoutineIds,
      );
    } catch (_) {}
    try {
      return _repository.loadAll();
    } catch (_) {
      return null;
    }
  }

  bool _adoptRoutineCatalog(
    List<Routine> readback, {
    required Set<String> runningBefore,
  }) {
    if (!hasUniqueRoutineIds(readback)) return false;
    state = state.copyWith(
      routines: _orderedRoutines(readback),
      runningRoutineIds: reconciledRunningRoutineIds(runningBefore, readback),
    );
    return true;
  }

  Future<T> _withRoutineMutation<T>(FutureOr<T> Function() action) {
    final predecessor = _routineMutationTail;
    final released = Completer<void>();
    _routineMutationTail = released.future;
    return (() async {
      await predecessor;
      try {
        return await action();
      } finally {
        released.complete();
      }
    })();
  }

  RoutineCreationReceipt _replaceReceiptPhase(
    RoutineCreationReceipt receipt,
    RoutineCreationReceiptPhase phase,
  ) {
    final updated = receipt.withPhase(phase);
    _creationReceipts.replacePending(updated);
    return updated;
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

  void _rememberCreationReceipt(RoutineCreationReceipt receipt) {
    _creationReceipts.addPending(receipt);
  }
}
