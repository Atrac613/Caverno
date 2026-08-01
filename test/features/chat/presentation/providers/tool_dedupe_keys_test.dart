import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_call_execution_policy.dart';
import 'package:caverno/features/chat/presentation/providers/tool_dedupe_keys.dart';

void main() {
  const projectRoot = '/workspace/project';
  const policy = ToolCallExecutionPolicy();

  String resolveLikeNotifier(String path, String? root) =>
      FilesystemTools.resolvePath(path, defaultRoot: root) ?? path;

  group('ToolDedupeKeys', () {
    test('resolves paths only from the supplied project root', () {
      expect(
        ToolDedupeKeys.resolvePath('lib/main.dart', projectRoot: projectRoot),
        '/workspace/project/lib/main.dart',
      );
      expect(
        ToolDedupeKeys.resolvePath('lib/main.dart', projectRoot: null),
        'lib/main.dart',
      );
    });

    test('matches policy keys with explicit project path resolution', () {
      final toolCall = ToolCallInfo(
        id: 'call-1',
        name: 'READ_FILE',
        arguments: const {'path': './lib/main.dart', 'z': 1},
      );
      final expectedCall = policy.toolCallDedupKey(
        toolCall.name,
        toolCall.arguments,
        resolveProjectPath: (path) => resolveLikeNotifier(path, projectRoot),
      );
      final expectedExecution = policy.toolExecutionKey(
        toolCall,
        commandRetryGeneration: 3,
        resolveProjectPath: (path) => resolveLikeNotifier(path, projectRoot),
      );

      expect(
        ToolDedupeKeys.toolCall(
          toolCall.name,
          toolCall.arguments,
          projectRoot: projectRoot,
        ),
        expectedCall,
      );
      expect(
        ToolDedupeKeys.toolExecution(
          toolCall,
          projectRoot: projectRoot,
          commandRetryGeneration: 3,
        ),
        expectedExecution,
      );
    });

    test('preserves absolute and unresolved relative path behavior', () {
      for (final path in ['/tmp/result.txt', 'relative/result.txt']) {
        final expected = policy.toolCallDedupKey(
          'read_file',
          {'path': path},
          resolveProjectPath: (value) => resolveLikeNotifier(value, null),
        );
        expect(
          ToolDedupeKeys.toolCall('read_file', {
            'path': path,
          }, projectRoot: null),
          expected,
        );
      }
    });

    test('builds matching result keys and reason-insensitive failure keys', () {
      final result = ToolResultInfo(
        id: 'result-1',
        name: 'read_file',
        arguments: const {'path': 'README.md'},
        result: 'content',
      );
      expect(
        ToolDedupeKeys.toolResult(result, projectRoot: projectRoot),
        ToolDedupeKeys.toolCall(
          result.name,
          result.arguments,
          projectRoot: projectRoot,
        ),
      );

      String failureKey(String reason) => ToolDedupeKeys.toolFailure(
        ToolCallInfo(
          id: reason,
          name: 'local_execute_command',
          arguments: {'command': 'dart test', 'reason': reason},
        ),
        projectRoot: projectRoot,
        commandRetryGeneration: 2,
      );
      expect(failureKey('first explanation'), failureKey('second explanation'));
      expect(
        failureKey('first explanation'),
        contains('commandRetryGeneration=2'),
      );

      final pathFailure = ToolCallInfo(
        id: 'path-failure',
        name: 'read_file',
        arguments: const {'path': 'lib/main.dart'},
      );
      expect(
        ToolDedupeKeys.toolFailure(pathFailure, projectRoot: projectRoot),
        policy.toolFailureKey(
          pathFailure,
          resolveProjectPath: (path) => resolveLikeNotifier(path, projectRoot),
        ),
      );
    });

    test('keeps content execution JSON byte-compatible', () {
      final arguments = <String, dynamic>{
        'path': 'README.md',
        'options': [1, true],
      };

      expect(
        ToolDedupeKeys.contentExecution('read_file', arguments),
        'read_file:${jsonEncode(arguments)}',
      );
    });
  });
}
