import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_multi_round_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'preserves sequential requests, observations, scores and physical metrics',
    () async {
      final harness = _Harness();
      final measurement = await harness.run();
      final result = measurement.result;
      expect(result.id, 'multi_round_tool_loop');
      expect(result.status, LiveLlmDiagnosticStatus.passed);
      expect(result.passedChecks, 6);
      expect(result.totalChecks, 6);
      expect(result.toolCalls, ['tool_search', 'get_current_datetime']);
      expect(() => result.toolCalls.add('other'), throwsUnsupportedError);
      expect(result.usage.toJson(), {
        'promptTokens': 6,
        'completionTokens': 9,
        'totalTokens': 15,
      });
      expect(measurement.metrics.modelTurnCount, 3);
      expect(measurement.metrics.toolCallCount, 2);
      expect(measurement.metrics.successfulToolExecutionCount, 2);
      expect(measurement.metrics.promptTokens, 6);
      expect(measurement.metrics.completionTokens, 9);
      expect(measurement.metrics.taskCompleted, isTrue);
      expect(
        measurement.metrics.totalElapsed,
        greaterThanOrEqualTo(Duration.zero),
      );
      expect(harness.requests[0].tools, [_searchTool]);
      expect(harness.requests[0].results, isNull);
      expect(harness.requests[1].tools, [_searchTool, _dateTool]);
      expect(harness.requests[2].tools, isEmpty);
      expect(
        harness.requests.every(
          (r) => identical(r.messages, harness.requests.first.messages),
        ),
        isTrue,
      );
      expect(
        harness.requests.first.messages.single.content,
        'Find the available tool that reports the current date and timezone, '
        'use it, then return JSON with marker="CAVERNO_MULTI_ROUND_LOOP_OK", '
        'today copied from relative_dates.today, and timezone copied from '
        'the datetime result.',
      );
      expect(harness.requests[1].results!.single.id, 'search-id');
      expect(harness.requests[1].results!.single.result, _discovery);
      expect(harness.requests[2].results!.single.id, 'date-id');
      expect(harness.requests[2].results!.single.result, _datetime);
      expect(harness.executions.map((e) => e.name), [
        'tool_search',
        'get_current_datetime',
      ]);
    },
  );

  for (final absent in ['search', 'datetime', 'execution']) {
    test('skips absent $absent without any requests or executions', () async {
      final harness = _Harness();
      final measurement = await harness.run(absent: absent);
      expect(measurement.result.status, LiveLlmDiagnosticStatus.skipped);
      expect(
        measurement.result.summary,
        'The sequential local tools are not available.',
      );
      expect(measurement.result.passedChecks, 0);
      expect(measurement.result.totalChecks, 3);
      expect(measurement.metrics.modelTurnCount, 0);
      expect(measurement.metrics.taskCompleted, isFalse);
      expect(harness.requests, isEmpty);
      expect(harness.executions, isEmpty);
    });
  }

  for (final calls in <List<ToolCallInfo>>[
    [],
    [_call('get_current_datetime')],
    [_call('tool_search'), _call('delete_file')],
  ]) {
    test(
      'rejects first-turn calls ${calls.map((c) => c.name)} before execution',
      () async {
        final harness = _Harness(replies: [_reply(calls: calls)]);
        final measurement = await harness.run();
        expect(measurement.result.status, LiveLlmDiagnosticStatus.failed);
        expect(
          measurement.result.summary,
          'The first turn did not call tool_search.',
        );
        expect(measurement.result.toolCalls, calls.map((c) => c.name));
        expect(measurement.metrics.toolCallCount, calls.length);
        expect(measurement.metrics.modelTurnCount, 1);
        expect(harness.executions, isEmpty);
        expect(harness.requests, hasLength(1));
      },
    );
  }

  test(
    'executes all parallel searches in order and unions discovery with fallback IDs',
    () async {
      final harness = _Harness(
        replies: [
          _reply(
            calls: [
              _call('tool_search', id: '', arguments: {'query': 'first'}),
              _call('tool_search', id: '', arguments: {'query': 'second'}),
            ],
          ),
          _reply(calls: [_call('get_current_datetime', id: '')]),
          _reply(content: _answer),
        ],
        execute: (name, arguments, _) => _execution(
          name,
          name == 'tool_search' && arguments['query'] == 'first'
              ? '{"matched_tools":[]}'
              : name == 'tool_search'
              ? _discovery
              : _datetime,
        ),
      );
      final measurement = await harness.run();
      expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
      expect(measurement.metrics.toolCallCount, 3);
      expect(measurement.metrics.successfulToolExecutionCount, 3);
      expect(harness.executions.map((e) => e.arguments), [
        {'query': 'first'},
        {'query': 'second'},
        {},
      ]);
      expect(harness.requests[1].results!.map((r) => r.id), [
        'diagnostic-tool-search-call-0',
        'diagnostic-tool-search-call-1',
      ]);
      expect(
        harness.requests[2].results!.single.id,
        'diagnostic-datetime-call',
      );
    },
  );

  test('counts repeated datetime calls but executes only the first', () async {
    final harness = _Harness(
      replies: [
        _searchReply,
        _reply(
          calls: [
            _call('get_current_datetime', arguments: {'selected': 1}),
            _call('get_current_datetime', arguments: {'selected': 2}),
          ],
        ),
        _reply(content: _answer),
      ],
    );
    final measurement = await harness.run();
    expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
    expect(measurement.metrics.toolCallCount, 3);
    expect(measurement.metrics.successfulToolExecutionCount, 2);
    expect(harness.executions.last.arguments, {'selected': 1});
    expect(harness.requests.last.results, hasLength(1));
  });

  for (final message in <String?>['catalog offline', null]) {
    test(
      'search failure retains ${message == null ? 'result fallback' : 'error message'} and stops',
      () async {
        final harness = _Harness(
          execute: (name, _, _) => McpToolResult(
            toolName: name,
            result: 'failure result',
            isSuccess: false,
            errorMessage: message,
          ),
        );
        final measurement = await harness.run();
        expect(measurement.result.status, LiveLlmDiagnosticStatus.failed);
        expect(
          measurement.result.summary,
          'The local tool catalog search failed.',
        );
        expect(measurement.result.details, message ?? 'failure result');
        expect(measurement.result.passedChecks, 0);
        expect(measurement.metrics.successfulToolExecutionCount, 0);
        expect(harness.requests, hasLength(1));
      },
    );
  }

  test(
    'failed later search retains successful execution and observed-call counts',
    () async {
      final harness = _Harness(
        replies: [
          _reply(calls: [_call('tool_search'), _call('tool_search')]),
        ],
        execute: (name, _, index) => index == 0
            ? _execution(name, _discovery)
            : McpToolResult(toolName: name, result: 'failed', isSuccess: false),
      );
      final measurement = await harness.run();
      expect(measurement.metrics.toolCallCount, 2);
      expect(measurement.metrics.successfulToolExecutionCount, 1);
      expect(harness.requests, hasLength(1));
    },
  );

  test(
    'missing datetime discovery bounds evidence and never asks the next turn',
    () async {
      final harness = _Harness(
        execute: (name, _, _) => _execution(name, 'x' * 1300),
      );
      final measurement = await harness.run();
      expect(
        measurement.result.summary,
        'Tool search did not discover get_current_datetime.',
      );
      expect(measurement.result.status, LiveLlmDiagnosticStatus.failed);
      expect(measurement.result.passedChecks, 1);
      expect(measurement.result.details.length, 1203);
      expect(harness.requests, hasLength(1));
    },
  );

  for (final calls in <List<ToolCallInfo>>[
    [],
    [_call('tool_search')],
    [_call('get_current_datetime'), _call('delete_file')],
  ]) {
    test(
      'rejects second-turn calls ${calls.map((c) => c.name)} before datetime execution',
      () async {
        final harness = _Harness(
          replies: [
            _searchReply,
            _reply(calls: calls),
          ],
        );
        final measurement = await harness.run();
        expect(
          measurement.result.summary,
          'The second turn did not call get_current_datetime.',
        );
        expect(measurement.result.status, LiveLlmDiagnosticStatus.failed);
        expect(measurement.result.passedChecks, 1);
        expect(measurement.metrics.toolCallCount, calls.length + 1);
        expect(harness.executions, hasLength(1));
        expect(harness.requests, hasLength(2));
      },
    );
  }

  test(
    'datetime execution failure retains partial usage and execution metrics',
    () async {
      final harness = _Harness(
        execute: (name, _, _) => name == 'tool_search'
            ? _execution(name, _discovery)
            : McpToolResult(
                toolName: name,
                result: 'failed',
                isSuccess: false,
                errorMessage: 'clock offline',
              ),
      );
      final measurement = await harness.run();
      expect(measurement.result.status, LiveLlmDiagnosticStatus.failed);
      expect(measurement.result.summary, 'The local datetime tool failed.');
      expect(measurement.result.details, 'clock offline');
      expect(measurement.result.usage.totalTokens, 10);
      expect(measurement.metrics.successfulToolExecutionCount, 1);
      expect(harness.requests, hasLength(2));
    },
  );

  for (final key in ['marker', 'today', 'timezone']) {
    test(
      'warns when final $key differs with original six-check denominator',
      () async {
        final answer = jsonDecode(_answer) as Map<String, dynamic>;
        answer[key] = 'wrong';
        final measurement = await _Harness(
          replies: [
            _searchReply,
            _dateReply,
            _reply(content: jsonEncode(answer)),
          ],
        ).run();
        expect(measurement.result.status, LiveLlmDiagnosticStatus.warning);
        expect(measurement.result.passedChecks, 5);
        expect(measurement.result.totalChecks, 6);
        expect(measurement.metrics.taskCompleted, isFalse);
      },
    );
  }

  test(
    'extra final calls warn, count as evidence and are never executed',
    () async {
      final harness = _Harness(
        replies: [
          _searchReply,
          _dateReply,
          _reply(content: _answer, calls: [_call('delete_file')]),
        ],
      );
      final measurement = await harness.run();
      expect(measurement.result.status, LiveLlmDiagnosticStatus.warning);
      expect(measurement.result.passedChecks, 5);
      expect(
        measurement.result.details,
        contains('No extra final calls: false'),
      );
      expect(measurement.result.toolCalls.last, 'delete_file');
      expect(measurement.metrics.toolCallCount, 3);
      expect(harness.executions, hasLength(2));
    },
  );

  test(
    'malformed final content warns and reasoning alone cannot satisfy fields',
    () async {
      final measurement = await _Harness(
        replies: [
          _searchReply,
          _dateReply,
          _reply(content: '<think>$_answer</think>Done'),
        ],
      ).run();
      expect(measurement.result.status, LiveLlmDiagnosticStatus.warning);
      expect(measurement.result.passedChecks, 3);
    },
  );

  test(
    'visible JSON after reasoning passes while raw preview stays bounded',
    () async {
      final content = '<think>${'x' * 2100}</think>$_answer';
      final measurement = await _Harness(
        replies: [
          _searchReply,
          _dateReply,
          _reply(content: content),
        ],
      ).run();
      expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
      expect(measurement.result.modelContent, startsWith('<think>'));
      expect(measurement.result.modelContent.length, 2003);
    },
  );

  test(
    'malformed datetime payload leaves copied date and timezone unsatisfied',
    () async {
      final measurement = await _Harness(
        execute: (name, _, _) =>
            _execution(name, name == 'tool_search' ? _discovery : 'invalid'),
      ).run();
      expect(measurement.result.status, LiveLlmDiagnosticStatus.warning);
      expect(measurement.result.passedChecks, 4);
    },
  );

  test('textual bridge calls retain sequential execution', () async {
    final measurement = await _Harness(
      replies: [
        _reply(
          content:
              '<tool_call>{"name":"tool_search","arguments":{"query":"clock"}}</tool_call>',
        ),
        _reply(
          content:
              '<tool_call>{"name":"get_current_datetime","arguments":{}}</tool_call>',
        ),
        _reply(content: _answer),
      ],
    ).run();
    expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
    expect(measurement.metrics.toolCallCount, 2);
  });

  for (final turn in [0, 1, 2]) {
    test(
      'completion exceptions at turn $turn propagate to the service boundary',
      () async {
        final error = StateError('completion failed');
        final replies = <Object>[
          _searchReply,
          _dateReply,
          _reply(content: _answer),
        ];
        replies[turn] = error;
        await expectLater(
          _Harness(replies: replies).run(),
          throwsA(same(error)),
        );
      },
    );
  }

  for (final tool in ['tool_search', 'get_current_datetime']) {
    test(
      '$tool execution exceptions propagate to the service boundary',
      () async {
        final error = StateError('execution failed');
        await expectLater(
          _Harness(
            execute: (name, _, _) {
              if (name == tool) {
                throw error;
              }
              return _execution(name, _discovery);
            },
          ).run(),
          throwsA(same(error)),
        );
      },
    );
  }

  test(
    'invalid typed datetime fields preserve the existing decoding exception',
    () async {
      await expectLater(
        _Harness(
          execute: (name, _, _) => _execution(
            name,
            name == 'tool_search'
                ? _discovery
                : '{"relative_dates":{"today":47},"timezone":"UTC"}',
          ),
        ).run(),
        throwsA(isA<TypeError>()),
      );
    },
  );
}

