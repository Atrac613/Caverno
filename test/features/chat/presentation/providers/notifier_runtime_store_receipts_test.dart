import 'package:caverno/features/chat/data/datasources/create_routine_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/data/datasources/save_skill_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/data/repositories/skill_repository.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/skill.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/create_routine_tool_handler.dart';
import 'package:caverno/features/chat/domain/services/save_skill_tool_handler.dart';
import 'package:caverno/features/chat/presentation/providers/create_routine_notifier_runtime_store.dart';
import 'package:caverno/features/chat/presentation/providers/save_skill_notifier_runtime_store.dart';
import 'package:caverno/features/chat/presentation/providers/skills_notifier.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/routines/presentation/providers/routines_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'skill store settles an exact receipt only for the active owner',
    () async {
      final repository = SkillRepository.inMemory();
      final container = ProviderContainer(
        overrides: [skillRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      container.read(skillsNotifierProvider);
      final notifier = container.read(skillsNotifierProvider.notifier);
      var current = true;
      final store = SaveSkillNotifierRuntimeStore(
        notifier: notifier,
        isOwnerCurrent: (_) => current,
      );
      final runtime = SaveSkillRuntimeInput(
        owner: _owner,
        toolCall: ToolCallInfo(
          id: 'save-call',
          name: canonicalSaveSkillToolName,
          arguments: const {
            'name': 'Release Check',
            'content': '# Verify the release',
          },
        ),
      ).identity;
      final snapshot = store.captureSnapshot(runtime);
      final catalog = SaveSkillCatalogIdentity(
        runtime: runtime,
        catalogDigest: saveSkillCatalogDigest(snapshot.skills!),
      );

      final write = await store.write(
        SaveSkillRuntimeWriteRequest(
          catalog: catalog,
          request: const SkillStoreWriteRequest(
            existingId: null,
            markdown: '# Release Check',
          ),
        ),
      );
      final successIdentity = SaveSkillSuccessIdentity(
        mutation: write.identity,
        compensationToken: write.compensationToken!,
        savedSkillDigest: saveSkillDigest(write.skill!),
      );
      final success = await store.recordSuccess(successIdentity);

      expect(write.disposition, SaveSkillWriteDisposition.committed);
      expect(success.disposition, SaveSkillSuccessDisposition.acknowledged);
      expect(
        notifier.pendingMutationReceipt(
          write.identity,
          write.compensationToken!,
        ),
        isNull,
      );

      current = false;
      expect(
        store.captureSnapshot(runtime).disposition,
        SaveSkillSnapshotDisposition.rejected,
      );
    },
  );

  test('skill store compensates a write after final owner expiry', () async {
    final repository = SkillRepository.inMemory();
    final container = ProviderContainer(
      overrides: [skillRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.read(skillsNotifierProvider);
    final notifier = container.read(skillsNotifierProvider.notifier);
    var current = true;
    final store = SaveSkillNotifierRuntimeStore(
      notifier: notifier,
      isOwnerCurrent: (_) => current,
    );
    final runtime = SaveSkillRuntimeInput(
      owner: _owner,
      toolCall: ToolCallInfo(
        id: 'save-call',
        name: canonicalSaveSkillToolName,
        arguments: const {
          'name': 'Release Check',
          'content': '# Verify the release',
        },
      ),
    ).identity;
    final catalog = SaveSkillCatalogIdentity(
      runtime: runtime,
      catalogDigest: saveSkillCatalogDigest(
        store.captureSnapshot(runtime).skills!,
      ),
    );
    final write = await store.write(
      SaveSkillRuntimeWriteRequest(
        catalog: catalog,
        request: const SkillStoreWriteRequest(
          existingId: null,
          markdown: '# Release Check',
        ),
      ),
    );
    current = false;

    final success = await store.recordSuccess(
      SaveSkillSuccessIdentity(
        mutation: write.identity,
        compensationToken: write.compensationToken!,
        savedSkillDigest: saveSkillDigest(write.skill!),
      ),
    );
    final compensation = await store.compensate(
      SaveSkillCompensationRequest(
        identity: write.identity,
        compensationToken: write.compensationToken!,
      ),
    );

    expect(success.disposition, SaveSkillSuccessDisposition.ownerExpired);
    expect(
      compensation.disposition,
      SaveSkillCompensationDisposition.compensated,
    );
    expect(notifier.skillsSnapshot, isEmpty);
  });

  test('runtime reconciles commit-then-throw with legacy error text', () async {
    final repository = _CommitThenThrowSkillRepository();
    final container = ProviderContainer(
      overrides: [skillRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.read(skillsNotifierProvider);
    final notifier = container.read(skillsNotifierProvider.notifier);
    final store = SaveSkillNotifierRuntimeStore(
      notifier: notifier,
      isOwnerCurrent: (_) => true,
    );
    final runtime = _saveRuntime(store: store);

    final completion = await runtime.handle(
      owner: _owner,
      toolCall: _saveToolCall,
    );

    expect(completion.disposition, SaveSkillRuntimeDisposition.rejected);
    expect(
      completion.result.errorMessage,
      'Failed to save skill: Bad state: repository write failed',
    );
    expect(notifier.skillsSnapshot, isEmpty);
    expect(notifier.pendingMutationReceiptCount, 0);
  });

  test(
    'runtime compensates owner expiry returned by final success store',
    () async {
      final repository = SkillRepository.inMemory();
      final container = ProviderContainer(
        overrides: [skillRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      container.read(skillsNotifierProvider);
      final notifier = container.read(skillsNotifierProvider.notifier);
      var current = true;
      final store = SaveSkillNotifierRuntimeStore(
        notifier: notifier,
        isOwnerCurrent: (_) => current,
      );
      final runtime = _saveRuntime(
        store: store,
        recordSuccess: (identity) async {
          current = false;
          return store.recordSuccess(identity);
        },
      );

      final completion = await runtime.handle(
        owner: _owner,
        toolCall: _saveToolCall,
      );

      expect(completion.disposition, SaveSkillRuntimeDisposition.ownerExpired);
      expect(
        completion.result.errorMessage,
        'The approval turn expired before execution',
      );
      expect(notifier.skillsSnapshot, isEmpty);
      expect(notifier.pendingMutationReceiptCount, 0);
    },
  );

  test(
    'runtime reconciles a final success callback that throws after settlement',
    () async {
      final repository = SkillRepository.inMemory();
      final container = ProviderContainer(
        overrides: [skillRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      container.read(skillsNotifierProvider);
      final notifier = container.read(skillsNotifierProvider.notifier);
      final store = SaveSkillNotifierRuntimeStore(
        notifier: notifier,
        isOwnerCurrent: (_) => true,
      );
      final runtime = _saveRuntime(
        store: store,
        recordSuccess: (identity) async {
          final acknowledgement = await store.recordSuccess(identity);
          expect(
            acknowledgement.disposition,
            SaveSkillSuccessDisposition.acknowledged,
          );
          throw StateError('injected post-settlement failure');
        },
      );

      final completion = await runtime.handle(
        owner: _owner,
        toolCall: _saveToolCall,
      );

      expect(completion.disposition, SaveSkillRuntimeDisposition.completed);
      expect(completion.result.isSuccess, isTrue);
      expect(repository.getAll(), hasLength(1));
      expect(notifier.pendingMutationReceiptCount, 0);
      expect(notifier.settledMutationReceiptCount, 1);
    },
  );

  test(
    'routine store settles and compensates exact creation receipts',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);
      container.read(routinesNotifierProvider);
      final notifier = container.read(routinesNotifierProvider.notifier);
      var current = true;
      final store = CreateRoutineNotifierRuntimeStore(
        notifier: notifier,
        isOwnerCurrent: (_) => current,
      );
      final firstIdentity = _routineIdentity('routine-call-1');
      final first = await store.create(firstIdentity, _routineRequest);
      final firstReceipt = first.receiptIdentity!;
      final firstSnapshot = store.captureSnapshot(firstReceipt);
      final firstSuccess = await store.recordSuccess(
        CreateRoutineSuccessIdentity(receiptIdentity: firstReceipt),
      );
      final firstRelease = await store.releaseSuccess(
        CreateRoutineSuccessIdentity(receiptIdentity: firstReceipt),
      );

      expect(
        firstSnapshot.disposition,
        CreateRoutineSnapshotDisposition.captured,
      );
      expect(
        firstSuccess.disposition,
        CreateRoutineSuccessDisposition.acknowledged,
      );
      expect(
        firstRelease.disposition,
        CreateRoutineSuccessReleaseDisposition.released,
      );
      expect(
        notifier.pendingCreationReceipt(_routineClaim(firstReceipt)),
        isNull,
      );

      final secondIdentity = _routineIdentity('routine-call-2');
      final second = await store.create(secondIdentity, _routineRequest);
      current = false;
      expect(
        store.captureSnapshot(second.receiptIdentity!).disposition,
        CreateRoutineSnapshotDisposition.ownerExpired,
      );
      final compensated = await store.compensate(second.receiptIdentity!);

      expect(
        compensated.disposition,
        CreateRoutineCompensationDisposition.reverted,
      );
      expect(notifier.routinesSnapshot, hasLength(1));
    },
  );

  test(
    'routine store rejects owner, call, and digest receipt poison',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);
      container.read(routinesNotifierProvider);
      final notifier = container.read(routinesNotifierProvider.notifier);
      final store = CreateRoutineNotifierRuntimeStore(
        notifier: notifier,
        isOwnerCurrent: (_) => true,
      );
      final write = await store.create(
        _routineIdentity('routine-call-poison'),
        _routineRequest,
      );
      final receipt = write.receiptIdentity!;
      final otherOwner = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: receipt.runtime.owner.interactionGeneration,
      );
      final poisons = [
        _changedRoutineReceipt(
          receipt,
          runtime: _changedRoutineRuntime(receipt.runtime, owner: otherOwner),
        ),
        _changedRoutineReceipt(
          receipt,
          runtime: _changedRoutineRuntime(
            receipt.runtime,
            toolCallId: 'other-call',
          ),
        ),
        _changedRoutineReceipt(
          receipt,
          runtime: _changedRoutineRuntime(
            receipt.runtime,
            argumentDigest: 'other-argument',
          ),
        ),
        _changedRoutineReceipt(receipt, requestDigest: 'other-request'),
        _changedRoutineReceipt(receipt, createdRoutineDigest: 'other-routine'),
      ];

      for (final poison in poisons) {
        expect(
          store.captureSnapshot(poison).disposition,
          CreateRoutineSnapshotDisposition.effectUncertain,
        );
        expect(
          (await store.compensate(poison)).disposition,
          CreateRoutineCompensationDisposition.effectUncertain,
        );
      }
      expect(
        (await store.recordSuccess(
          CreateRoutineSuccessIdentity(
            receiptIdentity: _changedRoutineReceipt(
              receipt,
              requestDigest: 'settlement-poison',
            ),
          ),
        )).disposition,
        CreateRoutineSuccessDisposition.effectUncertain,
      );
      final successIdentity = CreateRoutineSuccessIdentity(
        receiptIdentity: receipt,
      );
      expect(
        (await store.recordSuccess(successIdentity)).disposition,
        CreateRoutineSuccessDisposition.acknowledged,
      );
      expect(
        (await store.releaseSuccess(successIdentity)).disposition,
        CreateRoutineSuccessReleaseDisposition.released,
      );
    },
  );

  test('routine store classifies duplicate binding as rejection', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    container.read(routinesNotifierProvider);
    final notifier = container.read(routinesNotifierProvider.notifier);
    final store = CreateRoutineNotifierRuntimeStore(
      notifier: notifier,
      isOwnerCurrent: (_) => true,
    );
    final identity = _routineIdentity('duplicate-call');

    final first = await store.create(identity, _routineRequest);
    final duplicate = await store.create(identity, _routineRequest);

    expect(first.disposition, CreateRoutineStoreDisposition.committed);
    expect(duplicate.disposition, CreateRoutineStoreDisposition.rejected);
    expect(
      duplicate.errorMessage,
      'Failed to create routine: '
      'A routine creation receipt already exists for this exact call.',
    );
    expect(notifier.routinesSnapshot, hasLength(1));
    expect(notifier.pendingCreationReceiptCount, 1);
  });

  test(
    'routine runtime compensates when prepared settlement acknowledgement throws',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);
      container.read(routinesNotifierProvider);
      final notifier = container.read(routinesNotifierProvider.notifier);
      final store = CreateRoutineNotifierRuntimeStore(
        notifier: notifier,
        isOwnerCurrent: (_) => true,
      );
      final runtime = _routineRuntime(
        store: store,
        recordSuccess: (identity) async {
          final prepared = await store.recordSuccess(identity);
          expect(
            prepared.disposition,
            CreateRoutineSuccessDisposition.acknowledged,
          );
          throw StateError('settlement acknowledgement failed');
        },
      );

      final completion = await runtime.handle(
        owner: _owner,
        toolCall: _routineToolCall('prepare-then-throw'),
      );

      expect(completion.disposition, CreateRoutineRuntimeDisposition.rejected);
      expect(completion.result.errorMessage, contains('could not be settled'));
      expect(notifier.routinesSnapshot, isEmpty);
      expect(notifier.pendingCreationReceiptCount, 0);
    },
  );

  test('routine store rejects a throwing initial owner lookup', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    container.read(routinesNotifierProvider);
    final notifier = container.read(routinesNotifierProvider.notifier);
    final store = CreateRoutineNotifierRuntimeStore(
      notifier: notifier,
      isOwnerCurrent: (_) => throw StateError('owner lookup failed'),
    );

    final acknowledgement = await store.create(
      _routineIdentity('throwing-owner'),
      _routineRequest,
    );

    expect(acknowledgement.disposition, CreateRoutineStoreDisposition.rejected);
    expect(
      acknowledgement.errorMessage,
      'Failed to validate routine creation owner: '
      'Bad state: owner lookup failed',
    );
    expect(notifier.routinesSnapshot, isEmpty);
    expect(notifier.pendingCreationReceiptCount, 0);
  });

  test(
    'routine store rejects schedule overflow before allocating a receipt',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);
      container.read(routinesNotifierProvider);
      final notifier = container.read(routinesNotifierProvider.notifier);
      final store = CreateRoutineNotifierRuntimeStore(
        notifier: notifier,
        isOwnerCurrent: (_) => true,
      );
      const overflowingRequest = RoutineStoreCreateRequest(
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
        workspaceDirectory: '',
        allowWorkspaceWrites: false,
      );

      final acknowledgement = await store.create(
        _routineIdentity('overflowing-schedule'),
        overflowingRequest,
      );

      expect(
        acknowledgement.disposition,
        CreateRoutineStoreDisposition.rejected,
      );
      expect(
        acknowledgement.errorMessage,
        startsWith(
          'Failed to create routine: Routine creation could not be prepared:',
        ),
      );
      expect(notifier.routinesSnapshot, isEmpty);
      expect(notifier.pendingCreationReceiptCount, 0);
    },
  );

  test('routine store rejects receipt capacity before persistence', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    container.read(routinesNotifierProvider);
    final notifier = container.read(routinesNotifierProvider.notifier);
    final store = CreateRoutineNotifierRuntimeStore(
      notifier: notifier,
      isOwnerCurrent: (_) => true,
    );
    for (var index = 0; index < 64; index += 1) {
      final acknowledgement = await store.create(
        _routineIdentity('capacity-$index'),
        _routineRequest,
      );
      expect(
        acknowledgement.disposition,
        CreateRoutineStoreDisposition.committed,
      );
    }

    final overflow = await store.create(
      _routineIdentity('capacity-overflow'),
      _routineRequest,
    );

    expect(overflow.disposition, CreateRoutineStoreDisposition.rejected);
    expect(
      overflow.errorMessage,
      'Failed to create routine: '
      'Too many routine creation receipts are awaiting settlement.',
    );
    expect(notifier.routinesSnapshot, hasLength(64));
    expect(notifier.pendingCreationReceiptCount, 64);
  });
}

