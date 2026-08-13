import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/services/google_chat_delivery_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/routines/data/routine_repository.dart';
import 'package:caverno/features/routines/data/routine_execution_service.dart';
import 'package:caverno/features/routines/data/routine_retry_until_green_service.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/routines/presentation/providers/routines_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

void main() {
  Future<ProviderContainer> createContainer({
    required List<Routine> initialRoutines,
    RoutineExecutionService? executionService,
    NotificationService? notificationService,
    GoogleChatDeliveryService? googleChatDeliveryService,
    RoutineRepositoryApi? repository,
    AppSettings? settings,
  }) async {
    SharedPreferences.setMockInitialValues({
      'routines': jsonEncode(
        initialRoutines.map((routine) => routine.toJson()).toList(),
      ),
    });
    final prefs = await SharedPreferences.getInstance();

    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (repository != null)
          routineRepositoryProvider.overrideWithValue(repository),
        settingsNotifierProvider.overrideWith(
          () => _FixedSettingsNotifier(settings ?? AppSettings.defaults()),
        ),
        if (executionService != null)
          routineExecutionServiceProvider.overrideWithValue(executionService),
        routineRetryUntilGreenServiceProvider.overrideWithValue(null),
        if (notificationService != null)
          notificationServiceProvider.overrideWithValue(notificationService),
        if (googleChatDeliveryService != null)
          googleChatDeliveryServiceProvider.overrideWithValue(
            googleChatDeliveryService,
          ),
      ],
    );
  }

  Routine buildRoutine({
    required String id,
    required String name,
    bool enabled = true,
    bool toolsEnabled = false,
    String workspaceDirectory = '',
    bool allowWorkspaceWrites = false,
    bool notifyOnCompletion = true,
    RoutineCompletionAction completionAction = RoutineCompletionAction.none,
    RoutineGoogleChatRule googleChatRule = RoutineGoogleChatRule.onFailure,
    DateTime? nextRunAt,
    DateTime? lastRunAt,
    List<RoutineRunRecord> runs = const [],
    RoutineObjectiveEvidenceContract? objectiveEvidenceContract,
    RoutineRetryUntilGreenConfig? retryUntilGreenConfig,
  }) {
    final now = DateTime(2026, 4, 21, 10);
    return Routine(
      id: id,
      name: name,
      prompt: 'Summarize the latest updates.',
      createdAt: now,
      updatedAt: now,
      enabled: enabled,
      notifyOnCompletion: notifyOnCompletion,
      toolsEnabled: toolsEnabled,
      workspaceDirectory: workspaceDirectory,
      allowWorkspaceWrites: allowWorkspaceWrites,
      completionAction: completionAction,
      googleChatRule: googleChatRule,
      objectiveEvidenceContract: objectiveEvidenceContract,
      retryUntilGreenConfig: retryUntilGreenConfig,
      intervalValue: 1,
      intervalUnit: RoutineIntervalUnit.hours,
      nextRunAt: nextRunAt,
      lastRunAt: lastRunAt,
      runs: runs,
    );
  }

  Future<RoutineCreationReceipt> createReceipt(
    RoutinesNotifier notifier, {
    String name = 'Morning summary',
    RoutineCreationReceiptBinding? binding,
  }) async {
    final attempt = await notifier.attemptRoutineCreationWithReceipt(
      binding: binding ?? _receiptBinding(),
      preEffectOwnerIsCurrent: (_) => true,
      name: name,
      prompt: 'Summarize the latest updates.',
      intervalValue: 1,
      intervalUnit: RoutineIntervalUnit.hours,
      scheduleMode: RoutineScheduleMode.interval,
      timeOfDayMinutes: 0,
      enabled: true,
      notifyOnCompletion: true,
      toolsEnabled: false,
      completionAction: RoutineCompletionAction.none,
      googleChatRule: RoutineGoogleChatRule.onFailure,
    );
    expect(attempt.disposition, RoutineCreationCommitDisposition.committed);
    return attempt.receipt;
  }

  Future<RoutineCreationAttempt> createAttempt(
    RoutinesNotifier notifier, {
    required RoutineCreationReceiptBinding binding,
    String name = 'Morning summary',
    RoutineCreationPreEffectGuard? preEffectOwnerIsCurrent,
  }) {
    return notifier.attemptRoutineCreationWithReceipt(
      binding: binding,
      preEffectOwnerIsCurrent: preEffectOwnerIsCurrent ?? (_) => true,
      name: name,
      prompt: 'Summarize the latest updates.',
      intervalValue: 1,
      intervalUnit: RoutineIntervalUnit.hours,
      scheduleMode: RoutineScheduleMode.interval,
      timeOfDayMinutes: 0,
      enabled: true,
      notifyOnCompletion: true,
      toolsEnabled: false,
      completionAction: RoutineCompletionAction.none,
      googleChatRule: RoutineGoogleChatRule.onFailure,
    );
  }

  Future<void> createLocalRoutine(
    RoutinesNotifier notifier, {
    String name = 'Local routine',
  }) => notifier.createRoutine(
    name: name,
    prompt: 'Summarize the latest updates.',
    intervalValue: 1,
    intervalUnit: RoutineIntervalUnit.hours,
    scheduleMode: RoutineScheduleMode.interval,
    timeOfDayMinutes: 0,
    enabled: true,
    notifyOnCompletion: true,
    toolsEnabled: false,
    completionAction: RoutineCompletionAction.none,
    googleChatRule: RoutineGoogleChatRule.onFailure,
  );

  group('RoutinesNotifier', () {
    test('settles an exact routine creation receipt', () async {
      final container = await createContainer(initialRoutines: const []);
      addTearDown(container.dispose);
      final notifier = container.read(routinesNotifierProvider.notifier);

      final receipt = await createReceipt(notifier);

      expect(notifier.findRoutine(receipt.routine.id), receipt.routine);
      expect(
        await notifier.prepareRoutineCreationSettlement(receipt.claim),
        RoutineCreationSettlementDisposition.prepared,
      );
      expect(
        await notifier.releaseRoutineCreationSettlement(receipt.claim),
        isTrue,
      );
      expect(
        await notifier.prepareRoutineCreationSettlement(receipt.claim),
        RoutineCreationSettlementDisposition.released,
      );
      expect(notifier.findRoutine(receipt.routine.id), receipt.routine);
    });

    test('reverts an unchanged routine creation exactly once', () async {
      final container = await createContainer(initialRoutines: const []);
      addTearDown(container.dispose);
      final notifier = container.read(routinesNotifierProvider.notifier);
      final receipt = await createReceipt(notifier);

      final disposition = await notifier.compensateRoutineCreation(
        receipt.claim,
      );

      expect(disposition, RoutineCreationCompensationDisposition.reverted);
      expect(notifier.findRoutine(receipt.routine.id), isNull);
      expect(
        await notifier.compensateRoutineCreation(receipt.claim),
        RoutineCreationCompensationDisposition.reverted,
      );
    });

    test('refuses to remove a routine changed after creation', () async {
      final container = await createContainer(initialRoutines: const []);
      addTearDown(container.dispose);
      final notifier = container.read(routinesNotifierProvider.notifier);
      final receipt = await createReceipt(notifier);
      await notifier.toggleRoutine(receipt.routine.id, false);

      final disposition = await notifier.compensateRoutineCreation(
        receipt.claim,
      );

      expect(disposition, RoutineCreationCompensationDisposition.conflict);
      expect(notifier.findRoutine(receipt.routine.id)?.enabled, isFalse);
    });

    test(
      'accepts a separately deleted created routine as already absent',
      () async {
        final container = await createContainer(initialRoutines: const []);
        addTearDown(container.dispose);
        final notifier = container.read(routinesNotifierProvider.notifier);
        final receipt = await createReceipt(notifier);
        await notifier.deleteRoutine(receipt.routine.id);

        final disposition = await notifier.compensateRoutineCreation(
          receipt.claim,
        );

        expect(
          disposition,
          RoutineCreationCompensationDisposition.alreadyAbsent,
        );
        expect(notifier.findRoutine(receipt.routine.id), isNull);
      },
    );

    test('rejects cross-owner, call, and digest receipt poison', () async {
      final container = await createContainer(initialRoutines: const []);
      addTearDown(container.dispose);
      final notifier = container.read(routinesNotifierProvider.notifier);
      final receipt = await createReceipt(notifier, binding: _receiptBinding());
      final poisons = [
        _receiptBinding(conversationId: 'conversation-b'),
        _receiptBinding(toolCallId: 'call-b'),
        _receiptBinding(argumentDigest: 'argument-b'),
        _receiptBinding(requestDigest: 'request-b'),
      ];

      for (final binding in poisons) {
        final poison = RoutineCreationReceiptClaim(
          token: receipt.token,
          binding: binding,
          routineDigest: receipt.routineDigest,
        );
        expect(notifier.pendingCreationReceipt(poison), isNull);
        expect(
          await notifier.prepareRoutineCreationSettlement(poison),
          RoutineCreationSettlementDisposition.conflict,
        );
        expect(
          await notifier.compensateRoutineCreation(poison),
          RoutineCreationCompensationDisposition.conflict,
        );
      }
      final digestPoison = RoutineCreationReceiptClaim(
        token: receipt.token,
        binding: receipt.binding,
        routineDigest: 'different-routine-digest',
      );
      expect(
        await notifier.prepareRoutineCreationSettlement(digestPoison),
        RoutineCreationSettlementDisposition.conflict,
      );
      expect(
        await notifier.compensateRoutineCreation(digestPoison),
        RoutineCreationCompensationDisposition.conflict,
      );
      expect(notifier.findRoutine(receipt.routine.id), receipt.routine);
    });

    test('reconciles a repository commit that throws afterward', () async {
      final repository = _ControlledRoutineRepository()
        ..throwAfterNextCommit = true;
      final container = await createContainer(
        initialRoutines: const [],
        repository: repository,
      );
      addTearDown(container.dispose);
      final notifier = container.read(routinesNotifierProvider.notifier);

      final receipt = await createReceipt(notifier, binding: _receiptBinding());

      expect(receipt.phase, RoutineCreationReceiptPhase.committed);
      expect(repository.loadAll(), contains(receipt.routine));
      expect(notifier.pendingCreationReceipt(receipt.claim), receipt);
    });

    test(
      'local creation reconciles commit-then-throw without a receipt',
      () async {
        final repository = _ControlledRoutineRepository()
          ..throwAfterNextCommit = true;
        final container = await createContainer(
          initialRoutines: const [],
          repository: repository,
        );
        addTearDown(container.dispose);
        final notifier = container.read(routinesNotifierProvider.notifier);

        await createLocalRoutine(notifier);

        expect(notifier.routinesSnapshot, hasLength(1));
        expect(repository.loadAll(), notifier.routinesSnapshot);
        expect(notifier.pendingCreationReceiptCount, 0);
      },
    );

    test('local creation rolls back an exact readback mismatch', () async {
      final repository = _ControlledRoutineRepository()..ignoreNextSave = true;
      final container = await createContainer(
        initialRoutines: const [],
        repository: repository,
      );
      addTearDown(container.dispose);
      final notifier = container.read(routinesNotifierProvider.notifier);

      await expectLater(createLocalRoutine(notifier), throwsStateError);

      expect(notifier.routinesSnapshot, isEmpty);
      expect(repository.loadAll(), isEmpty);
      expect(notifier.pendingCreationReceiptCount, 0);
    });

    test('local creation repairs a compatible partial catalog write', () async {
      final first = buildRoutine(id: 'routine-a', name: 'Routine A');
      final second = buildRoutine(id: 'routine-b', name: 'Routine B');
      final repository = _ControlledRoutineRepository([first, second])
        ..transformNextSave = (routines) {
          final created = routines.singleWhere(
            (routine) => routine.name == 'Local routine',
          );
          return [first, created];
        };
      final container = await createContainer(
        initialRoutines: [first, second],
        repository: repository,
      );
      addTearDown(container.dispose);
      final notifier = container.read(routinesNotifierProvider.notifier);

      await createLocalRoutine(notifier);

      expect(repository.loadAll(), notifier.routinesSnapshot);
      expect(repository.loadAll().map((routine) => routine.id).toSet(), {
        first.id,
        second.id,
        notifier.routinesSnapshot
            .singleWhere((routine) => routine.name == 'Local routine')
            .id,
      });
      expect(repository.saveCount, 2);
      expect(notifier.pendingCreationReceiptCount, 0);
    });

    test(
      'classifies preparation failure before allocating a receipt',
      () async {
        final repository = _ControlledRoutineRepository();
        final container = await createContainer(
          initialRoutines: const [],
          repository: repository,
        );
        addTearDown(container.dispose);
        final notifier = container.read(routinesNotifierProvider.notifier);

        await expectLater(
          notifier.attemptRoutineCreationWithReceipt(
            binding: _receiptBinding(toolCallId: 'overflowing-schedule'),
            preEffectOwnerIsCurrent: (_) => true,
            name: 'Overflow',
            prompt: 'Overflow DateTime range.',
            intervalValue: 1 << 62,
            intervalUnit: RoutineIntervalUnit.days,
            scheduleMode: RoutineScheduleMode.interval,
            timeOfDayMinutes: 0,
            enabled: true,
            notifyOnCompletion: true,
            toolsEnabled: false,
            completionAction: RoutineCompletionAction.none,
            googleChatRule: RoutineGoogleChatRule.onFailure,
          ),
          throwsA(isA<RoutineCreationPreEffectRejection>()),
        );

        expect(repository.saveCount, 0);
        expect(notifier.routinesSnapshot, isEmpty);
        expect(notifier.pendingCreationReceiptCount, 0);
      },
    );

    test('retains and compensates a readback mismatch receipt', () async {
      final repository = _ControlledRoutineRepository()..ignoreNextSave = true;
      final container = await createContainer(
        initialRoutines: const [],
        repository: repository,
      );
      addTearDown(container.dispose);
      final notifier = container.read(routinesNotifierProvider.notifier);

      final attempt = await createAttempt(notifier, binding: _receiptBinding());

      expect(
        attempt.disposition,
        RoutineCreationCommitDisposition.effectUncertain,
      );
      expect(
        notifier.pendingCreationReceipt(attempt.receipt.claim)?.phase,
        RoutineCreationReceiptPhase.effectUncertain,
      );
      expect(
        await notifier.compensateRoutineCreation(attempt.receipt.claim),
        RoutineCreationCompensationDisposition.alreadyAbsent,
      );
      expect(notifier.routinesSnapshot, isEmpty);
    });

    test(
      'checks owner validity inside the serialized pre-effect boundary',
      () async {
        final repository = _ControlledRoutineRepository()..delayNextSave();
        final container = await createContainer(
          initialRoutines: const [],
          repository: repository,
        );
        addTearDown(container.dispose);
        final notifier = container.read(routinesNotifierProvider.notifier);
        final blocker = notifier.deleteRoutine('missing');
        await repository.nextSaveStarted.future;
        var current = true;
        RoutineCreationReceiptBinding? checkedBinding;
        final binding = _receiptBinding(toolCallId: 'queued-call');

        final attempt = createAttempt(
          notifier,
          binding: binding,
          preEffectOwnerIsCurrent: (candidate) {
            checkedBinding = candidate;
            return current;
          },
        );
        current = false;
        repository.releaseDelayedSave();
        await blocker;
        final completion = await attempt;

        expect(
          completion.disposition,
          RoutineCreationCommitDisposition.ownerExpiredBeforeEffect,
        );
        expect(checkedBinding, binding);
        expect(repository.saveCount, 1);
        expect(notifier.routinesSnapshot, isEmpty);
        expect(notifier.pendingCreationReceiptCount, 0);
      },
    );

    test(
      'serializes delayed compensation before a successor same-name create',
      () async {
        final repository = _ControlledRoutineRepository();
        final container = await createContainer(
          initialRoutines: const [],
          repository: repository,
        );
        addTearDown(container.dispose);
        final notifier = container.read(routinesNotifierProvider.notifier);
        final first = await createReceipt(notifier, binding: _receiptBinding());
        repository.delayNextSave();

        final compensation = notifier.compensateRoutineCreation(first.claim);
        await repository.nextSaveStarted.future;
        final settlement = notifier.prepareRoutineCreationSettlement(
          first.claim,
        );
        final successor = createReceipt(
          notifier,
          name: first.routine.name,
          binding: _receiptBinding(toolCallId: 'call-successor'),
        );
        repository.releaseDelayedSave();

        expect(
          await compensation,
          RoutineCreationCompensationDisposition.reverted,
        );
        expect(await settlement, RoutineCreationSettlementDisposition.conflict);
        final second = await successor;
        expect(notifier.findRoutine(first.routine.id), isNull);
        expect(notifier.findRoutine(second.routine.id), second.routine);
        expect(repository.loadAll(), [second.routine]);
      },
    );

    test(
      'preserves a delayed successor update while compensating another create',
      () async {
        final repository = _ControlledRoutineRepository();
        final container = await createContainer(
          initialRoutines: const [],
          repository: repository,
        );
        addTearDown(container.dispose);
        final notifier = container.read(routinesNotifierProvider.notifier);
        final first = await createReceipt(notifier, binding: _receiptBinding());
        final successor = await createReceipt(
          notifier,
          name: 'Successor',
          binding: _receiptBinding(toolCallId: 'call-successor'),
        );
        repository.delayNextSave();

        final compensation = notifier.compensateRoutineCreation(first.claim);
        await repository.nextSaveStarted.future;
        final update = notifier.toggleRoutine(successor.routine.id, false);
        repository.releaseDelayedSave();

        expect(
          await compensation,
          RoutineCreationCompensationDisposition.reverted,
        );
        await update;
        expect(notifier.findRoutine(first.routine.id), isNull);
        expect(notifier.findRoutine(successor.routine.id)?.enabled, isFalse);
        expect(repository.loadAll().map((routine) => routine.id), [
          successor.routine.id,
        ]);
      },
    );

    test('reconciles compensation that commits before throwing', () async {
      final repository = _ControlledRoutineRepository();
      final container = await createContainer(
        initialRoutines: const [],
        repository: repository,
      );
      addTearDown(container.dispose);
      final notifier = container.read(routinesNotifierProvider.notifier);
      final receipt = await createReceipt(notifier, binding: _receiptBinding());
      repository.throwAfterNextCommit = true;

      final disposition = await notifier.compensateRoutineCreation(
        receipt.claim,
      );

      expect(disposition, RoutineCreationCompensationDisposition.reverted);
      expect(repository.loadAll(), isEmpty);
      expect(notifier.routinesSnapshot, isEmpty);
      expect(notifier.pendingCreationReceiptCount, 0);
    });

    test('repairs duplicate-ID partial compensation readback', () async {
      final first = buildRoutine(id: 'routine-a', name: 'Routine A');
      final second = buildRoutine(id: 'routine-b', name: 'Routine B');
      final repository = _ControlledRoutineRepository([first, second]);
      final container = await createContainer(
        initialRoutines: [first, second],
        repository: repository,
      );
      addTearDown(container.dispose);
      final notifier = container.read(routinesNotifierProvider.notifier);
      final receipt = await createReceipt(
        notifier,
        binding: _receiptBinding(toolCallId: 'partial-compensation'),
      );
      repository.transformNextSave = (routines) => [
        routines.first,
        routines.first,
      ];

      final disposition = await notifier.compensateRoutineCreation(
        receipt.claim,
      );

      expect(disposition, RoutineCreationCompensationDisposition.reverted);
      expect(repository.loadAll(), notifier.routinesSnapshot);
      expect(repository.loadAll().map((routine) => routine.id).toSet(), {
        first.id,
        second.id,
      });
      expect(repository.loadAll(), hasLength(2));
      expect(notifier.pendingCreationReceiptCount, 0);
    });

    test('revalidates settlement after queued mutation completes', () async {
      final repository = _ControlledRoutineRepository();
      final container = await createContainer(
        initialRoutines: const [],
        repository: repository,
      );
      addTearDown(container.dispose);
      final notifier = container.read(routinesNotifierProvider.notifier);
      final receipt = await createReceipt(
        notifier,
        binding: _receiptBinding(toolCallId: 'settlement-race'),
      );
      repository.delayNextSave();
      final blocker = notifier.deleteRoutine('missing');
      await repository.nextSaveStarted.future;
      final update = notifier.toggleRoutine(receipt.routine.id, false);
      final settlement = notifier.prepareRoutineCreationSettlement(
        receipt.claim,
      );
      repository.releaseDelayedSave();

      await blocker;
      await update;
      expect(await settlement, RoutineCreationSettlementDisposition.conflict);
      expect(
        notifier.pendingCreationReceipt(receipt.claim)?.phase,
        RoutineCreationReceiptPhase.committed,
      );
      expect(notifier.findRoutine(receipt.routine.id)?.enabled, isFalse);
    });

    test('settlement wins when enqueued before compensation', () async {
      final repository = _ControlledRoutineRepository();
      final container = await createContainer(
        initialRoutines: const [],
        repository: repository,
      );
      addTearDown(container.dispose);
      final notifier = container.read(routinesNotifierProvider.notifier);
      final receipt = await createReceipt(notifier, binding: _receiptBinding());

      final settlement = notifier.prepareRoutineCreationSettlement(
        receipt.claim,
      );
      final release = notifier.releaseRoutineCreationSettlement(receipt.claim);
      final compensation = notifier.compensateRoutineCreation(receipt.claim);

      expect(await settlement, RoutineCreationSettlementDisposition.prepared);
      expect(await release, isTrue);
      expect(
        await compensation,
        RoutineCreationCompensationDisposition.conflict,
      );
      expect(notifier.findRoutine(receipt.routine.id), receipt.routine);
      expect(repository.loadAll(), contains(receipt.routine));
      expect(notifier.pendingCreationReceiptCount, 0);
    });

    test(
      'fails at receipt capacity before another repository effect',
      () async {
        final repository = _ControlledRoutineRepository();
        final container = await createContainer(
          initialRoutines: const [],
          repository: repository,
        );
        addTearDown(container.dispose);
        final notifier = container.read(routinesNotifierProvider.notifier);
        for (var index = 0; index < 64; index += 1) {
          await createReceipt(
            notifier,
            name: 'Routine $index',
            binding: _receiptBinding(toolCallId: 'call-$index'),
          );
        }
        final saveCount = repository.saveCount;

        await expectLater(
          createReceipt(
            notifier,
            name: 'Overflow',
            binding: _receiptBinding(toolCallId: 'call-overflow'),
          ),
          throwsA(
            isA<RoutineCreationPreEffectRejection>().having(
              (error) => error.message,
              'message',
              'Too many routine creation receipts are awaiting settlement.',
            ),
          ),
        );
        expect(repository.saveCount, saveCount);
        expect(notifier.routinesSnapshot, hasLength(64));
      },
    );

    test('duplicateRoutine creates a clean copy without run history', () async {
      final source = buildRoutine(
        id: 'routine-1',
        name: 'Morning summary',
        toolsEnabled: true,
        workspaceDirectory: '/tmp/caverno-routines/lan-watch',
        allowWorkspaceWrites: true,
        nextRunAt: DateTime(2026, 4, 21, 11),
        lastRunAt: DateTime(2026, 4, 21, 9),
        runs: [
          RoutineRunRecord(
            id: 'run-1',
            startedAt: DateTime(2026, 4, 21, 9),
            finishedAt: DateTime(2026, 4, 21, 9, 0, 5),
            preview: 'Latest summary ready',
          ),
        ],
      );
      final container = await createContainer(initialRoutines: [source]);
      addTearDown(container.dispose);

      final notifier = container.read(routinesNotifierProvider.notifier);
      final duplicate = await notifier.duplicateRoutine(
        routineId: source.id,
        duplicatedName: 'Copy of Morning summary',
      );

      final state = container.read(routinesNotifierProvider);
      expect(duplicate, isNotNull);
      expect(state.routines, hasLength(2));
      expect(duplicate!.name, 'Copy of Morning summary');
      expect(duplicate.prompt, source.prompt);
      expect(duplicate.toolsEnabled, isTrue);
      expect(duplicate.workspaceDirectory, source.workspaceDirectory);
      expect(duplicate.allowWorkspaceWrites, isTrue);
      expect(duplicate.runs, isEmpty);
      expect(duplicate.lastRunAt, isNull);
      expect(duplicate.nextRunAt, isNotNull);
    });

    test('saves and approves routine plan drafts with source hash', () async {
      final source = buildRoutine(
        id: 'routine-1',
        name: 'Morning summary',
        toolsEnabled: true,
      );
      final container = await createContainer(initialRoutines: [source]);
      addTearDown(container.dispose);

      final notifier = container.read(routinesNotifierProvider.notifier);
      await notifier.savePlanDraft(
        routineId: source.id,
        markdown: '# Routine Plan\n- Search before summarizing.',
      );

      final drafted = notifier.findRoutine(source.id);
      expect(drafted, isNotNull);
      expect(drafted!.hasPlanDraft, isTrue);
      expect(drafted.hasPendingPlanEdits, isTrue);
      expect(drafted.effectivePlanArtifact.historyEntries, hasLength(1));

      await notifier.approvePlanDraft(source.id);

      final approved = notifier.findRoutine(source.id);
      expect(approved, isNotNull);
      expect(approved!.isApprovedPlanFresh, isTrue);
      expect(approved.hasPendingPlanEdits, isFalse);
      expect(
        approved.effectivePlanArtifact.approvedSourceHash,
        approved.planSourceHash,
      );
      expect(approved.effectivePlanArtifact.historyEntries, hasLength(2));
    });

    test(
      'generates routine plan drafts through the execution service',
      () async {
        final source = buildRoutine(
          id: 'routine-1',
          name: 'Morning summary',
          toolsEnabled: true,
        );
        final executionService = _FakeRoutineExecutionService(
          generatedPlanDraft: '# Routine Plan\n- Search before summarizing.',
        );
        final container = await createContainer(
          initialRoutines: [source],
          executionService: executionService,
        );
        addTearDown(container.dispose);

        final notifier = container.read(routinesNotifierProvider.notifier);
        final markdown = await notifier.generatePlanDraft(source.id);

        final drafted = notifier.findRoutine(source.id);
        expect(markdown, '# Routine Plan\n- Search before summarizing.');
        expect(executionService.generatedPlanRoutineIds, [source.id]);
        expect(drafted, isNotNull);
        expect(drafted!.hasPlanDraft, isTrue);
        expect(drafted.hasPendingPlanEdits, isTrue);
        expect(
          drafted.effectivePlanArtifact.historyEntries.single.label,
          'Generated routine plan draft',
        );
        expect(
          container.read(routinesNotifierProvider).isGeneratingPlan(source.id),
          isFalse,
        );
      },
    );

    test(
      'clearRunHistory removes stored runs and last run timestamp',
      () async {
        final source = buildRoutine(
          id: 'routine-1',
          name: 'Morning summary',
          nextRunAt: DateTime(2026, 4, 21, 11),
          lastRunAt: DateTime(2026, 4, 21, 9),
          runs: [
            RoutineRunRecord(
              id: 'run-1',
              startedAt: DateTime(2026, 4, 21, 9),
              finishedAt: DateTime(2026, 4, 21, 9, 0, 5),
              preview: 'Latest summary ready',
            ),
          ],
        );
        final container = await createContainer(initialRoutines: [source]);
        addTearDown(container.dispose);

        final notifier = container.read(routinesNotifierProvider.notifier);
        await notifier.clearRunHistory(source.id);

        final cleared = container
            .read(routinesNotifierProvider.notifier)
            .findRoutine(source.id);
        expect(cleared, isNotNull);
        expect(cleared!.runs, isEmpty);
        expect(cleared.lastRunAt, isNull);
        expect(cleared.nextRunAt, source.nextRunAt);
      },
    );

    test(
      'acknowledgeLatestFailure clears attention without deleting run history',
      () async {
        final failedRun = RoutineRunRecord(
          id: 'run-failed',
          startedAt: DateTime(2026, 4, 21, 9),
          finishedAt: DateTime(2026, 4, 21, 9, 0, 5),
          status: RoutineRunStatus.failed,
          preview: 'Request timed out',
          error: 'Request timed out',
        );
        final previousRun = RoutineRunRecord(
          id: 'run-previous',
          startedAt: DateTime(2026, 4, 21, 8),
          finishedAt: DateTime(2026, 4, 21, 8, 0, 5),
          preview: 'Previous output',
        );
        final source = buildRoutine(
          id: 'routine-1',
          name: 'Morning summary',
          nextRunAt: DateTime(2026, 4, 21, 11),
          lastRunAt: DateTime(2026, 4, 21, 9),
          runs: [failedRun, previousRun],
        );
        final container = await createContainer(initialRoutines: [source]);
        addTearDown(container.dispose);

        final notifier = container.read(routinesNotifierProvider.notifier);
        await notifier.acknowledgeLatestFailure(source.id);

        final updated = notifier.findRoutine(source.id);
        expect(updated, isNotNull);
        expect(updated!.runs, hasLength(2));
        expect(updated.latestRun?.id, failedRun.id);
        expect(updated.latestRun?.failureAcknowledged, isTrue);
        expect(updated.latestRun?.requiresAttention, isFalse);
        expect(updated.latestRun?.error, 'Request timed out');
        expect(updated.lastRunAt, source.lastRunAt);
        expect(updated.nextRunAt, source.nextRunAt);
      },
    );

    test(
      'runDueRoutines executes only due routines with the requested trigger',
      () async {
        final dueRoutine = buildRoutine(
          id: 'routine-due',
          name: 'Due routine',
          nextRunAt: DateTime(2026, 4, 21, 9),
        );
        final futureRoutine = buildRoutine(
          id: 'routine-future',
          name: 'Future routine',
          nextRunAt: DateTime(3026, 4, 21, 11),
        );
        final container = await createContainer(
          initialRoutines: [dueRoutine, futureRoutine],
          executionService: _FakeRoutineExecutionService(),
        );
        addTearDown(container.dispose);

        final notifier = container.read(routinesNotifierProvider.notifier);
        final executedCount = await notifier.runDueRoutines(
          trigger: RoutineRunTrigger.manual,
        );

        final updatedDue = notifier.findRoutine(dueRoutine.id);
        final untouchedFuture = notifier.findRoutine(futureRoutine.id);

        expect(executedCount, 1);
        expect(updatedDue?.latestRun, isNotNull);
        expect(updatedDue?.latestRun?.trigger, RoutineRunTrigger.manual);
        expect(updatedDue?.latestRun?.preview, 'Executed by fake service');
        expect(untouchedFuture?.runs, isEmpty);
      },
    );

    test(
      'scheduled runs notify when routine notifications are enabled',
      () async {
        final notificationService = _FakeNotificationService();
        final dueRoutine = buildRoutine(
          id: 'routine-due',
          name: 'Due routine',
          nextRunAt: DateTime(2026, 4, 21, 9),
        );
        final container = await createContainer(
          initialRoutines: [dueRoutine],
          executionService: _FakeRoutineExecutionService(),
          notificationService: notificationService,
        );
        addTearDown(container.dispose);

        final notifier = container.read(routinesNotifierProvider.notifier);
        await notifier.runDueRoutines();

        expect(notificationService.calls, hasLength(1));
        expect(notificationService.calls.single.routineId, dueRoutine.id);
        expect(notificationService.calls.single.routineName, 'Due routine');
        expect(notificationService.calls.single.isSuccessful, isTrue);
        expect(
          notificationService.calls.single.body,
          'Executed by fake service',
        );
      },
    );

    test(
      'scheduled retry fails closed when workspace tools are unavailable',
      () async {
        final executionService = _FakeRoutineExecutionService();
        final dueRoutine = buildRoutine(
          id: 'routine-retry',
          name: 'Retry routine',
          notifyOnCompletion: false,
          nextRunAt: DateTime(2026, 4, 21, 9),
          objectiveEvidenceContract: const RoutineObjectiveEvidenceContract(
            objective: 'Produce a verified result.',
            acceptanceCriteria: ['The result is correct.'],
            verificationCommand: 'dart test',
          ),
          retryUntilGreenConfig: const RoutineRetryUntilGreenConfig(
            enabled: true,
          ),
        );
        final container = await createContainer(
          initialRoutines: [dueRoutine],
          executionService: executionService,
        );
        addTearDown(container.dispose);

        await container
            .read(routinesNotifierProvider.notifier)
            .runDueRoutines();

        final run = container
            .read(routinesNotifierProvider.notifier)
            .findRoutine(dueRoutine.id)
            ?.latestRun;
        expect(run?.status, RoutineRunStatus.failed);
        expect(run?.error, contains('requires available workspace tools'));
        expect(executionService.executedRoutineIds, isEmpty);
      },
    );

    test(
      'scheduled runs skip notifications when disabled on the routine',
      () async {
        final notificationService = _FakeNotificationService();
        final dueRoutine = buildRoutine(
          id: 'routine-due',
          name: 'Due routine',
          notifyOnCompletion: false,
          nextRunAt: DateTime(2026, 4, 21, 9),
        );
        final container = await createContainer(
          initialRoutines: [dueRoutine],
          executionService: _FakeRoutineExecutionService(),
          notificationService: notificationService,
        );
        addTearDown(container.dispose);

        final notifier = container.read(routinesNotifierProvider.notifier);
        await notifier.runDueRoutines();

        expect(notificationService.calls, isEmpty);
      },
    );

    test(
      'runRoutineNow posts to Google Chat when the rule matches and webhook exists',
      () async {
        final deliveryService = _FakeGoogleChatDeliveryService(
          result: GoogleChatDeliveryResult(
            isSuccessful: true,
            message: 'Posted to Google Chat.',
            deliveredAt: DateTime(2026, 4, 21, 10, 0, 3),
          ),
        );
        final routine = buildRoutine(
          id: 'routine-delivery',
          name: 'Delivery routine',
          completionAction: RoutineCompletionAction.googleChat,
          googleChatRule: RoutineGoogleChatRule.always,
          nextRunAt: DateTime(2026, 4, 21, 11),
        );
        final container = await createContainer(
          initialRoutines: [routine],
          executionService: _FakeRoutineExecutionService(),
          googleChatDeliveryService: deliveryService,
          settings: AppSettings.defaults().copyWith(
            googleChatWebhookUrl: 'https://chat.googleapis.com/v1/spaces/test',
          ),
        );
        addTearDown(container.dispose);

        final notifier = container.read(routinesNotifierProvider.notifier);
        final runRecord = await notifier.runRoutineNow(routine.id);
        final updatedRoutine = notifier.findRoutine(routine.id);

        expect(deliveryService.calls, hasLength(1));
        expect(
          deliveryService.calls.single.webhookUrl,
          'https://chat.googleapis.com/v1/spaces/test',
        );
        expect(
          deliveryService.calls.single.text,
          contains('Routine "Delivery routine" completed.'),
        );
        expect(runRecord?.deliveryStatus, RoutineDeliveryStatus.delivered);
        expect(runRecord?.deliveredAt, DateTime(2026, 4, 21, 10, 0, 3));
        expect(runRecord?.deliveryMessage, 'Posted to Google Chat.');
        expect(
          updatedRoutine?.latestRun?.deliveryStatus,
          RoutineDeliveryStatus.delivered,
        );
      },
    );

    test(
      'runRoutineNow skips Google Chat delivery when the rule does not match',
      () async {
        final deliveryService = _FakeGoogleChatDeliveryService();
        final routine = buildRoutine(
          id: 'routine-skip',
          name: 'Skip routine',
          completionAction: RoutineCompletionAction.googleChat,
          googleChatRule: RoutineGoogleChatRule.onFailure,
          nextRunAt: DateTime(2026, 4, 21, 11),
        );
        final container = await createContainer(
          initialRoutines: [routine],
          executionService: _FakeRoutineExecutionService(),
          googleChatDeliveryService: deliveryService,
          settings: AppSettings.defaults().copyWith(
            googleChatWebhookUrl: 'https://chat.googleapis.com/v1/spaces/test',
          ),
        );
        addTearDown(container.dispose);

        final runRecord = await container
            .read(routinesNotifierProvider.notifier)
            .runRoutineNow(routine.id);

        expect(deliveryService.calls, isEmpty);
        expect(runRecord?.deliveryStatus, RoutineDeliveryStatus.skipped);
        expect(runRecord?.deliveryMessage, contains('only failed runs'));
      },
    );
  });
}

