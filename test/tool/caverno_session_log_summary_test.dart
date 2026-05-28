import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/caverno_session_log_summary.dart';

void main() {
  test(
    'detects loop-limit recovery, final answer, and memory extraction',
    () async {
      final logFile = _writeSessionLog([
        _entry(
          operation: 'streamChatCompletionWithTools',
          finishReason: 'tool_calls',
          content: 'Inspecting the requested session log.',
          requestTools: [_toolDefinition('read_file')],
          toolCalls: [
            _toolCall(
              id: 'tool-read',
              name: 'read_file',
              arguments: {'path': 'lib/main.dart'},
            ),
          ],
        ),
        _entry(
          operation: 'createChatCompletionWithToolResults',
          finishReason: 'tool_calls',
          content: 'I still need one command.',
          requestMessages: [
            _message(
              'user',
              'You hit the bounded tool loop limit while working on the current saved task.',
            ),
          ],
          toolCalls: [
            _toolCall(
              id: 'tool-command',
              name: 'local_execute_command',
              arguments: {
                'command': 'python3 summarize_session_log.py',
                'reason': 'Inspect final state',
              },
            ),
          ],
        ),
        _entry(
          operation: 'streamChatCompletion',
          finishReason: 'stream_end',
          content:
              'Final investigation summary: tool loop limit was reached, '
              'but no fatal transport error was recorded.',
          requestMessages: [_message('user', 'Summarize the latest results.')],
        ),
        _entry(
          operation: 'createChatCompletion',
          finishReason: 'stop',
          content: jsonEncode({
            'summary': 'Session log investigation completed.',
            'open_loops': <String>[],
            'profile': <String, Object?>{},
            'memories': <Object?>[],
          }),
        ),
      ]);

      final summary = await buildCavernoLlmSessionLogSummary(
        logFile: logFile,
        generatedAt: DateTime.utc(2026, 5, 28, 1, 2, 3),
      );

      expect(summary.result, 'loop_limit_recovered');
      expect(summary.entryCount, 4);
      expect(summary.malformedLineCount, 0);
      expect(summary.hasFatalError, isFalse);
      expect(summary.hasLoopLimitPrompt, isTrue);
      expect(summary.loopLimitPromptLineNumbers, [2]);
      expect(summary.streamEndLineNumbers, [3]);
      expect(summary.memoryExtractionLineNumbers, [4]);
      expect(summary.finalAnswer?.lineNumber, 3);
      expect(summary.finalAnswer?.finishReason, 'stream_end');
      expect(
        summary.finalAnswer?.contentPreview,
        contains('Final investigation summary'),
      );
      expect(summary.operationCounts['createChatCompletion'], 1);
      expect(summary.finishReasonCounts['tool_calls'], 2);
      expect(summary.toolCallCount, 2);
      expect(summary.toolCalls.last.commandPreview, contains('summarize'));
      expect(summary.hasWarnings, isFalse);
      expect(summary.hasStreamEndMisinterpretationWarning, isFalse);

      final json = summary.toJson();
      expect(json['schemaName'], 'caverno_llm_session_log_summary');
      expect(json['generatedAt'], '2026-05-28T01:02:03.000Z');
      expect(json['finalAnswer'], isA<Map<String, dynamic>>());
      expect(json['streamEndMisinterpretationWarning'], isFalse);

      final markdown = summary.toMarkdown();
      expect(markdown, contains('Loop-limit prompt: `yes`'));
      expect(markdown, contains('It is not an interruption by itself'));
      expect(markdown, contains('Final Answer Preview'));
    },
  );

  test('does not classify stream_end alone as fatal', () async {
    final logFile = _writeSessionLog([
      _entry(
        operation: 'streamChatCompletion',
        finishReason: 'stream_end',
        content: 'The requested inspection is complete.',
      ),
    ]);

    final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);

    expect(summary.result, 'complete');
    expect(summary.hasFatalError, isFalse);
    expect(summary.hasLoopLimitPrompt, isFalse);
    expect(summary.streamEndLineNumbers, [1]);
    expect(summary.finalAnswer?.lineNumber, 1);
    expect(summary.warnings, isEmpty);
    expect(summary.toMarkdown(), contains('not an interruption by itself'));
  });

  test(
    'warns when the final answer treats stream_end as interruption',
    () async {
      final logFile = _writeSessionLog([
        _entry(
          operation: 'streamChatCompletion',
          finishReason: 'stream_end',
          content:
              'The root cause is stream_end. The stream_end finish reason '
              'means the connection was cut off and caused the interruption.',
        ),
      ]);

      final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);

      expect(summary.result, 'complete');
      expect(summary.hasFatalError, isFalse);
      expect(summary.hasWarnings, isTrue);
      expect(summary.hasStreamEndMisinterpretationWarning, isTrue);
      expect(summary.warnings.single.code, 'stream_end_misinterpretation');
      expect(summary.warnings.single.lineNumber, 1);
      expect(summary.warnings.single.message, contains('fully consumed'));
      expect(
        summary.warnings.single.evidencePreview,
        contains('connection was cut off'),
      );

      final json = summary.toJson();
      expect(json['streamEndMisinterpretationWarning'], isTrue);
      expect(json['warnings'], hasLength(1));

      final markdown = summary.toMarkdown();
      expect(markdown, contains('## Warnings'));
      expect(markdown, contains('stream_end_misinterpretation'));
    },
  );

  test(
    'does not warn when the final answer explains stream_end safely',
    () async {
      final logFile = _writeSessionLog([
        _entry(
          operation: 'streamChatCompletion',
          finishReason: 'stream_end',
          content:
              'stream_end means Caverno finished reading the stream. It is not '
              'an interruption by itself.',
        ),
      ]);

      final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);

      expect(summary.result, 'complete');
      expect(summary.hasWarnings, isFalse);
      expect(summary.hasStreamEndMisinterpretationWarning, isFalse);
    },
  );

  test('records malformed lines and error entries without crashing', () async {
    final logFile = _writeRawSessionLog([
      'not-json',
      jsonEncode(
        _entry(
          operation: 'streamChatCompletion',
          error: {
            'type': 'SocketException',
            'message': 'Connection closed before response completed',
          },
        ),
      ),
    ]);

    final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);

    expect(summary.result, 'error');
    expect(summary.entryCount, 1);
    expect(summary.malformedLineCount, 1);
    expect(summary.hasFatalError, isTrue);
    expect(summary.errorEntries.single.lineNumber, 2);
    expect(summary.errorEntries.single.type, 'SocketException');
    expect(summary.finalAnswer, isNull);
  });

  test('parses CLI options with positional and explicit log paths', () {
    expect(
      CavernoSessionLogSummaryOptions.parse(['session.jsonl'])?.logPath,
      'session.jsonl',
    );
    final jsonOptions = CavernoSessionLogSummaryOptions.parse([
      '--log',
      'session.jsonl',
      '--format',
      'json',
    ]);
    expect(jsonOptions?.logPath, 'session.jsonl');
    expect(jsonOptions?.format, CavernoSessionLogSummaryFormat.json);
    expect(CavernoSessionLogSummaryOptions.parse(['--format', 'xml']), isNull);
  });
}