final _owner = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 7,
);

final _saveToolCall = ToolCallInfo(
  id: 'save-call',
  name: canonicalSaveSkillToolName,
  arguments: const {'name': 'Release Check', 'content': '# Verify the release'},
);

SaveSkillToolRuntimeAdapter _saveRuntime({
  required SaveSkillNotifierRuntimeStore store,
  SaveSkillSuccessCallback? recordSuccess,
}) => SaveSkillToolRuntimeAdapter(
  captureSnapshot: store.captureSnapshot,
  requestFreshManualApproval: (request) async =>
      SaveSkillApprovalAcknowledgement(
        identity: request.identity,
        disposition: SaveSkillApprovalDisposition.approved,
      ),
  acknowledgeOwner: (identity) => SaveSkillOwnerAcknowledgement(
    identity: identity,
    disposition: SaveSkillOwnerDisposition.current,
  ),
  write: store.write,
  compensate: store.compensate,
  recordSuccess: recordSuccess ?? store.recordSuccess,
  reconcileSuccess: store.reconcileSuccess,
);

CreateRoutineToolRuntimeAdapter _routineRuntime({
  required CreateRoutineNotifierRuntimeStore store,
  CreateRoutineSuccessCallback? recordSuccess,
}) => CreateRoutineToolRuntimeAdapter(
  requestApproval: (identity, _) async => CreateRoutineApprovalAcknowledgement(
    identity: identity,
    disposition: CreateRoutineApprovalDisposition.approved,
  ),
  acknowledgeOwner: (identity) =>
      CreateRoutineOwnerAcknowledgement.current(identity: identity),
  create: store.create,
  captureSnapshot: store.captureSnapshot,
  compensate: store.compensate,
  recordSuccess: recordSuccess ?? store.recordSuccess,
  releaseSuccess: store.releaseSuccess,
);

