import 'dart:async';
import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/skill.dart';
import 'package:caverno/features/chat/domain/services/save_skill_tool_handler.dart';
import 'package:caverno/features/chat/domain/services/skill_markdown_parser.dart';
import 'package:test/test.dart';

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 4,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'conversation-b',
    interactionGeneration: 4,
  );
  final ownerANextGeneration = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 5,
  );

  group('SaveSkillToolRequest', () {
    test('recursively freezes nested arguments and normalizes fields', () {
      final labels = <Object?>['release'];
      final metadata = <String, dynamic>{
        'labels': labels,
        'flags': <Object?>['safe'],
        'owners': <String, Object?>{'primary': 'owner-a'},
      };
      final arguments = <String, dynamic>{
        'name': '  Release Skill  ',
        'description': '  Ship an app  ',
        'when_to_use': '  Before release  ',
        'content': '  # Steps\n\nArchive.  ',
        'reason': '  Save the verified workflow.  ',
        'allow_duplicate': true,
        'metadata': metadata,
      };
      final request = SaveSkillToolRequest(
        owner: ownerA,
        toolCallId: 'call-a',
        toolName: 'save_skill',
        arguments: arguments,
      );

      labels.add('poisoned');
      (metadata['flags'] as List<Object?>).add('poisoned');
      (metadata['owners'] as Map)['primary'] = 'visible';
      metadata['labels'] = ['replaced'];
      arguments['name'] = 'Poisoned';

      expect(request.toolName, 'save_skill');
      expect(request.name, 'Release Skill');
      expect(request.description, 'Ship an app');
      expect(request.whenToUse, 'Before release');
      expect(request.body, '# Steps\n\nArchive.');
      expect(request.reason, 'Save the verified workflow.');
      expect(request.allowDuplicate, isTrue);
      expect(request.arguments['metadata'], {
        'labels': ['release'],
        'flags': ['safe'],
        'owners': {'primary': 'owner-a'},
      });
      expect(
        () => (request.arguments['metadata'] as Map)['new'] = true,
        throwsUnsupportedError,
      );
      expect(
        () => ((request.arguments['metadata'] as Map)['labels'] as List).add(
          'late',
        ),
        throwsUnsupportedError,
      );
      expect(
        () => ((request.arguments['metadata'] as Map)['flags'] as List).add(
          'late',
        ),
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((request.arguments['metadata'] as Map)['owners']
                    as Map)['primary'] =
                'late',
        throwsUnsupportedError,
      );
      expect(
        () => _request(
          ownerA,
          arguments: {
            'name': 'Release Skill',
            'content': '# Steps',
            'metadata': <Object?, Object?>{7: 'owner-a'},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _request(
          ownerA,
          arguments: {
            'name': 'Release Skill',
            'content': '# Steps',
            'metadata': <Object?>{'not-json'},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _request(
          ownerA,
          arguments: {
            'name': 'Release Skill',
            'content': '# Steps',
            'metadata': double.infinity,
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _request(
          ownerA,
          arguments: {
            'name': 'Release Skill',
            'content': '# Steps',
            'metadata': DateTime.utc(2026),
          },
        ),
        throwsArgumentError,
      );
    });

    test('freezes the owner skill snapshot list', () {
      final source = <Skill>[_skill(id: 'one', name: 'One')];
      final snapshot = SkillStoreSnapshot(
        identity: _identity(ownerA),
        skills: source,
      );

      source.add(_skill(id: 'two', name: 'Two'));

      expect(snapshot.skills.map((skill) => skill.id), ['one']);
      expect(
        () => snapshot.skills.add(_skill(id: 'late', name: 'Late')),
        throwsUnsupportedError,
      );
    });
  });

  group('SaveSkillToolHandler validation and creation', () {
    test('preserves missing-field validation ordering and payloads', () async {
      final cases = [
        (arguments: <String, dynamic>{}, error: 'name is required'),
        (
          arguments: <String, dynamic>{'name': '   ', 'content': 'body'},
          error: 'name is required',
        ),
        (
          arguments: <String, dynamic>{'name': 'Release Skill'},
          error: 'content (the skill body) is required',
        ),
        (
          arguments: <String, dynamic>{
            'name': 'Release Skill',
            'content': '   ',
          },
          error: 'content (the skill body) is required',
        ),
      ];

      for (final testCase in cases) {
        final fixture = _fixture();
        final result = await fixture.handler.handle(
          _request(ownerA, arguments: testCase.arguments),
        );

        expect(result.toolName, 'save_skill');
        expect(result.result, isEmpty);
        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, testCase.error);
        expect(fixture.events, isEmpty);
      }
    });

    test(
      'materializes string fields before validation and duplicate flag later',
      () async {
        final malformedStringCases = <Map<String, dynamic>>[
          {'name': '', 'description': 7},
          {'name': '', 'description': '', 'when_to_use': false},
          {
            'name': '',
            'description': '',
            'when_to_use': '',
            'content': <String>[],
          },
        ];

        for (final arguments in malformedStringCases) {
          final fixture = _fixture();

          await expectLater(
            fixture.handler.handle(_request(ownerA, arguments: arguments)),
            throwsA(isA<TypeError>()),
          );
          expect(fixture.events, isEmpty);
        }

        final duplicateFlagFixture = _fixture();
        final result = await duplicateFlagFixture.handler.handle(
          _request(
            ownerA,
            arguments: const {'name': '', 'allow_duplicate': 'invalid'},
          ),
        );

        expect(result.errorMessage, 'name is required');
        expect(duplicateFlagFixture.events, isEmpty);
      },
    );

    test(
      'creates a new skill with exact preview, fields, and payload',
      () async {
        final fixture = _fixture();
        final saved = _skill(
          id: 'skill-new',
          name: 'Release Skill',
          description: 'Ship an app',
          whenToUse: 'Before release',
          content: '# Steps\n\nArchive.',
        );
        fixture.store.writeResults[ownerA] = SkillStoreWriteResult.committed(
          identity: _identity(ownerA),
          skill: saved,
        );
        final request = _request(
          ownerA,
          arguments: const {
            'name': '  Release Skill  ',
            'description': '  Ship an app  ',
            'when_to_use': '  Before release  ',
            'content': '  # Steps\n\nArchive.  ',
            'reason': '  Save the verified workflow.  ',
          },
        );
        final expectedMarkdown = SkillMarkdownParser.composeMarkdown(
          name: 'Release Skill',
          description: 'Ship an app',
          whenToUse: 'Before release',
          body: '# Steps\n\nArchive.',
        );

        final result = await fixture.handler.handle(request);

        expect(
          result.result,
          '{"ok":true,"action":"created","id":"skill-new",'
          '"name":"Release Skill","enabled":true}',
        );
        expect(result.isSuccess, isTrue);
        final approval = fixture.approval.requests.single.request;
        expect(approval.operation, 'Save Skill');
        expect(approval.path, 'Release Skill');
        expect(approval.preview, expectedMarkdown);
        expect(approval.reason, 'Save the verified workflow.');
        expect(approval.existingSkill, isNull);
        final write = fixture.store.writes.single;
        expect(write.owner, ownerA);
        expect(write.request.existingId, isNull);
        expect(write.request.markdown, expectedMarkdown);
        expect(fixture.store.recordedOwners, [ownerA]);
        expect(fixture.events, [
          'store.snapshot:conversation-a:4',
          'approval.request:conversation-a:4',
          'approval.expired:conversation-a:4',
          'store.write:conversation-a:4',
          'store.record:conversation-a:4',
        ]);
      },
    );

    test('always requests a fresh manual approval', () async {
      final fixture = _fixture();
      fixture.store.writeResults[ownerA] = SkillStoreWriteResult.committed(
        identity: _identity(ownerA),
        skill: _skill(id: 'saved', name: 'Release Skill'),
      );

      await fixture.handler.handle(_request(ownerA));
      await fixture.handler.handle(_request(ownerA));

      expect(fixture.approval.requests, hasLength(2));
      expect(fixture.store.writes, hasLength(2));
    });
  });

  group('SaveSkillToolHandler duplicates and replacement', () {
    test('updates an exact-name skill with a unified diff', () async {
      final existing = _skill(
        id: 'existing-id',
        name: 'iOS Release',
        description: 'Ship an iOS build',
        content: '# Steps\n\n1. Archive.',
        enabled: false,
      );
      final fixture = _fixture(skills: [existing]);
      fixture.store.writeResults[ownerA] = SkillStoreWriteResult.committed(
        identity: _identity(ownerA),
        skill: existing.copyWith(
          name: 'ios release',
          description: '',
          content: '# Steps\n\n1. Archive.\n2. Upload.',
        ),
      );

      final result = await fixture.handler.handle(
        _request(
          ownerA,
          arguments: const {
            'name': '  ios release  ',
            'content': '# Steps\n\n1. Archive.\n2. Upload.',
          },
        ),
      );

      final approval = fixture.approval.requests.single.request;
      expect(approval.operation, 'Update Skill');
      expect(approval.path, 'ios release');
      expect(approval.existingSkill, same(existing));
      expect(approval.preview, contains('--- skill: ios release'));
      expect(approval.preview, contains('+++ skill: ios release'));
      expect(approval.preview, contains('+2. Upload.'));
      expect(fixture.store.writes.single.request.existingId, 'existing-id');
      expect(
        result.result,
        '{"ok":true,"action":"updated","id":"existing-id",'
        '"name":"ios release","enabled":false}',
      );
    });

    test('reports a near-duplicate with the exact warning payload', () async {
      final existing = _skill(
        id: 'existing-id',
        name: 'iOS Release',
        description: 'Ship builds',
        content: '# Existing',
      );
      final fixture = _fixture(skills: [existing]);

      final result = await fixture.handler.handle(
        _request(
          ownerA,
          arguments: const {
            'name': 'iOS Release Helper',
            'description': 'Automate releases',
            'content': '# New',
          },
        ),
      );

      expect(
        result.result,
        '{"saved":false,"action":"similar_skill_found","matches":['
        '{"id":"existing-id","name":"iOS Release","score":0.85,'
        '"description":"Ship builds"}],"message":"A similar skill already '
        'exists. To improve it, call save_skill again using that skill\'s '
        'exact name (this updates it in place with a diff for approval). To '
        'create a separate skill anyway, call save_skill again with '
        'allow_duplicate set to true."}',
      );
      expect(result.isSuccess, isTrue);
      expect(fixture.approval.requests, isEmpty);
      expect(fixture.store.writes, isEmpty);
      expect(fixture.store.recordedOwners, isEmpty);
    });

    test('allow_duplicate creates a different-named similar skill', () async {
      final existing = _skill(
        id: 'existing-id',
        name: 'iOS Release',
        content: '# Existing',
      );
      final fixture = _fixture(skills: [existing]);
      fixture.store.writeResults[ownerA] = SkillStoreWriteResult.committed(
        identity: _identity(ownerA),
        skill: _skill(id: 'duplicate-id', name: 'iOS Release Helper'),
      );

      final result = await fixture.handler.handle(
        _request(
          ownerA,
          arguments: const {
            'name': 'iOS Release Helper',
            'content': '# Separate workflow',
            'allow_duplicate': true,
          },
        ),
      );

      expect(fixture.approval.requests.single.request.operation, 'Save Skill');
      expect(fixture.store.writes.single.request.existingId, isNull);
      expect(jsonDecode(result.result), containsPair('action', 'created'));
    });
  });

  group('SaveSkillToolHandler approval and persistence failures', () {
    test('preserves deny and expiration ordering', () async {
      final deniedFixture = _fixture();
      deniedFixture.approval.decisions[ownerA] = SkillSaveApprovalDecision(
        identity: _identity(ownerA),
        approved: false,
      );

      final denied = await deniedFixture.handler.handle(_request(ownerA));

      expect(denied.result, isEmpty);
      expect(denied.isSuccess, isFalse);
      expect(denied.errorMessage, 'User denied saving the skill');
      expect(deniedFixture.store.writes, isEmpty);

      final expiredFixture = _fixture();
      expiredFixture.approval.decisions[ownerA] = SkillSaveApprovalDecision(
        identity: _identity(ownerA),
        approved: false,
      );
      expiredFixture.approval.acknowledgements[_identity(ownerA)] =
          SkillSaveAcknowledgement.ownerExpired(identity: _identity(ownerA));

      final expired = await expiredFixture.handler.handle(_request(ownerA));
      expect(
        expired.errorMessage,
        'The approval turn expired before execution',
      );
      expect(expiredFixture.store.writes, isEmpty);
    });

    test('treats persistence errors as possible writes', () async {
      for (final error in [
        const FormatException('Invalid skill Markdown'),
        StateError('skill repository unavailable'),
      ]) {
        final fixture = _fixture();
        fixture.store.writeErrors[ownerA] = error;

        final result = await fixture.handler.handle(_request(ownerA));

        expect(result.result, isEmpty);
        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          'The skill may have been saved after its owner expired; inspect the '
          'skill catalog before retrying',
        );
        expect(fixture.store.recordedOwners, isEmpty);
      }
    });

    test('preserves a proven pre-effect persistence error', () async {
      final fixture = _fixture();
      fixture.store.writeResults[ownerA] = SkillStoreWriteResult.rejected(
        identity: _identity(ownerA),
        errorMessage:
            'Failed to save skill: Bad state: repository write failed',
      );

      final result = await fixture.handler.handle(_request(ownerA));

      expect(result.result, isEmpty);
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'Failed to save skill: Bad state: repository write failed',
      );
      expect(fixture.store.recordedOwners, isEmpty);
    });

    test('preserves uncertain write and settlement outcomes', () async {
      final uncertainWriteFixture = _fixture();
      uncertainWriteFixture.store.writeResults[ownerA] =
          SkillStoreWriteResult.effectUncertain(identity: _identity(ownerA));

      final uncertainWrite = await uncertainWriteFixture.handler.handle(
        _request(ownerA),
      );

      expect(
        uncertainWrite.errorMessage,
        'The skill may have been saved after its owner expired; inspect the '
        'skill catalog before retrying',
      );
      expect(uncertainWriteFixture.store.recordedOwners, isEmpty);

      final settlementCases = [
        (
          acknowledgement: SkillSaveAcknowledgement.ownerExpired(
            identity: _identity(ownerA),
          ),
          message: 'The approval turn expired before execution',
        ),
        (
          acknowledgement: SkillSaveAcknowledgement.effectUncertain(
            identity: _identity(ownerA),
          ),
          message:
              'The skill may have been saved after its owner expired; inspect '
              'the skill catalog before retrying',
        ),
      ];
      for (final testCase in settlementCases) {
        final fixture = _fixture();
        fixture.store.recordAcknowledgements[_identity(ownerA)] =
            testCase.acknowledgement;

        final result = await fixture.handler.handle(_request(ownerA));

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, testCase.message);
      }
    });

    test(
      'maps successful-save evidence errors through the same boundary',
      () async {
        final fixture = _fixture();
        fixture.store.recordErrors[ownerA] = StateError(
          'save evidence unavailable',
        );

        final result = await fixture.handler.handle(_request(ownerA));

        expect(
          result.errorMessage,
          'The skill may have been saved after its owner expired; inspect the '
          'skill catalog before retrying',
        );
        expect(fixture.store.writes, hasLength(1));
        expect(fixture.store.recordedOwners, [ownerA]);
      },
    );
  });

  group('SaveSkillToolHandler tool identity', () {
    test('requires a non-empty call ID and canonical tool name', () {
      expect(() => _request(ownerA, toolCallId: ''), throwsArgumentError);
      expect(() => _request(ownerA, toolCallId: '   '), throwsArgumentError);
      expect(
        () => _request(ownerA, toolName: 'save_skill_alias'),
        throwsArgumentError,
      );
    });

    test('preserves the exact invocation identity', () {
      final request = _request(ownerA, toolCallId: ' call-a ');

      expect(request.identity.owner, ownerA);
      expect(request.identity.toolCallId, ' call-a ');
      expect(request.identity.toolName, canonicalSaveSkillToolName);
    });
  });

  group('SaveSkillToolHandler owner poison', () {
    test('rejects same-owner call poisoning before persistence', () async {
      final otherCall = _identity(ownerA, toolCallId: 'call-b');

      final snapshotFixture = _fixture();
      snapshotFixture.store.snapshots[ownerA] = SkillStoreSnapshot(
        identity: otherCall,
        skills: const [],
      );
      await expectLater(
        snapshotFixture.handler.handle(_request(ownerA)),
        throwsA(isA<StateError>()),
      );

      final approvalFixture = _fixture();
      approvalFixture.approval.decisions[ownerA] = SkillSaveApprovalDecision(
        identity: otherCall,
        approved: true,
      );
      await expectLater(
        approvalFixture.handler.handle(_request(ownerA)),
        throwsA(isA<StateError>()),
      );

      final acknowledgementFixture = _fixture();
      acknowledgementFixture.approval.acknowledgements[_identity(ownerA)] =
          SkillSaveAcknowledgement.acknowledged(identity: otherCall);
      await expectLater(
        acknowledgementFixture.handler.handle(_request(ownerA)),
        throwsA(isA<StateError>()),
      );

      expect(snapshotFixture.store.writes, isEmpty);
      expect(approvalFixture.store.writes, isEmpty);
      expect(acknowledgementFixture.store.writes, isEmpty);
    });

    test('contains same-owner call poisoning after persistence', () async {
      const uncertainMessage =
          'The skill may have been saved after its owner expired; inspect the '
          'skill catalog before retrying';
      final otherCall = _identity(ownerA, toolCallId: 'call-b');

      final writeFixture = _fixture();
      writeFixture.store.writeResults[ownerA] = SkillStoreWriteResult.committed(
        identity: otherCall,
        skill: _skill(id: 'other-call', name: 'Release Skill'),
      );
      expect(
        (await writeFixture.handler.handle(_request(ownerA))).errorMessage,
        uncertainMessage,
      );

      final evidenceFixture = _fixture();
      evidenceFixture.store.recordAcknowledgements[_identity(ownerA)] =
          SkillSaveAcknowledgement.acknowledged(identity: otherCall);
      expect(
        (await evidenceFixture.handler.handle(_request(ownerA))).errorMessage,
        uncertainMessage,
      );
    });

    test('rejects mismatched store snapshots before approval', () async {
      for (final poisonedOwner in [ownerB, ownerANextGeneration]) {
        final fixture = _fixture();
        fixture.store.snapshots[ownerA] = SkillStoreSnapshot(
          identity: _identity(poisonedOwner),
          skills: const [],
        );

        await expectLater(
          fixture.handler.handle(_request(ownerA)),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Skill store snapshot identity mismatch.',
            ),
          ),
        );

        expect(fixture.approval.requests, isEmpty);
        expect(fixture.store.writes, isEmpty);
      }
    });

    test(
      'rejects another owner approval response without persisting',
      () async {
        for (final poisonedOwner in [ownerB, ownerANextGeneration]) {
          final fixture = _fixture();
          fixture.approval.decisions[ownerA] = SkillSaveApprovalDecision(
            identity: _identity(poisonedOwner),
            approved: true,
          );

          await expectLater(
            fixture.handler.handle(_request(ownerA)),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                'Skill save approval identity mismatch.',
              ),
            ),
          );

          expect(fixture.approval.expirationOwners, isEmpty);
          expect(fixture.store.writes, isEmpty);
        }
      },
    );

    test(
      'contains a mismatched store completion and never records success',
      () async {
        final fixture = _fixture();
        fixture.store.writeResults[ownerA] = SkillStoreWriteResult.committed(
          identity: _identity(ownerB),
          skill: _skill(id: 'owner-b-skill', name: 'Owner B'),
        );

        final result = await fixture.handler.handle(_request(ownerA));

        expect(
          result.errorMessage,
          'The skill may have been saved after its owner expired; inspect the '
          'skill catalog before retrying',
        );
        expect(fixture.store.recordedOwners, isEmpty);
      },
    );

    test(
      'contains owner expiration during persistence after compensation',
      () async {
        for (final expiredWriteDisposition
            in SkillStoreExpiredWriteDisposition.values) {
          final fixture = _fixture();
          final pendingWrite = Completer<SkillStoreWriteResult>();
          final writeStarted = Completer<void>();
          fixture.store.pendingWrites[ownerA] = pendingWrite;
          fixture.store.writeStarted[ownerA] = writeStarted;

          final pendingResult = fixture.handler.handle(_request(ownerA));
          await writeStarted.future;
          pendingWrite.complete(
            SkillStoreWriteResult.ownerExpired(
              identity: _identity(ownerA),
              expiredWriteDisposition: expiredWriteDisposition,
            ),
          );

          final result = await pendingResult;

          expect(result.result, isEmpty);
          expect(result.isSuccess, isFalse);
          expect(result.errorMessage, switch (expiredWriteDisposition) {
            SkillStoreExpiredWriteDisposition.notCommitted ||
            SkillStoreExpiredWriteDisposition.compensated =>
              'The approval turn expired before execution',
            SkillStoreExpiredWriteDisposition.retained ||
            SkillStoreExpiredWriteDisposition.uncertain =>
              'The skill may have been saved after its owner expired; '
                  'inspect the skill catalog before retrying',
          });
          expect(fixture.store.writes, hasLength(1));
          expect(fixture.store.recordedOwners, isEmpty);
          expect(
            fixture.events,
            isNot(contains('store.record:conversation-a:4')),
          );
        }
      },
    );

    test(
      'uses only the owner catalog, approval, and persistence state',
      () async {
        final ownerBSkill = _skill(
          id: 'owner-b-existing',
          name: 'Release Skill',
        );
        final fixture = _fixture();
        fixture.store.snapshots
          ..[ownerA] = SkillStoreSnapshot(
            identity: _identity(ownerA),
            skills: const [],
          )
          ..[ownerB] = SkillStoreSnapshot(
            identity: _identity(ownerB),
            skills: [ownerBSkill],
          )
          ..[ownerANextGeneration] = SkillStoreSnapshot(
            identity: _identity(ownerANextGeneration),
            skills: [ownerBSkill],
          );
        fixture.approval.decisions
          ..[ownerA] = SkillSaveApprovalDecision(
            identity: _identity(ownerA),
            approved: true,
          )
          ..[ownerB] = SkillSaveApprovalDecision(
            identity: _identity(ownerB),
            approved: false,
          )
          ..[ownerANextGeneration] = SkillSaveApprovalDecision(
            identity: _identity(ownerANextGeneration),
            approved: false,
          );
        fixture.store.writeResults[ownerA] = SkillStoreWriteResult.committed(
          identity: _identity(ownerA),
          skill: _skill(id: 'owner-a-new', name: 'Release Skill'),
        );

        final result = await fixture.handler.handle(_request(ownerA));

        expect(jsonDecode(result.result), containsPair('action', 'created'));
        expect(fixture.approval.requests.single.owner, ownerA);
        expect(fixture.store.writes.single.owner, ownerA);
        expect(fixture.store.snapshotOwners.toSet(), {ownerA});
        expect(fixture.store.owners.toSet(), {ownerA});
        expect(fixture.approval.owners.toSet(), {ownerA});
      },
    );
  });
}

