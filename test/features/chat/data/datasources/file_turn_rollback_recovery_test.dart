import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/background_process_monitor_service.dart';
import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';
import 'package:caverno/features/chat/data/datasources/built_in_filesystem_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/built_in_local_command_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/file_rollback_checkpoint_store.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service_owner_facade.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDirectory;
  late ChatTurnOwner owner;

  setUp(() async {
    final createdDirectory = await Directory.systemTemp.createTemp(
      'file_turn_rollback_recovery_test_',
    );
    tempDirectory = Directory(await createdDirectory.resolveSymbolicLinks());
    owner = ChatTurnOwner(
      conversationId: 'turn-rollback-recovery',
      interactionGeneration: 17,
    );
  });

  tearDown(() async {
    if (tempDirectory.existsSync()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('keeps the empty-checkpoint result compatible', () async {
    final store = FileRollbackCheckpointStore();

    final result = await store.rollbackLastFileTurnCheckpoint(owner, -1);

    expect(result.isSuccess, isFalse);
    expect(
      result.errorMessage,
      'No recent turn file checkpoint is available to roll back',
    );
  });

  test('external edit after preview causes zero rollback effects', () async {
    final file = File('${tempDirectory.path}/external_edit.txt')
      ..writeAsStringSync('before\n');
    var restoreCalls = 0;
    final store = FileRollbackCheckpointStore(
      snapshotRestorer:
          ({required path, required existedBefore, content}) async {
            restoreCalls++;
            return FilesystemTools.restoreTextSnapshot(
              path: path,
              existedBefore: existedBefore,
              content: content,
            );
          },
    );
    await _completeTurn(
      store: store,
      owner: owner,
      turnId: 'external-edit-turn',
      changes: [(file: file, after: 'after\n')],
    );
    final preview = (await store.previewLastFileTurnCheckpoint(owner))!;
    expect(preview.currentStateFingerprint, isNotEmpty);

    await file.writeAsString('external\n');
    final result = await store.rollbackLastFileTurnCheckpoint(
      owner,
      preview.checkpointToken,
    );

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('preview it again'));
    expect(restoreCalls, 0);
    expect(await file.readAsString(), 'external\n');
    final refreshed = (await store.previewLastFileTurnCheckpoint(owner))!;
    expect(refreshed.checkpointToken, isNot(preview.checkpointToken));
    expect(
      refreshed.currentStateFingerprint,
      isNot(preview.currentStateFingerprint),
    );
  });

  test(
    'owner expiry after a committed restore compensates it and skips peers',
    () async {
      final untouched = File('${tempDirectory.path}/untouched.txt')
        ..writeAsStringSync('untouched before\n');
      final attempted = File('${tempDirectory.path}/attempted.txt')
        ..writeAsStringSync('attempted before\n');
      late FileRollbackCheckpointStore store;
      var firstDispatch = true;
      store = FileRollbackCheckpointStore(
        snapshotRestorer:
            ({required path, required existedBefore, content}) async {
              final payload = await FilesystemTools.restoreTextSnapshot(
                path: path,
                existedBefore: existedBefore,
                content: content,
              );
              if (path == attempted.path && firstDispatch) {
                firstDispatch = false;
                store.clear(owner);
                throw StateError('owner cleared after restore commit');
              }
              return payload;
            },
      );
      await _completeTurn(
        store: store,
        owner: owner,
        turnId: 'owner-expiry-turn',
        changes: [
          (file: untouched, after: 'untouched after\n'),
          (file: attempted, after: 'attempted after\n'),
        ],
      );
      final preview = (await store.previewLastFileTurnCheckpoint(owner))!;

      final result = await store.rollbackLastFileTurnCheckpoint(
        owner,
        preview.checkpointToken,
      );
      final payload = jsonDecode(result.result) as Map<String, dynamic>;

      expect(result.isSuccess, isFalse);
      expect(payload['compensated'], isTrue);
      expect(payload.containsKey('recovery_receipt'), isFalse);
      expect(await attempted.readAsString(), 'attempted after\n');
      expect(await untouched.readAsString(), 'untouched after\n');
      expect(await store.previewLastFileTurnCheckpoint(owner), isNull);
    },
  );

  test(
    'failed compensation keeps every path fenced until exact reconciliation',
    () async {
      final peer = File('${tempDirectory.path}/peer.txt')
        ..writeAsStringSync('peer before\n');
      final attempted = File('${tempDirectory.path}/recovery.txt')
        ..writeAsStringSync('recovery before\n');
      var attemptedRestoreCalls = 0;
      final store = FileRollbackCheckpointStore(
        snapshotRestorer:
            ({required path, required existedBefore, content}) async {
              if (path != attempted.path) {
                return FilesystemTools.restoreTextSnapshot(
                  path: path,
                  existedBefore: existedBefore,
                  content: content,
                );
              }
              attemptedRestoreCalls++;
              if (attemptedRestoreCalls == 1) {
                await FilesystemTools.restoreTextSnapshot(
                  path: path,
                  existedBefore: existedBefore,
                  content: content,
                );
                throw StateError('restore committed before callback failure');
              }
              if (attemptedRestoreCalls == 2) {
                return jsonEncode({'error': 'compensation was not applied'});
              }
              return FilesystemTools.restoreTextSnapshot(
                path: path,
                existedBefore: existedBefore,
                content: content,
              );
            },
      );
      await _completeTurn(
        store: store,
        owner: owner,
        turnId: 'recovery-fence-turn',
        changes: [
          (file: peer, after: 'peer after\n'),
          (file: attempted, after: 'recovery after\n'),
        ],
      );
      final preview = (await store.previewLastFileTurnCheckpoint(owner))!;

      final failed = await store.rollbackLastFileTurnCheckpoint(
        owner,
        preview.checkpointToken,
      );
      final failedPayload = jsonDecode(failed.result) as Map<String, dynamic>;
      final receipt = failedPayload['recovery_receipt'] as String;
      final facade = _RecoveryOwnerFacade(
        BuiltInFilesystemToolHandler(checkpointStore: store),
      );
      expect(failedPayload['recovery_required'], isTrue);
      expect(await attempted.readAsString(), 'recovery before\n');
      expect(await peer.readAsString(), 'peer after\n');

      final peerStarted = Completer<void>();
      final attemptedStarted = Completer<void>();
      final handler = BuiltInFilesystemToolHandler(
        checkpointStore: store,
        operationRunner: ({required name, required arguments}) async {
          final path = arguments['path'] as String;
          if (path == peer.path) {
            peerStarted.complete();
          } else {
            attemptedStarted.complete();
          }
          return FilesystemTools.writeFile(
            path: path,
            content: arguments['content'] as String,
          );
        },
      );
      final peerSuccessor = handler.execute(
        name: 'write_file',
        arguments: {'path': peer.path, 'content': 'peer successor\n'},
        owner: owner,
      );
      final attemptedSuccessor = handler.execute(
        name: 'write_file',
        arguments: {'path': attempted.path, 'content': 'recovery successor\n'},
        owner: owner,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(peerStarted.isCompleted, isFalse);
      expect(attemptedStarted.isCompleted, isFalse);

      final pendingRetry = await store.rollbackLastFileTurnCheckpoint(
        owner,
        preview.checkpointToken,
      );
      expect(
        (jsonDecode(pendingRetry.result)
            as Map<String, dynamic>)['recovery_receipt'],
        receipt,
      );
      final otherOwner = ChatTurnOwner(
        conversationId: owner.conversationId,
        interactionGeneration: owner.interactionGeneration + 1,
      );
      for (final candidate in ['$receipt ', '${receipt}x']) {
        final rejected = await store.reconcileFileTurnRollbackRecovery(
          owner: owner,
          recoveryReceipt: candidate,
        );
        expect(rejected.isSuccess, isFalse);
      }
      final wrongOwner = await store.reconcileFileTurnRollbackRecovery(
        owner: otherOwner,
        recoveryReceipt: receipt,
      );
      expect(wrongOwner.isSuccess, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(peerStarted.isCompleted, isFalse);
      expect(attemptedStarted.isCompleted, isFalse);

      final reconciled = await facade.reconcileFileTurnRollbackRecovery(
        owner: owner,
        recoveryReceipt: receipt,
      );
      expect(reconciled.isSuccess, isTrue);
      expect(
        (jsonDecode(reconciled.result)
            as Map<String, dynamic>)['checkpoint_retained'],
        isTrue,
      );
      await peerStarted.future;
      await attemptedStarted.future;
      expect((await peerSuccessor).isSuccess, isTrue);
      expect((await attemptedSuccessor).isSuccess, isTrue);
      expect(await peer.readAsString(), 'peer successor\n');
      expect(await attempted.readAsString(), 'recovery successor\n');

      final consumed = await store.reconcileFileTurnRollbackRecovery(
        owner: owner,
        recoveryReceipt: receipt,
      );
      expect(consumed.isSuccess, isFalse);
    },
  );

  test(
    'retirement preserves an external successor and releases recovery fences',
    () async {
      final failsSecond = File('${tempDirectory.path}/fails-second.txt')
        ..writeAsStringSync('failure before\n');
      final restoredFirst = File('${tempDirectory.path}/restored-first.txt')
        ..writeAsStringSync('restored before\n');
      late FileRollbackCheckpointStore store;
      store = FileRollbackCheckpointStore(
        snapshotRestorer:
            ({required path, required existedBefore, content}) async {
              if (path == failsSecond.path) {
                await restoredFirst.writeAsString('external successor\n');
                return jsonEncode({'error': 'second restore failed'});
              }
              return FilesystemTools.restoreTextSnapshot(
                path: path,
                existedBefore: existedBefore,
                content: content,
              );
            },
      );
      await _completeTurn(
        store: store,
        owner: owner,
        turnId: 'external-successor-recovery-turn',
        changes: [
          (file: failsSecond, after: 'failure after\n'),
          (file: restoredFirst, after: 'restored after\n'),
        ],
      );
      final preview = (await store.previewLastFileTurnCheckpoint(owner))!;

      final failed = await store.rollbackLastFileTurnCheckpoint(
        owner,
        preview.checkpointToken,
      );
      final failedPayload = jsonDecode(failed.result) as Map<String, dynamic>;
      expect(failedPayload['recovery_required'], isTrue);
      final compensation = failedPayload['compensation'] as List<dynamic>;
      expect(
        compensation.cast<Map<String, dynamic>>().singleWhere(
          (entry) => entry['path'] == restoredFirst.path,
        )['conflict'],
        isTrue,
      );
      expect(await restoredFirst.readAsString(), 'external successor\n');
      expect(await failsSecond.readAsString(), 'failure after\n');

      final successorStarted = Completer<void>();
      final allowSuccessor = Completer<void>();
      String? observedBeforeSuccessor;
      final handler = BuiltInFilesystemToolHandler(
        checkpointStore: store,
        operationRunner: ({required name, required arguments}) async {
          observedBeforeSuccessor = await restoredFirst.readAsString();
          successorStarted.complete();
          await allowSuccessor.future;
          return FilesystemTools.writeFile(
            path: arguments['path'] as String,
            content: arguments['content'] as String,
          );
        },
      );
      final successor = handler.execute(
        name: 'write_file',
        arguments: {
          'path': restoredFirst.path,
          'content': 'queued successor\n',
        },
        owner: owner,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(successorStarted.isCompleted, isFalse);

      await store.retireConversation(owner.conversationId);
      await successorStarted.future;
      expect(observedBeforeSuccessor, 'external successor\n');
      allowSuccessor.complete();
      expect((await successor).isSuccess, isTrue);
      expect(await restoredFirst.readAsString(), 'queued successor\n');
    },
  );
}

Future<void> _completeTurn({
  required FileRollbackCheckpointStore store,
  required ChatTurnOwner owner,
  required String turnId,
  required List<({File file, String after})> changes,
}) async {
  store.beginFileTurnCheckpoint(owner, turnId);
  for (final change in changes) {
    store.push(
      owner,
      await FilesystemTools.captureTextSnapshot(change.file.path),
    );
    await change.file.writeAsString(change.after);
  }
  expect(store.endFileTurnCheckpoint(owner), isTrue);
}

final class _RecoveryOwnerFacade with McpToolServiceOwnerFacade {
  _RecoveryOwnerFacade(this.filesystemToolHandler);

  @override
  final BuiltInFilesystemToolHandler filesystemToolHandler;

  @override
  final BuiltInLocalCommandToolHandler localCommandToolHandler =
      BuiltInLocalCommandToolHandler();

  @override
  BackgroundProcessMonitorService? get backgroundProcessMonitorService => null;

  @override
  BackgroundProcessTools? get backgroundProcessTools => null;
}
