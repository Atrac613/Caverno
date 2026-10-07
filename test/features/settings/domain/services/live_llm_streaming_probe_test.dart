import 'dart:async';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_streaming_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('measures content TTFT, decode rate and terminal usage', () async {
    final harness = _Harness(chunks: [_sequence(1, 20), _sequence(21, 40)]);
    final measurement = await harness.run();
    expect(measurement.result.id, 'streaming_response');
    expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
    expect(
      measurement.result.summary,
      'The model streamed the full sequence over the streaming path.',
    );
    expect(measurement.result.passedChecks, 40);
    expect(measurement.result.totalChecks, 40);
    expect(measurement.result.elapsed, Duration.zero);
    expect(
      measurement.metrics.timeToFirstToken,
      const Duration(milliseconds: 250),
    );
    expect(measurement.metrics.totalElapsed, const Duration(seconds: 1));
    expect(measurement.metrics.chunkCount, 2);
    expect(measurement.metrics.finishReason, 'stop');
    expect(measurement.metrics.decodeTokensPerSecond, closeTo(40 / .75, .001));
    expect(measurement.result.usage.toJson(), {
      'promptTokens': 12,
      'completionTokens': 40,
      'totalTokens': 52,
    });
    expect(
      measurement.result.details,
      'Matched in order: 40/40\nChunks: 2\n'
      'Finish reason: stop\nTTFT: 250 ms\nTotal: 1000 ms\nDecode: 53.3 tok/s',
    );
    expect(harness.observed, [_sequence(1, 40)]);
  });

  test('ignores empty chunks before and after first content', () async {
    final harness = _Harness(
      chunks: ['', '', _sequence(1, 20), '', _sequence(21, 40), ''],
    );
    final measurement = await harness.run();
    expect(measurement.metrics.chunkCount, 2);
    expect(
      measurement.metrics.timeToFirstToken,
      const Duration(milliseconds: 250),
    );
    expect(harness.clock.reads, 2);
    expect(harness.observed, [_sequence(1, 40)]);
  });

  for (final chunks in [
    <String>[],
    ['', ''],
  ]) {
    test(
      'uses total elapsed as TTFT when ${chunks.length} empty chunks arrive',
      () async {
        final harness = _Harness(chunks: chunks);
        final measurement = await harness.run();
        expect(measurement.result.status, LiveLlmDiagnosticStatus.failed);
        expect(measurement.result.passedChecks, 0);
        expect(measurement.metrics.chunkCount, 0);
        expect(
          measurement.metrics.timeToFirstToken,
          measurement.metrics.totalElapsed,
        );
        expect(harness.clock.reads, 1);
        expect(harness.observed, ['']);
        expect(measurement.result.modelContent, isEmpty);
      },
    );
  }

  test('single-chunk delivery suppresses a decode-rate claim', () async {
    final measurement = await _Harness(chunks: [_sequence(1, 40)]).run();
    expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
    expect(measurement.metrics.isLikelyBuffered, isTrue);
    expect(measurement.metrics.decodeTokensPerSecond, isNull);
    expect(measurement.result.details, contains('Buffered delivery:'));
    expect(measurement.result.details, isNot(contains('Decode:')));
  });

  test('a late terminal burst suppresses a decode-rate claim', () async {
    final measurement = await _Harness(
      chunks: [_sequence(1, 20), _sequence(21, 40)],
      elapsed: [const Duration(milliseconds: 950), const Duration(seconds: 1)],
    ).run();
    expect(measurement.metrics.isLikelyBuffered, isTrue);
    expect(measurement.metrics.decodeTokensPerSecond, isNull);
    expect(measurement.result.details, contains('Buffered delivery:'));
  });

  test(
    'missing terminal usage and finish reason do not change sequence scoring',
    () async {
      final measurement = await _Harness(
        chunks: [_sequence(1, 20), _sequence(21, 40)],
        terminal: ChatCompletionTerminalMetadata.empty,
      ).run();
      expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
      expect(measurement.metrics.finishReason, '');
      expect(measurement.metrics.decodeTokensPerSecond, isNull);
      expect(measurement.result.usage.totalTokens, 0);
      expect(measurement.result.details, contains('Finish reason: (none)'));
    },
  );

  for (final (content, matched, status)
      in <(String, int, LiveLlmDiagnosticStatus)>[
        ('1\n2\n3', 3, LiveLlmDiagnosticStatus.warning),
        ('3\n2\n1', 1, LiveLlmDiagnosticStatus.warning),
        ('not an integer sequence', 0, LiveLlmDiagnosticStatus.failed),
      ]) {
    test(
      'scores an incomplete stream as $status with $matched checks',
      () async {
        final measurement = await _Harness(chunks: [content]).run();
        expect(measurement.result.status, status);
        expect(measurement.result.passedChecks, matched);
        expect(measurement.result.totalChecks, 40);
        expect(
          measurement.result.summary,
          'The streamed sequence was incomplete or out of order.',
        );
      },
    );
  }

  for (final content in [_sequence(1, 40), 'unrelated']) {
    test(
      'preserves length truncation for ${content.length} content characters',
      () async {
        final measurement = await _Harness(
          chunks: [content],
          terminal: const ChatCompletionTerminalMetadata(
            finishReason: 'length',
          ),
        ).run();
        expect(
          measurement.result.status,
          content.startsWith('1\n')
              ? LiveLlmDiagnosticStatus.warning
              : LiveLlmDiagnosticStatus.failed,
        );
        expect(
          measurement.result.summary,
          'The stream was cut short by the token limit.',
        );
        expect(measurement.metrics.finishReason, 'length');
      },
    );
  }

  test(
    'records raw reasoning while scoring only visible sequence content',
    () async {
      final raw = '<think>99\n100</think>${_sequence(1, 40)}';
      final harness = _Harness(chunks: [raw]);
      final measurement = await harness.run();
      expect(harness.observed, [raw]);
      expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
      expect(measurement.result.modelContent, raw.trim());
    },
  );

  test(
    'bounds content preview without truncating thinking observation',
    () async {
      final raw = List.filled(500, 'x').join();
      final harness = _Harness(chunks: [raw]);
      final measurement = await harness.run();
      expect(harness.observed, [raw]);
      expect(
        measurement.result.modelContent,
        '${List.filled(400, 'x').join()}...',
      );
    },
  );

  test('waits for terminal metadata after capturing stream elapsed', () async {
    final terminal = Completer<ChatCompletionTerminalMetadata>();
    final measuredElapsed = Completer<void>();
    final observed = <String>[];
    final clock = _Clock([
      const Duration(milliseconds: 250),
      const Duration(seconds: 1),
    ], afterLastRead: measuredElapsed.complete);
    final run = LiveLlmStreamingProbe(
      stream: () => StreamedChatCompletion(
        stream: Stream.value(_sequence(1, 40)),
        terminal: terminal.future,
      ),
      recordThinking: observed.add,
      stopwatch: () => clock,
    ).run();
    await measuredElapsed.future;
    expect(observed, isEmpty);
    terminal.complete(_terminal);
    final measurement = await run;
    expect(measurement.metrics.totalElapsed, const Duration(seconds: 1));
    expect(clock.reads, 2);
    expect(observed, [_sequence(1, 40)]);
  });

  for (final stage in ['request', 'stream', 'terminal', 'thinking']) {
    test('propagates $stage errors to the service boundary', () async {
      final failure = StateError(stage);
      final observed = <String>[];
      final run = LiveLlmStreamingProbe(
        stream: () {
          if (stage == 'request') throw failure;
          return StreamedChatCompletion.capture(
            stream: stage == 'stream'
                ? Stream<String>.error(failure)
                : Stream.value(_sequence(1, 40)),
            terminalMetadata: () {
              if (stage == 'terminal') throw failure;
              return _terminal;
            },
          );
        },
        recordThinking: (content) {
          if (stage == 'thinking') throw failure;
          observed.add(content);
        },
      ).run();
      await expectLater(run, throwsA(same(failure)));
      expect(observed, isEmpty);
    });
  }
}

