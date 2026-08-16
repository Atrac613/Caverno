import 'package:openai_dart/openai_dart.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/logger.dart';
import 'chat_completion_bounds.dart';
import 'chat_completion_parameter_compat.dart';

/// Adapts chat-completion requests after an endpoint rejects parameters.
final class ChatCompletionRequestFallback {
  ChatCompletionRequestFallback(
    String? reasoningEffort, {
    Future<void> Function(Duration)? delay,
  }) : _reasoningEffort = _normalizeReasoningEffort(reasoningEffort),
       _delay = delay ?? Future<void>.delayed;

  final String? _reasoningEffort;
  final Future<void> Function(Duration) _delay;
  final ChatCompletionParameterCompat _parameterCompat =
      ChatCompletionParameterCompat();

  /// A 429 says "not now", not "not ever", and the server usually says exactly
  /// how long to wait. Failing the whole turn on it throws away the tool
  /// results the turn already produced -- in session a00b77ce that meant
  /// abandoning an in-flight production release over a 3.3 second wait.
  static const int _maxRateLimitRetries = 4;
  static const Duration _maxRateLimitDelay = Duration(seconds: 30);
  static const Duration _initialRateLimitDelay = Duration(seconds: 1);

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

  /// True once the endpoint has 400'd on `temperature`, after which every
  /// request omits it and runs at the server default.
  bool get temperatureIsOmitted => _parameterCompat.omitTemperature;

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
    var rateLimitAttempt = 0;
    while (true) {
      try {
        return await boundedCompletion(send(includeReasoning), operation);
      } on ApiException catch (error, stackTrace) {
        if (_absorb(error, operation)) continue;
        final backoff = _rateLimitBackoff(error, rateLimitAttempt);
        if (backoff != null) {
          rateLimitAttempt += 1;
          _logRateLimitRetry(operation, backoff, rateLimitAttempt);
          await _delay(backoff);
          continue;
        }
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
    var rateLimitAttempt = 0;
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
        final backoff = _rateLimitBackoff(error, rateLimitAttempt);
        if (backoff != null) {
          rateLimitAttempt += 1;
          _logRateLimitRetry(operation, backoff, rateLimitAttempt);
          await _delay(backoff);
          continue;
        }
        if (!includeReasoning || !_shouldRetryWithoutReasoning(error)) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        _logReasoningFallback(operation);
        includeReasoning = false;
      }
    }
  }

  /// How long to wait before retrying [error], or null if it is not a
  /// retryable rate limit.
  ///
  /// Never shortens what the server asked for: the wait is the larger of the
  /// server's own figure and the local backoff, so a retry cannot arrive
  /// earlier than the endpoint said it would be accepted.
  Duration? _rateLimitBackoff(ApiException error, int attempt) {
    if (error.statusCode != 429 || attempt >= _maxRateLimitRetries) return null;
    final localBackoff = _initialRateLimitDelay * (1 << attempt);
    final serverRequest = _serverRequestedDelay(error);
    final backoff = serverRequest == null || serverRequest < localBackoff
        ? localBackoff
        : serverRequest;
    return backoff > _maxRateLimitDelay ? _maxRateLimitDelay : backoff;
  }

  /// The endpoint's own retry hint: the `Retry-After` header when the client
  /// parsed one, and otherwise the figure OpenAI-compatible servers put in the
  /// message body ("Please try again in 3.336s").
  Duration? _serverRequestedDelay(ApiException error) {
    if (error case RateLimitException(retryAfter: final retryAfter?)) {
      return retryAfter;
    }
    final match = RegExp(
      r'try again in\s+([0-9]+(?:\.[0-9]+)?)\s*(ms|s|m)\b',
      caseSensitive: false,
    ).firstMatch(error.message);
    final value = double.tryParse(match?.group(1) ?? '');
    if (match == null || value == null) return null;
    final microseconds = switch (match.group(2)!.toLowerCase()) {
      'ms' => value * Duration.microsecondsPerMillisecond,
      'm' => value * Duration.microsecondsPerMinute,
      _ => value * Duration.microsecondsPerSecond,
    };
    return Duration(microseconds: microseconds.ceil());
  }

  void _logRateLimitRetry(String operation, Duration backoff, int attempt) =>
      appLog(
        '[LLM] $operation hit a rate limit (HTTP 429); retrying in '
        '${backoff.inMilliseconds}ms '
        '(attempt $attempt of $_maxRateLimitRetries)',
      );

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