final class _CommitThenThrowSkillRepository extends SkillRepository {
  _CommitThenThrowSkillRepository() : super.inMemory();

  @override
  Future<void> save(Skill skill) async {
    await super.save(skill);
    throw StateError('repository write failed');
  }
}

CreateRoutineRuntimeIdentity _routineIdentity(String toolCallId) =>
    CreateRoutineRuntimeIdentity(
      owner: _owner,
      toolCallId: toolCallId,
      toolName: createRoutineToolName,
      argumentDigest: 'digest-$toolCallId',
    );

ToolCallInfo _routineToolCall(String toolCallId) => ToolCallInfo(
  id: toolCallId,
  name: createRoutineToolName,
  arguments: const {
    'name': 'Morning summary',
    'prompt': 'Summarize the latest updates.',
  },
);

CreateRoutineRuntimeIdentity _changedRoutineRuntime(
  CreateRoutineRuntimeIdentity identity, {
  ChatTurnOwner? owner,
  String? toolCallId,
  String? argumentDigest,
}) => CreateRoutineRuntimeIdentity(
  owner: owner ?? identity.owner,
  toolCallId: toolCallId ?? identity.toolCallId,
  toolName: identity.toolName,
  argumentDigest: argumentDigest ?? identity.argumentDigest,
);

