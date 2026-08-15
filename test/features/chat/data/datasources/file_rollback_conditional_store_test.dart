import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/file_rollback_checkpoint_store.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:test/test.dart';

TextFileSnapshot _snapshot(String path, String content, {bool exists = true}) {
  return TextFileSnapshot(path: path, exists: exists, content: content);
}

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 7,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'conversation-b',
    interactionGeneration: 7,
  );

  group('conditional single-file rollback', () {
    late Map<String, TextFileSnapshot> current;
    late List<String> restoredPaths;
    late String Function(String path) restorePayload;
    late void Function(String path)? snapshotHook;
    late FileRollbackCheckpointStore store;

    setUp(() {
      current = {};
      restoredPaths = [];
      snapshotHook = null;
      restorePayload = (path) => jsonEncode({'path': path, 'restored': true});
      store = FileRollbackCheckpointStore(
        snapshotLoader: (path) async {
          snapshotHook?.call(path);
          return current[path]!;
        },
        snapshotRestorer:
            ({required path, required existedBefore, content}) async {
              restoredPaths.add(path);
              return restorePayload(path);
            },
      );
    });

    void captureAndChange(
      ChatTurnOwner owner,
      String path,
      String before,
      String after,
    ) {
      store.push(owner, _snapshot(path, before));
      current[path] = _snapshot(path, after);
    }

    test('tokens are stable for one owner, entry, and file state', () async {
      captureAndChange(ownerA, '/a.txt', 'before-a', 'after-a');
      captureAndChange(ownerB, '/b.txt', 'before-b', 'after-b');

      final previewA = (await store.previewFileRollbackCheckpoint(ownerA))!;
      final repeatedA = (await store.previewFileRollbackCheckpoint(ownerA))!;
      final previewB = (await store.previewFileRollbackCheckpoint(ownerB))!;

      expect(previewA.owner, ownerA);
      expect(repeatedA.checkpointToken, previewA.checkpointToken);
      expect(previewB.owner, ownerB);
      expect(previewB.checkpointToken, isNot(previewA.checkpointToken));

      current['/a.txt'] = _snapshot('/a.txt', 'successor bytes');
      final changedA = (await store.previewFileRollbackCheckpoint(ownerA))!;
      expect(changedA.checkpointToken, isNot(previewA.checkpointToken));
    });

    test(
      'rejects stale state and successor entry tokens without effects',
      () async {
        captureAndChange(ownerA, '/first.txt', 'before-1', 'after-1');
        final staleState = (await store.previewFileRollbackCheckpoint(ownerA))!;
        current['/first.txt'] = _snapshot('/first.txt', 'externally changed');

        final stateResult = await store.rollbackFileCheckpoint(
          owner: ownerA,
          expectedCheckpointToken: staleState.checkpointToken,
          toolName: 'rollback_last_file_change',
        );

        expect(
          stateResult.disposition,
          FileRollbackCheckpointExecutionDisposition.checkpointChanged,
        );
        expect(restoredPaths, isEmpty);

        final firstCurrent = (await store.previewFileRollbackCheckpoint(
          ownerA,
        ))!;
        captureAndChange(ownerA, '/second.txt', 'before-2', 'after-2');
        final successor = (await store.previewFileRollbackCheckpoint(ownerA))!;
        final entryResult = await store.rollbackFileCheckpoint(
          owner: ownerA,
          expectedCheckpointToken: firstCurrent.checkpointToken,
          toolName: 'rollback_last_file_change',
        );

        expect(
          entryResult.disposition,
          FileRollbackCheckpointExecutionDisposition.checkpointChanged,
        );
        expect(
          (await store.previewFileRollbackCheckpoint(ownerA))!.checkpointToken,
          successor.checkpointToken,
        );
        expect(restoredPaths, isEmpty);
      },
    );

    test('a successor added during validation is never consumed', () async {
      captureAndChange(ownerA, '/first.txt', 'before-1', 'after-1');
      final first = (await store.previewFileRollbackCheckpoint(ownerA))!;
      snapshotHook = (_) {
        snapshotHook = null;
        captureAndChange(ownerA, '/second.txt', 'before-2', 'after-2');
      };

      final result = await store.rollbackFileCheckpoint(
        owner: ownerA,
        expectedCheckpointToken: first.checkpointToken,
        toolName: 'rollback_last_file_change',
      );

      expect(
        result.disposition,
        FileRollbackCheckpointExecutionDisposition.checkpointChanged,
      );
      expect(restoredPaths, isEmpty);
      expect(
        (await store.previewFileRollbackCheckpoint(ownerA))!.path,
        '/second.txt',
      );
    });

    test('conditionally consumes only the exact owner checkpoint', () async {
      captureAndChange(ownerA, '/a.txt', 'before-a', 'after-a');
      captureAndChange(ownerB, '/b.txt', 'before-b', 'after-b');
      final previewA = (await store.previewFileRollbackCheckpoint(ownerA))!;
      final previewB = (await store.previewFileRollbackCheckpoint(ownerB))!;

      final result = await store.rollbackFileCheckpoint(
        owner: ownerA,
        expectedCheckpointToken: previewA.checkpointToken,
        toolName: 'rollback_last_file_change',
      );

      expect(
        result.disposition,
        FileRollbackCheckpointExecutionDisposition.completed,
      );
      expect(result.owner, ownerA);
      expect(result.checkpointToken, previewA.checkpointToken);
      expect(result.result!.isSuccess, isTrue);
      expect(restoredPaths, ['/a.txt']);
      expect(await store.previewFileRollbackCheckpoint(ownerA), isNull);
      expect(
        (await store.previewFileRollbackCheckpoint(ownerB))!.checkpointToken,
        previewB.checkpointToken,
      );
    });

    test('restores an entry after an explicit restoration failure', () async {
      captureAndChange(ownerA, '/a.txt', 'before-a', 'after-a');
      final preview = (await store.previewFileRollbackCheckpoint(ownerA))!;
      restorePayload = (path) =>
          jsonEncode({'path': path, 'error': 'write failed'});

      final result = await store.rollbackFileCheckpoint(
        owner: ownerA,
        expectedCheckpointToken: preview.checkpointToken,
        toolName: 'rollback_last_file_change',
      );

      expect(
        result.disposition,
        FileRollbackCheckpointExecutionDisposition.effectUncertain,
      );
      expect(result.result!.isSuccess, isFalse);
      expect(
        (await store.previewFileRollbackCheckpoint(ownerA))!.checkpointToken,
        preview.checkpointToken,
      );
    });

    test(
      'restores an entry and reports uncertainty after an exception',
      () async {
        captureAndChange(ownerA, '/a.txt', 'before-a', 'after-a');
        final preview = (await store.previewFileRollbackCheckpoint(ownerA))!;
        restorePayload = (_) => throw StateError('failed after dispatch');

        final result = await store.rollbackFileCheckpoint(
          owner: ownerA,
          expectedCheckpointToken: preview.checkpointToken,
          toolName: 'rollback_last_file_change',
        );

        expect(
          result.disposition,
          FileRollbackCheckpointExecutionDisposition.effectUncertain,
        );
        expect(
          (await store.previewFileRollbackCheckpoint(ownerA))!.checkpointToken,
          preview.checkpointToken,
        );
      },
    );

    test('failed rollback never replaces a newer successor entry', () async {
      captureAndChange(ownerA, '/first.txt', 'before-1', 'after-1');
      final first = (await store.previewFileRollbackCheckpoint(ownerA))!;
      var calls = 0;
      restorePayload = (path) {
        calls += 1;
        if (calls == 1) {
          captureAndChange(ownerA, '/second.txt', 'before-2', 'after-2');
          return jsonEncode({'path': path, 'error': 'write failed'});
        }
        return jsonEncode({'path': path, 'restored': true});
      };

      final failed = await store.rollbackFileCheckpoint(
        owner: ownerA,
        expectedCheckpointToken: first.checkpointToken,
        toolName: 'rollback_last_file_change',
      );
      final successor = (await store.previewFileRollbackCheckpoint(ownerA))!;

      expect(failed.result!.isSuccess, isFalse);
      expect(successor.path, '/second.txt');
      expect(
        (await store.rollbackFileCheckpoint(
          owner: ownerA,
          expectedCheckpointToken: successor.checkpointToken,
          toolName: 'rollback_last_file_change',
        )).result!.isSuccess,
        isTrue,
      );
      expect(
        (await store.previewFileRollbackCheckpoint(ownerA))!.path,
        '/first.txt',
      );
    });

    test('classifies owner retirement before and after the effect', () async {
      captureAndChange(ownerA, '/before.txt', 'before', 'after');
      final before = (await store.previewFileRollbackCheckpoint(ownerA))!;
      store.clear(ownerA);

      final beforeResult = await store.rollbackFileCheckpoint(
        owner: ownerA,
        expectedCheckpointToken: before.checkpointToken,
        toolName: 'rollback_last_file_change',
      );
      expect(
        beforeResult.disposition,
        FileRollbackCheckpointExecutionDisposition.ownerExpiredBeforeEffect,
      );
      expect(restoredPaths, isEmpty);

      store.clearAll();
      captureAndChange(ownerA, '/after.txt', 'before', 'after');
      final after = (await store.previewFileRollbackCheckpoint(ownerA))!;
      restorePayload = (path) {
        store.clear(ownerA);
        return jsonEncode({'path': path, 'restored': true});
      };

      final afterResult = await store.rollbackFileCheckpoint(
        owner: ownerA,
        expectedCheckpointToken: after.checkpointToken,
        toolName: 'rollback_last_file_change',
      );
      expect(
        afterResult.disposition,
        FileRollbackCheckpointExecutionDisposition.ownerExpiredAfterEffect,
      );
      expect(await store.previewFileRollbackCheckpoint(ownerA), isNull);
    });

    test('legacy APIs preserve successful and empty-history shapes', () async {
      captureAndChange(ownerA, '/a.txt', 'before-a', 'after-a');

      final success = await store.rollbackLastFileChange(
        owner: ownerA,
        toolName: 'rollback_last_file_change',
      );
      final exhausted = await store.rollbackLastFileChange(
        owner: ownerA,
        toolName: 'rollback_last_file_change',
      );

      expect(success.isSuccess, isTrue);
      expect(exhausted.isSuccess, isFalse);
      expect(
        exhausted.errorMessage,
        'No recent file change is available to roll back',
      );
    });

    test(
      'turn checkpoints deduplicate entries by stable path identity',
      () async {
        const firstAlias = '/workspace/alias-a.txt';
        const secondAlias = '/workspace/alias-b.txt';
        const stablePath = '/workspace/target.txt';
        current[firstAlias] = const TextFileSnapshot(
          path: firstAlias,
          exists: true,
          content: 'after',
          resolvedPathKey: stablePath,
        );
        store.beginFileTurnCheckpoint(ownerA, 'stable-path-turn');
        store.push(
          ownerA,
          const TextFileSnapshot(
            path: firstAlias,
            exists: true,
            content: 'before',
            resolvedPathKey: stablePath,
          ),
        );
        store.push(
          ownerA,
          const TextFileSnapshot(
            path: secondAlias,
            exists: true,
            content: 'before',
            resolvedPathKey: stablePath,
          ),
        );
        expect(store.endFileTurnCheckpoint(ownerA), isTrue);

        final preview = await store.previewLastFileTurnCheckpoint(ownerA);

        expect(preview?.paths, [firstAlias]);
      },
    );
  });
}
