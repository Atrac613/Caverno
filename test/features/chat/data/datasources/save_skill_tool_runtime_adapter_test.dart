import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/save_skill_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/skill.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/save_skill_tool_handler.dart';
import 'package:test/test.dart';

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 7,
  );

  group('SaveSkillRuntimeInput', () {
    test('freezes strict JSON and canonicalizes the argument digest', () {
      final labels = <Object?>['release'];
      final arguments = <String, dynamic>{
        'name': 'Release Skill',
        'content': '# Steps',
        'metadata': {'labels': labels},
      };
      final input = _input(owner, arguments);
      final reordered = _input(owner, {
        'metadata': {
          'labels': ['release'],
        },
        'content': '# Steps',
        'name': 'Release Skill',
      });

      labels.add('poisoned');
      arguments['name'] = 'Poisoned';

      expect(input.identity, reordered.identity);
      expect(input.arguments['name'], 'Release Skill');
      expect(input.arguments['metadata'], {
        'labels': ['release'],
      });
      expect(() => input.arguments['late'] = true, throwsUnsupportedError);
    });

    test('rejects non-JSON values and ambiguous invocation identity', () {
      for (final invalid in <Object?>[
        <Object?>{'not-json'},
        <Object?, Object?>{1: 'non-string-key'},
        double.nan,
        DateTime.utc(2026),
      ]) {
        expect(
          () => _input(owner, _arguments({'invalid': invalid})),
          throwsArgumentError,
        );
      }
      expect(
        () => SaveSkillRuntimeInput(
          owner: owner,
          toolCall: ToolCallInfo(
            id: ' ',
            name: canonicalSaveSkillToolName,
            arguments: _arguments(),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => SaveSkillRuntimeInput(
          owner: owner,
          toolCall: ToolCallInfo(
            id: 'call-save',
            name: 'save_skill_alias',
            arguments: _arguments(),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('changes digest for arguments but ignores catalog ordering', () {
      expect(
        _input(owner, _arguments()).identity.argumentDigest,
        isNot(
          _input(
            owner,
            _arguments({'content': '# Different'}),
          ).identity.argumentDigest,
        ),
      );
      final first = _skill(id: 'one', name: 'One');
      final second = _skill(id: 'two', name: 'Two');
      expect(
        saveSkillCatalogDigest([first, second]),
        saveSkillCatalogDigest([second, first]),
      );
    });
  });

  group('SaveSkillToolRuntimeAdapter', () {
    test(
      'binds snapshot, approval, write, and success acknowledgement',
      () async {
        final fixture = _Fixture(owner);

        final completion = await fixture.handle();

        expect(completion.disposition, SaveSkillRuntimeDisposition.completed);
        expect(completion.result.isSuccess, isTrue);
        expect(jsonDecode(completion.result.result), {
          'ok': true,
          'action': 'created',
          'id': 'skill-new',
          'name': 'Release Skill',
          'enabled': true,
        });
        expect(fixture.events, [
          'snapshot',
          'approval',
          'owner',
          'owner',
          'snapshot',
          'write',
          'owner',
          'owner',
          'success',
        ]);
        expect(fixture.runtimeIdentities, everyElement(completion.identity));
        expect(
          fixture.catalogIdentities,
          everyElement(fixture.catalogIdentities.first),
        );
        expect(
          fixture.mutationIdentities,
          everyElement(fixture.mutationIdentities.first),
        );
        expect(fixture.writeRequest!.existingId, isNull);
        expect(fixture.writeRequest!.markdown, contains('Release Skill'));
        expect(
          fixture.successIdentity!.savedSkillDigest,
          saveSkillDigest(fixture.savedSkill),
        );
      },
    );

    test('does not reuse a poisoned approval receipt', () async {
      final fixture = _Fixture(owner)..poisonApprovalIdentity = true;

      final completion = await fixture.handle();

      expect(
        completion.disposition,
        SaveSkillRuntimeDisposition.boundaryMismatch,
      );
      expect(completion.result.isSuccess, isFalse);
      expect(fixture.events, ['snapshot', 'approval', 'owner']);
      expect(fixture.writeRequest, isNull);
    });

    test('expires an approval when the owner retires before write', () async {
      final fixture = _Fixture(owner)
        ..ownerDispositions.addAll([
          SaveSkillOwnerDisposition.current,
          SaveSkillOwnerDisposition.ownerExpired,
        ]);

      final completion = await fixture.handle();

      expect(completion.disposition, SaveSkillRuntimeDisposition.ownerExpired);
      expect(
        completion.result.errorMessage,
        'The approval turn expired before execution',
      );
      expect(fixture.events, ['snapshot', 'approval', 'owner', 'owner']);
      expect(fixture.writeRequest, isNull);
    });

    test('invalidates approval when the catalog snapshot changes', () async {
      final fixture = _Fixture(owner)..changeCatalogOnSecondSnapshot = true;

      final completion = await fixture.handle();

      expect(completion.disposition, SaveSkillRuntimeDisposition.rejected);
      expect(
        completion.result.errorMessage,
        'The approval turn expired before execution',
      );
      expect(fixture.events, [
        'snapshot',
        'approval',
        'owner',
        'owner',
        'snapshot',
      ]);
      expect(fixture.writeRequest, isNull);
    });

    test('compensates with the exact token after owner retirement', () async {
      final fixture = _Fixture(owner)
        ..ownerDispositions.addAll([
          SaveSkillOwnerDisposition.current,
          SaveSkillOwnerDisposition.current,
          SaveSkillOwnerDisposition.ownerExpired,
        ]);

      final completion = await fixture.handle();

      expect(completion.disposition, SaveSkillRuntimeDisposition.ownerExpired);
      expect(completion.result.isSuccess, isFalse);
      expect(fixture.compensationTokens, ['skill-new']);
      expect(fixture.events, [
        'snapshot',
        'approval',
        'owner',
        'owner',
        'snapshot',
        'write',
        'owner',
        'compensate',
      ]);
      expect(fixture.successIdentity, isNull);
    });

    test('keeps retained compensation explicitly uncertain', () async {
      final fixture = _Fixture(owner)
        ..ownerDispositions.addAll([
          SaveSkillOwnerDisposition.current,
          SaveSkillOwnerDisposition.current,
          SaveSkillOwnerDisposition.ownerExpired,
        ])
        ..compensationDisposition = SaveSkillCompensationDisposition.retained;

      final completion = await fixture.handle();

      expect(
        completion.disposition,
        SaveSkillRuntimeDisposition.effectUncertain,
      );
      expect(
        completion.result.errorMessage,
        contains('inspect the skill catalog'),
      );
      expect(fixture.compensationTokens, ['skill-new']);
    });

    test('contains a mismatched write receipt as uncertain', () async {
      final fixture = _Fixture(owner)..poisonMutationKind = 'argument';

      final completion = await fixture.handle();

      expect(
        completion.disposition,
        SaveSkillRuntimeDisposition.boundaryMismatch,
      );
      expect(completion.result.isSuccess, isFalse);
      expect(
        completion.result.errorMessage,
        contains('inspect the skill catalog'),
      );
      expect(fixture.successIdentity, isNull);
    });

    test(
      'rejects owner, call, catalog, and write digest token poison',
      () async {
        for (final kind in ['owner', 'call', 'argument', 'catalog', 'write']) {
          final fixture = _Fixture(owner)..poisonMutationKind = kind;

          final completion = await fixture.handle();

          expect(
            completion.disposition,
            SaveSkillRuntimeDisposition.boundaryMismatch,
            reason: kind,
          );
          expect(completion.result.isSuccess, isFalse, reason: kind);
          expect(fixture.successIdentity, isNull, reason: kind);
        }
      },
    );

    test('compensates stale owner after a confirmed write', () async {
      final fixture = _Fixture(owner)
        ..ownerDispositions.addAll([
          SaveSkillOwnerDisposition.current,
          SaveSkillOwnerDisposition.current,
          SaveSkillOwnerDisposition.current,
          SaveSkillOwnerDisposition.ownerExpired,
        ]);

      final completion = await fixture.handle();

      expect(completion.disposition, SaveSkillRuntimeDisposition.ownerExpired);
      expect(completion.result.isSuccess, isFalse);
      expect(
        completion.result.errorMessage,
        'The approval turn expired before execution',
      );
      expect(fixture.compensationTokens, ['skill-new']);
      expect(fixture.successIdentity, isNull);
    });

    test('contains a mismatched success receipt after persistence', () async {
      final fixture = _Fixture(owner)..poisonSuccessIdentity = true;

      final completion = await fixture.handle();

      expect(
        completion.disposition,
        SaveSkillRuntimeDisposition.boundaryMismatch,
      );
      expect(completion.result.isSuccess, isFalse);
      expect(
        completion.result.errorMessage,
        contains('inspect the skill catalog'),
      );
      expect(fixture.successIdentity, isNotNull);
      expect(fixture.compensationTokens, ['skill-new']);
    });

    test('compensates uncertain and throwing success settlement', () async {
      final fixtures = [
        _Fixture(owner)
          ..successDisposition = SaveSkillSuccessDisposition.effectUncertain,
        _Fixture(owner)..throwSuccess = true,
      ];

      for (final fixture in fixtures) {
        final completion = await fixture.handle();

        expect(
          completion.disposition,
          SaveSkillRuntimeDisposition.effectUncertain,
        );
        expect(completion.result.isSuccess, isFalse);
        expect(fixture.compensationTokens, ['skill-new']);
        expect(fixture.events.sublist(fixture.events.length - 3), [
          'success',
          'reconcile',
          'compensate',
        ]);
      }
    });

    test(
      'accepts a final success that reconciles after callback poison',
      () async {
        final fixture = _Fixture(owner)
          ..throwSuccess = true
          ..reconciliationDisposition =
              SaveSkillSuccessDisposition.acknowledged;

        final completion = await fixture.handle();

        expect(completion.disposition, SaveSkillRuntimeDisposition.completed);
        expect(completion.result.isSuccess, isTrue);
        expect(fixture.compensationTokens, isEmpty);
        expect(fixture.events.sublist(fixture.events.length - 2), [
          'success',
          'reconcile',
        ]);
      },
    );

    test('compensates explicit final success owner expiry', () async {
      final fixture = _Fixture(owner)
        ..successDisposition = SaveSkillSuccessDisposition.ownerExpired;

      final completion = await fixture.handle();

      expect(completion.disposition, SaveSkillRuntimeDisposition.ownerExpired);
      expect(
        completion.result.errorMessage,
        'The approval turn expired before execution',
      );
      expect(fixture.compensationTokens, ['skill-new']);
      expect(fixture.events.sublist(fixture.events.length - 2), [
        'success',
        'compensate',
      ]);
    });

    test(
      'restores legacy persistence error after safe reconciliation',
      () async {
        final fixture = _Fixture(owner)
          ..writeDisposition =
              SaveSkillWriteDisposition.effectUncertainAfterEffect;

        final completion = await fixture.handle();

        expect(completion.disposition, SaveSkillRuntimeDisposition.rejected);
        expect(
          completion.result.errorMessage,
          'Failed to save skill: Bad state: repository write failed',
        );
        expect(fixture.compensationTokens, ['skill-new']);
      },
    );
  });
}

final class _Fixture {
  _Fixture(this.owner) {
    adapter = SaveSkillToolRuntimeAdapter(
      captureSnapshot: (identity) {
        events.add('snapshot');
        runtimeIdentities.add(identity);
        snapshotCount += 1;
        final skills = changeCatalogOnSecondSnapshot && snapshotCount > 1
            ? [_skill(id: 'changed', name: 'Changed')]
            : catalog;
        return SaveSkillSnapshotAcknowledgement.captured(
          identity: identity,
          skills: skills,
        );
      },
      requestFreshManualApproval: (request) async {
        events.add('approval');
        catalogIdentities.add(request.identity);
        return SaveSkillApprovalAcknowledgement(
          identity: poisonApprovalIdentity
              ? _poisonCatalog(request.identity)
              : request.identity,
          disposition: approvalDisposition,
        );
      },
      acknowledgeOwner: (identity) {
        events.add('owner');
        runtimeIdentities.add(identity);
        final disposition = ownerDispositions.isEmpty
            ? SaveSkillOwnerDisposition.current
            : ownerDispositions.removeAt(0);
        return SaveSkillOwnerAcknowledgement(
          identity: identity,
          disposition: disposition,
        );
      },
      write: (request) async {
        events.add('write');
        mutationIdentities.add(request.identity);
        writeRequest = request.request;
        final identity = poisonMutationKind == null
            ? request.identity
            : _poisonMutation(request.identity, poisonMutationKind!);
        return switch (writeDisposition) {
          SaveSkillWriteDisposition.committed =>
            SaveSkillWriteAcknowledgement.committed(
              identity: identity,
              skill: savedSkill,
              compensationToken: 'skill-new',
            ),
          SaveSkillWriteDisposition.rejectedBeforeEffect =>
            SaveSkillWriteAcknowledgement.rejectedBeforeEffect(
              identity: identity,
              errorMessage:
                  'Failed to save skill: Bad state: repository write failed',
            ),
          SaveSkillWriteDisposition.ownerExpiredBeforeEffect =>
            SaveSkillWriteAcknowledgement.ownerExpiredBeforeEffect(
              identity: identity,
            ),
          SaveSkillWriteDisposition.ownerExpiredAfterEffect =>
            SaveSkillWriteAcknowledgement.ownerExpiredAfterEffect(
              identity: identity,
              compensationToken: 'skill-new',
            ),
          SaveSkillWriteDisposition.effectUncertainAfterEffect =>
            SaveSkillWriteAcknowledgement.effectUncertainAfterEffect(
              identity: identity,
              compensationToken: 'skill-new',
              errorMessage:
                  'Failed to save skill: Bad state: repository write failed',
            ),
        };
      },
      compensate: (request) async {
        events.add('compensate');
        mutationIdentities.add(request.identity);
        compensationTokens.add(request.compensationToken);
        return SaveSkillCompensationAcknowledgement(
          identity: request.identity,
          compensationToken: request.compensationToken,
          disposition: compensationDisposition,
        );
      },
      recordSuccess: (identity) async {
        events.add('success');
        successIdentity = identity;
        if (throwSuccess) {
          throw StateError('success settlement failed');
        }
        return SaveSkillSuccessAcknowledgement(
          identity: poisonSuccessIdentity
              ? SaveSkillSuccessIdentity(
                  mutation: _poisonMutation(identity.mutation, 'argument'),
                  compensationToken: identity.compensationToken,
                  savedSkillDigest: identity.savedSkillDigest,
                )
              : identity,
          disposition: successDisposition,
        );
      },
      reconcileSuccess: (identity) async {
        events.add('reconcile');
        return SaveSkillSuccessAcknowledgement(
          identity: identity,
          disposition: reconciliationDisposition,
        );
      },
    );
  }

  final ChatTurnOwner owner;
  late final SaveSkillToolRuntimeAdapter adapter;
  final List<String> events = [];
  final List<SaveSkillRuntimeIdentity> runtimeIdentities = [];
  final List<SaveSkillCatalogIdentity> catalogIdentities = [];
  final List<SaveSkillMutationIdentity> mutationIdentities = [];
  final List<SaveSkillOwnerDisposition> ownerDispositions = [];
  final List<String> compensationTokens = [];
  final List<Skill> catalog = [];
  final Skill savedSkill = _skill(id: 'skill-new', name: 'Release Skill');

  SaveSkillApprovalDisposition approvalDisposition =
      SaveSkillApprovalDisposition.approved;
  SaveSkillWriteDisposition writeDisposition =
      SaveSkillWriteDisposition.committed;
  SaveSkillCompensationDisposition compensationDisposition =
      SaveSkillCompensationDisposition.compensated;
  SaveSkillSuccessDisposition successDisposition =
      SaveSkillSuccessDisposition.acknowledged;
  SaveSkillSuccessDisposition reconciliationDisposition =
      SaveSkillSuccessDisposition.effectUncertain;
  bool poisonApprovalIdentity = false;
  bool poisonSuccessIdentity = false;
  bool throwSuccess = false;
  String? poisonMutationKind;
  bool changeCatalogOnSecondSnapshot = false;
  int snapshotCount = 0;
  SkillStoreWriteRequest? writeRequest;
  SaveSkillSuccessIdentity? successIdentity;

  Future<SaveSkillRuntimeCompletion> handle() => adapter.handle(
    owner: owner,
    toolCall: ToolCallInfo(
      id: 'call-save',
      name: canonicalSaveSkillToolName,
      arguments: _arguments(),
    ),
  );
}

SaveSkillRuntimeInput _input(
  ChatTurnOwner owner,
  Map<String, dynamic> arguments,
) => SaveSkillRuntimeInput(
  owner: owner,
  toolCall: ToolCallInfo(
    id: 'call-save',
    name: canonicalSaveSkillToolName,
    arguments: arguments,
  ),
);

Map<String, dynamic> _arguments([Map<String, dynamic>? overrides]) => {
  'name': 'Release Skill',
  'description': 'Ship an app',
  'when_to_use': 'Before release',
  'content': '# Steps\n\nArchive.',
  ...?overrides,
};

SaveSkillCatalogIdentity _poisonCatalog(SaveSkillCatalogIdentity identity) {
  return SaveSkillCatalogIdentity(
    runtime: SaveSkillRuntimeIdentity(
      owner: identity.runtime.owner,
      toolCallId: identity.runtime.toolCallId,
      toolName: identity.runtime.toolName,
      argumentDigest: 'poisoned',
    ),
    catalogDigest: identity.catalogDigest,
  );
}

SaveSkillMutationIdentity _poisonMutation(
  SaveSkillMutationIdentity identity,
  String kind,
) {
  final runtime = identity.catalog.runtime;
  final poisonedOwner = ChatTurnOwner(
    conversationId: '${runtime.owner.conversationId}-poisoned',
    interactionGeneration: runtime.owner.interactionGeneration,
  );
  final poisonedRuntime = SaveSkillRuntimeIdentity(
    owner: kind == 'owner' ? poisonedOwner : runtime.owner,
    toolCallId: kind == 'call'
        ? '${runtime.toolCallId}-poisoned'
        : runtime.toolCallId,
    toolName: runtime.toolName,
    argumentDigest: kind == 'argument'
        ? '${runtime.argumentDigest}-poisoned'
        : runtime.argumentDigest,
  );
  return SaveSkillMutationIdentity(
    catalog: SaveSkillCatalogIdentity(
      runtime: poisonedRuntime,
      catalogDigest: kind == 'catalog'
          ? '${identity.catalog.catalogDigest}-poisoned'
          : identity.catalog.catalogDigest,
    ),
    writeDigest: kind == 'write'
        ? '${identity.writeDigest}-poisoned'
        : identity.writeDigest,
  );
}

Skill _skill({required String id, required String name}) => Skill(
  id: id,
  name: name,
  content: '# Skill',
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 2),
);
