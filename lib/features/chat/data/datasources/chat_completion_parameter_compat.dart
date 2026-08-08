import 'package:openai_dart/openai_dart.dart';

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
