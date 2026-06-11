import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_execution_scheduler.dart';
import 'package:caverno/features/chat/presentation/providers/chat_tool_execution_log_formatter.dart';

void main() {
  group('ChatToolExecutionLogFormatter', () {
    test('formats skipped lifecycle payloads', () {
      final line = ChatToolExecutionLogFormatter.lifecycleLine(
        toolCall: _toolCall('read-1', 'read_file'),
        lifecycleState: 'skipped',
        loopIndex: 2,
        schedulerMode: ToolExecutionBatchMode.parallelFileRead,
        resultStatus: 'skipped',
        skipReason: 'duplicate_tool_call',
      );

      expect(
        line,
        '[Tool] Lifecycle {"toolCallId":"read-1","toolName":"read_file",'
        '"lifecycleState":"skipped","loopIndex":2,'
        '"schedulerClass":"parallelFileRead","resultStatus":"skipped",'
        '"skipReason":"duplicate_tool_call"}',
      );
    });

    test('formats scheduled lifecycle events', () {
      final line = ChatToolExecutionLogFormatter.lifecycleLineForEvent(
        ToolExecutionLifecycleEvent(
          toolCall: _toolCall('http-1', 'http_status'),
          state: ToolExecutionLifecycleState.completed,
          schedulerMode: ToolExecutionBatchMode.parallelNetworkRead,
          resultStatus: 'success',
          durationMs: 42,
        ),
        loopIndex: 3,
      );

      expect(
        line,
        '[Tool] Lifecycle {"toolCallId":"http-1","toolName":"http_status",'
        '"lifecycleState":"completed","loopIndex":3,'
        '"schedulerClass":"parallelNetworkRead","resultStatus":"success",'
        '"durationMs":42}',
      );
    });

    test('formats scheduler batch telemetry', () {
      final line = ChatToolExecutionLogFormatter.schedulerBatchLine(
        const ToolExecutionBatchTelemetry(
          mode: ToolExecutionBatchMode.parallelFileRead,
          toolNames: ['read_file', 'search_files'],
          note: 'parallel batch limit',
        ),
      );

      expect(
        line,
        '[Tool] Scheduler parallelFileRead batch '
        '(size=2, tools=read_file, search_files) • parallel batch limit',
      );
    });

    test('formats final inspection scheduler telemetry', () {
      final line = ChatToolExecutionLogFormatter.schedulerBatchLine(
        const ToolExecutionBatchTelemetry(
          mode: ToolExecutionBatchMode.serial,
          toolNames: ['read_file'],
        ),
        finalInspection: true,
      );

      expect(
        line,
        '[Tool] Scheduler serial final inspection batch '
        '(size=1, tools=read_file)',
      );
    });
  });
}

ToolCallInfo _toolCall(String id, String name) {
  return ToolCallInfo(id: id, name: name, arguments: const {});
}
