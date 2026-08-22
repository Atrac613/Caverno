import '../constants/api_constants.dart';

final class LlmEndpointTransportException implements Exception {
  const LlmEndpointTransportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Prevents LLM credentials and private prompts from crossing plaintext links.
final class LlmEndpointTransportPolicy {
  const LlmEndpointTransportPolicy();

  String validate({required String baseUrl, required String apiKey}) {
    final normalizedBaseUrl = baseUrl.trim();
    final uri = Uri.tryParse(normalizedBaseUrl);
    if (uri == null || uri.host.isEmpty || !uri.hasScheme) {
      throw const LlmEndpointTransportException(
        'The LLM endpoint must be a valid HTTP or HTTPS URL.',
      );
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const LlmEndpointTransportException(
        'The LLM endpoint must use HTTP or HTTPS.',
      );
    }
    if (scheme == 'https' || !_hasCredential(apiKey) || _isLoopback(uri.host)) {
      return normalizedBaseUrl;
    }

    throw const LlmEndpointTransportException(
      'Use HTTPS when an LLM endpoint outside this device has an API key.',
    );
  }

  bool _hasCredential(String apiKey) {
    final normalized = apiKey.trim();
    return normalized.isNotEmpty && normalized != ApiConstants.defaultApiKey;
  }

  bool _isLoopback(String host) {
    final normalized = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (normalized == 'localhost' || normalized.endsWith('.localhost')) {
      return true;
    }
    return switch (normalized) {
      '127.0.0.1' || '::1' || '0:0:0:0:0:0:0:1' => true,
      _ => false,
    };
  }
}