const _searchTool = <String, dynamic>{
  'type': 'function',
  'function': {'name': 'tool_search'},
};
const _dateTool = <String, dynamic>{
  'type': 'function',
  'function': {'name': 'get_current_datetime'},
};
const _discovery = '{"matched_tools":[{"name":"get_current_datetime"}]}';
const _datetime = '{"relative_dates":{"today":"2026-10-03"},"timezone":"UTC"}';
const _answer =
    '{"marker":"CAVERNO_MULTI_ROUND_LOOP_OK","today":"2026-10-03","timezone":"UTC"}';
final _searchReply = _reply(
  calls: [
    _call('tool_search', id: 'search-id', arguments: {'query': 'clock'}),
  ],
);
final _dateReply = _reply(
  calls: [_call('get_current_datetime', id: 'date-id')],
);
ToolCallInfo _call(
  String name, {
  String id = 'call-id',
  Map<String, dynamic> arguments = const {},
}) => ToolCallInfo(id: id, name: name, arguments: arguments);
ChatCompletionResult _reply({String content = '', List<ToolCallInfo>? calls}) =>
    ChatCompletionResult(
      content: content,
      toolCalls: calls,
      finishReason: calls == null ? 'stop' : 'tool_calls',
      usage: const TokenUsage(
        promptTokens: 2,
        completionTokens: 3,
        totalTokens: 5,
      ),
    );
