import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_service.dart';
import 'package:caverno/features/settings/domain/services/live_llm_thinking_control_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const classifications = [
    'never_reasoned',
    'controllable',
    'inverted',
    'always_on',
  ];
  const summaries = [
    'No reasoning came back with thinking switched on. A router or server '
        'default may force thinking off, or the model does not reason.',
    'The endpoint honours enable_thinking in both directions.',
    'Reasoning came back only with thinking switched off, the reverse of the request.',
    'The model reasoned with thinking switched off; something on the way ignores enable_thinking: false.',
  ];
  for (var mask = 0; mask < 4; mask++) {
    test('classifies both mode responses for mask $mask', () async {
      final onChars = mask & 1 == 0 ? 0 : 3;
      final offChars = mask & 2 == 0 ? 0 : 3;
      final h = _Harness(
        on: _reply(
          onChars == 0 ? 'answer' : '<think> abc </think>answer',
          finish: 'stop',
          prompt: 10,
          completion: 3,
        ),
        off: _reply(
          offChars == 0 ? 'answer' : '<think> xyz </think>answer',
          finish: 'length',
          prompt: 20,
          completion: 5,
        ),
      );
      final result = await h.run();
      expect(h.modes, [
        LiveLlmDiagnosticThinkingMode.on,
        LiveLlmDiagnosticThinkingMode.off,
      ]);
      expect(result.id, 'thinking_control');
      expect(
        result.status,
        mask == 1
            ? LiveLlmDiagnosticStatus.passed
            : LiveLlmDiagnosticStatus.warning,
      );
      expect(result.summary, summaries[mask]);
      expect(result.metadata, {'thinkingControl': classifications[mask]});
      expect(
        result.details,
        'Classification: ${classifications[mask]}\n'
        'Thinking on: $onChars reasoning chars (finish_reason: stop)\n'
        'Thinking off: $offChars reasoning chars (finish_reason: length)',
      );
      expect(result.usage.toJson(), {
        'promptTokens': 30,
        'completionTokens': 8,
        'totalTokens': 38,
      });
      expect(result.modelContent, isEmpty);
      expect(result.toolCalls, isEmpty);
      expect(result.passedChecks, 0);
      expect(result.totalChecks, 0);
    });
  }

  test('retains public prompt and service metadata compatibility', () {
    expect(
      LiveLlmThinkingControlProbe.prompt,
      'Reply with exactly CAVERNO_THINKING_CONTROL and no other text.',
    );
    expect(
      LiveLlmDiagnosticService.thinkingControlMetadataKey,
      LiveLlmThinkingControlProbe.metadataKey,
    );
  });

  for (final entry in <String, int>{
    '<think> first </think>answer<think>second</think>': 11,
    '<think>unfinished': 10,
    '<think> \n </think>answer': 0,
    'plain visible reasoning': 0,
  }.entries) {
    test('uses existing reasoning parser for ${entry.key}', () async {
      final result = await _Harness(on: _reply(entry.key)).run();
      expect(
        result.metadata['thinkingControl'],
        entry.value > 0 ? 'controllable' : 'never_reasoned',
      );
      expect(
        result.details,
        contains('Thinking on: ${entry.value} reasoning chars'),
      );
    });
  }

  test('does not count stream-only reasoning absent from content', () async {
    final result = await _Harness(
      on: ChatCompletionResult(
        content: 'answer',
        streamedReasoning: 'reasoning',
        finishReason: 'stop',
      ),
    ).run();
    expect(result.metadata['thinkingControl'], 'never_reasoned');
  });

  for (final failure in LiveLlmDiagnosticThinkingMode.values) {
    test('propagates $failure failure and stops subsequent requests', () async {
      final h = _Harness(failure: failure);
      await expectLater(h.run(), throwsStateError);
      expect(
        h.modes,
        failure == LiveLlmDiagnosticThinkingMode.on
            ? [LiveLlmDiagnosticThinkingMode.on]
            : LiveLlmDiagnosticThinkingMode.values,
      );
    });
  }
}

ChatCompletionResult _reply(
  String content, {
  String finish = 'stop',
  int prompt = 0,
  int completion = 0,
}) => ChatCompletionResult(
  content: content,
  finishReason: finish,
  usage: TokenUsage(
    promptTokens: prompt,
    completionTokens: completion,
    totalTokens: prompt + completion,
  ),
);

class _Harness {
  _Harness({ChatCompletionResult? on, ChatCompletionResult? off, this.failure})
    : on = on ?? _reply('answer'),
      off = off ?? _reply('answer');
  final ChatCompletionResult on;
  final ChatCompletionResult off;
  final LiveLlmDiagnosticThinkingMode? failure;
  final modes = <LiveLlmDiagnosticThinkingMode>[];
  Future<LiveLlmDiagnosticProbeResult> run() => LiveLlmThinkingControlProbe(
    complete: (mode) async {
      modes.add(mode);
      if (mode == failure) throw StateError('thinking $mode');
      return mode == LiveLlmDiagnosticThinkingMode.on ? on : off;
    },
  ).run();
}