class _FixedSettingsNotifier extends SettingsNotifier {
  _FixedSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  AppSettings build() => _settings;
}

RoutineCreationReceiptBinding _receiptBinding({
  String conversationId = 'conversation-a',
  String toolCallId = 'call-a',
  String argumentDigest = 'argument-a',
  String requestDigest = 'request-a',
}) => RoutineCreationReceiptBinding(
  conversationId: conversationId,
  interactionGeneration: 7,
  toolCallId: toolCallId,
  toolName: 'create_routine',
  argumentDigest: argumentDigest,
  requestDigest: requestDigest,
);

final class _ControlledRoutineRepository implements RoutineRepositoryApi {
  _ControlledRoutineRepository([List<Routine> initial = const []])
    : _routines = [...initial];

  List<Routine> _routines;
  bool throwAfterNextCommit = false;
  bool ignoreNextSave = false;
  List<Routine> Function(List<Routine> routines)? transformNextSave;
  bool _delayNextSave = false;
  int saveCount = 0;
  Completer<void> nextSaveStarted = Completer<void>();
  Completer<void>? _delayedSaveRelease;

  @override
  List<Routine> loadAll() => List<Routine>.unmodifiable(_routines);

  void delayNextSave() {
    _delayNextSave = true;
    nextSaveStarted = Completer<void>();
    _delayedSaveRelease = Completer<void>();
  }