McpToolResult _execution(String name, String result) =>
    McpToolResult(toolName: name, result: result, isSuccess: true);
typedef _Execution =
    McpToolResult Function(
      String name,
      Map<String, dynamic> arguments,
      int index,
    );

class _Request {
  _Request(this.messages, this.tools, this.results);
  final List<Message> messages;
  final List<Map<String, dynamic>> tools;
  final List<ToolResultInfo>? results;
}

class _Harness {
  _Harness({List<Object>? replies, this.execute})
    : replies = replies ?? [_searchReply, _dateReply, _reply(content: _answer)];
  final List<Object> replies;
  final _Execution? execute;
  final requests = <_Request>[];
  final executions = <ToolCallInfo>[];
  Future<ChatCompletionResult> complete(
    List<Message> messages,
    List<Map<String, dynamic>> tools,
    List<ToolResultInfo>? results,
  ) async {
    final response = replies[requests.length];
    requests.add(_Request(messages, tools, results));
    if (response is ChatCompletionResult) {
      return response;
    }
    throw response;
  }

  Future<LiveLlmMultiRoundProbeMeasurement> run({String? absent}) =>
      LiveLlmMultiRoundProbe(
        complete: ({required messages, required tools}) =>
            complete(messages, tools, null),
        completeWithToolResults:
            ({required messages, required tools, required toolResults}) =>
                complete(messages, tools, toolResults),
        messages: (user) => [
          Message(
            id: 'user',
            content: user,
            role: MessageRole.user,
            timestamp: DateTime.utc(2026, 10, 3),
          ),
        ],
      ).run(
        searchTool: absent == 'search' ? null : _searchTool,
        dateTool: absent == 'datetime' ? null : _dateTool,
        execute: absent == 'execution'
            ? null
            : ({required name, required arguments}) async {
                final index = executions.length;
                executions.add(_call(name, arguments: arguments));
                return execute?.call(name, arguments, index) ??
                    _execution(
                      name,
                      name == 'tool_search' ? _discovery : _datetime,
                    );
              },
      );
}
