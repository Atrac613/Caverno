import 'chat_completion_terminal_metadata.dart';
import 'model_usage_role.dart';

/// Receives one completed LLM request for per-model usage accounting.
///
/// Kept as a narrow interface so [ChatRemoteDataSource] does not depend on
/// drift, and so a test can observe recordings without a database.
///
/// Implementations must never throw and never block the caller: usage
/// accounting is bookkeeping, and a failure to write it must not break a chat
/// turn.
abstract interface class ModelUsageSink {
  /// [label] names the main-loop recovery path that issued the request. It is
  /// left null by the data source — which cannot read the session-log context
  /// without an import cycle — and resolved from the ambient context by the
  /// implementation. Callers that know the label may pass it explicitly.
  ///
  /// [conversationId] is captured when the request is issued, for the same
  /// zone reason as the label; null when no conversation owns the request.
  void record({
    required String model,
    required String endpointId,
    required ModelUsageRole role,
    required TokenUsage usage,
    required int durationMs,
    String? label,
    String? conversationId,
    String? finishReason,
    bool isError = false,
  });
}

/// Sink that drops everything, used when no database is available.
final class NoopModelUsageSink implements ModelUsageSink {
  const NoopModelUsageSink();

  @override
  void record({
    required String model,
    required String endpointId,
    required ModelUsageRole role,
    required TokenUsage usage,
    required int durationMs,
    String? label,
    String? conversationId,
    String? finishReason,
    bool isError = false,
  }) {}
}