  void releaseDelayedSave() => _delayedSaveRelease?.complete();

  @override
  Future<void> saveAll(List<Routine> routines) async {
    saveCount += 1;
    if (ignoreNextSave) {
      ignoreNextSave = false;
      return;
    }
    if (_delayNextSave) {
      _delayNextSave = false;
      nextSaveStarted.complete();
      await _delayedSaveRelease!.future;
    }
    final transform = transformNextSave;
    transformNextSave = null;
    _routines = transform == null ? [...routines] : transform([...routines]);
    if (throwAfterNextCommit) {
      throwAfterNextCommit = false;
      throw StateError('commit completed before transport failure');
    }
  }
}

class _FakeRoutineExecutionService extends RoutineExecutionService {
  _FakeRoutineExecutionService({this.generatedPlanDraft})
    : super(
        dataSource: _StubChatDataSource(),
        settings: AppSettings.defaults(),
      );

  final String? generatedPlanDraft;
  final List<String> generatedPlanRoutineIds = [];
  final List<String> executedRoutineIds = [];

  @override
  Future<String> generatePlanDraft(Routine routine) async {
    generatedPlanRoutineIds.add(routine.id);
    return generatedPlanDraft ?? '# Routine Plan\n- Generated by fake service.';
  }

  @override
  Future<RoutineRunRecord> execute(
    Routine routine, {
    RoutineRunTrigger trigger = RoutineRunTrigger.manual,
    ChatTurnOwner? fileToolOwner,
  }) async {
    executedRoutineIds.add(routine.id);
    return RoutineRunRecord(
      id: 'fake-run-${routine.id}',
      startedAt: DateTime(2026, 4, 21, 10),
      finishedAt: DateTime(2026, 4, 21, 10, 0, 2),
      trigger: trigger,
      preview: 'Executed by fake service',
      output: 'Fake output',
      durationMs: 2000,
    );
  }
}

