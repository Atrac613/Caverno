import 'dart:async';
import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/create_routine_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/create_routine_tool_handler.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/routines/presentation/providers/routine_creation_receipt.dart';
import 'package:test/test.dart';

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 7,
  );

  group('CreateRoutineRuntimeInput', () {
    test('shares the notifier routine digest contract exactly', () {
      expect(
        createRoutineDigest(_routine()),
        routineCreationDigest(_routine()),
      );
    });

    test('freezes strict JSON and computes a canonical argument digest', () {
      final labels = <Object?>['daily'];
      final metadata = <String, Object?>{'labels': labels};
      final arguments = <String, dynamic>{
        'prompt': 'Inspect alerts',
        'name': 'Alert review',
        'metadata': metadata,
      };
      final input = CreateRoutineRuntimeInput(
        owner: owner,
        toolCall: ToolCallInfo(
          id: 'call-create',
          name: 'create_routine',
          arguments: arguments,
        ),
      );
      final reordered = CreateRoutineRuntimeInput(
        owner: owner,
        toolCall: ToolCallInfo(
          id: 'call-create',
          name: 'create_routine',
          arguments: {
            'metadata': {
              'labels': ['daily'],
            },
            'name': 'Alert review',
            'prompt': 'Inspect alerts',
          },
        ),
      );

      labels.add('poisoned');
      metadata['labels'] = ['replaced'];
      arguments['name'] = 'Poisoned';

      expect(input.identity, reordered.identity);
      expect(input.arguments['name'], 'Alert review');
      expect(input.arguments['metadata'], {
        'labels': ['daily'],
      });
      expect(() => input.arguments['late'] = true, throwsUnsupportedError);
      expect(
        () => ((input.arguments['metadata'] as Map)['labels'] as List).add(
          'late',
        ),
        throwsUnsupportedError,
      );
    });

    test('rejects non-JSON values and ambiguous invocation identity', () {
      for (final invalid in <Object?>[
        <Object?>{'mutable'},
        double.nan,
        double.infinity,
        <Object?, Object?>{1: 'non-string-key'},
      ]) {
        expect(
          () => CreateRoutineRuntimeInput(
            owner: owner,
            toolCall: ToolCallInfo(
              id: 'call-create',
              name: 'create_routine',
              arguments: {
                'name': 'Alert review',
                'prompt': 'Inspect alerts',
                'invalid': invalid,
              },
            ),
          ),
          throwsArgumentError,
        );
      }
      for (final toolCall in [
        ToolCallInfo(id: ' ', name: 'create_routine', arguments: _arguments()),
        ToolCallInfo(
          id: 'call-create',
          name: 'create_routine ',
          arguments: _arguments(),
        ),
      ]) {
        expect(
          () => CreateRoutineRuntimeInput(owner: owner, toolCall: toolCall),
          throwsArgumentError,
        );
      }
    });

    test('rejects whitespace aliases in every receipt identity field', () {
      final runtime = _input(owner, _arguments()).identity;
      final routine = _routine();
      final routineDigest = createRoutineDigest(routine);
      final binding = RoutineCreationReceiptBinding(
        conversationId: owner.conversationId,
        interactionGeneration: owner.interactionGeneration,
        toolCallId: runtime.toolCallId,
        toolName: runtime.toolName,
        argumentDigest: runtime.argumentDigest,
        requestDigest: 'request-digest',
      );
      final invalidRuntimeBuilders = <Object Function()>[
        () => CreateRoutineRuntimeIdentity(
          owner: owner,
          toolCallId: ' ${runtime.toolCallId}',
          toolName: runtime.toolName,
          argumentDigest: runtime.argumentDigest,
        ),
        () => CreateRoutineRuntimeIdentity(
          owner: owner,
          toolCallId: runtime.toolCallId,
          toolName: runtime.toolName,
          argumentDigest: '${runtime.argumentDigest} ',
        ),
        () => CreateRoutineReceiptIdentity(
          runtime: runtime,
          compensationToken: ' token',
          requestDigest: 'request-digest',
          createdRoutineDigest: routineDigest,
        ),
        () => CreateRoutineReceiptIdentity(
          runtime: runtime,
          compensationToken: 'token',
          requestDigest: 'request-digest ',
          createdRoutineDigest: routineDigest,
        ),
        () => CreateRoutineReceiptIdentity(
          runtime: runtime,
          compensationToken: 'token',
          requestDigest: 'request-digest',
          createdRoutineDigest: ' $routineDigest',
        ),
      ];
      final invalidBindingBuilders = <Object Function()>[
        () => RoutineCreationReceiptBinding(
          conversationId: ' ${owner.conversationId}',
          interactionGeneration: owner.interactionGeneration,
          toolCallId: runtime.toolCallId,
          toolName: runtime.toolName,
          argumentDigest: runtime.argumentDigest,
          requestDigest: 'request-digest',
        ),
        () => RoutineCreationReceiptBinding(
          conversationId: owner.conversationId,
          interactionGeneration: owner.interactionGeneration,
          toolCallId: '${runtime.toolCallId} ',
          toolName: runtime.toolName,
          argumentDigest: runtime.argumentDigest,
          requestDigest: 'request-digest',
        ),
        () => RoutineCreationReceiptBinding(
          conversationId: owner.conversationId,
          interactionGeneration: owner.interactionGeneration,
          toolCallId: runtime.toolCallId,
          toolName: ' ${runtime.toolName}',
          argumentDigest: runtime.argumentDigest,
          requestDigest: 'request-digest',
        ),
        () => RoutineCreationReceiptBinding(
          conversationId: owner.conversationId,
          interactionGeneration: owner.interactionGeneration,
          toolCallId: runtime.toolCallId,
          toolName: runtime.toolName,
          argumentDigest: '${runtime.argumentDigest} ',
          requestDigest: 'request-digest',
        ),
        () => RoutineCreationReceiptBinding(
          conversationId: owner.conversationId,
          interactionGeneration: owner.interactionGeneration,
          toolCallId: runtime.toolCallId,
          toolName: runtime.toolName,
          argumentDigest: runtime.argumentDigest,
          requestDigest: ' request-digest',
        ),
      ];
      final invalidClaimBuilders = <Object Function()>[
        () => RoutineCreationReceiptClaim(
          token: ' token',
          binding: binding,
          routineDigest: routineDigest,
        ),
        () => RoutineCreationReceiptClaim(
          token: 'token',
          binding: binding,
          routineDigest: '$routineDigest ',
        ),
        () => RoutineCreationReceipt(
          token: ' token',
          binding: binding,
          routine: routine,
          routineDigest: routineDigest,
          phase: RoutineCreationReceiptPhase.prepared,
        ),
      ];

      for (final builder in [
        ...invalidRuntimeBuilders,
        ...invalidBindingBuilders,
        ...invalidClaimBuilders,
      ]) {
        expect(builder, throwsArgumentError);
      }
    });

    test('changes the digest when any argument changes', () {
      final first = _input(owner, _arguments());
      final second = _input(owner, _arguments({'prompt': 'Inspect incidents'}));

      expect(
        first.identity.argumentDigest,
        isNot(second.identity.argumentDigest),
      );
    });
  });

  group('CreateRoutineToolRuntimeAdapter', () {
    test('acknowledges approval, store, snapshot, and exact success', () async {
      final fixture = _Fixture(owner);

      final completion = await fixture.handle();

      expect(completion.disposition, CreateRoutineRuntimeDisposition.completed);
      expect(completion.result.isSuccess, isTrue);
      expect(jsonDecode(completion.result.result), {
        'ok': true,
        'action': 'created',
        'id': 'routine-1',
        'name': 'Alert review',
        'schedule': 'every 1 hour',
        'tools_enabled': false,
        'notify_on_completion': true,
        'completion_action': 'none',
      });
      expect(fixture.events, [
        'approval',
        'owner',
        'store',
        'snapshot:routine-1',
        'owner',
        'owner',
        'success:routine-1',
      ]);
      expect(fixture.identities, everyElement(completion.identity));
      expect(
        fixture.successIdentity,
        CreateRoutineSuccessIdentity(
          receiptIdentity: fixture.committedReceipt!,
        ),
      );
      expect(fixture.storeRequest!.name, 'Alert review');
      expect(fixture.storeRequest!.prompt, 'Inspect alerts');
    });

    test('keeps an explicit approval rejection distinct', () async {
      final fixture = _Fixture(owner)
        ..approvalDisposition = CreateRoutineApprovalDisposition.rejected;

      final completion = await fixture.handle();

      expect(completion.disposition, CreateRoutineRuntimeDisposition.rejected);
      expect(completion.result.isSuccess, isFalse);
      expect(
        completion.result.errorMessage,
        'User denied creating the routine',
      );
      expect(fixture.events, ['approval', 'owner']);
    });

    test(
      'rejects malformed typed arguments before any runtime effect',
      () async {
        final fixture = _Fixture(owner);

        final completion = await fixture.handle(
          arguments: {'name': 7, 'prompt': 'Inspect alerts'},
        );

        expect(
          completion.disposition,
          CreateRoutineRuntimeDisposition.rejected,
        );
        expect(completion.result.isSuccess, isFalse);
        expect(fixture.events, isEmpty);
      },
    );

    test('reports owner retirement before persistence', () async {
      final fixture = _Fixture(owner)
        ..ownerDispositions.add(CreateRoutineOwnerDisposition.ownerExpired);

      final completion = await fixture.handle();

      expect(
        completion.disposition,
        CreateRoutineRuntimeDisposition.ownerExpired,
      );
      expect(
        completion.result.errorMessage,
        'The create_routine turn expired.',
      );
      expect(fixture.events, ['approval', 'owner']);
    });

    test('keeps a store rejection distinct from uncertain effect', () async {
      final rejected = _Fixture(owner)
        ..storeDisposition = CreateRoutineStoreDisposition.rejected;
      final preEffectRejected = _Fixture(owner)
        ..storeDisposition = CreateRoutineStoreDisposition.rejected
        ..storeError = 'Failed to create routine: duplicate receipt binding.';
      final uncertain = _Fixture(owner)
        ..storeDisposition = CreateRoutineStoreDisposition.effectUncertain;

      final rejectedCompletion = await rejected.handle();
      final preEffectCompletion = await preEffectRejected.handle();
      final uncertainCompletion = await uncertain.handle();

      expect(
        rejectedCompletion.disposition,
        CreateRoutineRuntimeDisposition.rejected,
      );
      expect(
        rejectedCompletion.result.errorMessage,
        'Routine store rejected an owner that is still current.',
      );
      expect(
        preEffectCompletion.result.errorMessage,
        'Failed to create routine: duplicate receipt binding.',
      );
      expect(
        preEffectCompletion.disposition,
        CreateRoutineRuntimeDisposition.rejected,
      );
      expect(
        uncertainCompletion.disposition,
        CreateRoutineRuntimeDisposition.effectUncertain,
      );
      expect(
        uncertainCompletion.result.errorMessage,
        contains('may have persisted'),
      );
    });

    test('classifies a poisoned store acknowledgement as mismatch', () async {
      final fixture = _Fixture(owner)..poisonStoreIdentity = true;

      final completion = await fixture.handle();

      expect(
        completion.disposition,
        CreateRoutineRuntimeDisposition.boundaryMismatch,
      );
      expect(completion.result.errorMessage, contains('may have persisted'));
    });

    test(
      'rejects cross-owner, cross-call, and cross-digest approvals',
      () async {
        final otherOwner = ChatTurnOwner(
          conversationId: 'conversation-b',
          interactionGeneration: owner.interactionGeneration,
        );
        final poisoners =
            <
              CreateRoutineRuntimeIdentity Function(
                CreateRoutineRuntimeIdentity,
              )
            >[
              (identity) => _changedIdentity(identity, owner: otherOwner),
              (identity) =>
                  _changedIdentity(identity, toolCallId: 'other-call'),
              (identity) =>
                  _changedIdentity(identity, argumentDigest: 'poisoned'),
            ];

        for (final poison in poisoners) {
          final fixture = _Fixture(owner)
            ..approvalOverride = (identity, request) => Future.value(
              CreateRoutineApprovalAcknowledgement(
                identity: poison(identity),
                disposition: CreateRoutineApprovalDisposition.approved,
              ),
            );

          final completion = await fixture.handle();

          expect(
            completion.disposition,
            CreateRoutineRuntimeDisposition.boundaryMismatch,
          );
          expect(completion.result.isSuccess, isFalse);
          expect(fixture.events, ['approval', 'owner']);
        }
      },
    );

    test(
      'compensates a snapshot token mismatch with the commit token',
      () async {
        final fixture = _Fixture(owner)..poisonSnapshotToken = true;

        final completion = await fixture.handle();

        expect(
          completion.disposition,
          CreateRoutineRuntimeDisposition.boundaryMismatch,
        );
        expect(completion.result.isSuccess, isFalse);
        expect(fixture.compensationTokens, ['routine-1']);
        expect(fixture.events, [
          'approval',
          'owner',
          'store',
          'snapshot:routine-1',
          'owner',
          'compensate:routine-1',
        ]);
      },
    );

    test('compensates when the owner retires after persistence', () async {
      final fixture = _Fixture(owner)
        ..ownerDispositions.addAll([
          CreateRoutineOwnerDisposition.current,
          CreateRoutineOwnerDisposition.ownerExpired,
        ]);

      final completion = await fixture.handle();

      expect(
        completion.disposition,
        CreateRoutineRuntimeDisposition.ownerExpired,
      );
      expect(fixture.compensationTokens, ['routine-1']);
      expect(
        completion.result.errorMessage,
        'The create_routine turn expired.',
      );
    });

    test('rejects a same-call parsed-request digest poison', () async {
      final fixture = _Fixture(owner)..poisonReceiptRequestDigest = true;

      final completion = await fixture.handle();

      expect(
        completion.disposition,
        CreateRoutineRuntimeDisposition.boundaryMismatch,
      );
      expect(completion.result.isSuccess, isFalse);
      expect(fixture.events, ['approval', 'owner', 'store']);
    });

    test(
      'compensates when the owner retires before final settlement',
      () async {
        final fixture = _Fixture(owner)
          ..ownerDispositions.addAll([
            CreateRoutineOwnerDisposition.current,
            CreateRoutineOwnerDisposition.current,
            CreateRoutineOwnerDisposition.ownerExpired,
          ]);

        final completion = await fixture.handle();

        expect(
          completion.disposition,
          CreateRoutineRuntimeDisposition.ownerExpired,
        );
        expect(
          completion.result.errorMessage,
          'The create_routine turn expired.',
        );
        expect(fixture.compensationTokens, ['routine-1']);
        expect(fixture.successIdentity, isNull);
      },
    );

    test('compensates an unconfirmed final settlement', () async {
      final fixture = _Fixture(owner)
        ..successDisposition = CreateRoutineSuccessDisposition.effectUncertain;

      final completion = await fixture.handle();

      expect(completion.disposition, CreateRoutineRuntimeDisposition.rejected);
      expect(completion.result.errorMessage, contains('could not be settled'));
      expect(fixture.successIdentity, isNotNull);
      expect(fixture.compensationTokens, ['routine-1']);
    });

    test('compensates when final settlement throws', () async {
      final fixture = _Fixture(owner)
        ..successError = StateError('settlement transport failed');

      final completion = await fixture.handle();

      expect(completion.disposition, CreateRoutineRuntimeDisposition.rejected);
      expect(completion.result.errorMessage, contains('could not be settled'));
      expect(fixture.compensationTokens, ['routine-1']);
    });

    test('compensates a mismatched final settlement receipt', () async {
      final fixture = _Fixture(owner)..poisonSuccessIdentity = true;

      final completion = await fixture.handle();

      expect(
        completion.disposition,
        CreateRoutineRuntimeDisposition.boundaryMismatch,
      );
      expect(
        completion.result.errorMessage,
        contains('mismatched settlement receipt'),
      );
      expect(fixture.compensationTokens, ['routine-1']);
    });

    test('compensates an unconfirmed prepared-receipt release', () async {
      final fixture = _Fixture(owner)
        ..releaseDisposition =
            CreateRoutineSuccessReleaseDisposition.effectUncertain;

      final completion = await fixture.handle();

      expect(completion.disposition, CreateRoutineRuntimeDisposition.rejected);
      expect(
        completion.result.errorMessage,
        'Routine creation receipt settlement failed.',
      );
      expect(fixture.releaseIdentity, fixture.successIdentity);
      expect(fixture.compensationTokens, ['routine-1']);
    });

    test('compensates when prepared-receipt release throws', () async {
      final fixture = _Fixture(owner)
        ..releaseError = StateError('release transport failed');

      final completion = await fixture.handle();

      expect(completion.disposition, CreateRoutineRuntimeDisposition.rejected);
      expect(
        completion.result.errorMessage,
        'Routine creation receipt settlement failed.',
      );
      expect(fixture.compensationTokens, ['routine-1']);
    });

    test('compensates a mismatched prepared-receipt release', () async {
      final fixture = _Fixture(owner)..poisonReleaseIdentity = true;

      final completion = await fixture.handle();

      expect(
        completion.disposition,
        CreateRoutineRuntimeDisposition.boundaryMismatch,
      );
      expect(fixture.compensationTokens, ['routine-1']);
    });

    test(
      'reports an uncertain effect when compensation is unconfirmed',
      () async {
        final fixture = _Fixture(owner)
          ..snapshotDisposition = CreateRoutineSnapshotDisposition.rejected
          ..compensationDisposition =
              CreateRoutineCompensationDisposition.effectUncertain;

        final completion = await fixture.handle();

        expect(
          completion.disposition,
          CreateRoutineRuntimeDisposition.effectUncertain,
        );
        expect(
          completion.result.errorMessage,
          contains('may still be persisted'),
        );
        expect(fixture.compensationTokens, ['routine-1']);
      },
    );

    test(
      'captures arguments before an awaited approval can be poisoned',
      () async {
        final gate = Completer<CreateRoutineApprovalAcknowledgement>();
        final arguments = _arguments({
          'metadata': {
            'labels': ['safe'],
          },
        });
        late Map<String, dynamic> captured;
        late CreateRoutineRuntimeIdentity identity;
        final fixture = _Fixture(owner)
          ..approvalOverride = (receivedIdentity, request) {
            identity = receivedIdentity;
            captured = request.toolRequest.arguments;
            return gate.future;
          };

        final pending = fixture.handle(arguments: arguments);
        arguments['name'] = 'Poisoned';
        ((arguments['metadata'] as Map)['labels'] as List).add('poisoned');
        gate.complete(
          CreateRoutineApprovalAcknowledgement(
            identity: identity,
            disposition: CreateRoutineApprovalDisposition.rejected,
          ),
        );
        await pending;

        expect(captured['name'], 'Alert review');
        expect(captured['metadata'], {
          'labels': ['safe'],
        });
      },
    );
  });
}

