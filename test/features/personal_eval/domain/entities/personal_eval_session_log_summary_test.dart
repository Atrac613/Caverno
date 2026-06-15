import 'dart:convert';

import 'package:caverno/features/personal_eval/domain/entities/personal_eval_session_log_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String entry({
    required String operation,
    int durationMs = 0,
    String? content,
    String? finishReason,
    List<Map<String, dynamic>> toolCalls = const [],
    List<Map<String, dynamic>> requestMessages = const [],
    Map<String, dynamic>? error,
  }) {
    return jsonEncode({
      'operation': operation,
      'durationMs': durationMs,
      'request': {'messages': requestMessages},
      if (content != null || finishReason != null || toolCalls.isNotEmpty)
        'response': {
          'content': ?content,
          'finishReason': ?finishReason,
          if (toolCalls.isNotEmpty) 'toolCalls': toolCalls,
        },
      'error': ?error,
    });
  }

  test('counts entries, tools, durations, and operations', () {
    final log = [
      entry(
        operation: 'chat',
        durationMs: 100,
        finishReason: 'tool_calls',
        toolCalls: [
          {'name': 'read_file'},
          {'name': 'edit_file'},
        ],
      ),
      entry(
        operation: 'chat',
        durationMs: 250,
        content: 'Done. The fix is applied.',
        finishReason: 'stream_end',
      ),
      'not json at all',
      '',
    ].join('\n');

    final summary = PersonalEvalSessionLogSummary.parseLogContents(log);

    expect(summary.entryCount, 2);
    expect(summary.turnCount, 2);
    expect(summary.malformedLineCount, 1);
    expect(summary.toolCallCount, 2);
    expect(summary.totalDurationMs, 350);
    expect(summary.operationCounts, {'chat': 2});
    expect(summary.finishReasonCounts, {'stream_end': 1, 'tool_calls': 1});
    expect(summary.finalAnswerLineNumber, 2);
    expect(summary.result, 'complete');
  });

  test('derives incomplete when there is no final answer', () {
    final log = entry(
      operation: 'chat',
      finishReason: 'tool_calls',
      toolCalls: [
        {'name': 'read_file'},
      ],
    );

    final summary = PersonalEvalSessionLogSummary.parseLogContents(log);
    expect(summary.result, 'incomplete');
    expect(summary.finalAnswerLineNumber, isNull);
  });

  test('derives error when any entry carries an error', () {
    final log = [
      entry(operation: 'chat', content: 'partial'),
      entry(
        operation: 'chat',
        error: {'type': 'TimeoutException', 'message': 'timed out'},
      ),
    ].join('\n');

    final summary = PersonalEvalSessionLogSummary.parseLogContents(log);
    expect(summary.result, 'error');
  });

  test('derives loop_limit_recovered from a loop-limit prompt plus answer', () {
    final log = [
      entry(
        operation: 'chat',
        finishReason: 'tool_calls',
        toolCalls: [
          {'name': 'read_file'},
        ],
        requestMessages: [
          {'role': 'user', 'content': 'You hit the bounded tool loop limit.'},
        ],
      ),
      entry(operation: 'chat', content: 'Final answer after recovery.'),
    ].join('\n');

    final summary = PersonalEvalSessionLogSummary.parseLogContents(log);
    expect(summary.result, 'loop_limit_recovered');
  });

  test('excludes memory-extraction responses from the final answer', () {
    final memoryJson = jsonEncode({
      'summary': 'user likes dark mode',
      'memories': [],
    });
    final log = entry(operation: 'memory_extraction', content: memoryJson);

    final summary = PersonalEvalSessionLogSummary.parseLogContents(log);
    expect(summary.result, 'incomplete');
    expect(summary.finalAnswerLineNumber, isNull);
    // Memory-extraction calls are not counted as agent turns.
    expect(summary.turnCount, 0);
    expect(summary.operationCounts, {'memory_extraction': 1});
  });

  test('emits a manifest source block embedding the summary', () {
    final summary = PersonalEvalSessionLogSummary.parseLogContents(
      entry(operation: 'chat', content: 'done', durationMs: 10),
    );

    final source = summary.toCaseManifestSourceJson(
      sessionLogPath: '/logs/session.jsonl',
    );
    expect(source['sessionLogPath'], '/logs/session.jsonl');
    final embedded = source['sessionLogSummary'] as Map<String, dynamic>;
    expect(embedded['result'], 'complete');
    expect(embedded['entryCount'], 1);
    // A null final answer line is omitted from the serialized summary.
    expect(embedded.containsKey('finalAnswerLineNumber'), isTrue);
  });
}