class _StubChatDataSource implements ChatDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }
}

class _FakeNotificationService extends NotificationService {
  final List<_RoutineNotificationCall> calls = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> showRoutineCompletionNotification({
    required String routineId,
    required String routineName,
    required bool isSuccessful,
    required String body,
  }) async {
    calls.add(
      _RoutineNotificationCall(
        routineId: routineId,
        routineName: routineName,
        isSuccessful: isSuccessful,
        body: body,
      ),
    );
  }
}

class _FakeGoogleChatDeliveryService extends GoogleChatDeliveryService {
  _FakeGoogleChatDeliveryService({
    this.result = const GoogleChatDeliveryResult(
      isSuccessful: true,
      message: 'Posted to Google Chat.',
    ),
  }) : super();

  final GoogleChatDeliveryResult result;
  final List<_GoogleChatDeliveryCall> calls = [];

  @override
  Future<GoogleChatDeliveryResult> sendMessage({
    required String webhookUrl,
    required String text,
  }) async {
    calls.add(_GoogleChatDeliveryCall(webhookUrl: webhookUrl, text: text));
    return result;
  }
}

class _RoutineNotificationCall {
  const _RoutineNotificationCall({
    required this.routineId,
    required this.routineName,
    required this.isSuccessful,
    required this.body,
  });

  final String routineId;
  final String routineName;
  final bool isSuccessful;
  final String body;
}

class _GoogleChatDeliveryCall {
  const _GoogleChatDeliveryCall({required this.webhookUrl, required this.text});

  final String webhookUrl;
  final String text;
}
