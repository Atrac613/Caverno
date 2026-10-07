import 'dart:math' as math;

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_effective_context_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (maximum, targets) in <(int, List<int>)>[
    (1, [1]),
    (128, [128]),
    (2048, [2048]),
    (2049, [2048, 2049]),
    (5000, [2048, 4096, 5000]),
  ]) {
    test('measures the exact bounded ladder for maximum $maximum', () async {
      final harness = _Harness();
      final measurement = await harness.run(maximum);
      expect(harness.targets, targets);
      expect(harness.events.last, 'metadata');
      expect(measurement.metrics.configuredMaximumTokens, maximum);
      expect(measurement.metrics.advertisedContextTokens, 32768);
      expect(measurement.metrics.reachedConfiguredMaximum, isTrue);
      expect(measurement.metrics.firstFailedApproximateTokens, isNull);
      expect(measurement.result.id, 'effective_context');
      expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
      expect(measurement.result.passedChecks, targets.length);
      expect(measurement.result.totalChecks, targets.length);
      expect(measurement.result.elapsed, const Duration(seconds: 7));
      expect(measurement.result.modelContent, isEmpty);
      expect(measurement.result.metadata, {
        'maxSuccessfulPromptTokens': '${maximum + 50}',
      });
      expect(
        measurement.result.usage.promptTokens,
        targets.fold<int>(0, (sum, target) => sum + target + 50),
      );
      expect(measurement.result.usage.completionTokens, 8 * targets.length);
      expect(
        measurement.result.usage.totalTokens,
        targets.fold<int>(0, (sum, target) => sum + target + 58),
      );
      expect(
        measurement.result.details,
        [
          'Measured prompt tokens: ${maximum + 50}',
          'Configured approximate maximum: $maximum',
          for (final target in targets)
            '$target: passed (${target + 50} prompt tokens) finish=stop',
        ].join('\n'),
      );
      expect(measurement.metrics.trials.clear, throwsUnsupportedError);
      for (var i = 0; i < targets.length; i++) {
        final target = targets[i];
        expect(
          harness.requests[i].single.content,
          'Read the DATA block. Return the exact line beginning CTX_BEGIN_ and '
          'the exact line beginning CTX_END_, separated by |, with no spaces or '
          'other text.\nDATA\nCTX_BEGIN_$target\n'
          '${List.filled(math.max(1, target - 128), 'pad').join(' ')}\n'
          'CTX_END_$target\nEND DATA',
        );
      }
    });
  }

  test('scores visible markers without reasoning', () async {
    final harness = _Harness(
      reply: (target) => _reply(
        target,
        content: '<think>reasoning</think>${_markers(target)}',
      ),
    );
    final measurement = await harness.run(2048);
    expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
    expect(measurement.metrics.trials.single.responsePreview, isEmpty);
  });

  test('accepts surrounding whitespace on an otherwise exact reply', () async {
    final harness = _Harness(
      reply: (target) => _reply(target, content: ' ${_markers(target)} '),
    );
    final measurement = await harness.run(2048);
    expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
    expect(measurement.metrics.trials.single.responsePreview, isEmpty);
  });

  for (final (content, kind) in <(String, String)>[
    ('', 'response_empty'),
    ('   ', 'response_empty'),
    ('CTX_BEGIN_2048', 'response_begin_marker_only'),
    ('CTX_END_2048', 'response_end_marker_only'),
    ('prefix CTX_BEGIN_2048|CTX_END_2048', 'response_both_markers_non_exact'),
    ('wrong markers', 'response_mismatch'),
  ]) {
    test(
      'classifies $kind for ${content.length} response characters',
      () async {
        final harness = _Harness(
          reply: (target) =>
              _reply(target, content: content, finishReason: 'length'),
        );
        final measurement = await harness.run(8192);
        expect(harness.targets, [2048]);
        expect(measurement.result.status, LiveLlmDiagnosticStatus.failed);
        expect(
          measurement.result.summary,
          'The context ladder could not produce a measured successful request.',
        );
        expect(measurement.result.passedChecks, 0);
        expect(measurement.result.totalChecks, 1);
        expect(measurement.result.modelContent, content.trim());
        final trial = measurement.metrics.trials.single;
        expect(trial.failureKind, kind);
        expect(trial.finishReason, 'length');
        expect(trial.responsePreview, content.trim());
        expect(
          trial.failure,
          'The response did not reproduce both boundary markers.',
        );
        expect(measurement.result.usage.promptTokens, 2098);
      },
    );
  }

  test('requires reported prompt usage even when recall succeeds', () async {
    final harness = _Harness(
      reply: (target) =>
          ChatCompletionResult(content: _markers(target), finishReason: 'stop'),
    );
    final measurement = await harness.run(8192);
    expect(harness.targets, [2048]);
    expect(measurement.result.status, LiveLlmDiagnosticStatus.failed);
    final trial = measurement.metrics.trials.single;
    expect(trial.failureKind, 'prompt_usage_missing');
    expect(trial.failure, 'The endpoint omitted prompt token usage.');
    expect(trial.responsePreview, isEmpty);
  });

  test(
    'stops after a request error and retains only completed-response usage',
    () async {
      final harness = _Harness(
        reply: (target) {
          if (target > 2048) throw StateError('context overflow');
          return _reply(target);
        },
      );
      final measurement = await harness.run(8192);
      expect(harness.targets, [2048, 4096]);
      expect(measurement.result.status, LiveLlmDiagnosticStatus.warning);
      expect(
        measurement.result.summary,
        'The context ladder found a boundary above the last successful request.',
      );
      expect(measurement.result.passedChecks, 1);
      expect(measurement.result.totalChecks, 2);
      expect(measurement.result.usage.totalTokens, 2106);
      final trial = measurement.metrics.trials.last;
      expect(trial.failureKind, 'request_error');
      expect(trial.failure, 'Bad state: context overflow');
      expect(trial.responsePreview, isEmpty);
      expect(measurement.metrics.maxSuccessfulPromptTokens, 2098);
      expect(measurement.metrics.firstFailedApproximateTokens, 4096);
    },
  );

  test('bounds error previews and clamps the requested maximum', () async {
    final harness = _Harness(
      reply: (_) => throw StateError(List.filled(400, 'x').join()),
    );
    final measurement = await harness.run(1048577);
    expect(harness.targets, [2048]);
    expect(measurement.metrics.configuredMaximumTokens, 1048576);
    expect(
      measurement.result.details,
      contains('Requested maximum was clamped to 1048576 tokens.'),
    );
    expect(measurement.metrics.trials.single.failure, hasLength(303));
    expect(measurement.metrics.trials.single.failure, endsWith('...'));
    expect(measurement.result.usage.totalTokens, 0);
  });

  test(
    'bounds response previews and uses the first nonempty trial preview',
    () async {
      final harness = _Harness(
        reply: (target) => _reply(
          target,
          content: target == 2048 ? null : List.filled(300, 'x').join(),
        ),
      );
      final measurement = await harness.run(8192);
      expect(measurement.metrics.trials.first.responsePreview, isEmpty);
      expect(
        measurement.result.modelContent,
        '${List.filled(240, 'x').join()}...',
      );
      expect(measurement.result.usage.completionTokens, 16);
    },
  );

  test('metadata port errors propagate after trial completion', () async {
    final harness = _Harness(
      metadata: () async => throw StateError('metadata'),
    );
    await expectLater(harness.run(2048), throwsStateError);
    expect(harness.events, ['trial:2048', 'metadata']);
  });
}

