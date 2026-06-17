import 'dart:convert';

import 'package:http/http.dart' as http;

/// Result of an embeddings request.
class EmbeddingsResult {
  const EmbeddingsResult({required this.vectors, required this.model});

  /// One vector per input, in input order.
  final List<List<double>> vectors;
  final String model;

  int get dimension => vectors.isEmpty ? 0 : vectors.first.length;
}

/// Embeds [inputs], returning null when embeddings are unavailable. Lets
/// services depend on the capability without binding to the HTTP client.
typedef EmbedTexts = Future<EmbeddingsResult?> Function(List<String> inputs);

/// LL5 OpenAI-compatible embeddings client (`POST /v1/embeddings`).
///
/// Used to embed conversation history and code chunks for local semantic
/// search. It degrades gracefully: any failure (no embeddings endpoint, non-2xx,
/// malformed body, network error) returns null so callers fall back to lexical
/// FTS instead of breaking.
class EmbeddingsClient {
  EmbeddingsClient({
    required String baseUrl,
    required String apiKey,
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
  }) : _baseUrl = baseUrl,
       _apiKey = apiKey,
       _client = client ?? http.Client(),
       _timeout = timeout;

  final String _baseUrl;
  final String _apiKey;
  final http.Client _client;
  final Duration _timeout;

  /// `{baseUrl}/embeddings`, tolerating a trailing slash.
  Uri get embeddingsUri {
    final normalized = _baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$normalized/embeddings');
  }

  /// Embeds [inputs] with [model]. Returns null on any failure so the caller can
  /// fall back to lexical search.
  Future<EmbeddingsResult?> embed({
    required List<String> inputs,
    required String model,
  }) async {
    if (inputs.isEmpty) {
      return EmbeddingsResult(vectors: const [], model: model);
    }
    try {
      final response = await _client
          .post(
            embeddingsUri,
            headers: _headers(),
            body: jsonEncode({'model': model, 'input': inputs}),
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      return _parse(Map<String, dynamic>.from(decoded), fallbackModel: model);
    } on Object {
      return null;
    }
  }

  static EmbeddingsResult? _parse(
    Map<String, dynamic> response, {
    required String fallbackModel,
  }) {
    final data = response['data'];
    if (data is! List) return null;
    // Preserve input order via each entry's `index` when present.
    final indexed = <(int, List<double>)>[];
    for (var position = 0; position < data.length; position += 1) {
      final entry = data[position];
      if (entry is! Map) continue;
      final embedding = entry['embedding'];
      if (embedding is! List) continue;
      final vector = [
        for (final value in embedding)
          if (value is num) value.toDouble(),
      ];
      final index = entry['index'] is int ? entry['index'] as int : position;
      indexed.add((index, vector));
    }
    if (indexed.isEmpty) return null;
    indexed.sort((a, b) => a.$1.compareTo(b.$1));
    return EmbeddingsResult(
      vectors: [for (final item in indexed) item.$2],
      model: response['model'] is String
          ? response['model'] as String
          : fallbackModel,
    );
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
