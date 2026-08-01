import 'dart:async';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/built_in_filesystem_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/file_mutation_runtime_contract.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/dart_project_tooling.dart';
import 'package:caverno/features/chat/domain/services/file_mutation_tool_handler.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDirectory;
  late ChatTurnOwner owner;

  setUp(() async {
    final createdDirectory = await Directory.systemTemp.createTemp(
      'filesystem_mutation_effect_boundary_test_',
    );
    tempDirectory = Directory(await createdDirectory.resolveSymbolicLinks());
    owner = ChatTurnOwner(
      conversationId: 'file-effect-boundary',
      interactionGeneration: 7,
    );
  });

  tearDown(() async {
    if (tempDirectory.existsSync()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('raw effect records exactly one explicit rollback checkpoint', () async {
    final file = File('${tempDirectory.path}/target.txt')
      ..writeAsStringSync('before\n');
    final handler = BuiltInFilesystemToolHandler();
    final operation = _writeOperation(file.path, 'after\n');
    final identity = _identity(owner, operation, tempDirectory.path);
    final capture = await _capture(handler, identity);
    var effectStarts = 0;
    final authorization = FileMutationEffectAuthorization(
      identity: identity,
      beginEffect: () {
        effectStarts++;
        return true;
      },
    );

    final execution = await handler.executeRawFileMutation(
      FileMutationEffectRequest(
        operationRequest: FileMutationRuntimeOperationRequest(
          identity: identity,
          operation: operation,
        ),
        capture: capture,
      ),
      authorization,
    );

    expect(effectStarts, 1);
    expect(authorization.started, isTrue);
    expect(
      execution.effectDisposition,
      FileMutationRawEffectDisposition.applied,
    );
    expect(execution.postcondition?.identity, identity);
    expect(
      execution.postcondition?.compensationToken,
      capture.compensationToken,
    );
    expect(await file.readAsString(), 'after\n');
    expect(
      await handler.checkpointStore.previewFileRollbackCheckpoint(owner),
      isNull,
      reason: 'Raw execution must not record the legacy checkpoint.',
    );

    final recordRequest = FileMutationRollbackRecordRequest(
      capture: capture,
      expectedAfterFingerprint: execution.postcondition!.afterFingerprint,
    );
    final firstRecord = await handler.recordFileMutation(recordRequest);
    final repeatedRecord = await handler.recordFileMutation(recordRequest);

    expect(
      firstRecord.disposition,
      FileMutationRuntimeAcknowledgementDisposition.completed,
    );
    expect(
      repeatedRecord.disposition,
      FileMutationRuntimeAcknowledgementDisposition.completed,
    );
    expect(
      repeatedRecord.value?.recordToken,
      firstRecord.value?.recordToken,
      reason: 'Retrying the exact record handoff must be idempotent.',
    );
    expect(
      await handler.checkpointStore.previewFileRollbackCheckpoint(owner),
      isNotNull,
    );

    final rollback = await handler.execute(
      name: 'rollback_last_file_change',
      arguments: const {},
      owner: owner,
    );

    expect(rollback.isSuccess, isTrue);
    expect(await file.readAsString(), 'before\n');
    expect(
      await handler.checkpointStore.previewFileRollbackCheckpoint(owner),
      isNull,
      reason: 'A duplicate checkpoint would survive the first rollback.',
    );
  });

  test(
    'compensation restores the exact effect and removes its record',
    () async {
      final file = File('${tempDirectory.path}/target.txt')
        ..writeAsStringSync('before\n');
      final handler = BuiltInFilesystemToolHandler();
      final operation = _writeOperation(file.path, 'after\n');
      final identity = _identity(owner, operation, tempDirectory.path);
      final capture = await _capture(handler, identity);
      final execution = await _execute(handler, identity, operation, capture);
      final postcondition = execution.postcondition!;
      handler.checkpointStore.beginFileTurnCheckpoint(owner, 'turn-7');
      final record = await handler.recordFileMutation(
        FileMutationRollbackRecordRequest(
          capture: capture,
          expectedAfterFingerprint: postcondition.afterFingerprint,
        ),
      );
      expect(handler.checkpointStore.endFileTurnCheckpoint(owner), isTrue);
      final peerOwner = ChatTurnOwner(
        conversationId: owner.conversationId,
        interactionGeneration: owner.interactionGeneration + 1,
      );
      expect(
        handler.checkpointStore.removeRecordedMutation(
          peerOwner,
          recordToken: record.value!.recordToken,
          compensationToken: capture.compensationToken,
        ),
        isFalse,
      );
      expect(
        await handler.checkpointStore.previewLastFileTurnCheckpoint(owner),
        isNotNull,
      );

      final compensation = await handler.compensateFileMutation(
        FileMutationCompensationRequest(
          capture: capture,
          expectedAfterFingerprint: postcondition.afterFingerprint,
          recordToken: record.value!.recordToken,
        ),
      );

      expect(
        compensation.disposition,
        FileMutationRuntimeCompensationDisposition.reverted,
      );
      expect(compensation.identity, identity);
      expect(compensation.compensationToken, capture.compensationToken);
      expect(await file.readAsString(), 'before\n');
      expect(
        await handler.checkpointStore.previewFileRollbackCheckpoint(owner),
        isNull,
      );
      expect(
        await handler.checkpointStore.previewLastFileTurnCheckpoint(owner),
        isNull,
      );
    },
  );

  test(
    'reports a partial effect and still exposes safe compensation',
    () async {
      final file = File('${tempDirectory.path}/target.txt')
        ..writeAsStringSync('before\n');
      final handler = BuiltInFilesystemToolHandler(
        operationRunner: ({required name, required arguments}) async {
          await FilesystemTools.writeFile(
            path: arguments['path'] as String,
            content: arguments['content'] as String,
            createParents: arguments['create_parents'] as bool,
          );
          throw StateError('runner failed after write');
        },
      );
      final operation = _writeOperation(file.path, 'partial\n');
      final identity = _identity(owner, operation, tempDirectory.path);
      final capture = await _capture(handler, identity);

      final execution = await _execute(handler, identity, operation, capture);

      expect(
        execution.effectDisposition,
        FileMutationRawEffectDisposition.partialOrUnknown,
      );
      expect(execution.result.isSuccess, isFalse);
      expect(execution.postcondition, isNotNull);
      expect(await file.readAsString(), 'partial\n');

      final compensation = await handler.compensateFileMutation(
        FileMutationCompensationRequest(
          capture: capture,
          expectedAfterFingerprint: execution.postcondition!.afterFingerprint,
          recordToken: null,
        ),
      );

      expect(
        compensation.disposition,
        FileMutationRuntimeCompensationDisposition.reverted,
      );
      expect(await file.readAsString(), 'before\n');
    },
  );

  test('refuses compensation after a successor changes the target', () async {
    final file = File('${tempDirectory.path}/target.txt')
      ..writeAsStringSync('before\n');
    final handler = BuiltInFilesystemToolHandler();
    final operation = _writeOperation(file.path, 'after\n');
    final identity = _identity(owner, operation, tempDirectory.path);
    final capture = await _capture(handler, identity);
    final execution = await _execute(handler, identity, operation, capture);
    file.writeAsStringSync('successor\n');

    final compensation = await handler.compensateFileMutation(
      FileMutationCompensationRequest(
        capture: capture,
        expectedAfterFingerprint: execution.postcondition!.afterFingerprint,
        recordToken: null,
      ),
    );

    expect(
      compensation.disposition,
      FileMutationRuntimeCompensationDisposition.fingerprintConflict,
    );
    expect(await file.readAsString(), 'successor\n');
  });

  test(
    'queues a successor mutation until compensation releases the path',
    () async {
      final file = File('${tempDirectory.path}/target.txt')
        ..writeAsStringSync('before\n');
      final restoreStarted = Completer<void>();
      final allowRestore = Completer<void>();
      final successorStarted = Completer<void>();
      var operationStarts = 0;
      final handler = BuiltInFilesystemToolHandler(
        operationRunner: ({required name, required arguments}) async {
          operationStarts++;
          if (operationStarts == 2) {
            successorStarted.complete();
          }
          return FilesystemTools.writeFile(
            path: arguments['path'] as String,
            content: arguments['content'] as String,
            createParents: arguments['create_parents'] as bool,
          );
        },
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
      final operation = _writeOperation(file.path, 'after\n');
      final identity = _identity(owner, operation, tempDirectory.path);
      final capture = await _capture(handler, identity);
      final execution = await _execute(handler, identity, operation, capture);

      final compensationFuture = handler.compensateFileMutation(
        FileMutationCompensationRequest(
          capture: capture,
          expectedAfterFingerprint: execution.postcondition!.afterFingerprint,
          recordToken: null,
        ),
      );
      await restoreStarted.future;
      final successorFuture = handler.execute(
        name: 'write_file',
        arguments: {'path': file.path, 'content': 'successor\n'},
        owner: owner,
      );

      await Future<void>.delayed(Duration.zero);
      expect(successorStarted.isCompleted, isFalse);
      allowRestore.complete();

      final compensation = await compensationFuture;
      final successor = await successorFuture;
      expect(
        compensation.disposition,
        FileMutationRuntimeCompensationDisposition.reverted,
      );
      expect(successor.isSuccess, isTrue);
      expect(successorStarted.isCompleted, isTrue);
      expect(await file.readAsString(), 'successor\n');
    },
  );

  test(
    'queues a successor until rollback recording releases the path',
    () async {
      final file = File('${tempDirectory.path}/target.txt')
        ..writeAsStringSync('before\n');
      final recordReadStarted = Completer<void>();
      final allowRecordRead = Completer<void>();
      final successorStarted = Completer<void>();
      var snapshotReads = 0;
      var operationStarts = 0;
      final handler = BuiltInFilesystemToolHandler(
        snapshotReader: (path) async {
          snapshotReads++;
          if (snapshotReads == 4) {
            recordReadStarted.complete();
            await allowRecordRead.future;
          }
          return FilesystemTools.captureTextSnapshot(path);
        },
        operationRunner: ({required name, required arguments}) async {
          operationStarts++;
          if (operationStarts == 2) successorStarted.complete();
          return FilesystemTools.writeFile(
            path: arguments['path'] as String,
            content: arguments['content'] as String,
            createParents: arguments['create_parents'] as bool,
          );
        },
      );
      final operation = _writeOperation(file.path, 'after\n');
      final identity = _identity(owner, operation, tempDirectory.path);
      final capture = await _capture(handler, identity);
      final execution = await _execute(handler, identity, operation, capture);
      final recordFuture = handler.recordFileMutation(
        FileMutationRollbackRecordRequest(
          capture: capture,
          expectedAfterFingerprint: execution.postcondition!.afterFingerprint,
        ),
      );
      await recordReadStarted.future;
      final successorFuture = handler.execute(
        name: 'write_file',
        arguments: {'path': file.path, 'content': 'successor\n'},
        owner: owner,
      );

      await Future<void>.delayed(Duration.zero);
      expect(successorStarted.isCompleted, isFalse);
      allowRecordRead.complete();
      final record = await recordFuture;
      final successor = await successorFuture;

      expect(
        record.disposition,
        FileMutationRuntimeAcknowledgementDisposition.completed,
      );
      expect(successor.isSuccess, isTrue);
      expect(await file.readAsString(), 'successor\n');
    },
  );

  test('rejects a mismatched effect authorization before mutation', () async {
    final file = File('${tempDirectory.path}/target.txt')
      ..writeAsStringSync('before\n');
    final handler = BuiltInFilesystemToolHandler();
    final operation = _writeOperation(file.path, 'after\n');
    final identity = _identity(owner, operation, tempDirectory.path);
    final capture = await _capture(handler, identity);
    final otherIdentity = _identity(
      ChatTurnOwner(
        conversationId: owner.conversationId,
        interactionGeneration: owner.interactionGeneration + 1,
      ),
      operation,
      tempDirectory.path,
    );
    final authorization = FileMutationEffectAuthorization(
      identity: otherIdentity,
      beginEffect: () => true,
    );

    await expectLater(
      handler.executeRawFileMutation(
        FileMutationEffectRequest(
          operationRequest: FileMutationRuntimeOperationRequest(
            identity: identity,
            operation: operation,
          ),
          capture: capture,
        ),
        authorization,
      ),
      throwsArgumentError,
    );

    expect(authorization.attempted, isFalse);
    expect(await file.readAsString(), 'before\n');
  });

  test('legacy owner-bound mutation still records automatically', () async {
    final file = File('${tempDirectory.path}/legacy.txt')
      ..writeAsStringSync('before\n');
    final handler = BuiltInFilesystemToolHandler();

    final result = await handler.execute(
      name: 'write_file',
      arguments: {'path': file.path, 'content': 'after\n'},
      owner: owner,
    );

    expect(result.isSuccess, isTrue);
    expect(await file.readAsString(), 'after\n');
    expect(
      await handler.checkpointStore.previewFileRollbackCheckpoint(owner),
      isNotNull,
    );
    final rollback = await handler.execute(
      name: 'rollback_last_file_change',
      arguments: const {},
      owner: owner,
    );
    expect(rollback.isSuccess, isTrue);
    expect(await file.readAsString(), 'before\n');
  });
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
    toolCallId: 'raw-mutation-call',
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

Future<FileMutationExecutionAcknowledgement> _execute(
  BuiltInFilesystemToolHandler handler,
  FileMutationRuntimeIdentity identity,
  FileMutationOperation operation,
  FileMutationRollbackCapture<TextFileSnapshot> capture,
) {
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
      beginEffect: () => true,
    ),
  );
}
