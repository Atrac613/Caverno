import 'package:openai_dart/openai_dart.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/logger.dart';
import 'chat_completion_bounds.dart';

/// Remembers which chat-completion parameter shapes the current endpoint
/// rejects, so subsequent requests are built the way that endpoint accepts.
///
/// OpenAI's reasoning models (GPT-5 family and o-series) reject `max_tokens`
/// in favour of `max_completion_tokens`, and reject any `temperature` other
/// than the default. Every OpenAI-compatible server Caverno talks to has its
/// own subset of quirks, so the decision is driven by the server's own 400
/// response (`param` / `message`) instead of by matching model names — a name
/// list would go stale on every model release and would misfire on proxies
/// that rename models.
class ChatCompletionParameterCompat {
  /// Send the token budget as `max_completion_tokens` instead of `max_tokens`.
  bool useMaxCompletionTokens = false;

  /// Omit `temperature` entirely and let the server apply its default.
  bool omitTemperature = false;

  /// Send `reasoning_effort: 'none'` explicitly.
  ///
  /// GPT-5.x rejects function tools combined with reasoning on
  /// `/v1/chat/completions`, and omitting the parameter is not enough because
  /// the server then applies its own default — the value has to be pinned to
  /// `none`. The alternative the API suggests is `/v1/responses`, which Caverno
  /// does not speak; disabling reasoning keeps tool calling working instead.
  bool forceReasoningEffortNone = false;

  /// Applies whatever [error] reveals about unsupported parameters.
  ///
  /// Returns `true` when this changed the compat state, meaning the same
  /// request is worth retrying in the corrected shape.
  bool absorb(ApiException error) {
    if (error.statusCode != 400) {
      return false;
    }

    final param = error.param?.toLowerCase() ?? '';
    final message = error.message.toLowerCase();
    var changed = false;

    // Accept either the structured `param` or the prose message: some
    // gateways forward OpenAI's text without the machine-readable fields.
    if (!useMaxCompletionTokens &&
        message.contains('max_completion_tokens') &&
        (param == 'max_tokens' || message.contains('max_tokens'))) {
      useMaxCompletionTokens = true;
      changed = true;
    }

    if (!omitTemperature &&
        (param == 'temperature' ||
            (message.contains('temperature') &&
                _reportsUnsupported(message)))) {
      omitTemperature = true;
      changed = true;
    }

    if (!forceReasoningEffortNone &&
        message.contains('reasoning_effort') &&
        message.contains("'none'")) {
      forceReasoningEffortNone = true;
      changed = true;
    }

    return changed;
  }

  static bool _reportsUnsupported(String message) {
    return message.contains('unsupported') ||
        message.contains('not supported') ||
        message.contains('does not support');
  }
}

/// Builds each request's negotiable parameters and re-sends it in the shape the
/// endpoint accepts when it answers with an unsupported-parameter 400.
///
/// Owns the negotiation so the datasource only asks what to put in the request:
/// the retry loop, the learned [ChatCompletionParameterCompat] state, and the
/// user's configured reasoning effort all move together.
class ChatCompletionParameterNegotiator {
  ChatCompletionParameterNegotiator({String? reasoningEffort})
    : _reasoningEffort = normalizeReasoningEffort(reasoningEffort);

  final String? _reasoningEffort;
  final ChatCompletionParameterCompat _compat = ChatCompletionParameterCompat();

  static String? normalizeReasoningEffort(String? value) {
    final normalized = value?.trim().toLowerCase();
    return switch (normalized) {
      'low' || 'medium' || 'high' => normalized,
      _ => null,
    };
  }

  /// `temperature` for the request, dropped once the server has rejected it.
  double? temperature(double? requested) {
    if (_compat.omitTemperature) {
      return null;
    }
    return requested ?? ApiConstants.defaultTemperature;
  }

  /// Token budget under the `max_tokens` key (null when the server wants
  /// `max_completion_tokens` instead).
  int? maxTokens(int? requested) {
    if (_compat.useMaxCompletionTokens) {
      return null;
    }
    return requested ?? ApiConstants.defaultMaxTokens;
  }

  /// Token budget under the `max_completion_tokens` key, used only for servers
  /// that rejected `max_tokens` (OpenAI reasoning models).
  int? maxCompletionTokens(int? requested) {
    if (!_compat.useMaxCompletionTokens) {
      return null;
    }
    return requested ?? ApiConstants.defaultMaxTokens;
  }

  ReasoningEffort? reasoningEffort(bool includeReasoning) {
    // Pinned regardless of the user's setting: this server refuses function
    // tools unless reasoning is explicitly switched off, and omitting the
    // parameter lets its own default apply.
    if (_compat.forceReasoningEffortNone) {
      return ReasoningEffort.none;
    }
    if (!includeReasoning) {
      return null;
    }
    return switch (_reasoningEffort) {
      'low' => ReasoningEffort.low,
      'medium' => ReasoningEffort.medium,
      'high' => ReasoningEffort.high,
      _ => null,
    };
  }

  /// Sends [send], retrying in a shape the endpoint accepts.
  ///
  /// Two independent 400 causes are handled: an unsupported parameter shape
  /// (recorded in [ChatCompletionParameterCompat], so later requests skip the
  /// round trip) and `reasoning_effort` on servers that do not implement it.
  /// Each cause can only be absorbed once, so the loop always terminates.
  Future<T> create<T>({
    required String operation,
    required Future<T> Function(bool includeReasoning) send,
  }) async {
    var includeReasoning = _reasoningEffort != null;
    while (true) {
      try {
        return await boundedCompletion(send(includeReasoning), operation);
      } on ApiException catch (error, stackTrace) {
        if (_absorb(error, operation)) {
          continue;
        }
        if (!includeReasoning || error.statusCode != 400) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        _logReasoningFallback(operation);
        includeReasoning = false;
      }
    }
  }

  /// Streaming counterpart of [create].
  ///
  /// Events are re-emitted with `await for` rather than `yield*` because errors
  /// from a `yield*`-ed stream are forwarded straight to the consumer and never
  /// enter this function's `try`, which would leave the retry unreachable.
  ///
  /// A retry only happens while the attempt has emitted nothing, so a rejected
  /// request (which fails before the first event) is recovered without any risk
  /// of replaying content the caller already received.
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
        if (emittedEvent) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        if (_absorb(error, operation)) {
          continue;
        }
        if (!includeReasoning || error.statusCode != 400) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        _logReasoningFallback(operation);
        includeReasoning = false;
      }
    }
  }

  /// Absorbs an unsupported-parameter 400 so the retry is built differently.
  bool _absorb(ApiException error, String operation) {
    if (!_compat.absorb(error)) {
      return false;
    }
    appLog(
      '[LLM] $operation rejected a request parameter with HTTP 400 '
      '(${error.param ?? 'unknown param'}); retrying with '
      'useMaxCompletionTokens=${_compat.useMaxCompletionTokens}, '
      'omitTemperature=${_compat.omitTemperature}, '
      'forceReasoningEffortNone=${_compat.forceReasoningEffortNone}',
    );
    return true;
  }

  void _logReasoningFallback(String operation) {
    appLog(
      '[LLM] $operation rejected reasoning_effort with HTTP 400; '
      'retrying without reasoning_effort',
    );
  }
}