typedef _ApprovalOverride =
    Future<CreateRoutineApprovalAcknowledgement> Function(
      CreateRoutineRuntimeIdentity identity,
      RoutineCreationApprovalRequest request,
    );

final class _Fixture {
  _Fixture(this.owner) {
    adapter = CreateRoutineToolRuntimeAdapter(
      requestApproval: (identity, request) {
        events.add('approval');
        identities.add(identity);
        final override = approvalOverride;
        if (override != null) return override(identity, request);
        return Future.value(
          CreateRoutineApprovalAcknowledgement(
            identity: identity,
            disposition: approvalDisposition,
          ),
        );
      },
      acknowledgeOwner: (identity) {
        events.add('owner');
        identities.add(identity);
        final disposition = ownerDispositions.isEmpty
            ? CreateRoutineOwnerDisposition.current
            : ownerDispositions.removeAt(0);
        return switch (disposition) {
          CreateRoutineOwnerDisposition.current =>
            CreateRoutineOwnerAcknowledgement.current(identity: identity),
          CreateRoutineOwnerDisposition.ownerExpired =>
            CreateRoutineOwnerAcknowledgement.ownerExpired(identity: identity),
          CreateRoutineOwnerDisposition.effectUncertain =>
            CreateRoutineOwnerAcknowledgement.effectUncertain(
              identity: identity,
            ),
        };
      },
      create: (identity, request) async {
        events.add('store');
        identities.add(identity);
        storeRequest = request;
        final acknowledgementIdentity = poisonStoreIdentity
            ? _poisoned(identity)
            : identity;
        final receipt = CreateRoutineReceiptIdentity(
          runtime: acknowledgementIdentity,
          compensationToken: 'routine-1',
          requestDigest: poisonReceiptRequestDigest
              ? 'poisoned-request'
              : createRoutineRequestDigest(request),
          createdRoutineDigest: createRoutineDigest(_routine()),
        );
        committedReceipt = receipt;
        return switch (storeDisposition) {
          CreateRoutineStoreDisposition.committed =>
            CreateRoutineStoreAcknowledgement.committed(
              identity: acknowledgementIdentity,
              receiptIdentity: receipt,
              createdRoutine: _routine(),
            ),
          CreateRoutineStoreDisposition.rejected =>
            CreateRoutineStoreAcknowledgement.rejected(
              identity: acknowledgementIdentity,
              errorMessage: storeError,
            ),
          CreateRoutineStoreDisposition.ownerExpired =>
            CreateRoutineStoreAcknowledgement.ownerExpired(
              identity: acknowledgementIdentity,
            ),
          CreateRoutineStoreDisposition.effectUncertain =>
            CreateRoutineStoreAcknowledgement.effectUncertain(
              identity: acknowledgementIdentity,
            ),
        };
      },
      captureSnapshot: (identity) {
        events.add('snapshot:${identity.compensationToken}');
        identities.add(identity.runtime);
        final returnedIdentity = poisonSnapshotToken
            ? CreateRoutineReceiptIdentity(
                runtime: identity.runtime,
                compensationToken: 'poisoned',
                requestDigest: identity.requestDigest,
                createdRoutineDigest: identity.createdRoutineDigest,
              )
            : identity;
        return switch (snapshotDisposition) {
          CreateRoutineSnapshotDisposition.captured =>
            CreateRoutineSnapshotAcknowledgement.captured(
              receiptIdentity: returnedIdentity,
              routines: [_routine()],
            ),
          CreateRoutineSnapshotDisposition.rejected =>
            CreateRoutineSnapshotAcknowledgement.rejected(
              receiptIdentity: returnedIdentity,
            ),
          CreateRoutineSnapshotDisposition.ownerExpired =>
            CreateRoutineSnapshotAcknowledgement.ownerExpired(
              receiptIdentity: returnedIdentity,
            ),
          CreateRoutineSnapshotDisposition.effectUncertain =>
            CreateRoutineSnapshotAcknowledgement.effectUncertain(
              receiptIdentity: returnedIdentity,
            ),
        };
      },
      compensate: (identity) async {
        events.add('compensate:${identity.compensationToken}');
        identities.add(identity.runtime);
        compensationTokens.add(identity.compensationToken);
        return CreateRoutineCompensationAcknowledgement(
          receiptIdentity: identity,
          disposition: compensationDisposition,
        );
      },
      recordSuccess: (identity) async {
        events.add('success:${identity.compensationToken}');
        successIdentity = identity;
        if (successError case final error?) throw error;
        return CreateRoutineSuccessAcknowledgement(
          identity: poisonSuccessIdentity
              ? CreateRoutineSuccessIdentity(
                  receiptIdentity: CreateRoutineReceiptIdentity(
                    runtime: _poisoned(identity.runtime),
                    compensationToken: identity.compensationToken,
                    requestDigest: identity.receiptIdentity.requestDigest,
                    createdRoutineDigest:
                        identity.receiptIdentity.createdRoutineDigest,
                  ),
                )
              : identity,
          disposition: successDisposition,
        );
      },
      releaseSuccess: (identity) async {
        releaseIdentity = identity;
        if (releaseError case final error?) throw error;
        return CreateRoutineSuccessReleaseAcknowledgement(
          identity: poisonReleaseIdentity
              ? CreateRoutineSuccessIdentity(
                  receiptIdentity: CreateRoutineReceiptIdentity(
                    runtime: _poisoned(identity.runtime),
                    compensationToken: identity.compensationToken,
                    requestDigest: identity.receiptIdentity.requestDigest,
                    createdRoutineDigest:
                        identity.receiptIdentity.createdRoutineDigest,
                  ),
                )
              : identity,
          disposition: releaseDisposition,
        );
      },
    );
  }