final _now = DateTime.utc(2026, 10, 8);

String _markers(int target) => 'CTX_BEGIN_$target|CTX_END_$target';

ChatCompletionResult _reply(
  int target, {
  String? content,
  String finishReason = 'stop',
}) => ChatCompletionResult(
  content: content ?? _markers(target),
  finishReason: finishReason,
  usage: TokenUsage(
    promptTokens: target + 50,
    completionTokens: 8,
    totalTokens: target + 58,
  ),
);

class _Harness {
  _Harness({
    ChatCompletionResult Function(int)? reply,
    Future<int> Function()? metadata,
  }) : _replyFor = reply ?? _reply,
       _metadata = metadata;

  final ChatCompletionResult Function(int) _replyFor;
  final Future<int> Function()? _metadata;
  final targets = <int>[];
  final requests = <List<Message>>[];
  final events = <String>[];

  Future<LiveLlmEffectiveContextProbeMeasurement> run(int maximum) =>
      LiveLlmEffectiveContextProbe(
        complete: (target, messages) async {
          targets.add(target);
          requests.add(messages);
          events.add('trial:$target');
          return _replyFor(target);
        },
        messages: (user) => [
          Message(
            id: 'fixture',
            content: user,
            role: MessageRole.user,
            timestamp: _now,
          ),
        ],
        advertisedContextTokens: () async {
          events.add('metadata');
          return await _metadata?.call() ?? 32768;
        },
        now: () => _now,
      ).run(
        requestedMaximumTokens: maximum,
        startedAt: _now.subtract(const Duration(seconds: 7)),
      );
}
