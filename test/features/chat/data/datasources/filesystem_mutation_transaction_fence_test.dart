import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/built_in_filesystem_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/file_mutation_runtime_contract.dart';
import 'package:caverno/features/chat/data/datasources/file_mutation_runtime_ports.dart';
import 'package:caverno/features/chat/data/datasources/file_mutation_runtime_state.dart';
import 'package:caverno/features/chat/data/datasources/file_rollback_checkpoint_store.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/dart_project_tooling.dart';
import 'package:caverno/features/chat/domain/services/file_mutation_effect_coordinator.dart';
import 'package:caverno/features/chat/domain/services/file_mutation_tool_handler.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDirectory;
  late ChatTurnOwner owner;

  setUp(() async {
    final createdDirectory = await Directory.systemTemp.createTemp(
      'filesystem_mutation_transaction_fence_test_',
    );
    tempDirectory = Directory(await createdDirectory.resolveSymbolicLinks());
    owner = ChatTurnOwner(
      conversationId: 'filesystem-fence',
      interactionGeneration: 11,
    );
  });

  tearDown(() async {
    if (tempDirectory.existsSync()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'keeps a successor behind the raw-to-record handoff across rebuilds',
    () async {
      final file = File('${tempDirectory.path}/handoff.txt')
        ..writeAsStringSync('before\n');
      final store = FileRollbackCheckpointStore();
      final rawHandler = BuiltInFilesystemToolHandler(checkpointStore: store);
      final successorStarted = Completer<void>();
      final rebuiltHandler = BuiltInFilesystemToolHandler(
        checkpointStore: store,
        operationRunner: ({required name, required arguments}) async {
          successorStarted.complete();
          return _runWrite(arguments);
        },
      );
      final operation = _writeOperation(file.path, 'raw\n');
      final identity = _identity(owner, operation, tempDirectory.path);
      final capture = await _capture(rawHandler, identity);
      final execution = await _executeRaw(
        rawHandler,
        identity,
        operation,
        capture,
      );

      final successorFuture = rebuiltHandler.execute(
        name: 'write_file',
        arguments: {'path': file.path, 'content': 'successor\n'},
        owner: owner,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(successorStarted.isCompleted, isFalse);
      expect(await file.readAsString(), 'raw\n');

      final record = await rawHandler.recordFileMutation(
        FileMutationRollbackRecordRequest(
          capture: capture,
          expectedAfterFingerprint: execution.postcondition!.afterFingerprint,
        ),
      );
      final successor = await successorFuture;

      expect(
        record.disposition,
        FileMutationRuntimeAcknowledgementDisposition.completed,
      );
      expect(successor.isSuccess, isTrue);
      expect(successorStarted.isCompleted, isTrue);
      expect(await file.readAsString(), 'successor\n');
    },
  );

  test(
    'rejects a duplicate transaction token without poisoning its retry',
    () async {
      final file = File('${tempDirectory.path}/duplicate.txt')
        ..writeAsStringSync('before\n');
      final fence = FileRollbackCheckpointStore().mutationPathFence;
      final first = await fence.beginTransaction(
        path: file.path,
        transactionToken: 'exact-transaction',
      );

      await expectLater(
        fence.beginTransaction(
          path: file.path,
          transactionToken: 'exact-transaction',
        ),
        throwsStateError,
      );
      fence.finishWithoutEffect(first);

      final retry = await fence.beginTransaction(
        path: file.path,
        transactionToken: 'exact-transaction',
      );
      fence.finishWithoutEffect(retry);
    },
  );

  test('rejects an unsafe reset while a path effect is active', () async {
    final file = File('${tempDirectory.path}/reset.txt')
      ..writeAsStringSync('before\n');
    final fence = FileRollbackCheckpointStore().mutationPathFence;
    final firstStarted = Completer<void>();
    final allowFirst = Completer<void>();
    final successorStarted = Completer<void>();

    final first = fence.runExclusive(file.path, () async {
      firstStarted.complete();
      await allowFirst.future;
    });
    await firstStarted.future;
    final successor = fence.runExclusive(file.path, () async {
      successorStarted.complete();
    });

    expect(fence.clearAll, throwsStateError);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(successorStarted.isCompleted, isFalse);

    allowFirst.complete();
    await first;
    await successor;
    expect(successorStarted.isCompleted, isTrue);
  });

  test(
    'close drains an active effect and rejects its queued successor',
    () async {
      final file = File('${tempDirectory.path}/close.txt')
        ..writeAsStringSync('before\n');
      final fence = FileRollbackCheckpointStore().mutationPathFence;
      final firstStarted = Completer<void>();
      final allowFirst = Completer<void>();
      var successorStarted = false;

      final first = fence.runExclusive(file.path, () async {
        firstStarted.complete();
        await allowFirst.future;
      });
      await firstStarted.future;
      final successor = fence.runExclusive(file.path, () async {
        successorStarted = true;
      });
      final close = fence.close();

      allowFirst.complete();
      await first;
      await expectLater(successor, throwsStateError);
      await close;
      expect(successorStarted, isFalse);
      await expectLater(
        fence.runExclusive(file.path, () async {}),
        throwsStateError,
      );
    },
  );

  test(
    'reconciles a started effect when its post-effect snapshot throws',
    () async {
      final file = File('${tempDirectory.path}/post_effect_throw.txt')
        ..writeAsStringSync('before\n');
      final store = FileRollbackCheckpointStore();
      var effectApplied = false;
      var postEffectReadFailed = false;
      final handler = BuiltInFilesystemToolHandler(
        checkpointStore: store,
        snapshotReader: (path) async {
          if (effectApplied && !postEffectReadFailed) {
            postEffectReadFailed = true;
            throw StateError('post-effect snapshot failed');
          }
          return FilesystemTools.captureTextSnapshot(path);
        },
        operationRunner: ({required name, required arguments}) async {
          final payload = await _runWrite(arguments);
          effectApplied = true;
          return payload;
        },
      );
      final operation = _writeOperation(file.path, 'after\n');
      final identity = _identity(owner, operation, tempDirectory.path);
      final effectCoordinator = FileMutationEffectCoordinator();
      final state = FileMutationRuntimeState(
        identity: identity,
        acknowledgeLifecycle: (candidate) => FileMutationRuntimeAcknowledgement(
          identity: candidate,
          disposition: FileMutationRuntimeAcknowledgementDisposition.completed,
        ),
        retireOwner: () {
          effectCoordinator.retireOwner(owner);
        },
      );
      final ports = FileMutationRuntimePorts<TextFileSnapshot>(
        identity: identity,
        state: state,
        effectCoordinator: effectCoordinator,
        preflightEdit: (_) async => throw StateError('unused preflight'),
        fingerprint: handler.readFileMutationFingerprint,
        isRegularFile: (_) async =>
            throw StateError('unused regular-file check'),
        captureDeleteSnapshot: (_) async =>
            throw StateError('unused delete snapshot'),
        buildPreview: (_) async => throw StateError('unused preview'),
        captureBefore: handler.captureFileMutationBefore,
        recordMutation: handler.recordFileMutation,
        execute: handler.executeRawFileMutation,
        compensate: handler.compensateFileMutation,
      );
      await ports.captureBefore(owner, file.path);

      await expectLater(
        ports.execute(owner, operation),
        throwsA(isA<FileMutationRuntimeBoundaryException>()),
      );

      expect(postEffectReadFailed, isTrue);
      expect(await file.readAsString(), 'before\n');
      expect(effectCoordinator.isPathBusy(identity.canonicalPath), isFalse);
      final successor = await handler
          .execute(
            name: 'write_file',
            arguments: {'path': file.path, 'content': 'successor\n'},
            owner: owner,
          )
          .timeout(const Duration(seconds: 1));
      expect(successor.isSuccess, isTrue);
      expect(await file.readAsString(), 'successor\n');
    },
  );

  test('single-file rollback fences a queued successor', () async {
    final file = File('${tempDirectory.path}/single.txt')
      ..writeAsStringSync('before\n');
    final restoreStarted = Completer<void>();
    final allowRestore = Completer<void>();
    final store = FileRollbackCheckpointStore(
      snapshotRestorer:
          ({required path, required existedBefore, content}) async {
            restoreStarted.complete();
            await allowRestore.future;
            return FilesystemTools.restoreTextSnapshot(
              path: path,
              existedBefore: existedBefore,
              content: content,
            );
          },
    );
    store.push(owner, await FilesystemTools.captureTextSnapshot(file.path));
    await file.writeAsString('after\n');
    final preview = (await store.previewFileRollbackCheckpoint(owner))!;
    final rollbackFuture = store.rollbackFileCheckpoint(
      owner: owner,
      expectedCheckpointToken: preview.checkpointToken,
      toolName: 'rollback_last_file_change',
    );
    await restoreStarted.future;

    final successorStarted = Completer<void>();
    final allowSuccessor = Completer<void>();
    final handler = BuiltInFilesystemToolHandler(
      checkpointStore: store,
      operationRunner: ({required name, required arguments}) async {
        successorStarted.complete();
        await allowSuccessor.future;
        return _runWrite(arguments);
      },
    );
    final successorFuture = handler.execute(
      name: 'write_file',
      arguments: {'path': file.path, 'content': 'successor\n'},
      owner: owner,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(successorStarted.isCompleted, isFalse);

    allowRestore.complete();
    final rollback = await rollbackFuture;
    await successorStarted.future;
    expect(
      rollback.disposition,
      FileRollbackCheckpointExecutionDisposition.completed,
    );
    expect(await file.readAsString(), 'before\n');

    allowSuccessor.complete();
    expect((await successorFuture).isSuccess, isTrue);
    expect(await file.readAsString(), 'successor\n');
  });

  test('whole-turn rollback fences each restored target', () async {
    final file = File('${tempDirectory.path}/turn.txt')
      ..writeAsStringSync('before\n');
    final restoreStarted = Completer<void>();
    final allowRestore = Completer<void>();
    final store = FileRollbackCheckpointStore(
      snapshotRestorer:
          ({required path, required existedBefore, content}) async {
            restoreStarted.complete();
            await allowRestore.future;
            return FilesystemTools.restoreTextSnapshot(
              path: path,
              existedBefore: existedBefore,
              content: content,
            );
          },
    );
    store.beginFileTurnCheckpoint(owner, 'turn-11');
    store.push(owner, await FilesystemTools.captureTextSnapshot(file.path));
    await file.writeAsString('after\n');
    expect(store.endFileTurnCheckpoint(owner), isTrue);
    final preview = (await store.previewLastFileTurnCheckpoint(owner))!;
    final rollbackFuture = store.rollbackLastFileTurnCheckpoint(
      owner,
      preview.checkpointToken,
    );
    await restoreStarted.future;

    final successorStarted = Completer<void>();
    final allowSuccessor = Completer<void>();
    final handler = BuiltInFilesystemToolHandler(
      checkpointStore: store,
      operationRunner: ({required name, required arguments}) async {
        successorStarted.complete();
        await allowSuccessor.future;
        return _runWrite(arguments);
      },
    );
    final successorFuture = handler.execute(
      name: 'write_file',
      arguments: {'path': file.path, 'content': 'successor\n'},
      owner: owner,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(successorStarted.isCompleted, isFalse);

    allowRestore.complete();
    final rollback = await rollbackFuture;
    await successorStarted.future;
    expect(rollback.isSuccess, isTrue);
    expect(await file.readAsString(), 'before\n');

    allowSuccessor.complete();
    expect((await successorFuture).isSuccess, isTrue);
    expect(await file.readAsString(), 'successor\n');
  });

  test('whole-turn rollback reserves every target before restoring', () async {
    final first = File('${tempDirectory.path}/first.txt')
      ..writeAsStringSync('first before\n');
    final second = File('${tempDirectory.path}/second.txt')
      ..writeAsStringSync('second before\n');
    final restoreStarted = Completer<void>();
    final allowRestore = Completer<void>();
    final store = FileRollbackCheckpointStore(
      snapshotRestorer:
          ({required path, required existedBefore, content}) async {
            if (path == second.path) {
              restoreStarted.complete();
              await allowRestore.future;
            }
            return FilesystemTools.restoreTextSnapshot(
              path: path,
              existedBefore: existedBefore,
              content: content,
            );
          },
    );
    store.beginFileTurnCheckpoint(owner, 'turn-11-two-paths');
    store.push(owner, await FilesystemTools.captureTextSnapshot(first.path));
    await first.writeAsString('first after\n');
    store.push(owner, await FilesystemTools.captureTextSnapshot(second.path));
    await second.writeAsString('second after\n');
    expect(store.endFileTurnCheckpoint(owner), isTrue);
    final preview = (await store.previewLastFileTurnCheckpoint(owner))!;
    final rollbackFuture = store.rollbackLastFileTurnCheckpoint(
      owner,
      preview.checkpointToken,
    );
    await restoreStarted.future;

    final successorStarted = Completer<void>();
    final successorHandler = BuiltInFilesystemToolHandler(
      checkpointStore: store,
      operationRunner: ({required name, required arguments}) async {
        successorStarted.complete();
        return _runWrite(arguments);
      },
    );
    final successorFuture = successorHandler.execute(
      name: 'write_file',
      arguments: {'path': first.path, 'content': 'first successor\n'},
      owner: owner,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final successorStartedBeforeRelease = successorStarted.isCompleted;
    if (successorStartedBeforeRelease) {
      await successorFuture;
    }

    allowRestore.complete();
    final rollback = await rollbackFuture;
    final successor = await successorFuture;

    expect(successorStartedBeforeRelease, isFalse);
    expect(rollback.isSuccess, isTrue);
    expect(successor.isSuccess, isTrue);
    expect(await first.readAsString(), 'first successor\n');
    expect(await second.readAsString(), 'second before\n');
  });

  test(
    'symlink aliases wait for the target fence and are rejected before effect',
    () async {
      if (Platform.isWindows) return;
      final target = File('${tempDirectory.path}/target.txt')
        ..writeAsStringSync('before\n');
      final alias = Link('${tempDirectory.path}/alias.txt')
        ..createSync(target.path);
      final store = FileRollbackCheckpointStore();
      final firstStarted = Completer<void>();
      final allowFirst = Completer<void>();
      final firstHandler = BuiltInFilesystemToolHandler(
        checkpointStore: store,
        operationRunner: ({required name, required arguments}) async {
          firstStarted.complete();
          await allowFirst.future;
          return _runWrite(arguments);
        },
      );
      final aliasStarted = Completer<void>();
      final aliasHandler = BuiltInFilesystemToolHandler(
        checkpointStore: store,
        operationRunner: ({required name, required arguments}) async {
          aliasStarted.complete();
          return _runWrite(arguments);
        },
      );

      final firstFuture = firstHandler.execute(
        name: 'write_file',
        arguments: {'path': target.path, 'content': 'target\n'},
        owner: owner,
      );
      await firstStarted.future;
      final aliasFuture = aliasHandler.execute(
        name: 'write_file',
        arguments: {'path': alias.path, 'content': 'alias\n'},
        owner: owner,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(aliasStarted.isCompleted, isFalse);

      allowFirst.complete();
      expect((await firstFuture).isSuccess, isTrue);
      expect((await aliasFuture).isSuccess, isFalse);
      expect(aliasStarted.isCompleted, isFalse);
      expect(await target.readAsString(), 'target\n');
      expect(
        (await store.previewFileRollbackCheckpoint(owner))!.path,
        target.absolute.path,
      );
    },
  );

  test(
    'whole-turn rollback rejects an equal-content symlink retarget',
    () async {
      if (Platform.isWindows) return;
      final retargeted = File('${tempDirectory.path}/retargeted.txt')
        ..writeAsStringSync('before\n');
      final peer = File('${tempDirectory.path}/retarget-peer.txt')
        ..writeAsStringSync('peer before\n');
      final external = File('${tempDirectory.path}/external.txt')
        ..writeAsStringSync('after\n');
      final store = FileRollbackCheckpointStore();
      store.beginFileTurnCheckpoint(owner, 'symlink-retarget-turn');
      store.push(
        owner,
        await FilesystemTools.captureTextSnapshot(retargeted.path),
      );
      await retargeted.writeAsString('after\n');
      store.push(owner, await FilesystemTools.captureTextSnapshot(peer.path));
      await peer.writeAsString('peer after\n');
      expect(store.endFileTurnCheckpoint(owner), isTrue);
      final preview = (await store.previewLastFileTurnCheckpoint(owner))!;

      await retargeted.delete();
      await Link(retargeted.path).create(external.path);
      final result = await store.rollbackLastFileTurnCheckpoint(
        owner,
        preview.checkpointToken,
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('preview it again'));
      expect(await external.readAsString(), 'after\n');
      expect(await peer.readAsString(), 'peer after\n');
    },
  );

  for (final restoreFailure in ['throw', 'error-payload']) {
    test(
      'reconciles exact before-state after $restoreFailure and releases fence',
      () async {
        final file = File('${tempDirectory.path}/compensate.txt')
          ..writeAsStringSync('before\n');
        final store = FileRollbackCheckpointStore();
        final rawHandler = BuiltInFilesystemToolHandler(
          checkpointStore: store,
          snapshotRestorer:
              ({required path, required existedBefore, content}) async {
                await FilesystemTools.restoreTextSnapshot(
                  path: path,
                  existedBefore: existedBefore,
                  content: content,
                );
                if (restoreFailure == 'throw') {
                  throw StateError('restorer failed after dispatch');
                }
                return jsonEncode({'error': 'reported after restore'});
              },
        );
        final operation = _writeOperation(file.path, 'raw\n');
        final identity = _identity(owner, operation, tempDirectory.path);
        final capture = await _capture(rawHandler, identity);
        final effectCoordinator = FileMutationEffectCoordinator();
        final coordinatorIdentity = FileMutationOperationIdentity(
          owner: owner,
          toolCallId: identity.toolCallId,
          toolName: identity.toolName,
          canonicalPath: identity.canonicalPath,
        );
        final lease = effectCoordinator
            .acquire(
              coordinatorIdentity,
              beforeFingerprint: capture.beforeFingerprint,
            )
            .lease!;
        final execution = await _executeRaw(
          rawHandler,
          identity,
          operation,
          capture,
          beginEffect: () =>
              effectCoordinator.beginEffect(coordinatorIdentity, lease),
        );
        final appliedReceipt = effectCoordinator
            .markApplied(
              coordinatorIdentity,
              lease,
              expectedAfterFingerprint:
                  execution.postcondition!.afterFingerprint,
              compensationToken: capture.compensationToken,
            )
            .receipt!;
        final recordToken = store.recordMutationSnapshot(
          owner,
          capture.snapshot,
          compensationToken: capture.compensationToken,
        );
        expect(recordToken, isNotNull);

        final successorStarted = Completer<void>();
        final allowSuccessor = Completer<void>();
        final successorHandler = BuiltInFilesystemToolHandler(
          checkpointStore: store,
          operationRunner: ({required name, required arguments}) async {
            successorStarted.complete();
            await allowSuccessor.future;
            return _runWrite(arguments);
          },
        );
        final successorFuture = successorHandler.execute(
          name: 'write_file',
          arguments: {'path': file.path, 'content': 'successor\n'},
          owner: owner,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(successorStarted.isCompleted, isFalse);

        expect(
          effectCoordinator.beginCompensation(
            coordinatorIdentity,
            appliedReceipt,
            observedCurrentFingerprint:
                execution.postcondition!.afterFingerprint,
          ),
          FileMutationCompensationDisposition.ready,
        );
        final compensation = await rawHandler.compensateFileMutation(
          FileMutationCompensationRequest(
            capture: capture,
            expectedAfterFingerprint: execution.postcondition!.afterFingerprint,
            recordToken: recordToken,
          ),
        );
        await successorStarted.future;

        expect(
          compensation.disposition,
          FileMutationRuntimeCompensationDisposition.reverted,
        );
        expect(
          effectCoordinator.completeCompensation(
            coordinatorIdentity,
            appliedReceipt,
            succeeded:
                compensation.disposition ==
                FileMutationRuntimeCompensationDisposition.reverted,
          ),
          FileMutationCompensationDisposition.reverted,
        );
        expect(effectCoordinator.isPathBusy(identity.canonicalPath), isFalse);
        expect(await file.readAsString(), 'before\n');
        expect(
          await store.previewFileRollbackCheckpoint(owner),
          isNull,
          reason: 'The exact runtime checkpoint must be cleared.',
        );

        allowSuccessor.complete();
        expect((await successorFuture).isSuccess, isTrue);
        expect(await file.readAsString(), 'successor\n');
      },
    );
  }
}

Future<String> _runWrite(Map<String, dynamic> arguments) {
  return FilesystemTools.writeFile(
    path: arguments['path'] as String,
    content: arguments['content'] as String,
    createParents: arguments['create_parents'] as bool? ?? true,
  );
}

FileMutationOperation _writeOperation(String path, String content) {
  return FileMutationOperation(
    kind: FileMutationKind.writeFile,
    arguments: {
      'path': File(path).absolute.path,
      'content': content,
      'create_parents': true,
    },
  );
}

FileMutationRuntimeIdentity _identity(
  ChatTurnOwner owner,
  FileMutationOperation operation,
  String projectRoot,
) {
  final digest = fileMutationJsonDigest(operation.arguments);
  return FileMutationRuntimeIdentity(
    owner: owner,
    toolCallId: 'transaction-fence-call',
    toolName: operation.toolName,
    argumentDigest: digest,
    resolvedArgumentDigest: digest,
    projectRoot: Directory(projectRoot).absolute.path,
    canonicalPath: DartProjectPath.pathKey(operation.path),
    approvalContextDigest: 'approval-context',
  );
}

Future<FileMutationRollbackCapture<TextFileSnapshot>> _capture(
  BuiltInFilesystemToolHandler handler,
  FileMutationRuntimeIdentity identity,
) async {
  final acknowledgement = await handler.captureFileMutationBefore(identity);
  expect(
    acknowledgement.disposition,
    FileMutationRuntimeAcknowledgementDisposition.completed,
  );
  return acknowledgement.value!;
}

Future<FileMutationExecutionAcknowledgement> _executeRaw(
  BuiltInFilesystemToolHandler handler,
  FileMutationRuntimeIdentity identity,
  FileMutationOperation operation,
  FileMutationRollbackCapture<TextFileSnapshot> capture, {
  bool Function()? beginEffect,
}) {
  return handler.executeRawFileMutation(
    FileMutationEffectRequest(
      operationRequest: FileMutationRuntimeOperationRequest(
        identity: identity,
        operation: operation,
      ),
      capture: capture,
    ),
    FileMutationEffectAuthorization(
      identity: identity,
      beginEffect: beginEffect ?? () => true,
    ),
  );
}