  final ChatTurnOwner owner;
  late final CreateRoutineToolRuntimeAdapter adapter;
  final List<String> events = [];
  final List<CreateRoutineRuntimeIdentity> identities = [];
  final List<CreateRoutineOwnerDisposition> ownerDispositions = [];
  final List<String> compensationTokens = [];

  CreateRoutineApprovalDisposition approvalDisposition =
      CreateRoutineApprovalDisposition.approved;
  CreateRoutineStoreDisposition storeDisposition =
      CreateRoutineStoreDisposition.committed;
  CreateRoutineSnapshotDisposition snapshotDisposition =
      CreateRoutineSnapshotDisposition.captured;
  CreateRoutineCompensationDisposition compensationDisposition =
      CreateRoutineCompensationDisposition.reverted;
  CreateRoutineSuccessDisposition successDisposition =
      CreateRoutineSuccessDisposition.acknowledged;
  CreateRoutineSuccessReleaseDisposition releaseDisposition =
      CreateRoutineSuccessReleaseDisposition.released;
  bool poisonStoreIdentity = false;
  bool poisonReceiptRequestDigest = false;
  bool poisonSnapshotToken = false;
  bool poisonSuccessIdentity = false;
  bool poisonReleaseIdentity = false;
  RoutineStoreCreateRequest? storeRequest;
  String? storeError;
  Object? successError;
  Object? releaseError;
  CreateRoutineSuccessIdentity? successIdentity;
  CreateRoutineSuccessIdentity? releaseIdentity;
  CreateRoutineReceiptIdentity? committedReceipt;
  _ApprovalOverride? approvalOverride;

