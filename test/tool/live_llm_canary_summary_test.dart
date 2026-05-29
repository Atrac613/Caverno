import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/live_llm_canary_summary.dart';

void main() {
  test('builds a passing summary from Flutter JSON reporter output', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-summary-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final logFile = File('${directory.path}/flutter_test.jsonl');
    await logFile.writeAsString(
      [
        'The following plugins do not support Swift Package Manager for ios:',
        jsonEncode({'protocolVersion': '0.1.1', 'type': 'start', 'time': 0}),
        jsonEncode({
          'test': {
            'id': 1,
            'name': 'loading tool/canaries/chat_live_llm_canary_test.dart',
            'metadata': {'skip': false, 'skipReason': null},
          },
          'type': 'testStart',
          'time': 0,
        }),
        jsonEncode({
          'testID': 1,
          'result': 'success',
          'skipped': false,
          'hidden': true,
          'type': 'testDone',
          'time': 10,
        }),
        jsonEncode({
          'test': {
            'id': 2,
            'name': 'live LLM embedded tool call executes once',
            'metadata': {'skip': false, 'skipReason': null},
          },
          'type': 'testStart',
          'time': 20,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[ChatNotifier] Recovered content-tool continuation with non-streaming completion',
          'type': 'print',
          'time': 30,
        }),
        jsonEncode({
          'testID': 2,
          'message': '[ContentTool] Recovering incomplete tool_call(s): 1',
          'type': 'print',
          'time': 31,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[ContentTool] Ignoring assistant-authored tool_result tag(s): arp',
          'type': 'print',
          'time': 32,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              'assistant: I can fix it now.\n\n[Tool: edit_file]\nArguments: {"path":"lib/src/ping_command.dart"}',
          'type': 'print',
          'time': 33,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[CodingDiagnostics] Analyzer feedback summary: {"toolName":"dart_analyze_feedback","diagnosticCount":2,"files":["lib/main.dart"]}',
          'type': 'print',
          'time': 34,
        }),
        jsonEncode({
          'testID': 2,
          'result': 'success',
          'skipped': false,
          'hidden': false,
          'type': 'testDone',
          'time': 120,
        }),
        jsonEncode({
          'test': {
            'id': 3,
            'name': 'live LLM answers from compacted oversized tool results',
            'metadata': {'skip': false, 'skipReason': null},
          },
          'type': 'testStart',
          'time': 130,
        }),
        jsonEncode({
          'testID': 3,
          'message':
              '[Compaction] Retrying tool-result follow-up after context-length error with compact tool results',
          'type': 'print',
          'time': 135,
        }),
        jsonEncode({
          'testID': 3,
          'result': 'success',
          'skipped': false,
          'hidden': false,
          'type': 'testDone',
          'time': 240,
        }),
        jsonEncode({'success': true, 'type': 'done', 'time': 250}),
      ].join('\n'),
    );

    final summary = await buildLiveLlmCanarySummary(
      logFile: logFile,
      canaryName: 'chat_live_llm_canary',
      surface: 'chat',
      baseUrl: 'http://127.0.0.1:1234/v1',
      model: 'test-model',
      command: 'tool/run_chat_live_llm_canary.sh',
      generatedAt: DateTime.utc(2026, 5, 23, 1, 2, 3),
    );

    expect(summary.result, 'passed');
    expect(summary.isSuccessful, isTrue);
    expect(summary.testCount, 2);
    expect(summary.passedCount, 2);
    expect(summary.failedCount, 0);
    expect(summary.skippedCount, 0);
    expect(summary.hiddenTestCount, 1);
    expect(summary.durationMs, 250);
    expect(summary.signals.recoveredStreamFallbackCount, 1);
    expect(summary.signals.toolResultCompactionRetryCount, 1);
    expect(summary.signals.incompleteContentToolRecoveryCount, 1);
    expect(summary.signals.ignoredAssistantToolResultCount, 1);
    expect(summary.signals.assistantAuthoredToolBlockCount, 1);
    expect(summary.signals.dartAnalyzeFeedback.observed, isTrue);
    expect(summary.signals.dartAnalyzeFeedback.feedbackCount, 1);
    expect(summary.signals.dartAnalyzeFeedback.diagnosticCount, 2);
    expect(summary.signals.dartAnalyzeFeedback.files, ['lib/main.dart']);

    final json = summary.toJson();
    expect(json['schemaName'], 'live_llm_canary_summary');
    expect(json['generatedAt'], '2026-05-23T01:02:03.000Z');
    expect(json['tests'], hasLength(2));
    expect(
      (json['signals'] as Map<String, dynamic>)['dartAnalyzeFeedback'],
      containsPair('diagnosticCount', 2),
    );
    expect(summary.toMarkdown(), contains('Live LLM Canary Summary'));
    expect(summary.toMarkdown(), contains('Recovered stream fallback count'));
    expect(
      summary.toMarkdown(),
      contains('Incomplete content-tool recovery count'),
    );
    expect(summary.toMarkdown(), contains('Assistant-authored tool block'));
    expect(
      summary.toMarkdown(),
      contains('Dart analyzer feedback observed: `yes`'),
    );
    expect(summary.toMarkdown(), contains('lib/main.dart'));
  });

  test('marks skipped live canaries as skipped instead of passed', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-summary-skipped-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final logFile = File('${directory.path}/flutter_test.jsonl');
    await logFile.writeAsString(
      [
        jsonEncode({
          'test': {
            'id': 1,
            'name': 'live LLM produces a plain chat response without tools',
            'metadata': {
              'skip': true,
              'skipReason': 'Set CAVERNO_CHAT_LIVE_CANARY=1 to run.',
            },
          },
          'type': 'testStart',
          'time': 0,
        }),
        jsonEncode({
          'testID': 1,
          'result': 'success',
          'skipped': true,
          'hidden': false,
          'type': 'testDone',
          'time': 1,
        }),
        jsonEncode({'success': true, 'type': 'done', 'time': 2}),
      ].join('\n'),
    );

    final summary = await buildLiveLlmCanarySummary(
      logFile: logFile,
      canaryName: 'chat_live_llm_canary',
      surface: 'chat',
      baseUrl: 'http://127.0.0.1:1234/v1',
      model: 'test-model',
      command: 'tool/run_chat_live_llm_canary.sh',
      generatedAt: DateTime.utc(2026, 5, 23),
    );

    expect(summary.result, 'skipped');
    expect(summary.isSuccessful, isFalse);
    expect(summary.skippedCount, 1);
    expect(summary.tests.single.skipReason, contains('CAVERNO_CHAT'));
  });

  test('aggregates repeated Flutter JSON reporter output', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-summary-repeat-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final logFile = File('${directory.path}/flutter_test.jsonl');
    await logFile.writeAsString(
      [
        jsonEncode({'protocolVersion': '0.1.1', 'type': 'start', 'time': 0}),
        jsonEncode({
          'test': {
            'id': 1,
            'name': '[run_01] live LLM edits code and runs the fixture test',
            'metadata': {'skip': false, 'skipReason': null},
          },
          'type': 'testStart',
          'time': 10,
        }),
        jsonEncode({
          'testID': 1,
          'result': 'success',
          'skipped': false,
          'hidden': false,
          'type': 'testDone',
          'time': 110,
        }),
        jsonEncode({'success': true, 'type': 'done', 'time': 120}),
        jsonEncode({'protocolVersion': '0.1.1', 'type': 'start', 'time': 0}),
        jsonEncode({
          'test': {
            'id': 1,
            'name': '[run_02] live LLM edits code and runs the fixture test',
            'metadata': {'skip': false, 'skipReason': null},
          },
          'type': 'testStart',
          'time': 20,
        }),
        jsonEncode({
          'testID': 1,
          'result': 'success',
          'skipped': false,
          'hidden': false,
          'type': 'testDone',
          'time': 140,
        }),
        jsonEncode({'success': false, 'type': 'done', 'time': 160}),
      ].join('\n'),
    );

    final summary = await buildLiveLlmCanarySummary(
      logFile: logFile,
      canaryName: 'coding_goal_live_edit_canary',
      surface: 'coding_goal_edit',
      baseUrl: 'http://127.0.0.1:1234/v1',
      model: 'test-model',
      command: 'tool/run_coding_goal_live_edit_canary.sh',
      generatedAt: DateTime.utc(2026, 5, 26),
    );

    expect(summary.result, 'failed');
    expect(summary.runnerSuccess, isFalse);
    expect(summary.testCount, 2);
    expect(summary.passedCount, 2);
    expect(summary.failedCount, 0);
    expect(summary.durationMs, 280);
    expect(summary.tests.map((test) => test.name), [
      '[run_01] live LLM edits code and runs the fixture test',
      '[run_02] live LLM edits code and runs the fixture test',
    ]);
  });
}
