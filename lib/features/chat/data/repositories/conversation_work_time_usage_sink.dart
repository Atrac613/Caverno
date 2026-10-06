import '../../domain/entities/chat_completion_terminal_metadata.dart';
import '../../domain/entities/conversation_work_time.dart';
import '../../domain/entities/model_usage_role.dart';
import '../../domain/entities/model_usage_sink.dart';

/// Forwards every request to the per-model [usage] sink and also books its
/// duration as LLM inference time of the conversation that issued it.
///
/// A decorator rather than a second sink on the data source: every request
/// already funnels through `ModelUsageSink.record` exactly once, so this is
/// the one place that cannot miss or double-count a request.
final class ConversationWorkTimeUsageSink implements ModelUsageSink {
  const ConversationWorkTimeUsageSink({this.usage, required this.workTime});

  final ModelUsageSink? usage;
  final ConversationWorkTimeSink workTime;

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
  }) {
    this.usage?.record(
      model: model,
      endpointId: endpointId,
      role: role,
      usage: usage,
      durationMs: durationMs,
      label: label,
      conversationId: conversationId,
      finishReason: finishReason,
      isError: isError,
    );
    // Recorded even with zero tokens: a cancelled or failed request still
    // occupied the inference server for its duration.
    if (conversationId == null || conversationId.isEmpty) return;
    workTime.record(
      conversationId: conversationId,
      kind: ConversationWorkKind.llmInference,
      detail: role.name,
      durationMs: durationMs,
      isError: isError,
    );
  }
}