  Future<CreateRoutineRuntimeCompletion> handle({
    Map<String, dynamic>? arguments,
  }) {
    return adapter.handle(
      owner: owner,
      toolCall: ToolCallInfo(
        id: 'call-create',
        name: 'create_routine',
        arguments: arguments ?? _arguments(),
      ),
    );
  }
}

CreateRoutineRuntimeInput _input(
  ChatTurnOwner owner,
  Map<String, dynamic> arguments,
) {
  return CreateRoutineRuntimeInput(
    owner: owner,
    toolCall: ToolCallInfo(
      id: 'call-create',
      name: 'create_routine',
      arguments: arguments,
    ),
  );
}

CreateRoutineRuntimeIdentity _poisoned(CreateRoutineRuntimeIdentity identity) {
  return _changedIdentity(identity, argumentDigest: 'poisoned');
}

CreateRoutineRuntimeIdentity _changedIdentity(
  CreateRoutineRuntimeIdentity identity, {
  ChatTurnOwner? owner,
  String? toolCallId,
  String? argumentDigest,
}) {
  return CreateRoutineRuntimeIdentity(
    owner: owner ?? identity.owner,
    toolCallId: toolCallId ?? identity.toolCallId,
    toolName: identity.toolName,
    argumentDigest: argumentDigest ?? identity.argumentDigest,
  );
}

Map<String, dynamic> _arguments([Map<String, dynamic> overrides = const {}]) {
  return <String, dynamic>{
    'name': 'Alert review',
    'prompt': 'Inspect alerts',
    ...overrides,
  };
}

Routine _routine() {
  final createdAt = DateTime.utc(2026, 7, 31, 3);
  return Routine(
    id: 'routine-1',
    name: 'Alert review',
    prompt: 'Inspect alerts',
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}