SaveSkillToolRequest _request(
  ChatTurnOwner owner, {
  String toolCallId = 'call-a',
  String toolName = 'save_skill',
  Map<String, dynamic> arguments = const {
    'name': 'Release Skill',
    'content': '# Steps\n\nArchive.',
  },
}) {
  return SaveSkillToolRequest(
    owner: owner,
    toolCallId: toolCallId,
    toolName: toolName,
    arguments: arguments,
  );
}

SaveSkillOperationIdentity _identity(
  ChatTurnOwner owner, {
  String toolCallId = 'call-a',
  String toolName = 'save_skill',
}) {
  return SaveSkillOperationIdentity(
    owner: owner,
    toolCallId: toolCallId,
    toolName: toolName,
  );
}

Skill _skill({
  required String id,
  required String name,
  String description = '',
  String whenToUse = '',
  String content = '# Skill',
  bool enabled = true,
}) {
  return Skill(
    id: id,
    name: name,
    description: description,
    whenToUse: whenToUse,
    content: content,
    enabled: enabled,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 2),
  );
}

typedef _Fixture = ({
  SaveSkillToolHandler handler,
  _StorePort store,
  _ApprovalPort approval,
  List<String> events,
});

_Fixture _fixture({List<Skill> skills = const []}) {
  final events = <String>[];
  final store = _StorePort(events, defaultSkills: skills);
  final approval = _ApprovalPort(events);
  return (
    handler: SaveSkillToolHandler(storePort: store, approvalPort: approval),
    store: store,
    approval: approval,
    events: events,
  );
}

