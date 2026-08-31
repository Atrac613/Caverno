import 'dart:io';

import 'package:caverno/features/chat/data/datasources/built_in_filesystem_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/data/datasources/first_party_tool_execution_result.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _OperationCall = ({String name, Map<String, dynamic> arguments});

void main() {
  group('BuiltInFilesystemToolHandler', () {
    final owner = ChatTurnOwner(
      conversationId: 'filesystem-handler',
      interactionGeneration: 1,
    );

    test('owns the exact split filesystem family', () {
      final handler = BuiltInFilesystemToolHandler(
        operationRunner: ({required name, required arguments}) async => '',
      );

      expect(
        handler.inspectionDefinitions.map(_definitionName),
        BuiltInFilesystemToolHandler.inspectionToolNames,
      );
      expect(
        handler.mutationDefinitions.map(_definitionName),
        BuiltInFilesystemToolHandler.mutationToolNames,
      );
      expect(BuiltInFilesystemToolHandler.toolNames, [
        ...BuiltInFilesystemToolHandler.inspectionToolNames,
        ...BuiltInFilesystemToolHandler.mutationToolNames,
      ]);
      for (final name in BuiltInFilesystemToolHandler.toolNames) {
        expect(handler.handles(name), isTrue, reason: name);
      }
      expect(handler.handles('resolve_installed_dependency'), isFalse);
    });

    test('carries whether a mutation actually changed the file', () async {
      // The whole point of the fact: a byte-identical write succeeds and looks
      // exactly like a real one, so without this a no-op edit reads as
      // progress and the edit/re-read loop has nothing to stop it.
      Future<McpToolResult> run(String payload, {ToolOutcome? outcome}) {
        final handler = BuiltInFilesystemToolHandler(
          operationResultRunner: ({required name, required arguments}) async =>
              FirstPartyToolExecutionResult(result: payload, outcome: outcome),
          snapshotReader: (path) async =>
              TextFileSnapshot(path: path, exists: false),
        );
        return handler.execute(
          name: 'write_file',
          arguments: const {'path': '/tmp/x.txt', 'content': 'hello'},
        );
      }

      final changed = await run(
        '{"path":"/tmp/x.txt","changed":true}',
        outcome: const ToolOutcome(
          fileMutations: [ToolFileMutation(path: '/tmp/x.txt', changed: true)],
        ),
      );
      final unchanged = await run(
        '{"path":"/tmp/x.txt","changed":false}',
        outcome: const ToolOutcome(
          fileMutations: [ToolFileMutation(path: '/tmp/x.txt', changed: false)],
        ),
      );
      final silent = await run('{"path":"/tmp/x.txt"}');
      final failed = await run('{"error":"permission denied"}');

      expect(changed.outcome?.effectiveFileChanged, isTrue);
      expect(unchanged.outcome?.effectiveFileChanged, isFalse);
      expect(unchanged.outcome?.isNoOpMutation, isTrue);
      // Absent means unknown, never "unchanged".
      expect(silent.outcome, isNull);
      expect(failed.outcome, isNull);
    });

    test('carries the whole-file hash a read reported', () async {
      Future<McpToolResult> run(String payload, {ToolOutcome? outcome}) {
        final handler = BuiltInFilesystemToolHandler(
          operationResultRunner: ({required name, required arguments}) async =>
              FirstPartyToolExecutionResult(result: payload, outcome: outcome),
        );
        return handler.execute(
          name: 'read_file',
          arguments: const {'path': '/tmp/x.dart'},
        );
      }

      final hashed = await run(
        '{"path":"/tmp/x.dart","content":"x","content_hash":"abc"}',
        outcome: const ToolOutcome(
          readOutcome: ToolReadOutcome(
            path: '/tmp/x.dart',
            contentHash: 'abc',
            byteSize: 1,
            lineCount: 1,
          ),
        ),
      );
      final legacy = await run('{"path":"/tmp/x.dart","content":"x"}');
      final missing = await run('{"error":"File does not exist: /tmp/x.dart"}');

      expect(hashed.outcome?.effectiveContentHash, 'abc');
      expect(hashed.outcome?.readOutcome?.byteSize, 1);
      expect(hashed.isSuccess, isTrue);
      // A read reports no failure, so success is unchanged in every case; only
      // the identity of what was read is new.
      expect(legacy.isSuccess, isTrue);
      expect(legacy.outcome, isNull);
      expect(missing.isSuccess, isTrue);
      expect(missing.outcome, isNull);
    });

    test(
      'rejects missing required arguments without invoking dependencies',
      () async {
        final calls = <_OperationCall>[];
        final snapshotPaths = <String>[];
        final handler = BuiltInFilesystemToolHandler(
          operationRunner: ({required name, required arguments}) async {
            calls.add((name: name, arguments: arguments));
            return 'unexpected';
          },
          snapshotReader: (path) async {
            snapshotPaths.add(path);
            return TextFileSnapshot(path: path, exists: false);
          },
        );
        const cases = [
          ('list_directory', <String, dynamic>{}, 'path is required'),
          ('read_file', <String, dynamic>{}, 'path is required'),
          ('inspect_file', <String, dynamic>{}, 'path is required'),
          ('write_file', <String, dynamic>{}, 'path is required'),
          ('edit_file', <String, dynamic>{}, 'path is required'),
          ('delete_file', <String, dynamic>{}, 'path is required'),
          ('find_files', <String, dynamic>{}, 'path and pattern are required'),
          ('search_files', <String, dynamic>{}, 'path and query are required'),
          (
            'rollback_last_file_change',
            <String, dynamic>{},
            'No recent file change is available to roll back',
          ),
        ];

        for (final testCase in cases) {
          final result = await handler.execute(
            name: testCase.$1,
            arguments: testCase.$2,
          );
          expect(result.toolName, testCase.$1);
          expect(result.result, isEmpty);
          expect(result.isSuccess, isFalse);
          expect(result.errorMessage, testCase.$3);
        }
        expect(calls, isEmpty);
        expect(snapshotPaths, isEmpty);
      },
    );

    test('normalizes every operation before invoking the runner', () async {
      final calls = <_OperationCall>[];
      final snapshotPaths = <String>[];
      final handler = BuiltInFilesystemToolHandler(
        operationRunner: ({required name, required arguments}) async {
          calls.add((
            name: name,
            arguments: Map<String, dynamic>.from(arguments),
          ));
          return '{}';
        },
        snapshotReader: (path) async {
          snapshotPaths.add(path);
          return TextFileSnapshot(path: path, exists: false);
        },
      );
      final cases =
          <
            ({
              String name,
              Map<String, dynamic> arguments,
              Map<String, dynamic> normalized,
              bool capturesSnapshot,
            })
          >[
            (
              name: 'list_directory',
              arguments: {
                'path': ' /tmp/project ',
                'recursive': true,
                'max_entries': 9999,
              },
              normalized: {
                'path': '/tmp/project',
                'recursive': true,
                'max_entries': 1000,
              },
              capturesSnapshot: false,
            ),
            (
              name: 'read_file',
              arguments: {
                'path': ' /tmp/file.txt ',
                'max_chars': 1,
                'offset': 0,
                'limit': 99999,
                'start_page': 0,
              },
              normalized: {
                'path': '/tmp/file.txt',
                'max_chars': 100,
                'offset': 1,
                'limit': 20000,
                'start_page': 1,
              },
              capturesSnapshot: false,
            ),
            (
              name: 'inspect_file',
              arguments: {
                'path': ' /tmp/file.txt ',
                'head_lines': 999,
                'tail_lines': -1,
              },
              normalized: {
                'path': '/tmp/file.txt',
                'head_lines': 100,
                'tail_lines': 0,
              },
              capturesSnapshot: false,
            ),
            (
              name: 'write_file',
              arguments: {'path': ' /tmp/new.txt ', 'content': 'contents'},
              normalized: {
                'path': '/tmp/new.txt',
                'content': 'contents',
                'create_parents': true,
              },
              capturesSnapshot: true,
            ),
            (
              name: 'edit_file',
              arguments: {
                'path': ' /tmp/edit.txt ',
                'old_text': 'old',
                'new_text': 'new',
              },
              normalized: {
                'path': '/tmp/edit.txt',
                'old_text': 'old',
                'new_text': 'new',
                'replace_all': false,
              },
              capturesSnapshot: true,
            ),
            (
              name: 'delete_file',
              arguments: {'path': ' /tmp/delete.txt ', 'reason': 'cleanup'},
              normalized: {'path': '/tmp/delete.txt'},
              capturesSnapshot: true,
            ),
            (
              name: 'find_files',
              arguments: {
                'path': ' /tmp/project ',
                'pattern': ' *.dart ',
                'max_results': 0,
              },
              normalized: {
                'path': '/tmp/project',
                'pattern': '*.dart',
                'recursive': true,
                'max_results': 1,
              },
              capturesSnapshot: false,
            ),
            (
              name: 'search_files',
              arguments: {
                'path': ' /tmp/project ',
                'query': ' needle ',
                'file_pattern': ' *.dart ',
                'case_sensitive': true,
                'max_results': 9999,
                'offset': 9999999,
                'max_line_length': 1,
                'max_bytes_scanned': 12345,
              },
              normalized: {
                'path': '/tmp/project',
                'query': 'needle',
                'file_pattern': '*.dart',
                'case_sensitive': true,
                'max_results': 1000,
                'offset': 1000000,
                'max_line_length': 40,
                'max_bytes_scanned': 12345,
              },
              capturesSnapshot: false,
            ),
          ];

      for (final testCase in cases) {
        calls.clear();
        snapshotPaths.clear();
        final result = await handler.execute(
          name: testCase.name,
          arguments: testCase.arguments,
        );
        expect(result.toolName, testCase.name);
        expect(result.result, '{}');
        expect(result.isSuccess, isTrue);
        expect(calls, hasLength(1));
        expect(calls.single.name, testCase.name);
        expect(calls.single.arguments, testCase.normalized);
        expect(
          snapshotPaths,
          testCase.capturesSnapshot ? [testCase.normalized['path']] : isEmpty,
        );
      }
    });

    test('pushes snapshots only for successful mutations', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'built_in_filesystem_handler_snapshot_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final targetPath = '${tempDir.path}/target.txt';

      BuiltInFilesystemToolHandler handlerReturning(
        String payload, {
        ToolOutcome? outcome,
      }) {
        return BuiltInFilesystemToolHandler(
          operationResultRunner: ({required name, required arguments}) async =>
              FirstPartyToolExecutionResult(result: payload, outcome: outcome),
          snapshotReader: (path) async =>
              TextFileSnapshot(path: path, exists: false),
        );
      }

      final failedWrite = handlerReturning('{"error":"failed"}');
      final failedWriteResult = await failedWrite.execute(
        name: 'write_file',
        arguments: {'path': targetPath, 'content': 'content'},
        owner: owner,
      );
      expect(failedWriteResult.isSuccess, isTrue);
      expect(
        await failedWrite.checkpointStore.previewLastFileRollbackChange(owner),
        isNull,
      );

      final alreadyApplied = handlerReturning(
        '{"already_applied":true,"changed":false}',
        outcome: const ToolOutcome(
          fileMutations: [
            ToolFileMutation(path: '/tmp/target.txt', changed: false),
          ],
        ),
      );
      final alreadyAppliedResult = await alreadyApplied.execute(
        name: 'edit_file',
        arguments: {'path': targetPath, 'old_text': 'old', 'new_text': 'new'},
        owner: owner,
      );
      expect(alreadyAppliedResult.isSuccess, isTrue);
      expect(alreadyAppliedResult.outcome?.effectiveFileChanged, isFalse);
      expect(alreadyAppliedResult.outcome?.isNoOpMutation, isTrue);
      expect(
        await alreadyApplied.checkpointStore.previewLastFileRollbackChange(
          owner,
        ),
        isNull,
      );

      final failedDelete = handlerReturning('{"error":"failed"}');
      final failedDeleteResult = await failedDelete.execute(
        name: 'delete_file',
        arguments: {'path': targetPath},
        owner: owner,
      );
      expect(failedDeleteResult.isSuccess, isFalse);
      expect(failedDeleteResult.errorMessage, 'Failed to delete file');
      expect(
        await failedDelete.checkpointStore.previewLastFileRollbackChange(owner),
        isNull,
      );

      final successfulWrite = handlerReturning('{}');
      final successfulWriteResult = await successfulWrite.execute(
        name: 'write_file',
        arguments: {'path': targetPath, 'content': 'content'},
        owner: owner,
      );
      expect(successfulWriteResult.isSuccess, isTrue);
      expect(
        await successfulWrite.checkpointStore.previewLastFileRollbackChange(
          owner,
        ),
        isNotNull,
      );
    });

    test('owns the turn checkpoint used by mutation execution', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'built_in_filesystem_handler_checkpoint_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final changed = File('${tempDir.path}/changed.txt')
        ..writeAsStringSync('before\n');
      final created = File('${tempDir.path}/created.txt');
      final deleted = File('${tempDir.path}/deleted.txt')
        ..writeAsStringSync('restore\n');
      final handler = BuiltInFilesystemToolHandler();

      handler.checkpointStore.beginFileTurnCheckpoint(owner, ' turn-1 ');
      await handler.execute(
        name: 'write_file',
        arguments: {'path': changed.path, 'content': 'after\n'},
        owner: owner,
      );
      await handler.execute(
        name: 'edit_file',
        arguments: {
          'path': changed.path,
          'old_text': 'after',
          'new_text': 'final',
        },
        owner: owner,
      );
      await handler.execute(
        name: 'write_file',
        arguments: {'path': created.path, 'content': 'created\n'},
        owner: owner,
      );
      await handler.execute(
        name: 'delete_file',
        arguments: {'path': deleted.path},
        owner: owner,
      );
      handler.checkpointStore.endFileTurnCheckpoint(owner);

      final preview = await handler.checkpointStore
          .previewLastFileTurnCheckpoint(owner);
      expect(preview, isNotNull);
      expect(preview!.turnId, 'turn-1');
      expect(preview.paths, [
        changed.absolute.path,
        created.absolute.path,
        deleted.absolute.path,
      ]);

      final result = await handler.checkpointStore
          .rollbackLastFileTurnCheckpoint(owner, preview.checkpointToken);
      expect(result.isSuccess, isTrue);
      expect(await changed.readAsString(), 'before\n');
      expect(created.existsSync(), isFalse);
      expect(await deleted.readAsString(), 'restore\n');
    });

    test(
      'does not record ownerless mutations in chat rollback history',
      () async {
        final handler = BuiltInFilesystemToolHandler(
          operationRunner: ({required name, required arguments}) async => '{}',
          snapshotReader: (path) async =>
              TextFileSnapshot(path: path, exists: false),
        );

        final result = await handler.execute(
          name: 'write_file',
          arguments: const {'path': '/tmp/ownerless.txt', 'content': 'content'},
        );

        expect(result.isSuccess, isTrue);
        expect(
          await handler.checkpointStore.previewLastFileRollbackChange(owner),
          isNull,
        );
      },
    );

    test('propagates runner exceptions and rejects unknown operations', () {
      final handler = BuiltInFilesystemToolHandler(
        operationRunner: ({required name, required arguments}) async {
          throw StateError('filesystem runner failed');
        },
      );

      expect(
        () => handler.execute(
          name: 'read_file',
          arguments: const {'path': '/tmp/file.txt'},
        ),
        throwsStateError,
      );
      expect(
        () => handler.execute(
          name: 'resolve_installed_dependency',
          arguments: const {},
        ),
        throwsArgumentError,
      );
    });
  });

  test(
    'McpToolService delegates filesystem execution to the handler',
    () async {
      final calls = <_OperationCall>[];
      final handler = BuiltInFilesystemToolHandler(
        operationRunner: ({required name, required arguments}) async {
          calls.add((name: name, arguments: arguments));
          return '{"content":"data"}';
        },
      );
      final service = McpToolService(filesystemToolHandler: handler);

      final result = await service.executeTool(
        name: 'read_file',
        arguments: const {'path': ' /tmp/file.txt '},
      );

      expect(result.isSuccess, isTrue);
      expect(result.result, '{"content":"data"}');
      expect(calls, hasLength(1));
      expect(calls.single.name, 'read_file');
      expect(calls.single.arguments, {
        'path': '/tmp/file.txt',
        'max_chars': 120000,
        'offset': 1,
        'limit': null,
        'start_page': 1,
      });
    },
  );
}

String _definitionName(Map<String, dynamic> tool) =>
    (tool['function']! as Map<String, dynamic>)['name']! as String;