CreateRoutineReceiptIdentity _changedRoutineReceipt(
  CreateRoutineReceiptIdentity identity, {
  CreateRoutineRuntimeIdentity? runtime,
  String? requestDigest,
  String? createdRoutineDigest,
}) => CreateRoutineReceiptIdentity(
  runtime: runtime ?? identity.runtime,
  compensationToken: identity.compensationToken,
  requestDigest: requestDigest ?? identity.requestDigest,
  createdRoutineDigest: createdRoutineDigest ?? identity.createdRoutineDigest,
);

RoutineCreationReceiptClaim _routineClaim(
  CreateRoutineReceiptIdentity identity,
) => RoutineCreationReceiptClaim(
  token: identity.compensationToken,
  binding: RoutineCreationReceiptBinding(
    conversationId: identity.runtime.owner.conversationId,
    interactionGeneration: identity.runtime.owner.interactionGeneration,
    toolCallId: identity.runtime.toolCallId,
    toolName: identity.runtime.toolName,
    argumentDigest: identity.runtime.argumentDigest,
    requestDigest: identity.requestDigest,
  ),
  routineDigest: identity.createdRoutineDigest,
);

const _routineRequest = RoutineStoreCreateRequest(
  name: 'Morning summary',
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
  workspaceDirectory: '',
  allowWorkspaceWrites: false,
);
