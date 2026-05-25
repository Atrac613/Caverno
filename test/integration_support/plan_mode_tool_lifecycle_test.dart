import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_tool_lifecycle.dart';

void main() {
  test('builds lifecycle summary from structured tool logs', () {
    final report = buildPlanModeToolLifecycleReport(const <String>[
      '[Tool] Lifecycle {"toolCallId":"read-1","toolName":"read_file","lifecycleState":"queued","loopIndex":1,"schedulerClass":"parallelFileRead"}',
      '[Tool] Lifecycle {"toolCallId":"read-1","toolName":"read_file","lifecycleState":"started","loopIndex":1,"schedulerClass":"parallelFileRead"}',
      '[Tool] Lifecycle {"toolCallId":"read-1","toolName":"read_file","lifecycleState":"completed","loopIndex":1,"schedulerClass":"parallelFileRead","resultStatus":"success","durationMs":12}',
      '[Tool] Lifecycle {"toolCallId":"write-1","toolName":"write_file","lifecycleState":"queued","loopIndex":1,"schedulerClass":"serial"}',
      '[Tool] Lifecycle {"toolCallId":"write-1","toolName":"write_file","lifecycleState":"skipped","loopIndex":1,"schedulerClass":"serial","resultStatus":"skipped","skipReason":"duplicate_tool_call"}',
      'plain debug noise',
      '[Tool] Lifecycle malformed',
    ]);

    expect(report['detected'], isTrue);
    expect(report['eventCount'], 5);
    expect(report['serviceExecutionCount'], 0);
    expect(report['toolCallCount'], 2);
    expect(report['completedCount'], 1);
    expect(report['skippedCount'], 1);
    expect(report['maxDurationMs'], 12);
    expect(report['states'], containsPair('queued', 2));
    expect(report['resultStatuses'], containsPair('success', 1));
    expect(report['schedulerClasses'], containsPair('parallelFileRead', 3));
    expect(report['incompleteToolCount'], 0);
    expect(report['observedToolNames'], const <String>[
      'read_file',
      'write_file',
    ]);

    final tools = report['tools'] as List<Object?>;
    expect(
      tools,
      contains(
        allOf(
          containsPair('toolCallId', 'read-1'),
          containsPair('lastState', 'completed'),
          containsPair('durationMs', 12),
        ),
      ),
    );
  });

  test('reports incomplete tools when no terminal lifecycle state appears', () {
    final report = buildPlanModeToolLifecycleReport(const <String>[
      '[Tool] Lifecycle {"toolCallId":"slow-1","toolName":"http_status","lifecycleState":"queued","loopIndex":2,"schedulerClass":"parallelNetworkRead"}',
      '[Tool] Lifecycle {"toolCallId":"slow-1","toolName":"http_status","lifecycleState":"started","loopIndex":2,"schedulerClass":"parallelNetworkRead"}',
    ]);

    expect(report['incompleteToolCount'], 1);
    final incompleteTools = report['incompleteTools'] as List<Object?>;
    expect(incompleteTools.single, containsPair('toolName', 'http_status'));
  });

  test('reports direct MCP tool service executions', () {
    final report = buildPlanModeToolLifecycleReport(const <String>[
      '[Workflow] Planning research pass started',
      '[McpToolService] Executing tool: list_directory',
      '[McpToolService] Arguments: {path: /tmp/project}',
      '[McpToolService] Executing tool: find_files',
    ]);

    expect(report['detected'], isTrue);
    expect(report['eventCount'], 0);
    expect(report['serviceExecutionCount'], 2);
    expect(report['toolCallCount'], 0);
    expect(report['observedToolNames'], const <String>[
      'find_files',
      'list_directory',
    ]);

    final serviceExecutions = report['serviceExecutions'] as List<Object?>;
    expect(
      serviceExecutions.first,
      allOf(
        containsPair('toolName', 'list_directory'),
        containsPair('logIndex', 1),
      ),
    );
  });
}