typedef _WriteUse = ({
  ChatTurnOwner owner,
  SaveSkillOperationIdentity identity,
  SkillStoreWriteRequest request,
});

final class _StorePort implements SkillStorePort {
  _StorePort(this.events, {required this.defaultSkills});

  final List<String> events;
  final List<Skill> defaultSkills;
  final Map<ChatTurnOwner, SkillStoreSnapshot> snapshots = {};
  final Map<SaveSkillOperationIdentity, SkillStoreSnapshot> identitySnapshots =
      {};
  final Map<ChatTurnOwner, SkillStoreWriteResult> writeResults = {};
  final Map<SaveSkillOperationIdentity, SkillStoreWriteResult>
  identityWriteResults = {};
  final Map<ChatTurnOwner, Completer<SkillStoreWriteResult>> pendingWrites = {};
  final Map<ChatTurnOwner, Completer<void>> writeStarted = {};
  final Map<ChatTurnOwner, Object> writeErrors = {};
  final Map<ChatTurnOwner, Object> recordErrors = {};
  final Map<SaveSkillOperationIdentity, SkillSaveAcknowledgement>
  recordAcknowledgements = {};
  final List<ChatTurnOwner> snapshotOwners = [];
  final List<_WriteUse> writes = [];
  final List<ChatTurnOwner> recordedOwners = [];

