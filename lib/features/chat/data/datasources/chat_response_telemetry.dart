import 'package:openai_dart/openai_dart.dart' hide MessageRole;

import '../../domain/entities/chat_completion_terminal_metadata.dart';
import '../../domain/entities/model_usage_role.dart';
import '../../domain/entities/model_usage_sink.dart';

/// Owns everything a completed request reports about itself: the last usage and
/// finish reason the data source exposes, and the per-model usage accounting.
///
/// Extracted from `ChatRemoteDataSource` so the request methods stay about
/// issuing requests. Instances are per data source, and therefore per endpoint.
final class ChatResponseTelemetry {
  ChatResponseTelemetry({
    ModelUsageSink? usageSink,
    String endpointId = '',
    String? Function()? labelResolver,
  }) : _usageSink = usageSink,
       _endpointId = endpointId,
       _labelResolver = labelResolver;

  final ModelUsageSink? _usageSink;

  /// Supplies the session-log request label. Injected rather than read here so
  /// this file does not have to import the session log store, which imports the
  /// data source in turn.
  final String? Function()? _labelResolver;

  /// Which configured endpoint the owning data source talks to. Recorded
  /// alongside the model because the same model name can be served locally, by
  /// a LAN host, or by a paid cloud provider.
  final String _endpointId;

  /// Last token usage captured from a streaming or non-streaming response.
  TokenUsage lastUsage = TokenUsage.zero;

  /// Last finish reason captured from a streaming or non-streaming response.
  String? lastFinishReason;

  void reset() {
    lastUsage = TokenUsage.zero;
    lastFinishReason = null;
  }

  /// The finish reason on a streaming choice, if it carries a usable one.
  String? streamingFinishReason(dynamic choice) {
    final Object? finishReason = choice?.finishReason?.value;
    if (finishReason is String && finishReason.isNotEmpty) {
      return finishReason;
    }
    return null;
  }

  /// Publishes terminal facts without recording usage, for the compatibility
  /// paths that re-report a response the sink has already accounted for.
  void publishCompatibility(ChatCompletionTerminalMetadata metadata) {
    lastUsage = metadata.usage;
    lastFinishReason = metadata.finishReason;
  }

  /// Snapshots who this request belongs to. Must be called while the caller's
  /// zone is still current, i.e. when the request is issued — see
  /// [ModelUsageAttribution].
  ModelUsageAttribution captureAttribution() =>
      ModelUsageAttribution.capture(labelResolver: _labelResolver);

  /// The single funnel every request passes through on its way out, whether it
  /// succeeded, failed, or came back through a compatibility fallback.
  ///
  /// [timer] is always request-local: turns run concurrently across threads, so
  /// a start time stored on this instance would attribute one request's
  /// duration to another.
  void publishRequest({
    required String modelId,
    required ChatCompletionTerminalMetadata metadata,
    required Stopwatch timer,
    required ModelUsageAttribution attribution,
    bool isError = false,
  }) {
    publishCompatibility(metadata);
    final sink = _usageSink;
    if (sink == null) return;
    timer.stop();
    sink.record(
      model: modelId,
      endpointId: _endpointId,
      role: attribution.role,
      label: attribution.label,
      usage: metadata.usage,
      durationMs: timer.elapsedMilliseconds,
      finishReason: metadata.finishReason,
      isError: isError,
    );
  }

  /// Records a request that threw before producing terminal metadata.
  void publishFailure({
    required String modelId,
    required Stopwatch timer,
    required ModelUsageAttribution attribution,
  }) {
    publishRequest(
      modelId: modelId,
      metadata: ChatCompletionTerminalMetadata(
        finishReason: lastFinishReason,
        usage: TokenUsage.zero,
      ),
      timer: timer,
      attribution: attribution,
      isError: true,
    );
  }

  /// Extracts token usage from a completion response, keeping the full
  /// `prompt_tokens_details` / `completion_tokens_details` breakdown so
  /// per-model statistics can report cache hits and reasoning tokens.
  /// Providers that omit those objects leave the fields at 0.
  static TokenUsage extractUsage(Usage? usage) {
    if (usage == null) return TokenUsage.zero;
    final promptDetails = usage.promptTokensDetails;
    final completionDetails = usage.completionTokensDetails;
    return TokenUsage(
      promptTokens: usage.promptTokens,
      completionTokens: usage.completionTokens ?? 0,
      totalTokens: usage.totalTokens,
      cachedPromptTokens: promptDetails?.cachedTokens ?? 0,
      audioPromptTokens: promptDetails?.audioTokens ?? 0,
      reasoningTokens: completionDetails?.reasoningTokens ?? 0,
      audioCompletionTokens: completionDetails?.audioTokens ?? 0,
      acceptedPredictionTokens:
          completionDetails?.acceptedPredictionTokens ?? 0,
      rejectedPredictionTokens:
          completionDetails?.rejectedPredictionTokens ?? 0,
    );
  }
}
