import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/tool_execution_scheduler.dart';

void main() {
  test('runs concurrency-safe tools in parallel and preserves result order', () async {
    final started = <String>[];
    final readCompleter = Completer<void>();
    final searchCompleter = Completer<void>();
    final writeCompleter = Completer<void>();

    final future = ToolExecutionScheduler.executeBatch(
      toolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'read_file',
          arguments: const {'path': 'alpha.dart'},
        ),
        ToolCallInfo(
          id: 'tool-2',
          name: 'search_files',
          arguments: const {'query': 'ChatNotifier'},
        ),
        ToolCallInfo(
          id: 'tool-3',
          name: 'write_file',
          arguments: const {'path': 'beta.dart'},
        ),
      ],
      execute: (toolCall) async {
        started.add(toolCall.name);
        switch (toolCall.name) {
          case 'read_file':
            await readCompleter.future;
            break;
          case 'search_files':
            await searchCompleter.future;
            break;
          case 'write_file':
            await writeCompleter.future;
            break;
        }
        return McpToolResult(
          toolName: toolCall.name,
          result: '${toolCall.name} complete',
          isSuccess: true,
        );
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(started, ['read_file', 'search_files']);

    readCompleter.complete();
    searchCompleter.complete();
    await Future<void>.delayed(Duration.zero);
    expect(started, ['read_file', 'search_files', 'write_file']);

    writeCompleter.complete();
    final results = await future;

    expect(
      results.map((item) => item.toolCall.name).toList(),
      ['read_file', 'search_files', 'write_file'],
    );
    expect(results.every((item) => item.isSuccess), isTrue);
  });

  test('limits parallel batch size and separates file and network groups', () async {
    final started = <String>[];
    final fileCompleters = {
      'read_file': Completer<void>(),
      'search_files': Completer<void>(),
      'find_files': Completer<void>(),
    };
    final networkCompleter = Completer<void>();
    final telemetry = <ToolExecutionBatchTelemetry>[];

    final future = ToolExecutionScheduler.executeBatch(
      toolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'read_file',
          arguments: const {'path': 'alpha.dart'},
        ),
        ToolCallInfo(
          id: 'tool-2',
          name: 'search_files',
          arguments: const {'query': 'ChatNotifier'},
        ),
        ToolCallInfo(
          id: 'tool-3',
          name: 'find_files',
          arguments: const {'pattern': '*.dart'},
        ),
        ToolCallInfo(
          id: 'tool-4',
          name: 'http_status',
          arguments: const {'url': 'https://example.com'},
        ),
      ],
      execute: (toolCall) async {
        started.add(toolCall.name);
        final fileCompleter = fileCompleters[toolCall.name];
        if (fileCompleter != null) {
          await fileCompleter.future;
        } else if (toolCall.name == 'http_status') {
          await networkCompleter.future;
        }
        return McpToolResult(
          toolName: toolCall.name,
          result: '${toolCall.name} complete',
          isSuccess: true,
        );
      },
      onBatch: telemetry.add,
    );

    await Future<void>.delayed(Duration.zero);
    expect(started, ['read_file', 'search_files', 'find_files']);

    for (final completer in fileCompleters.values) {
      completer.complete();
    }
    await Future<void>.delayed(Duration.zero);
    expect(started, ['read_file', 'search_files', 'find_files', 'http_status']);

    networkCompleter.complete();
    final results = await future;

    expect(results.map((item) => item.toolCall.name).toList(), [
      'read_file',
      'search_files',
      'find_files',
      'http_status',
    ]);
    expect(
      telemetry.map((item) => (item.mode, item.batchSize, item.note)).toList(),
      [
        (
          ToolExecutionBatchMode.parallelFileRead,
          3,
          'group switch',
        ),
        (
          ToolExecutionBatchMode.parallelNetworkRead,
          1,
          null,
        ),
      ],
    );
  });

  test('flushes file-read batches when the parallel limit is reached', () async {
    final started = <String>[];
    final firstBatchCompleters = {
      'read_file': Completer<void>(),
      'search_files': Completer<void>(),
      'find_files': Completer<void>(),
    };
    final listDirectoryCompleter = Completer<void>();
    final telemetry = <ToolExecutionBatchTelemetry>[];

    final future = ToolExecutionScheduler.executeBatch(
      toolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'read_file',
          arguments: const {'path': 'alpha.dart'},
        ),
        ToolCallInfo(
          id: 'tool-2',
          name: 'search_files',
          arguments: const {'query': 'ChatNotifier'},
        ),
        ToolCallInfo(
          id: 'tool-3',
          name: 'find_files',
          arguments: const {'pattern': '*.dart'},
        ),
        ToolCallInfo(
          id: 'tool-4',
          name: 'list_directory',
          arguments: const {'path': 'lib'},
        ),
      ],
      execute: (toolCall) async {
        started.add(toolCall.name);
        final completer = firstBatchCompleters[toolCall.name];
        if (completer != null) {
          await completer.future;
        } else {
          await listDirectoryCompleter.future;
        }
        return McpToolResult(
          toolName: toolCall.name,
          result: '${toolCall.name} complete',
          isSuccess: true,
        );
      },
      onBatch: telemetry.add,
    );

    await Future<void>.delayed(Duration.zero);
    expect(started, ['read_file', 'search_files', 'find_files']);

    for (final completer in firstBatchCompleters.values) {
      completer.complete();
    }
    await Future<void>.delayed(Duration.zero);
    expect(started, ['read_file', 'search_files', 'find_files', 'list_directory']);

    listDirectoryCompleter.complete();
    await future;

    expect(
      telemetry.map((item) => (item.mode, item.batchSize, item.note)).toList(),
      [
        (
          ToolExecutionBatchMode.parallelFileRead,
          3,
          'parallel batch limit',
        ),
        (
          ToolExecutionBatchMode.parallelFileRead,
          1,
          null,
        ),
      ],
    );
  });

  test('emits per-tool lifecycle events with scheduler context', () async {
    final lifecycleEvents = <ToolExecutionLifecycleEvent>[];

    final results = await ToolExecutionScheduler.executeBatch(
      toolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'read_file',
          arguments: const {'path': 'alpha.dart'},
        ),
        ToolCallInfo(
          id: 'tool-2',
          name: 'write_file',
          arguments: const {'path': 'beta.dart'},
        ),
      ],
      execute: (toolCall) async {
        if (toolCall.name == 'write_file') {
          return McpToolResult(
            toolName: toolCall.name,
            result: 'Permission denied',
            isSuccess: false,
            errorMessage: 'Permission denied',
          );
        }
        return McpToolResult(
          toolName: toolCall.name,
          result: '${toolCall.name} complete',
          isSuccess: true,
        );
      },
      onLifecycle: lifecycleEvents.add,
    );

    expect(results.map((item) => item.toolCall.name).toList(), [
      'read_file',
      'write_file',
    ]);
    expect(
      lifecycleEvents
          .map(
            (event) => (
              event.toolCall.name,
              event.state,
              event.schedulerMode,
              event.resultStatus,
            ),
          )
          .toList(),
      [
        (
          'read_file',
          ToolExecutionLifecycleState.queued,
          ToolExecutionBatchMode.parallelFileRead,
          null,
        ),
        (
          'read_file',
          ToolExecutionLifecycleState.started,
          ToolExecutionBatchMode.parallelFileRead,
          null,
        ),
        (
          'read_file',
          ToolExecutionLifecycleState.completed,
          ToolExecutionBatchMode.parallelFileRead,
          'success',
        ),
        (
          'write_file',
          ToolExecutionLifecycleState.queued,
          ToolExecutionBatchMode.serial,
          null,
        ),
        (
          'write_file',
          ToolExecutionLifecycleState.started,
          ToolExecutionBatchMode.serial,
          null,
        ),
        (
          'write_file',
          ToolExecutionLifecycleState.completed,
          ToolExecutionBatchMode.serial,
          'tool_failure',
        ),
      ],
    );
    expect(
      lifecycleEvents
          .where((event) => event.state == ToolExecutionLifecycleState.completed)
          .map((event) => event.durationMs),
      everyElement(isNotNull),
    );
  });

  test('preserves result order when a parallel tool fails', () async {
    final lifecycleEvents = <ToolExecutionLifecycleEvent>[];

    final results = await ToolExecutionScheduler.executeBatch(
      toolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'read_file',
          arguments: const {'path': 'alpha.dart'},
        ),
        ToolCallInfo(
          id: 'tool-2',
          name: 'search_files',
          arguments: const {'query': 'missing'},
        ),
      ],
      execute: (toolCall) async {
        if (toolCall.name == 'search_files') {
          throw StateError('search failed');
        }
        return McpToolResult(
          toolName: toolCall.name,
          result: '${toolCall.name} complete',
          isSuccess: true,
        );
      },
      onLifecycle: lifecycleEvents.add,
    );

    expect(results.map((item) => item.toolCall.name).toList(), [
      'read_file',
      'search_files',
    ]);
    expect(results.first.isSuccess, isTrue);
    expect(results.last.isSuccess, isFalse);
    expect(results.last.error, isA<StateError>());
    final failedLifecycleEvent = lifecycleEvents.singleWhere(
      (event) =>
          event.toolCall.name == 'search_files' &&
          event.state == ToolExecutionLifecycleState.completed,
    );
    expect(failedLifecycleEvent.resultStatus, 'exception');
    expect(failedLifecycleEvent.durationMs, isNotNull);
  });

  test('labels structured non-zero command outcomes separately', () async {
    final lifecycleEvents = <ToolExecutionLifecycleEvent>[];

    await ToolExecutionScheduler.executeBatch(
      toolCalls: [
        ToolCallInfo(
          id: 'command-1',
          name: 'local_execute_command',
          arguments: const {'command': 'dart test'},
        ),
      ],
      execute: (toolCall) async => McpToolResult(
        toolName: toolCall.name,
        result:
            '{"exit_code":1,"stdout":"","stderr":"Tests failed."}',
        isSuccess: false,
        errorMessage: 'Command exited non-zero.',
      ),
      onLifecycle: lifecycleEvents.add,
    );

    final completed = lifecycleEvents.singleWhere(
      (event) => event.state == ToolExecutionLifecycleState.completed,
    );
    expect(completed.resultStatus, 'command_failure');
  });
}
