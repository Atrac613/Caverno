import 'package:flutter_test/flutter_test.dart';

import '../../tool/live_llm_benchmark_warmup.dart';

void main() {
  test('defaults to diagnostic warm-up mode', () {
    expect(
      parseLiveLlmBenchmarkWarmupMode(null),
      LiveLlmBenchmarkWarmupMode.diagnostic,
    );
    expect(
      parseLiveLlmBenchmarkWarmupMode(''),
      LiveLlmBenchmarkWarmupMode.diagnostic,
    );
  });

  test('parses unrelated completion mode exactly', () {
    expect(
      parseLiveLlmBenchmarkWarmupMode('unrelatedCompletion'),
      LiveLlmBenchmarkWarmupMode.unrelatedCompletion,
    );
    expect(
      () => parseLiveLlmBenchmarkWarmupMode('unrelated'),
      throwsStateError,
    );
  });

  test('builds a fixed tool-free marker request', () {
    final messages = buildUnrelatedLiveLlmBenchmarkWarmupMessages(
      timestamp: DateTime.utc(2026, 8, 14),
    );

    expect(messages, hasLength(1));
    expect(messages.single.content, contains(liveLlmBenchmarkWarmupMarker));
    expect(
      isValidUnrelatedLiveLlmBenchmarkWarmupContent(
        '  $liveLlmBenchmarkWarmupMarker\n',
      ),
      isTrue,
    );
    expect(isValidUnrelatedLiveLlmBenchmarkWarmupContent('extra'), isFalse);
  });
}