  List<ChatTurnOwner> get owners => [
    ...snapshotOwners,
    ...writes.map((write) => write.owner),
    ...recordedOwners,
  ];

  @override
  SkillStoreSnapshot snapshot(SaveSkillOperationIdentity identity) {
    final owner = identity.owner;
    events.add(_event('store.snapshot', owner));
    snapshotOwners.add(owner);
    return identitySnapshots[identity] ??
        snapshots[owner] ??
        SkillStoreSnapshot(identity: identity, skills: defaultSkills);
  }

  @override
  Future<SkillStoreWriteResult> upsertMarkdown(
    SaveSkillOperationIdentity identity,
    SkillStoreWriteRequest request,
  ) async {
    final owner = identity.owner;
    events.add(_event('store.write', owner));
    writes.add((owner: owner, identity: identity, request: request));
    final started = writeStarted.putIfAbsent(owner, Completer<void>.new);
    if (!started.isCompleted) {
      started.complete();
    }
    final error = writeErrors[owner];
    if (error != null) {
      throw error;
    }
    final pendingWrite = pendingWrites[owner];
    if (pendingWrite != null) {
      return pendingWrite.future;
    }
    return identityWriteResults[identity] ??
        writeResults[owner] ??
        SkillStoreWriteResult.committed(
          identity: identity,
          skill: _skill(id: 'default-skill', name: 'Release Skill'),
        );
  }

