import '../../data/datasources/apple_foundation_models_datasource.dart';
import '../../domain/entities/message.dart';

/// Converts provider and transport failures into concise user-facing text.
final class ChatErrorMessageBuilder {
  const ChatErrorMessageBuilder._();

  static String build(String rawError, {required String baseUrl}) {
    final cleanedError = _clean(rawError);
    final lower = cleanedError.toLowerCase();

    if (cleanedError.contains("Only 'text' content type is supported")) {
      return 'This LLM server does not support image input. Please send text only.\nDetails: $cleanedError';
    }
    if (lower.contains('failed host lookup') ||
        lower.contains('socketexception')) {
      return 'Could not connect to LLM server. Check your network connection and endpoint URL. ($baseUrl)\nDetails: $cleanedError';
    }
    if (lower.contains('connection refused')) {
      return 'Could not connect to LLM server. Make sure the server is running. ($baseUrl)\nDetails: $cleanedError';
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return 'LLM request timed out. Please wait and try again.\nDetails: $cleanedError';
    }
    if (lower.contains('401') || lower.contains('unauthorized')) {
      return 'Authentication failed. Please check your API key.\nDetails: $cleanedError';
    }
    if (lower.contains('403') || lower.contains('forbidden')) {
      return 'Access denied. Please check your API key permissions or server settings.\nDetails: $cleanedError';
    }
    if (lower.contains('404') || lower.contains('not found')) {
      return 'Endpoint or model not found. Please check your settings.\nDetails: $cleanedError';
    }
    if (lower.contains('429') || lower.contains('rate limit')) {
      return 'Too many requests. Please wait a moment and try again.\nDetails: $cleanedError';
    }
    if (AppleFoundationModelsException.isUnsupportedLanguageOrLocaleText(
      cleanedError,
    )) {
      return 'The selected local model rejected this language or locale. Try an English prompt, reduce system/tool context, or switch to an OpenAI-compatible provider for this task.\nDetails: $cleanedError';
    }
    if (AppleFoundationModelsException.isProviderUnavailableText(
      cleanedError,
    )) {
      return 'Apple Foundation Models is not ready on this device. Check Apple Intelligence, model readiness, device eligibility, and OS support, or switch to an OpenAI-compatible provider.\nDetails: $cleanedError';
    }
    if (lower.contains('500') ||
        lower.contains('502') ||
        lower.contains('503') ||
        lower.contains('504') ||
        lower.contains('server error') ||
        lower.contains('internal server error')) {
      return 'An error occurred on the LLM server. Please check the server logs.\nDetails: $cleanedError';
    }
    if (lower.contains('json') ||
        lower.contains('decode') ||
        lower.contains('parse') ||
        lower.contains('unexpected')) {
      return 'Could not parse the response from the LLM server.\nDetails: $cleanedError';
    }
    return cleanedError;
  }

  static String _clean(String rawError) {
    var cleaned = rawError.trim();
    const prefixes = [
      'Exception: ',
      'Bad state: ',
      'ClientException: ',
      'Invalid argument(s): ',
    ];
    for (final prefix in prefixes) {
      if (cleaned.startsWith(prefix)) {
        cleaned = cleaned.substring(prefix.length);
      }
    }
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

/// Applies a terminal error to the owning transcript without reading UI state.
final class TurnErrorMessageProjection {
  const TurnErrorMessageProjection._();

  static List<Message> apply({
    required Iterable<Message> messages,
    required String displayError,
    required Message Function() createAssistant,
  }) {
    final updated = [...messages];
    if (updated.isEmpty || updated.last.role != MessageRole.assistant) {
      updated.add(createAssistant());
    } else {
      final lastIndex = updated.length - 1;
      updated[lastIndex] = updated[lastIndex].copyWith(
        isStreaming: false,
        error: displayError,
      );
    }
    return updated;
  }
}
