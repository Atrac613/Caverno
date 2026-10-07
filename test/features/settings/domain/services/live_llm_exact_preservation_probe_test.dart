import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_exact_preservation_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (var mask = 0; mask < 8; mask++) {
    test('scores all three literal arms for failure mask $mask', () async {
      final harness = _Harness(
        replies: [
          for (var i = 0; i < 3; i++)
            mask & (1 << i) == 0 ? _values[i] : '${_values[i]}.',
        ],
      );
      final result = await harness.run();
      final failures = [
        for (var i = 0; i < 3; i++)
          if (mask & (1 << i) != 0) i,
      ];
      expect(harness.requests, hasLength(3));
      expect(result.id, 'exact_preservation');
      expect(
        result.status,
        failures.isEmpty
            ? LiveLlmDiagnosticStatus.passed
            : failures.length == 3
            ? LiveLlmDiagnosticStatus.failed
            : LiveLlmDiagnosticStatus.warning,
      );
      expect(
        result.summary,
        failures.isEmpty
            ? 'The model preserved exact literal values across direct and tool-result prompts.'
            : failures.length == 3
            ? 'The model changed every exact literal preservation probe value.'
            : 'The model changed at least one exact literal preservation probe value.',
      );
      expect(result.passedChecks, 3 - failures.length);
      expect(result.totalChecks, 3);
      expect(result.elapsed, Duration.zero);
      expect(result.usage.toJson(), {
        'promptTokens': 30,
        'completionTokens': 9,
        'totalTokens': 39,
      });
      expect(
        result.details,
        [
          for (var i = 0; i < 3; i++)
            '${_labels[i]}: ${failures.contains(i) ? 'failed' : 'passed'}\n'
                'Expected: ${_values[i]}\nActual: ${harness.replies[i]}',
        ].join('\n\n'),
      );
      expect(
        result.modelContent,
        [
          for (var i = 0; i < 3; i++) '${_labels[i]}: ${harness.replies[i]}',
        ].join('\n'),
      );
    });
  }

  test(
    'preserves prompt text, tool-result envelope, roles and timestamps',
    () async {
      final harness = _Harness();
      await harness.run();
      expect(
        harness.requests.first.single.content,
        'Reply with exactly this text and no extra characters:\n${_values[0]}',
      );
      expect(
        harness.requests.last.single.content,
        'Reply with exactly this URL and no extra characters:\n${_values[2]}',
      );
      final toolMessages = harness.requests[1];
      expect(toolMessages, hasLength(2));
      expect(
        toolMessages.first.content,
        'Return only the product_label value from the diagnostic tool result. '
        'Do not add quotes, punctuation, or explanatory text.',
      );
      final tool = toolMessages.last;
      expect(tool.role, MessageRole.user);
      expect(
        tool.id,
        'live-llm-diagnostic-tool-result-${_now.microsecondsSinceEpoch}',
      );
      expect(tool.timestamp, _now.add(const Duration(milliseconds: 1)));
      expect(harness.nowCalls, 2);
      expect(
        tool.content,
        ToolResultPromptBuilder.buildAnswerPrompt(
          [
            ToolResultInfo(
              id: 'diagnostic-exact-value-call',
              name: 'diagnostic_exact_value',
              arguments: const {'field': 'product_label'},
              result: 'Raw result:\n{"product_label":"ZX-900_α 2026-06-12"}',
            ),
          ],
          descriptionsByName: const {
            'diagnostic_exact_value':
                'Provides exact raw values for preservation diagnostics.',
          },
        ),
      );
    },
  );

  test(
    'scores visible values but preserves raw reasoning in previews',
    () async {
      final harness = _Harness(
        replies: [
          for (final value in _values)
            '  <think>different literal</think>$value  ',
        ],
      );
      final result = await harness.run();
      expect(result.status, LiveLlmDiagnosticStatus.passed);
      expect(result.modelContent, contains('<think>different literal</think>'));
      expect(result.details, isNot(contains('<think>')));
    },
  );

  test(
    'bounds raw content and visible detail previews independently',
    () async {
      final content = List.filled(1000, 'x').join();
      final result = await _Harness(
        replies: [content, _values[1], _values[2]],
      ).run();
      expect(
        result.modelContent.split('\n').first,
        '${_labels[0]}: ${List.filled(360, 'x').join()}...',
      );
      expect(
        result.details,
        contains('Actual: ${List.filled(800, 'x').join()}...'),
      );
    },
  );

  test('finish reason does not override exact visible value scoring', () async {
    final result = await _Harness(finishReason: 'length').run();
    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(result.passedChecks, 3);
  });

  for (final arm in [1, 2, 3]) {
    test(
      'propagates arm $arm errors without running subsequent requests',
      () async {
        final failure = StateError('arm $arm');
        final harness = _Harness(failingArm: arm, failure: failure);
        await expectLater(harness.run(), throwsA(same(failure)));
        expect(harness.requests, hasLength(arm));
      },
    );
  }
}

const _values = [
  '12 GiB, ¥3,980',
  'ZX-900_α 2026-06-12',
  'https://example.test/downloads/build_2026-06-10.tar.zst?sha=abc123_def',
];
const _labels = [
  'direct_echo_money_unit',
  'tool_result_raw_value',
  'url_preservation',
];
final _now = DateTime.utc(2026, 10, 8);

class _Harness {
  _Harness({
    this.replies = _values,
    this.failingArm,
    this.failure,
    this.finishReason = 'stop',
  });
  final List<String> replies;
  final int? failingArm;
  final Object? failure;
  final String finishReason;
  final requests = <List<Message>>[];
  int nowCalls = 0;

  Future<LiveLlmDiagnosticProbeResult> run() => LiveLlmExactPreservationProbe(
    complete: ({required messages}) async {
      requests.add(messages);
      if (requests.length == failingArm) throw failure!;
      return ChatCompletionResult(
        content: replies[requests.length - 1],
        finishReason: finishReason,
        usage: const TokenUsage(
          promptTokens: 10,
          completionTokens: 3,
          totalTokens: 13,
        ),
      );
    },
    messages: (user) => [
      Message(
        id: 'fixture',
        role: MessageRole.user,
        content: user,
        timestamp: _now,
      ),
    ],
    now: () => _now.add(Duration(milliseconds: nowCalls++)),
  ).run();
}
