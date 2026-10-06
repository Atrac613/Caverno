import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_tool_depth_probe.dart';
import 'package:caverno/features/settings/domain/services/live_llm_tool_depth_staircase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'passes all rungs with immutable metrics and completed-response usage',
    () async {
      final harness = _Harness();
      final measurement = await harness.run();
      final result = measurement.result;
      expect(result.id, 'tool_state_staircase');
      expect(result.status, LiveLlmDiagnosticStatus.passed);
      expect(
        result.summary,
        'The model carried state through every rung of the staircase.',
      );
      expect(
        result.details,
        'Deepest passed depth: 4 of 4\nAttempted depths: 2, 3, 4',
      );
      expect(result.passedChecks, 3);
      expect(result.totalChecks, 3);
      expect(result.modelContent, 'att-91');
      expect(result.usage.toJson(), {
        'promptTokens': 24,
        'completionTokens': 36,
        'totalTokens': 60,
      });
      expect(result.elapsed, const Duration(seconds: 7));
      expect(measurement.metrics.deepestPassedDepth, 4);
      expect(measurement.metrics.attemptedDepths, [2, 3, 4]);
      expect(measurement.metrics.failureDetail, '');
      expect(
        () => measurement.metrics.attemptedDepths.add(5),
        throwsUnsupportedError,
      );
      expect(harness.requests, hasLength(12));
    },
  );

  test(
    'step catalogs, observation wording and final tool omission are preserved',
    () async {
      final harness = _Harness();
      await harness.run();
      for (final request in harness.requests) {
        final rung = _rungFor(request.messages);
        if (_isFinal(request.messages)) {
          expect(request.tools, isNull);
          final message = request.messages.last;
          expect(message.role, MessageRole.user);
          expect(
            message.id,
            'live-llm-tool-depth-final-${_now.microsecondsSinceEpoch}',
          );
          expect(message.timestamp, _now);
          expect(
            message.content,
            'Every tool call is done. Now answer, using the exact values the '
            'tool results gave you and no other text.',
          );
        } else {
          expect(
            request.tools,
            same(LiveLlmToolDepthStaircase.toolDefinitions),
          );
        }
        final observations = request.messages
            .where((m) => m.content.startsWith('Tool result for '))
            .toList();
        for (var i = 0; i < observations.length; i++) {
          final step = rung.steps[i];
          final message = observations[i];
          expect(message.role, MessageRole.user);
          expect(message.timestamp, _now);
          expect(
            message.id,
            'live-llm-tool-depth-${step.toolName}-${_now.microsecondsSinceEpoch}',
          );
          expect(
            message.content,
            'Tool result for ${step.toolName}:\n'
            '${jsonEncode(step.result)}\n\n'
            'The task is not finished. Call the next tool you need, using '
            'the values this result gave you. Do not answer in text yet.',
          );
        }
      }
    },
  );

  final failures =
      <
        String,
        ({int depth, int turn, ChatCompletionResult reply, String detail})
      >{
        'text instead of first call': (
          depth: 2,
          turn: 0,
          reply: _answer('Cannot search'),
          detail: 'expected a search_docs call and got a text answer',
        ),
        'wrong search tool': (
          depth: 2,
          turn: 0,
          reply: _call('search_wiki', {'query': 'flash attention'}),
          detail: 'called search_wiki where search_docs was expected',
        ),
        'wrong pinned query': (
          depth: 2,
          turn: 0,
          reply: _call('search_docs', {'query': 'other'}),
          detail:
              'search_docs carried query=other where flash attention was expected',
        ),
        'missing pinned argument': (
          depth: 2,
          turn: 0,
          reply: _call('search_docs', {}),
          detail:
              'search_docs carried query=nothing where flash attention was expected',
        ),
        'opens first rather than newest document': (
          depth: 3,
          turn: 1,
          reply: _call('open_doc', {'doc_id': 'doc-ds-17'}),
          detail:
              'open_doc carried doc_id=doc-ds-17 where doc-ds-42 was expected',
        ),
        'answers before third step': (
          depth: 3,
          turn: 2,
          reply: _answer('doc-ds-42'),
          detail: 'expected a summarize_doc call and got a text answer',
        ),
        'wrong attach revision': (
          depth: 4,
          turn: 3,
          reply: _call('attach_summary', {
            'doc_id': 'doc-ds-42',
            'revision': 'rev-6',
          }),
          detail:
              'attach_summary carried revision=rev-6 where rev-7 was expected',
        ),
        'loses final document': (
          depth: 2,
          turn: 2,
          reply: _answer('Done'),
          detail: 'the answer lost doc-ds-42',
        ),
        'loses final revision': (
          depth: 3,
          turn: 3,
          reply: _answer('doc-ds-42'),
          detail: 'the answer lost rev-7',
        ),
        'reasoning alone carries attachment': (
          depth: 4,
          turn: 4,
          reply: _answer('<think>att-91</think>Done'),
          detail: 'the answer lost att-91',
        ),
        'final matching remains case sensitive': (
          depth: 2,
          turn: 2,
          reply: _answer('DOC-DS-42'),
          detail: 'the answer lost doc-ds-42',
        ),
      };
  for (final entry in failures.entries) {
    test(
      'stops at ${entry.key} with warning headroom and exact failure evidence',
      () async {
        final failure = entry.value;
        final harness = _Harness(
          override: (rung, turn, _) =>
              rung.depth == failure.depth && turn == failure.turn
              ? failure.reply
              : null,
        );
        final measurement = await harness.run();
        final result = measurement.result;
        final attempted = LiveLlmToolDepthStaircase.stageDepths
            .where((d) => d <= failure.depth)
            .toList();
        final deepest = failure.depth == 2 ? 0 : failure.depth - 1;
        expect(result.status, LiveLlmDiagnosticStatus.warning);
        expect(measurement.metrics.deepestPassedDepth, deepest);
        expect(measurement.metrics.attemptedDepths, attempted);
        expect(
          measurement.metrics.failureDetail,
          'depth ${failure.depth}: ${failure.detail}',
        );
        expect(
          result.details,
          'Deepest passed depth: $deepest of 4\n'
          'Attempted depths: ${attempted.join(', ')}\n'
          'depth ${failure.depth}: ${failure.detail}',
        );
        expect(
          result.summary,
          deepest == 0
              ? 'The model did not carry state through two tool calls.'
              : 'The model carried state through $deepest sequential tool calls.',
        );
        expect(result.passedChecks, attempted.length - 1);
        expect(result.totalChecks, 3);
        expect(
          harness.requests.where(
            (r) => _rungFor(r.messages).depth == failure.depth,
          ),
          hasLength(failure.turn + 1),
        );
        expect(
          harness.requests.any(
            (r) => _rungFor(r.messages).depth > failure.depth,
          ),
          isFalse,
        );
        expect(result.usage.totalTokens, harness.requests.length * 5);
        if (failure.reply.toolCalls != null) {
          // Depth originally uses content for mismatched-call previews, unlike recovery.
          expect(result.modelContent, isEmpty);
        }
      },
    );
  }

  for (final finalRequest in [false, true]) {
    test(
      'contains ${finalRequest ? 'final' : 'step'} request errors and excludes their usage',
      () async {
        final harness = _Harness(
          override: (rung, turn, isFinal) {
            if (rung.depth == 3 &&
                isFinal == finalRequest &&
                (isFinal || turn == 1)) {
              throw StateError('offline');
            }
            return null;
          },
        );
        final measurement = await harness.run();
        expect(measurement.result.status, LiveLlmDiagnosticStatus.warning);
        expect(measurement.metrics.deepestPassedDepth, 2);
        expect(measurement.metrics.attemptedDepths, [2, 3]);
        expect(
          measurement.metrics.failureDetail,
          'depth 3: the ${finalRequest ? 'final request' : 'request'} failed (Bad state: offline)',
        );
        expect(measurement.result.modelContent, isEmpty);
        expect(
          measurement.result.usage.totalTokens,
          (harness.requests.length - 1) * 5,
        );
      },
    );
  }

  test(
    'bounds request-error previews and reports zero-depth warning',
    () async {
      final measurement = await _Harness(
        override: (_, _, _) => throw StateError('x' * 200),
      ).run();
      expect(measurement.result.status, LiveLlmDiagnosticStatus.warning);
      expect(measurement.result.passedChecks, 0);
      expect(measurement.result.usage.totalTokens, 0);
      expect(measurement.metrics.attemptedDepths, [2]);
      expect(measurement.metrics.failureDetail, endsWith('...)'));
      expect(
        measurement.metrics.failureDetail.length,
        'depth 2: the request failed ('.length + 123 + 1,
      );
    },
  );

  test('optional arguments and trimmed pinned values stay accepted', () async {
    final measurement = await _Harness(
      override: (rung, turn, _) {
        if (turn == 0) {
          return _call('search_docs', {
            'query': ' flash attention ',
            'top_k': 99,
            'optional': true,
          });
        }
        return null;
      },
    ).run();
    expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
  });

  test(
    'only the first tool call is scored, retaining the existing contract',
    () async {
      final measurement = await _Harness(
        override: (rung, turn, _) {
          if (turn == 0) {
            return ChatCompletionResult(
              content: '',
              finishReason: 'tool_calls',
              toolCalls: [
                ToolCallInfo(
                  id: 'first',
                  name: 'search_docs',
                  arguments: {'query': 'flash attention'},
                ),
                ToolCallInfo(id: 'second', name: 'search_wiki', arguments: {}),
              ],
            );
          }
          return null;
        },
      ).run();
      expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
    },
  );

  test(
    'final response remains scored by content even if it includes a tool call',
    () async {
      final measurement = await _Harness(
        override: (rung, _, isFinal) {
          if (!isFinal) return null;
          return ChatCompletionResult(
            content: rung.expectedFinalValues.join(' '),
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(id: 'final', name: 'search_wiki', arguments: {}),
            ],
          );
        },
      ).run();
      expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
    },
  );

  test(
    'final previews strip reasoning and keep the original 240-character cap',
    () async {
      final measurement = await _Harness(
        override: (rung, _, isFinal) {
          if (rung.depth == 4 && isFinal) {
            return _answer('<think>hidden</think>att-91 ${'x' * 300}');
          }
          return null;
        },
      ).run();
      expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
      expect(measurement.result.modelContent, startsWith('att-91 '));
      expect(measurement.result.modelContent, endsWith('...'));
      expect(measurement.result.modelContent.length, 243);
    },
  );
}

