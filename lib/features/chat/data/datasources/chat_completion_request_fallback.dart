import 'package:openai_dart/openai_dart.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/logger.dart';
import 'chat_completion_bounds.dart';
import 'chat_completion_parameter_compat.dart';

/// Adapts chat-completion requests after an endpoint rejects parameters.
final class ChatCompletionRequestFallback {
  ChatCompletionRequestFallback(String? reasoningEffort)
    : _reasoningEffort = _normalizeReasoningEffort(reasoningEffort);

  final String? _reasoningEffort;
  final ChatCompletionParameterCompat _parameterCompat =
      ChatCompletionParameterCompat();

  ReasoningEffort? reasoningEffortForRequest(bool includeReasoning) {
    if (_parameterCompat.forceReasoningEffortNone) return ReasoningEffort.none;
    if (!includeReasoning) return null;
    return switch (_reasoningEffort) {
      'low' => ReasoningEffort.low,
      'medium' => ReasoningEffort.medium,
      'high' => ReasoningEffort.high,
      _ => null,
    };
  }

  double? temperatureForRequest(double? temperature) =>
      _parameterCompat.omitTemperature
      ? null
      : temperature ?? ApiConstants.defaultTemperature;

  int? maxTokensForRequest(int? maxTokens) =>
      _parameterCompat.useMaxCompletionTokens
      ? null
      : maxTokens ?? ApiConstants.defaultMaxTokens;

  int? maxCompletionTokensForRequest(int? maxTokens) =>
      _parameterCompat.useMaxCompletionTokens
      ? maxTokens ?? ApiConstants.defaultMaxTokens
      : null;

  Future<T> create<T>({
    required String operation,
    required Future<T> Function(bool includeReasoning) send,
  }) async {
    var includeReasoning = _reasoningEffort != null;
    while (true) {
      try {
        return await boundedCompletion(send(includeReasoning), operation);
      } on ApiException catch (error, stackTrace) {
        if (_absorb(error, operation)) continue;
        if (!includeReasoning || !_shouldRetryWithoutReasoning(error)) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        _logReasoningFallback(operation);
        includeReasoning = false;
      }
    }
  }

  Stream<T> stream<T>({
    required String operation,
    required Stream<T> Function(bool includeReasoning) send,
  }) async* {
    var includeReasoning = _reasoningEffort != null;
    while (true) {
      var emittedEvent = false;
      try {
        await for (final event in boundedCompletionStream(
          send(includeReasoning),
          operation,
        )) {
          emittedEvent = true;
          yield event;
        }
        return;
      } on ApiException catch (error, stackTrace) {
        if (emittedEvent) Error.throwWithStackTrace(error, stackTrace);
        if (_absorb(error, operation)) continue;
        if (!includeReasoning || !_shouldRetryWithoutReasoning(error)) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        _logReasoningFallback(operation);
        includeReasoning = false;
      }
    }
  }

  bool _absorb(ApiException error, String operation) {
    if (!_parameterCompat.absorb(error)) return false;
    appLog(
      '[LLM] $operation rejected a request parameter with HTTP 400 '
      '(${error.param ?? 'unknown param'}); retrying with '
      'useMaxCompletionTokens=${_parameterCompat.useMaxCompletionTokens}, '
      'omitTemperature=${_parameterCompat.omitTemperature}, '
      'forceReasoningEffortNone=${_parameterCompat.forceReasoningEffortNone}',
    );
    return true;
  }

  bool _shouldRetryWithoutReasoning(ApiException error) =>
      _reasoningEffort != null && error.statusCode == 400;

  void _logReasoningFallback(String operation) => appLog(
    '[LLM] $operation rejected reasoning_effort with HTTP 400; '
    'retrying without reasoning_effort',
  );

  static String? _normalizeReasoningEffort(String? value) {
    final normalized = value?.trim().toLowerCase();
    return switch (normalized) {
      'low' || 'medium' || 'high' => normalized,
      _ => null,
    };
  }
}
