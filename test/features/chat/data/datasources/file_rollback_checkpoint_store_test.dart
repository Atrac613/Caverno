import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/file_rollback_checkpoint_store.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';

void main() {
  group('FileRollbackCheckpointStore', () {
    late Directory tempDir;
    late FileRollbackCheckpointStore store;
    late ChatTurnOwner ownerA;
    late ChatTurnOwner ownerB;

    setUp(() {
      final createdDirectory = Directory.systemTemp.createTempSync(
        'file_rollback_checkpoint_store_test_',
      );
      tempDir = Directory(createdDirectory.resolveSymbolicLinksSync());
      store = FileRollbackCheckpointStore();
      ownerA = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 7,
      );
      ownerB = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: 7,
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    String tempPath(String name) {
      return '${tempDir.path}${Platform.pathSeparator}$name';
    }

    Future<void> captureAndChange(
      ChatTurnOwner owner,
      File file,
      String content,
    ) async {
      store.push(owner, await FilesystemTools.captureTextSnapshot(file.path));
      await file.writeAsString(content);
    }

    Future<McpToolResult> rollbackLastTurn(ChatTurnOwner owner) async {
      final preview = await store.previewLastFileTurnCheckpoint(owner);
      return store.rollbackLastFileTurnCheckpoint(
        owner,
        preview?.checkpointToken ?? -1,
      );
    }

    test('rolls back only files captured by the exact owner', () async {
      final changed = File(tempPath('changed.txt'))
        ..writeAsStringSync('before\n');
      final createdPath = tempPath('created.txt');
      final untouched = File(tempPath('untouched.txt'))
        ..writeAsStringSync('untouched\n');

      store.beginFileTurnCheckpoint(ownerA, 'turn-1');
      await captureAndChange(ownerA, changed, 'after\n');
      store.push(
        ownerA,
        await FilesystemTools.captureTextSnapshot(createdPath),
      );
      await File(createdPath).writeAsString('created\n');

      expect(store.endFileTurnCheckpoint(ownerA), isTrue);
      expect(
        store.latestCompletedCheckpointOwner(ownerA.conversationId),
        ownerA,
      );
      expect(await store.previewLastFileTurnCheckpoint(ownerB), isNull);

      final preview = await store.previewLastFileTurnCheckpoint(ownerA);
      expect(preview, isNotNull);
      expect(preview!.owner, ownerA);
      expect(preview.turnId, 'turn-1');
      expect(preview.paths, [
        changed.absolute.path,
        File(createdPath).absolute.path,
      ]);

      final result = await rollbackLastTurn(ownerA);

      expect(result.isSuccess, isTrue);
      expect(await changed.readAsString(), 'before\n');
      expect(File(createdPath).existsSync(), isFalse);
      expect(await untouched.readAsString(), 'untouched\n');
      expect(
        store.latestCompletedCheckpointOwner(ownerA.conversationId),
        isNull,
      );
    });

    test(
      'keeps simultaneous active checkpoints isolated and captures each path '
      'once per owner',
      () async {
        final sharedConversationOwner = ChatTurnOwner(
          conversationId: ownerA.conversationId,
          interactionGeneration: 8,
        );
        final repeated = File(tempPath('repeated.txt'))
          ..writeAsStringSync('before\n');
        final otherFirst = File(tempPath('other_first.txt'))
          ..writeAsStringSync('other first before\n');
        final otherSecond = File(tempPath('other_second.txt'))
          ..writeAsStringSync('other second before\n');

        store.beginFileTurnCheckpoint(ownerA, 'turn-a-first');
        store.beginFileTurnCheckpoint(sharedConversationOwner, 'turn-b');
        await captureAndChange(ownerA, repeated, 'after first\n');
        await captureAndChange(ownerA, repeated, 'after second\n');
        await captureAndChange(
          sharedConversationOwner,
          otherFirst,
          'other first after\n',
        );

        store.beginFileTurnCheckpoint(ownerA, 'turn-a-empty');
        await captureAndChange(
          sharedConversationOwner,
          otherSecond,
          'other second after\n',
        );
        expect(store.endFileTurnCheckpoint(sharedConversationOwner), isTrue);
        expect(store.endFileTurnCheckpoint(ownerA), isFalse);

        final ownerAPreview = await store.previewLastFileTurnCheckpoint(ownerA);
        final otherPreview = await store.previewLastFileTurnCheckpoint(
          sharedConversationOwner,
        );
        expect(ownerAPreview, isNull);
        expect(otherPreview!.owner, sharedConversationOwner);
        expect(otherPreview.paths, [
          otherFirst.absolute.path,
          otherSecond.absolute.path,
        ]);
        expect(
          store.latestCompletedCheckpointOwner(ownerA.conversationId),
          sharedConversationOwner,
        );

        final otherResult = await rollbackLastTurn(sharedConversationOwner);
        expect(otherResult.isSuccess, isTrue);
        expect(await repeated.readAsString(), 'after second\n');
        expect(await otherFirst.readAsString(), 'other first before\n');
        expect(await otherSecond.readAsString(), 'other second before\n');

        final currentOwnerAPreview = await store
            .previewLastFileTurnCheckpoint(ownerA);
        expect(currentOwnerAPreview!.turnId, 'turn-a-first');
        expect(currentOwnerAPreview.paths, [repeated.absolute.path]);
        final result = await rollbackLastTurn(ownerA);
        expect(result.isSuccess, isTrue);
        expect(await repeated.readAsString(), 'before\n');
      },
    );

    test('isolates equal generations from different conversations', () async {
      final targetA = File(tempPath('target_a.txt'))
        ..writeAsStringSync('a before\n');
      final targetB = File(tempPath('target_b.txt'))
        ..writeAsStringSync('b before\n');

      await captureAndChange(ownerA, targetA, 'a after\n');
      await captureAndChange(ownerB, targetB, 'b after\n');

      final previewA = await store.previewLastFileRollbackChange(ownerA);
      final previewB = await store.previewLastFileRollbackChange(ownerB);
      expect(previewA!.path, targetA.absolute.path);
      expect(previewB!.path, targetB.absolute.path);

      final resultA = await store.rollbackLastFileChange(
        owner: ownerA,
        toolName: 'rollback_a',
      );
      expect(resultA.isSuccess, isTrue);
      expect(await targetA.readAsString(), 'a before\n');
      expect(await targetB.readAsString(), 'b after\n');
      expect(await store.previewLastFileRollbackChange(ownerA), isNull);
      expect(await store.previewLastFileRollbackChange(ownerB), isNotNull);
    });

    test('retains twenty individual changes per owner without cross-owner '
        'eviction', () async {
      final ownerAFiles = <File>[];
      for (var index = 0; index < 22; index += 1) {
        final file = File(tempPath('owner_a_$index.txt'))
          ..writeAsStringSync('before-$index\n');
        ownerAFiles.add(file);
        await captureAndChange(ownerA, file, 'after-$index\n');
      }
      final ownerBFile = File(tempPath('owner_b.txt'))
        ..writeAsStringSync('b before\n');
      await captureAndChange(ownerB, ownerBFile, 'b after\n');

      for (var index = 21; index >= 2; index -= 1) {
        final result = await store.rollbackLastFileChange(
          owner: ownerA,
          toolName: 'rollback',
        );
        expect(result.isSuccess, isTrue);
        expect(await ownerAFiles[index].readAsString(), 'before-$index\n');
      }

      final exhausted = await store.rollbackLastFileChange(
        owner: ownerA,
        toolName: 'rollback',
      );
      expect(exhausted.isSuccess, isFalse);
      expect(await ownerAFiles[0].readAsString(), 'after-0\n');
      expect(await ownerAFiles[1].readAsString(), 'after-1\n');

      final ownerBResult = await store.rollbackLastFileChange(
        owner: ownerB,
        toolName: 'rollback',
      );
      expect(ownerBResult.isSuccess, isTrue);
      expect(await ownerBFile.readAsString(), 'b before\n');
    });

    test(
      'retains ten turn checkpoints per owner and keeps owner chronology',
      () async {
        final laterOwner = ChatTurnOwner(
          conversationId: 'conversation-later',
          interactionGeneration: 8,
        );
        final ownerAFiles = <File>[];

        final evicted = File(tempPath('turn_a_0.txt'))
          ..writeAsStringSync('before-0\n');
        ownerAFiles.add(evicted);
        store.beginFileTurnCheckpoint(ownerA, 'turn-a-0');
        await captureAndChange(ownerA, evicted, 'after-0\n');
        expect(store.endFileTurnCheckpoint(ownerA), isTrue);

        final laterFile = File(tempPath('turn_later.txt'))
          ..writeAsStringSync('later before\n');
        store.beginFileTurnCheckpoint(laterOwner, 'turn-later');
        await captureAndChange(laterOwner, laterFile, 'later after\n');
        expect(store.endFileTurnCheckpoint(laterOwner), isTrue);

        for (var index = 1; index <= 10; index += 1) {
          final file = File(tempPath('turn_a_$index.txt'))
            ..writeAsStringSync('before-$index\n');
          ownerAFiles.add(file);
          store.beginFileTurnCheckpoint(ownerA, 'turn-a-$index');
          await captureAndChange(ownerA, file, 'after-$index\n');
          expect(store.endFileTurnCheckpoint(ownerA), isTrue);
        }

        expect(
          store.latestCompletedCheckpointOwner(ownerA.conversationId),
          ownerA,
        );
        for (var expectedIndex = 10; expectedIndex >= 1; expectedIndex -= 1) {
          final result = await rollbackLastTurn(ownerA);
          final decoded = jsonDecode(result.result) as Map<String, dynamic>;
          expect(result.isSuccess, isTrue);
          expect(decoded['turn_id'], 'turn-a-$expectedIndex');
          expect(
            await ownerAFiles[expectedIndex].readAsString(),
            'before-$expectedIndex\n',
          );
        }

        expect(
          store.latestCompletedCheckpointOwner(ownerA.conversationId),
          isNull,
        );
        expect(
          (await store.rollbackLastFileTurnCheckpoint(ownerA, -1)).isSuccess,
          isFalse,
        );
        expect(await evicted.readAsString(), 'after-0\n');

        expect((await rollbackLastTurn(laterOwner)).isSuccess, isTrue);
        expect(await laterFile.readAsString(), 'later before\n');
        expect(
          store.latestCompletedCheckpointOwner(laterOwner.conversationId),
          isNull,
        );
      },
    );

    test(
      'keeps turn checkpoint entries after individual stack eviction',
      () async {
        final changedFiles = <File>[];

        store.beginFileTurnCheckpoint(ownerA, 'turn-overflow');
        for (var index = 0; index < 25; index += 1) {
          final file = File(tempPath('changed_$index.txt'))
            ..writeAsStringSync('before-$index\n');
          changedFiles.add(file);
          await captureAndChange(ownerA, file, 'after-$index\n');
        }
        expect(store.endFileTurnCheckpoint(ownerA), isTrue);

        final preview = await store.previewLastFileTurnCheckpoint(ownerA);
        expect(preview!.paths, hasLength(25));

        final result = await rollbackLastTurn(ownerA);
        expect(result.isSuccess, isTrue);
        for (var index = 0; index < changedFiles.length; index += 1) {
          expect(await changedFiles[index].readAsString(), 'before-$index\n');
        }
      },
    );

    test(
      'clear removes only the selected owner state and index entries',
      () async {
        final sameConversationOwner = ChatTurnOwner(
          conversationId: ownerA.conversationId,
          interactionGeneration: 8,
        );
        final ownerACompleted = File(tempPath('a_completed.txt'))
          ..writeAsStringSync('a completed before\n');
        final ownerAActive = File(tempPath('a_active.txt'))
          ..writeAsStringSync('a active before\n');
        final otherCompleted = File(tempPath('other_completed.txt'))
          ..writeAsStringSync('other completed before\n');
        final otherActive = File(tempPath('other_active.txt'))
          ..writeAsStringSync('other active before\n');

        store.beginFileTurnCheckpoint(ownerA, 'a-completed');
        await captureAndChange(ownerA, ownerACompleted, 'a completed after\n');
        expect(store.endFileTurnCheckpoint(ownerA), isTrue);
        store.beginFileTurnCheckpoint(ownerA, 'a-active');
        await captureAndChange(ownerA, ownerAActive, 'a active after\n');

        store.beginFileTurnCheckpoint(sameConversationOwner, 'other-completed');
        await captureAndChange(
          sameConversationOwner,
          otherCompleted,
          'other completed after\n',
        );
        expect(store.endFileTurnCheckpoint(sameConversationOwner), isTrue);
        store.beginFileTurnCheckpoint(sameConversationOwner, 'other-active');
        await captureAndChange(
          sameConversationOwner,
          otherActive,
          'other active after\n',
        );

        store.clear(sameConversationOwner);
        store.beginFileTurnCheckpoint(sameConversationOwner, 'late-owner');
        store.push(
          sameConversationOwner,
          TextFileSnapshot(path: tempPath('late_owner.txt'), exists: false),
        );

        expect(
          await store.previewLastFileRollbackChange(sameConversationOwner),
          isNull,
        );
        expect(
          await store.previewLastFileTurnCheckpoint(sameConversationOwner),
          isNull,
        );
        expect(store.endFileTurnCheckpoint(sameConversationOwner), isFalse);
        expect(
          store.latestCompletedCheckpointOwner(ownerA.conversationId),
          ownerA,
        );
        expect(await store.previewLastFileRollbackChange(ownerA), isNotNull);
        expect(store.endFileTurnCheckpoint(ownerA), isTrue);
        expect((await rollbackLastTurn(ownerA)).isSuccess, isTrue);
        expect(await ownerAActive.readAsString(), 'a active before\n');
        expect(await otherCompleted.readAsString(), 'other completed after\n');
        expect(await otherActive.readAsString(), 'other active after\n');
      },
    );

    test('clear removes the sole completed owner index', () async {
      final target = File(tempPath('sole_owner.txt'))
        ..writeAsStringSync('before\n');
      store.beginFileTurnCheckpoint(ownerA, 'sole-owner-turn');
      await captureAndChange(ownerA, target, 'after\n');
      expect(store.endFileTurnCheckpoint(ownerA), isTrue);
      expect(
        store.latestCompletedCheckpointOwner(ownerA.conversationId),
        ownerA,
      );

      store.clear(ownerA);

      expect(
        store.latestCompletedCheckpointOwner(ownerA.conversationId),
        isNull,
      );
      expect(await store.previewLastFileTurnCheckpoint(ownerA), isNull);
      expect(await store.previewLastFileRollbackChange(ownerA), isNull);
    });

    test(
      'restores only the failing owner individual entry for retry',
      () async {
        final targetA = File(tempPath('failing_a.txt'))
          ..writeAsStringSync('a before\n');
        final targetB = File(tempPath('safe_b.txt'))
          ..writeAsStringSync('b before\n');
        await captureAndChange(ownerA, targetA, 'a after\n');
        await captureAndChange(ownerB, targetB, 'b after\n');

        targetA.deleteSync();
        Directory(targetA.path).createSync();

        final failed = await store.rollbackLastFileChange(
          owner: ownerA,
          toolName: 'rollback',
        );
        expect(failed.isSuccess, isFalse);
        expect(await store.previewLastFileRollbackChange(ownerA), isNotNull);
        expect(await store.previewLastFileRollbackChange(ownerB), isNotNull);

        Directory(targetA.path).deleteSync();
        expect(
          (await store.rollbackLastFileChange(
            owner: ownerA,
            toolName: 'rollback',
          )).isSuccess,
          isTrue,
        );
        expect(await targetA.readAsString(), 'a before\n');
        expect(await targetB.readAsString(), 'b after\n');
      },
    );

    test(
      'keeps a failed turn checkpoint and owner index available for retry',
      () async {
        final earlierOwner = ChatTurnOwner(
          conversationId: ownerA.conversationId,
          interactionGeneration: 6,
        );
        final earlier = File(tempPath('earlier.txt'))
          ..writeAsStringSync('earlier before\n');
        final target = File(tempPath('target.txt'))
          ..writeAsStringSync('before\n');

        store.beginFileTurnCheckpoint(earlierOwner, 'turn-earlier');
        await captureAndChange(earlierOwner, earlier, 'earlier after\n');
        expect(store.endFileTurnCheckpoint(earlierOwner), isTrue);
        store.beginFileTurnCheckpoint(ownerA, 'turn-retry');
        await captureAndChange(ownerA, target, 'after\n');
        expect(store.endFileTurnCheckpoint(ownerA), isTrue);

        target.deleteSync();
        Directory(target.path).createSync();

        final firstResult = await rollbackLastTurn(ownerA);

        expect(firstResult.isSuccess, isFalse);
        expect(await store.previewLastFileTurnCheckpoint(ownerA), isNotNull);
        expect(
          await store.previewLastFileTurnCheckpoint(earlierOwner),
          isNull,
        );
        expect(
          store.latestCompletedCheckpointOwner(ownerA.conversationId),
          ownerA,
        );

        Directory(target.path).deleteSync();
        final secondResult = await rollbackLastTurn(ownerA);

        expect(secondResult.isSuccess, isTrue);
        expect(await target.readAsString(), 'before\n');
        expect(
          store.latestCompletedCheckpointOwner(ownerA.conversationId),
          earlierOwner,
        );
        expect(
          await store.previewLastFileTurnCheckpoint(earlierOwner),
          isNotNull,
        );
      },
    );

    test(
      'rejects a stale preview when the same owner completes another checkpoint',
      () async {
        final first = File(tempPath('stale_first.txt'))
          ..writeAsStringSync('first before\n');
        final second = File(tempPath('stale_second.txt'))
          ..writeAsStringSync('second before\n');

        store.beginFileTurnCheckpoint(ownerA, 'same-owner-first');
        await captureAndChange(ownerA, first, 'first after\n');
        expect(store.endFileTurnCheckpoint(ownerA), isTrue);
        final stalePreview = (await store.previewLastFileTurnCheckpoint(
          ownerA,
        ))!;

        store.beginFileTurnCheckpoint(ownerA, 'same-owner-second');
        await captureAndChange(ownerA, second, 'second after\n');
        expect(store.endFileTurnCheckpoint(ownerA), isTrue);

        final staleResult = await store.rollbackLastFileTurnCheckpoint(
          ownerA,
          stalePreview.checkpointToken,
        );

        expect(staleResult.isSuccess, isFalse);
        expect(staleResult.errorMessage, contains('preview it again'));
        expect(await first.readAsString(), 'first after\n');
        expect(await second.readAsString(), 'second after\n');
        final currentPreview = (await store.previewLastFileTurnCheckpoint(
          ownerA,
        ))!;
        expect(currentPreview.turnId, 'same-owner-second');
        expect(
          (await store.rollbackLastFileTurnCheckpoint(
            ownerA,
            currentPreview.checkpointToken,
          )).isSuccess,
          isTrue,
        );
        expect(await second.readAsString(), 'second before\n');
        final consumedAgain = await store.rollbackLastFileTurnCheckpoint(
          ownerA,
          currentPreview.checkpointToken,
        );
        expect(consumedAgain.isSuccess, isFalse);
        expect(
          (await store.previewLastFileTurnCheckpoint(ownerA))?.turnId,
          'same-owner-first',
        );
        expect((await rollbackLastTurn(ownerA)).isSuccess, isTrue);
        expect(await first.readAsString(), 'first before\n');
      },
    );

    test(
      'retains ten conversation checkpoints without evicting a peer',
      () async {
        final owners = <ChatTurnOwner>[];
        for (var index = 0; index <= 10; index += 1) {
          final owner = ChatTurnOwner(
            conversationId: 'bounded-conversation',
            interactionGeneration: index + 1,
          );
          owners.add(owner);
          final file = File(tempPath('bounded_$index.txt'))
            ..writeAsStringSync('before-$index\n');
          store.beginFileTurnCheckpoint(owner, 'bounded-turn-$index');
          await captureAndChange(owner, file, 'after-$index\n');
          expect(store.endFileTurnCheckpoint(owner), isTrue);
        }
        final peerOwner = ChatTurnOwner(
          conversationId: 'bounded-peer',
          interactionGeneration: 1,
        );
        final peerFile = File(tempPath('bounded_peer.txt'))
          ..writeAsStringSync('peer before\n');
        store.beginFileTurnCheckpoint(peerOwner, 'peer-turn');
        await captureAndChange(peerOwner, peerFile, 'peer after\n');
        expect(store.endFileTurnCheckpoint(peerOwner), isTrue);

        expect(await store.previewLastFileTurnCheckpoint(owners.first), isNull);
        expect(
          store.latestCompletedCheckpointOwner('bounded-conversation'),
          owners.last,
        );
        expect(
          (await store.previewLastFileTurnCheckpoint(peerOwner))?.turnId,
          'peer-turn',
        );
      },
    );

    test('retireConversation blocks late checkpoint resurrection', () async {
      final peerOwner = ChatTurnOwner(
        conversationId: 'retire-peer',
        interactionGeneration: 1,
      );
      for (final owner in [ownerA, peerOwner]) {
        final file = File(tempPath('retire_${owner.interactionGeneration}.txt'))
          ..writeAsStringSync('before\n');
        store.beginFileTurnCheckpoint(owner, 'retire-turn');
        await captureAndChange(owner, file, 'after\n');
        expect(store.endFileTurnCheckpoint(owner), isTrue);
      }

      await store.retireConversation(ownerA.conversationId);
      store.beginFileTurnCheckpoint(ownerA, 'late-turn');
      store.push(
        ownerA,
        TextFileSnapshot(path: tempPath('late.txt'), exists: false),
      );

      expect(store.endFileTurnCheckpoint(ownerA), isFalse);
      expect(await store.previewLastFileTurnCheckpoint(ownerA), isNull);
      expect(
        store.latestCompletedCheckpointOwner(ownerA.conversationId),
        isNull,
      );
      expect(
        (await store.previewLastFileTurnCheckpoint(peerOwner))?.turnId,
        'retire-turn',
      );
    });

    test('clearAll releases state and retirement tombstones', () async {
      final target = File(tempPath('clear_all.txt'))
        ..writeAsStringSync('before\n');
      store.beginFileTurnCheckpoint(ownerA, 'before-clear-all');
      await captureAndChange(ownerA, target, 'after\n');
      expect(store.endFileTurnCheckpoint(ownerA), isTrue);
      await store.retireConversation(ownerB.conversationId);

      store.clearAll();

      expect(await store.previewLastFileTurnCheckpoint(ownerA), isNull);
      store.beginFileTurnCheckpoint(ownerB, 'after-clear-all');
      store.push(
        ownerB,
        TextFileSnapshot(path: tempPath('after_clear_all.txt'), exists: false),
      );
      expect(store.endFileTurnCheckpoint(ownerB), isTrue);
    });
  });
}
