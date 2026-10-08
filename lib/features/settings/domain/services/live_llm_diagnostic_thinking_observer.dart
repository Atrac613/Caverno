import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/data/datasources/chat_remote_datasource.dart';
import '../../../chat/domain/entities/message.dart';
import '../../../chat/domain/services/model_routing/chat_request_thinking_policy.dart';
import '../entities/app_settings.dart';
import '../entities/live_llm_diagnostic.dart';

/// Counts the reasoning the probe responses carried. See
/// [LiveLlmDiagnosticThinkingMetrics].
///
/// Reads the reasoning out of the response content: the datasource folds a
/// separate `reasoning_content` field into a leading `<think>` block, so one
/// parse covers both the field and inline tags. A block the token cap cut off
/// before its closing tag still counts, since the model did reason.
final class LiveLlmDiagnosticThinkingObserver {
  var _responseCount = 0;
  var _reasoningResponseCount = 0;
  var _reasoningChars = 0;

  void reset() {
    _responseCount = 0;
    _reasoningResponseCount = 0;
    _reasoningChars = 0;
  }

  static int reasoningChars(String content) {
    final parsed = ContentParser.parse(content);
    var chars = 0;
    for (final segment in parsed.segments) {
      if (segment.type == ContentType.thinking) {
        chars += segment.content.trim().length;
      }
    }
    if (parsed.incompleteTagType == 'thinking') {
      chars += parsed.incompleteTagContent?.trim().length ?? 0;
    }
    return chars;
  }

  void record(String content) {
    _responseCount += 1;
    final chars = reasoningChars(content);
    if (chars > 0) {
      _reasoningResponseCount += 1;
      _reasoningChars += chars;
    }
  }

  /// The run's metrics, with the reasoning controls the requests carried read
  /// back from [dataSource]. Null when no response was recorded.
  LiveLlmDiagnosticThinkingMetrics? metrics(
    ChatDataSource dataSource, {
    required String model,
    required int maxTokens,
    required ReasoningEffortPreference effort,
  }) {
    if (_responseCount == 0) return null;
    final overrides = dataSource is ChatRemoteDataSource
        ? dataSource.thinkingOverrides(model: model, maxTokens: maxTokens)
        : null;
    return LiveLlmDiagnosticThinkingMetrics(
      requested: overrides?.chatTemplateKwargs['enable_thinking'] as bool?,
      requestedEffort: dataSource is ChatRemoteDataSource
          ? _requestedEffort(overrides, effort)
          : null,
      responseCount: _responseCount,
      reasoningResponseCount: _reasoningResponseCount,
      reasoningChars: _reasoningChars,
    );
  }

  /// Resolved the way the policy client resolves the wire request. The probes
  /// set no [ModelUsageRole], so no role suppression applies. A Qwen3.8
  /// override carries the effort in the template kwargs and strips the
  /// top-level field unless it preserves it.
  static String? _requestedEffort(
    ChatRequestThinkingOverrides? overrides,
    ReasoningEffortPreference effort,
  ) {
    if (overrides != null) {
      final templateEffort = overrides.chatTemplateKwargs['reasoning_effort'];
      if (templateEffort is String) return templateEffort;
      if (!overrides.preserveReasoningEffort) return null;
    }
    return effort == ReasoningEffortPreference.automatic ? null : effort.name;
  }
}

/// The request methods the probes call, each recording its response with
/// [LiveLlmDiagnosticThinkingObserver] before returning it unchanged.
final class LiveLlmDiagnosticObservedChatCalls {
  LiveLlmDiagnosticObservedChatCalls(this._dataSource, this._observer);

  final ChatDataSource _dataSource;
  final LiveLlmDiagnosticThinkingObserver _observer;

  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final result = await _dataSource.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    _observer.record(result.content);
    return result;
  }

  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final result = await _dataSource.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    _observer.record(result.content);
    return result;
  }
}
