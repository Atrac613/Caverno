import 'dart:convert';

import 'package:http/http.dart' as http;

/// llama.cpp / LM Studio response `timings` block.
///
/// `openai_dart`'s typed client drops these provider extension fields, so the
/// LL20 substrate sends and parses them over raw HTTP. They are how cache reuse
/// (LL6/LL22) and slot progress (LL7) are measured without wall-clock guesses.
class LlamaCppTimings {
  const LlamaCppTimings({
    this.cacheN,
    this.promptN,
    this.promptMs,
    this.predictedN,
    this.predictedMs,
    this.promptPerSecond,
    this.predictedPerSecond,
  });

  final int? cacheN;
  final int? promptN;
  final double? promptMs;
  final int? predictedN;
  final double? predictedMs;
  final double? promptPerSecond;
  final double? predictedPerSecond;

  bool get hasCacheTiming => cacheN != null && promptN != null;

  /// Share of the prompt served from cache: cache_n / (cache_n + prompt_n).
  double? get cachedPromptShare {
    final cacheTokens = cacheN;
    final promptTokens = promptN;
    if (cacheTokens == null || promptTokens == null) return null;
    final total = cacheTokens + promptTokens;
    if (total <= 0) return null;
    return cacheTokens / total;
  }

  factory LlamaCppTimings.fromJson(Map<String, dynamic> timings) {
    return LlamaCppTimings(
      cacheN: _asInt(timings['cache_n']),
      promptN: _asInt(timings['prompt_n']),
      promptMs: _asDouble(timings['prompt_ms']),
      predictedN: _asInt(timings['predicted_n']),
      predictedMs: _asDouble(timings['predicted_ms']),
      promptPerSecond: _asDouble(timings['prompt_per_second']),
      predictedPerSecond: _asDouble(timings['predicted_per_second']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (cacheN != null) 'cacheN': cacheN,
      if (promptN != null) 'promptN': promptN,
      if (promptMs != null) 'promptMs': promptMs,
      if (predictedN != null) 'predictedN': predictedN,
      if (predictedMs != null) 'predictedMs': predictedMs,
      if (promptPerSecond != null) 'promptPerSecond': promptPerSecond,
      if (predictedPerSecond != null) 'predictedPerSecond': predictedPerSecond,
      if (cachedPromptShare != null) 'cachedPromptShare': cachedPromptShare,
    };
  }
}

/// Result of a slot-aware chat completion: the assistant content plus the
/// provider extension fields the typed SDK discards (`id_slot`, `timings`).
class SlotChatResult {
  const SlotChatResult({
    required this.content,
    required this.finishReason,
    this.idSlot,
    this.timings,
    this.promptTokens,
    this.completionTokens,
    required this.raw,
  });

  final String content;
  final String? finishReason;

  /// The slot the server actually served. llama.cpp echoes `id_slot`; when it
  /// does not, this falls back to the requested slot.
  final int? idSlot;
  final LlamaCppTimings? timings;
  final int? promptTokens;
  final int? completionTokens;

  /// The full decoded response, so callers can read fields not modeled here.
  final Map<String, dynamic> raw;

  factory SlotChatResult.fromResponseJson(
    Map<String, dynamic> response, {
    int? requestedIdSlot,
  }) {
    final choices = response['choices'];
    final firstChoice = choices is List && choices.isNotEmpty
        ? _asStringMap(choices.first)
        : null;
    final message = _asStringMap(firstChoice?['message']);
    final usage = _asStringMap(response['usage']);
    final timings = _asStringMap(response['timings']);

    return SlotChatResult(
      content: message?['content'] is String
          ? message!['content'] as String
          : '',
      finishReason: firstChoice?['finish_reason'] as String?,
      idSlot: _asInt(response['id_slot']) ?? requestedIdSlot,
      timings: timings == null ? null : LlamaCppTimings.fromJson(timings),
      promptTokens: _asInt(usage?['prompt_tokens']),
      completionTokens: _asInt(usage?['completion_tokens']),
      raw: response,
    );
  }
}

class SlotChatTransportException implements Exception {
  const SlotChatTransportException({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;

  @override
  String toString() => 'SlotChatTransport HTTP $statusCode: $body';
}

/// LL20 transport substrate: an OpenAI-compatible chat-completions client that
/// preserves llama.cpp / LM Studio provider extension fields end-to-end.
///
/// Unlike the typed `openai_dart` client, this sends `id_slot` and
/// `cache_prompt` on the request and parses `timings` from the response, so a
/// conversation or Best-of-N candidate can be pinned to a server slot and its
/// cache reuse measured. It degrades to a plain completion when `idSlot` is
/// omitted, so non-slot endpoints behave exactly as today.
class LlamaCppSlotTransport {
  LlamaCppSlotTransport({
    required String baseUrl,
    required String apiKey,
    http.Client? client,
    Duration timeout = const Duration(seconds: 120),
  }) : _baseUrl = baseUrl,
       _apiKey = apiKey,
       _client = client ?? http.Client(),
       _timeout = timeout;

  final String _baseUrl;
  final String _apiKey;
  final http.Client _client;
  final Duration _timeout;

  /// `{baseUrl}/chat/completions`, tolerating a trailing slash.
  Uri get chatCompletionsUri {
    final normalized = _baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$normalized/chat/completions');
  }

  Future<SlotChatResult> createChatCompletion({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    double? temperature,
    int? maxTokens,
    int? idSlot,
    bool cachePrompt = true,
  }) async {
    final body = buildRequestBody(
      model: model,
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxTokens: maxTokens,
      idSlot: idSlot,
      cachePrompt: cachePrompt,
    );

    final response = await _client
        .post(chatCompletionsUri, headers: _headers(), body: jsonEncode(body))
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SlotChatTransportException(
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Expected a JSON object response.');
    }
    return SlotChatResult.fromResponseJson(
      Map<String, dynamic>.from(decoded),
      requestedIdSlot: idSlot,
    );
  }

  /// Builds the request body with extension fields injected. Exposed for
  /// focused round-trip tests.
  static Map<String, dynamic> buildRequestBody({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    double? temperature,
    int? maxTokens,
    int? idSlot,
    bool cachePrompt = true,
  }) {
    return {
      'model': model,
      'messages': messages,
      'stream': false,
      'cache_prompt': cachePrompt,
      'temperature': ?temperature,
      'max_tokens': ?maxTokens,
      'id_slot': ?idSlot,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
    };
  }

  Map<String, String> _headers() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final apiKey = _apiKey.trim();
    if (apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    return headers;
  }

  void close() => _client.close();
}

Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
