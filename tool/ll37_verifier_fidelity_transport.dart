part of 'll37_verifier_fidelity_probe.dart';

final class OpenAiCompatibleLl37VerifierClient {
  const OpenAiCompatibleLl37VerifierClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.timeout,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final Duration timeout;

  Future<String> complete(Ll37VerifierPrompt prompt) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .postUrl(_chatCompletionsUri(baseUrl))
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      if (apiKey.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      }
      final requestBody = utf8.encode(
        jsonEncode({
          'model': model,
          'temperature': 0,
          'max_tokens': 512,
          'messages': [
            {'role': 'system', 'content': prompt.systemPrompt},
            {'role': 'user', 'content': prompt.userPrompt},
          ],
        }),
      );
      request.contentLength = requestBody.length;
      request.add(requestBody);
      final response = await request.close().timeout(timeout);
      final responseBody = await utf8.decoder
          .bind(response)
          .join()
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'LL37 verifier completion failed with HTTP '
          '${response.statusCode}: $responseBody',
        );
      }
      final json = _decodeObject(responseBody, 'chat completion response');
      final choices = json['choices'];
      if (choices is! List || choices.isEmpty) {
        throw const FormatException(
          'LL37 verifier completion response has no choices.',
        );
      }
      final first = _object(choices.first);
      final message = _object(first?['message']);
      final content = _string(message?['content']) ?? _string(first?['text']);
      if (content == null || content.trim().isEmpty) {
        throw const FormatException(
          'LL37 verifier completion response has no text content.',
        );
      }
      return content.trim();
    } finally {
      client.close(force: true);
    }
  }
}

final class Ll37VerifierFidelityProbeOptions {
  const Ll37VerifierFidelityProbeOptions({
    required this.showHelp,
    required this.fixtureResponse,
    required this.casePaths,
    required this.timeoutSeconds,
    this.baseUrl,
    this.apiKey,
    this.model,
    this.outJsonPath,
    this.outMarkdownPath,
  });

  static const usage =
      'Usage: dart run tool/ll37_verifier_fidelity_probe.dart '
      '--case PATH --case PATH [--fixture-response] '
      '[--base-url URL --api-key KEY --model MODEL] '
      '[--timeout-seconds N] [--out-json PATH] [--out-md PATH]';

  final bool showHelp;
  final bool fixtureResponse;
  final List<String> casePaths;
  final int timeoutSeconds;
  final String? baseUrl;
  final String? apiKey;
  final String? model;
  final String? outJsonPath;
  final String? outMarkdownPath;

  String get effectiveBaseUrl =>
      (baseUrl ?? Platform.environment['CAVERNO_LLM_BASE_URL'] ?? '').trim();

  String get effectiveApiKey =>
      (apiKey ?? Platform.environment['CAVERNO_LLM_API_KEY'] ?? '').trim();

  String get effectiveModel =>
      (model ?? Platform.environment['CAVERNO_LLM_MODEL'] ?? '').trim();

  void validateLiveEnvironment() {
    if (effectiveBaseUrl.isEmpty || effectiveModel.isEmpty) {
      throw const FormatException(
        'A base URL and model are required for the live LL37 probe.',
      );
    }
  }

  static Ll37VerifierFidelityProbeOptions parse(List<String> args) {
    var showHelp = false;
    var fixtureResponse = false;
    final casePaths = <String>[];
    var timeoutSeconds = 120;
    String? baseUrl;
    String? apiKey;
    String? model;
    String? outJsonPath;
    String? outMarkdownPath;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--help' || '-h':
          showHelp = true;
        case '--fixture-response':
          fixtureResponse = true;
        case '--case':
          casePaths.add(_nextValue(args, ++index, arg));
        case '--timeout-seconds':
          final value = int.tryParse(_nextValue(args, ++index, arg));
          if (value == null || value <= 0) {
            throw const FormatException(
              'Timeout seconds must be a positive integer.',
            );
          }
          timeoutSeconds = value;
        case '--base-url':
          baseUrl = _nextValue(args, ++index, arg);
        case '--api-key':
          apiKey = _nextValue(args, ++index, arg);
        case '--model':
          model = _nextValue(args, ++index, arg);
        case '--out-json':
          outJsonPath = _nextValue(args, ++index, arg);
        case '--out-md':
          outMarkdownPath = _nextValue(args, ++index, arg);
        default:
          throw FormatException('Unknown LL37 probe option: $arg');
      }
    }
    if (!showHelp && casePaths.isEmpty) {
      throw const FormatException('At least one --case path is required.');
    }
    return Ll37VerifierFidelityProbeOptions(
      showHelp: showHelp,
      fixtureResponse: fixtureResponse,
      casePaths: List.unmodifiable(casePaths),
      timeoutSeconds: timeoutSeconds,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      outJsonPath: outJsonPath,
      outMarkdownPath: outMarkdownPath,
    );
  }
}

String _nextValue(List<String> args, int index, String option) {
  if (index >= args.length || args[index].startsWith('--')) {
    throw FormatException('Missing value for $option.');
  }
  return args[index];
}

Uri _chatCompletionsUri(String baseUrl) {
  var normalized = baseUrl.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return Uri.parse('$normalized/chat/completions');
}
