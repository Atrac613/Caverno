import '../../data/datasources/llm_request_failure.dart';

/// User-facing headline for each [LlmRequestFailureCode].
///
/// `null` means the code has nothing to add, and the bounded error text is
/// shown on its own.
abstract final class LlmFailureHeadline {
  static String? of(
    LlmRequestFailure failure, {
    required String baseUrl,
  }) => switch (failure.code) {
    LlmRequestFailureCode.localStorage =>
      'Could not save the conversation to local storage. Check free disk space and file access, then try again.',
    LlmRequestFailureCode.unsupportedInput =>
      'This LLM server does not support image input. Please send text only.',
    LlmRequestFailureCode.transport =>
      'Could not connect to LLM server. Check your network connection, endpoint URL, and that the server is running. ($baseUrl)',
    LlmRequestFailureCode.timeout =>
      'LLM request timed out. Please wait and try again.',
    LlmRequestFailureCode.auth =>
      'Authentication failed. Please check your API key.',
    LlmRequestFailureCode.permissionDenied =>
      'Access denied. Please check your API key permissions or server settings.',
    LlmRequestFailureCode.notFound =>
      'Endpoint or model not found. Please check your settings.',
    LlmRequestFailureCode.rateLimit => switch (failure.retryAfter) {
      final retryAfter? =>
        'Too many requests. The server asked to wait ${retryAfter.inSeconds}s before trying again.',
      null => 'Too many requests. Please wait a moment and try again.',
    },
    LlmRequestFailureCode.unsupportedLocale =>
      'The selected local model rejected this language or locale. Try an English prompt, reduce system/tool context, or switch to an OpenAI-compatible provider for this task.',
    LlmRequestFailureCode.providerUnavailable =>
      'Apple Foundation Models is not ready on this device. Check Apple Intelligence, model readiness, device eligibility, and OS support, or switch to an OpenAI-compatible provider.',
    LlmRequestFailureCode.server =>
      'An error occurred on the LLM server. Please check the server logs.',
    LlmRequestFailureCode.contextOverflow =>
      'The conversation no longer fits in the model\'s context window. Start a new conversation or shorten the request.',
    LlmRequestFailureCode.invalidRequest =>
      'The LLM server rejected the request${_status(failure)}.',
    LlmRequestFailureCode.invalidResponse =>
      'Could not parse the response from the LLM server.',
    LlmRequestFailureCode.cancelled || LlmRequestFailureCode.unknown => null,
  };

  static String _status(LlmRequestFailure failure) =>
      failure.statusCode == null ? '' : ' (HTTP ${failure.statusCode})';
}
