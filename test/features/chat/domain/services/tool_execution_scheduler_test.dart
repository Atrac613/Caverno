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
}