String _sequence(int first, int last) =>
    [for (var n = first; n <= last; n++) '$n\n'].join();

const _terminal = ChatCompletionTerminalMetadata(
  finishReason: 'stop',
  usage: TokenUsage(promptTokens: 12, completionTokens: 40, totalTokens: 52),
);

class _Clock extends Stopwatch {
  _Clock(this.values, {this.afterLastRead});
  final List<Duration> values;
  final void Function()? afterLastRead;
  int reads = 0;

  @override
  Duration get elapsed {
    final value = values[reads++];
    if (reads == values.length) afterLastRead?.call();
    return value;
  }
}

class _Harness {
  _Harness({
    required this.chunks,
    this.terminal = _terminal,
    List<Duration>? elapsed,
  }) : clock = _Clock(
         elapsed ??
             [const Duration(milliseconds: 250), const Duration(seconds: 1)],
       );

  final List<String> chunks;
  final ChatCompletionTerminalMetadata terminal;
  final _Clock clock;
  final observed = <String>[];

  Future<LiveLlmStreamingProbeMeasurement> run() => LiveLlmStreamingProbe(
    stream: () => StreamedChatCompletion.capture(
      stream: Stream.fromIterable(chunks),
      terminalMetadata: () => terminal,
    ),
    recordThinking: observed.add,
    stopwatch: () => clock,
  ).run();
}