  @override
  Future<SkillSaveAcknowledgement> recordSuccessfulSave(
    SaveSkillOperationIdentity identity,
  ) async {
    final owner = identity.owner;
    events.add(_event('store.record', owner));
    recordedOwners.add(owner);
    final error = recordErrors[owner];
    if (error != null) {
      throw error;
    }
    return recordAcknowledgements[identity] ??
        SkillSaveAcknowledgement.acknowledged(identity: identity);
  }
}

typedef _ApprovalUse = ({
  ChatTurnOwner owner,
  SkillSaveApprovalRequest request,
});

final class _ApprovalPort implements SkillSaveApprovalPort {
  _ApprovalPort(this.events);

  final List<String> events;
  final Map<ChatTurnOwner, SkillSaveApprovalDecision> decisions = {};
  final Map<SaveSkillOperationIdentity, SkillSaveApprovalDecision>
  identityDecisions = {};
  final Map<SaveSkillOperationIdentity, SkillSaveAcknowledgement>
  acknowledgements = {};
  final List<_ApprovalUse> requests = [];
  final List<ChatTurnOwner> expirationOwners = [];
  final List<String> expirationToolNames = [];

  List<ChatTurnOwner> get owners => [
    ...requests.map((request) => request.owner),
    ...expirationOwners,
  ];

  @override
  Future<SkillSaveApprovalDecision> requestApproval(
    SkillSaveApprovalRequest request,
  ) async {
    final identity = request.toolRequest.identity;
    final owner = identity.owner;
    events.add(_event('approval.request', owner));
    requests.add((owner: owner, request: request));
    return identityDecisions[identity] ??
        decisions[owner] ??
        SkillSaveApprovalDecision(identity: identity, approved: true);
  }

  @override
  SkillSaveAcknowledgement acknowledgeOwner(
    SaveSkillOperationIdentity identity,
  ) {
    final owner = identity.owner;
    events.add(_event('approval.expired', owner));
    expirationOwners.add(owner);
    expirationToolNames.add(identity.toolName);
    return acknowledgements[identity] ??
        SkillSaveAcknowledgement.acknowledged(identity: identity);
  }
}

String _event(String name, ChatTurnOwner owner) {
  return '$name:${owner.conversationId}:${owner.interactionGeneration}';
}
