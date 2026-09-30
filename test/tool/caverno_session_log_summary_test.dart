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

  test('warns when memory extraction drafts one-off lookup memory', () async {
    final logFile = _writeSessionLog([
      _entry(
        operation: 'createChatCompletion',
        finishReason: 'stop',
        requestMessages: [
          _message(
            'user',
            'Conversation log:\n'
                '- user: Create a Tokyo weather report for 2026-06-03.\n'
                'Output rules:\n'
                '- Do not add memories for one-off lookup results.',
          ),
        ],
        content: jsonEncode({
          'summary':
              'Retrieved Tokyo weather for 2026-06-03 and saved the report.',
          'open_loops': <String>[],
          'profile': <String, Object?>{},
          'memories': [
            {
              'text':
                  'Tokyo weather on 2026-06-03: Heavy Rain, 160.6mm precipitation, max 19.2°C, min 16.7°C, max wind 19.5 km/h.',
              'type': 'fact',
              'confidence': 1.0,
              'importance': 0.8,
              'ttl_days': 365,
            },
          ],
        }),
      ),
    ]);

    final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);

    expect(summary.memoryExtractionLineNumbers, [1]);
    expect(summary.hasWarnings, isTrue);
    expect(summary.hasMemoryEphemeralDraftWarning, isTrue);
    expect(summary.warnings.single.code, 'memory_ephemeral_draft');
    expect(summary.warnings.single.lineNumber, 1);
    expect(summary.warnings.single.message, contains('LLM draft output'));
    expect(summary.warnings.single.evidencePreview, contains('Tokyo weather'));

    final json = summary.toJson();
    expect(json['memoryEphemeralDraftWarning'], isTrue);

    final markdown = summary.toMarkdown();
    expect(markdown, contains('memory_ephemeral_draft'));
  });

  test(
    'does not warn on lookup-like memory when user explicitly asks to remember',
    () async {
      final logFile = _writeSessionLog([
        _entry(
          operation: 'createChatCompletion',
          finishReason: 'stop',
          requestMessages: [
            _message(
              'user',
              'Conversation log:\n'
                  '- user: Remember that Tokyo weather on 2026-06-03 was Heavy Rain.',
            ),
          ],
          content: jsonEncode({
            'summary': 'User explicitly asked to remember a weather fact.',
            'open_loops': <String>[],
            'profile': <String, Object?>{},
            'memories': [
              {
                'text':
                    'Tokyo weather on 2026-06-03: Heavy Rain, 160.6mm precipitation, max 19.2°C, min 16.7°C, max wind 19.5 km/h.',
                'type': 'fact',
                'confidence': 1.0,
                'importance': 0.8,
                'ttl_days': 365,
              },
            ],
          }),
        ),
      ]);

      final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);

      expect(summary.hasWarnings, isFalse);
      expect(summary.hasMemoryEphemeralDraftWarning, isFalse);
      expect(summary.toJson()['memoryEphemeralDraftWarning'], isFalse);
    },
  );

  test(
    'warns when coding final answer promises action without tool calls',
    () async {
      final logFile = _writeSessionLog([
        _entry(
          operation: 'streamChatCompletionWithTools',
          finishReason: 'stop',
          requestMessages: [_message('user', 'continue')],
          requestTools: [_toolDefinition('read_file')],
          content:
              'I will inspect the existing Dart code and port the Python logic.',
        ),
      ]);

      final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);

      expect(summary.result, 'complete');
      expect(summary.finalAnswer?.lineNumber, 1);
      expect(summary.hasWarnings, isTrue);
      expect(summary.hasCodingActionPromiseWithoutToolWarning, isTrue);
      expect(
        summary.warnings.single.code,
        'coding_action_promise_without_tool',
      );
      expect(summary.warnings.single.lineNumber, 1);
      expect(summary.warnings.single.message, contains('continuation-stall'));
      expect(summary.warnings.single.evidencePreview, contains('port'));

      final json = summary.toJson();
      expect(json['schemaVersion'], 4);
      expect(json['codingActionPromiseWithoutToolWarning'], isTrue);

      final markdown = summary.toMarkdown();
      expect(markdown, contains('Coding action promise without tool: `yes`'));
      expect(markdown, contains('coding_action_promise_without_tool'));
    },
  );

  test('warns from an unexecuted command-action turn transform', () async {
    final logFile = _writeSessionLog([
      _entry(
        operation: 'streamChatCompletionWithTools',
        finishReason: 'stop',
        requestMessages: [_message('user', 'Implement the requested MVP.')],
        requestTools: [_toolDefinition('read_file')],
        content: 'A structured execution plan was returned.',
      ),
      _entry(
        operation: 'turn_exit',
        turnExitTransforms: const ['unexecuted_command_action_notice'],
      ),
    ]);

    final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);

    expect(summary.result, 'complete');
    expect(summary.finalAnswer?.lineNumber, 1);
    expect(summary.hasWarnings, isTrue);
    expect(summary.hasCodingActionPromiseWithoutToolWarning, isTrue);
    expect(summary.warnings.single.lineNumber, 2);
    expect(
      summary.warnings.single.evidencePreview,
      'unexecuted_command_action_notice',
    );
    expect(
      summary.toMarkdown(),
      contains('Coding action promise without tool: `yes`'),
    );
  });

  test(
    'warns on visible promises despite completion words in thinking',
    () async {
      final logFile = _writeSessionLog([
        _entry(
          operation: 'streamChatCompletion',
          finishReason: 'tool_calls',
          content:
              '<think>${'The code was updated and verified. ' * 800}</think>'
              "I'll implement the remaining Python code and tests.",
        ),
      ]);
      final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);
      expect(summary.result, 'complete');
      expect(summary.hasCodingActionPromiseWithoutToolWarning, isTrue);
      expect(
        summary.warnings.single.evidencePreview,
        startsWith("I'll implement"),
      );
    },
  );

  test('does not warn on promises confined to thinking', () async {
    final logFile = _writeSessionLog([
      _entry(
        operation: 'streamChatCompletion',
        finishReason: 'stop',
        content:
            '<think>I will implement the Python code.</think>'
            'The Python code was implemented and tested.',
      ),
    ]);
    final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);
    expect(summary.result, 'complete');
    expect(summary.hasWarnings, isFalse);
  });

  test('warns on a let-me fix promise after completed substeps', () async {
    final logFile = _writeSessionLog([
      _entry(
        operation: 'streamChatCompletion',
        finishReason: 'stop',
        content: 'watcher.py was updated. Let me make the fixes:',
      ),
    ]);
    final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);
    expect(summary.result, 'complete');
    expect(summary.hasCodingActionPromiseWithoutToolWarning, isTrue);
  });

  test('pending verification prose is advisory', () async {
    final logFile = _writeSessionLog([
      _entry(
        operation: 'streamChatCompletion',
        finishReason: 'stop',
        content:
            'The implementation is complete.\nUnexecuted verification command:\n'
            '```\n.venv/bin/python -m pytest test_watcher.py\n```',
      ),
    ]);
    final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);
    expect(summary.result, 'complete');
    expect(summary.warnings.single.code, 'coding_task_incomplete');
  });

  test('remaining work prose preserves the loop-limit result', () async {
    final logFile = _writeSessionLog([
      _entry(
        operation: 'streamChatCompletion',
        finishReason: 'stop',
        requestMessages: [
          _message('user', 'You hit the bounded tool loop limit.'),
        ],
        content:
            '**\u672a\u5b8c\u4e86\u306e\u4f5c\u696d:**\n'
            '`test_watcher.py` \u306b `**kwargs` \u3092\u8ffd\u52a0\u3059\u308b\u3002\n'
            '\u30bf\u30b9\u30af\u306f\u672a\u5b8c\u3067\u3059\u3002',
      ),
    ]);
    final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);
    expect(summary.result, 'loop_limit_recovered');
    expect(summary.warnings.single.code, 'coding_task_incomplete');
  });

  test('partial completion prose is advisory', () async {
    final logFile = _writeSessionLog([
      _entry(
        operation: 'streamChatCompletion',
        finishReason: 'stop',
        content:
            'The Python implementation is partially complete.\n'
            '- Implement notifier.py.\nThe task remains incomplete.',
      ),
      _entry(operation: 'turn_exit', turnExitReason: 'text_response'),
    ]);
    final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);
    expect(summary.result, 'complete');
    expect(summary.warnings.single.code, 'coding_task_incomplete');
  });

  for (final status in const [
    'missing',
    'progressLogged',
    'completionRejected',
    'blockerLogged',
    'completionRecorded',
  ]) {
    test('uses structured task status $status regardless of prose', () async {
      final summary = await buildCavernoLlmSessionLogSummary(
        logFile: _writeSessionLog([
          _entry(
            operation: 'streamChatCompletion',
            finishReason: 'stop',
            content: 'Done.',
          ),
          _entry(
            operation: 'turn_exit',
            turnExitReason: 'text_response',
            turnExitTransforms: ['coding_task_status_$status'],
          ),
        ]),
      );
      expect(
        summary.result,
        status == 'completionRecorded' ? 'complete' : 'incomplete',
      );
      expect(
        summary.warnings.any(
          (warning) => warning.code == 'coding_task_status_unresolved',
        ),
        status != 'completionRecorded',
      );
    });
  }

  test('a later final answer supersedes an earlier coding promise', () async {
    final logFile = _writeSessionLog([
      _entry(
        operation: 'streamChatCompletion',
        finishReason: 'stop',
        content: 'I will implement the Python code.',
      ),
      _entry(
        operation: 'streamChatCompletion',
        finishReason: 'stop',
        content: 'The Python code was implemented and tested.',
      ),
    ]);
    final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);
    expect(summary.result, 'complete');
    expect(summary.finalAnswer?.lineNumber, 2);
  });

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

  test('discarded calls remain visible despite a final answer', () async {
    final logFile = _writeSessionLog([
      _entry(
        operation: 'streamChatCompletion',
        finishReason: 'stop',
        content: 'The retry implementation remains incomplete.',
      ),
      _entry(
        operation: 'turn_exit',
        turnExitReason: 'all_calls_discarded',
        turnExitTransforms: const ['unwritten_file_claim_notice'],
      ),
    ]);
    final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);

    expect(summary.result, 'all_calls_discarded');
    expect(summary.finalAnswer?.lineNumber, 1);
    expect(summary.hasFatalError, isFalse);
    expect(summary.warnings.map((warning) => warning.code), [
      'coding_task_incomplete',
      'all_calls_discarded',
      'unwritten_file_claim',
    ]);
    expect(summary.toMarkdown(), contains('all_calls_discarded'));
  });

  test('a later terminal turn supersedes an earlier discarded turn', () async {
    final logFile = _writeSessionLog([
      _entry(operation: 'turn_exit', turnExitReason: 'all_calls_discarded'),
      _entry(
        operation: 'streamChatCompletion',
        finishReason: 'stop',
        content: 'The requested inspection is complete.',
      ),
      _entry(operation: 'turn_exit', turnExitReason: 'text_response'),
    ]);
    final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);

    expect(summary.result, 'complete');
    expect(summary.warnings.single.code, 'all_calls_discarded');
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
  return _writeRawSessionLog(entries.map(jsonEncode).toList(growable: false));
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
  List<String> turnExitTransforms = const [],
  String? turnExitReason,
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
    if (turnExitTransforms.isNotEmpty || turnExitReason != null)
      'turnExit': {
        'reason': turnExitReason ?? 'text_response',
        'transforms': turnExitTransforms,
      },
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