File _writeSessionLog(List<Map<String, Object?>> entries) {
  return _writeRawSessionLog(
    entries.map((entry) => jsonEncode(entry)).toList(growable: false),
  );
}

File _writeRawSessionLog(List<String> lines) {
  final directory = Directory.systemTemp.createTempSync(
    'session-log-summary-test-',
  );
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  final logFile = File('${directory.path}/session.jsonl');
  logFile.writeAsStringSync(lines.join('\n'));
  return logFile;
}

Map<String, Object?> _entry({
  required String operation,
  String? finishReason,
  String content = '',
  List<Map<String, Object?>> requestMessages = const [],
  List<Map<String, Object?>> requestTools = const [],
  List<Map<String, Object?>> toolCalls = const [],
  Map<String, Object?>? error,
}) {
  return {
    'schemaName': 'caverno_llm_session_log_entry',
    'schemaVersion': 1,
    'timestamp': '2026-05-28T00:00:00.000',
    'startedAt': '2026-05-28T00:00:00.000',
    'finishedAt': '2026-05-28T00:00:01.000',
    'durationMs': 1000,
    'operation': operation,
    'context': {'phase': 'chat_turn', 'workspaceMode': 'coding'},
    'request': {
      'messages': requestMessages,
      'tools': requestTools,
      'model': 'test-model',
      'temperature': 0.7,
      'maxTokens': 4096,
    },
    if (error == null)
      'response': {
        ...?finishReason == null ? null : {'finishReason': finishReason},
        'content': content,
        'toolCalls': toolCalls,
      },
    ...?error == null ? null : {'error': error},
  };
}

Map<String, Object?> _message(String role, String content) {
  return {'role': role, 'content': content};
}

Map<String, Object?> _toolDefinition(String name) {
  return {
    'type': 'function',
    'function': {'name': name},
  };
}

Map<String, Object?> _toolCall({
  required String id,
  required String name,
  required Map<String, Object?> arguments,
}) {
  return {'id': id, 'name': name, 'arguments': arguments};
}