final _startedAt = DateTime.utc(2026, 10, 3);
final _now = _startedAt.add(const Duration(seconds: 7));

ChatCompletionResult _answer(String content) =>
    ChatCompletionResult(content: content, finishReason: 'stop');
ChatCompletionResult _call(String name, Map<String, dynamic> arguments) =>
    ChatCompletionResult(
      content: '',
      finishReason: 'tool_calls',
      toolCalls: [
        ToolCallInfo(id: 'test-$name', name: name, arguments: arguments),
      ],
    );
LiveLlmToolDepthRung _rungFor(List<Message> messages) =>
    LiveLlmToolDepthStaircase.rungs.firstWhere(
      (r) => r.prompt == messages.first.content,
    );
bool _isFinal(List<Message> messages) =>
    messages.last.content.startsWith('Every tool call is done.');

typedef _Override =
    ChatCompletionResult? Function(
      LiveLlmToolDepthRung rung,
      int turn,
      bool isFinal,
    );

class _Request {
  _Request(this.messages, this.tools);
  final List<Message> messages;
  final List<Map<String, dynamic>>? tools;
}

class _Harness {
  _Harness({this.override});
  final _Override? override;
  final requests = <_Request>[];

  Future<LiveLlmToolDepthProbeMeasurement> run() => LiveLlmToolDepthProbe(
    messages: (user) => [
      Message(
        id: 'user',
        content: user,
        role: MessageRole.user,
        timestamp: _now,
      ),
    ],
    now: () => _now,
    complete: ({required messages, tools}) async {
      requests.add(_Request(messages, tools));
      final rung = _rungFor(messages);
      final turn = messages
          .where((m) => m.content.startsWith('Tool result for '))
          .length;
      final isFinal = _isFinal(messages);
      final step = isFinal ? null : rung.steps[turn];
      final result =
          override?.call(rung, turn, isFinal) ??
          (isFinal
              ? _answer(rung.expectedFinalValues.join(' '))
              : _call(
                  step!.toolName,
                  Map<String, dynamic>.from(step.expectedArguments),
                ));
      return ChatCompletionResult(
        content: result.content,
        toolCalls: result.toolCalls,
        finishReason: result.finishReason,
        usage: const TokenUsage(
          promptTokens: 2,
          completionTokens: 3,
          totalTokens: 5,
        ),
      );
    },
  ).run(startedAt: _startedAt);
}
