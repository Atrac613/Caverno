import 'package:caverno/features/chat/domain/entities/message.dart';

enum LiveLlmBenchmarkWarmupMode { diagnostic, unrelatedCompletion }

const liveLlmBenchmarkWarmupMarker = 'CAVERNO_BENCHMARK_WARMUP_OK';

LiveLlmBenchmarkWarmupMode parseLiveLlmBenchmarkWarmupMode(String? raw) {
  final normalized = raw?.trim() ?? '';
  if (normalized.isEmpty) {
    return LiveLlmBenchmarkWarmupMode.diagnostic;
  }
  for (final mode in LiveLlmBenchmarkWarmupMode.values) {
    if (mode.name == normalized) return mode;
  }
  throw StateError(
    'CAVERNO_BENCHMARK_CANARY_WARMUP_MODE must be one of: '
    '${LiveLlmBenchmarkWarmupMode.values.map((mode) => mode.name).join(", ")}.',
  );
}

List<Message> buildUnrelatedLiveLlmBenchmarkWarmupMessages({
  required DateTime timestamp,
}) {
  return [
    Message(
      id: 'live-llm-benchmark-unrelated-warmup-${timestamp.microsecondsSinceEpoch}',
      content:
          'Reply with exactly $liveLlmBenchmarkWarmupMarker and no other text.',
      role: MessageRole.user,
      timestamp: timestamp,
    ),
  ];
}

bool isValidUnrelatedLiveLlmBenchmarkWarmupContent(String content) =>
    content.trim() == liveLlmBenchmarkWarmupMarker;
