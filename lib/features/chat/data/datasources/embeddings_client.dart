import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/constants/api_constants.dart';

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

/// Why the most recent [EmbeddingsClient.embed] call produced no vectors.
///
/// The client's contract is to return null on every failure so semantic search
/// degrades to lexical FTS instead of breaking. That graceful degradation also
/// erases the cause, which is exactly what a diagnostic needs: a stale
/// `embeddingsModel` pointed at a new endpoint fails as a plain 404, and
/// without this the report can only say "no vectors".
final class EmbeddingsFailure {
  const EmbeddingsFailure({
    required this.kind,
    required this.uri,
    required this.model,
    this.statusCode,
    this.body,
    this.error,
  });

  final EmbeddingsFailureKind kind;
  final Uri uri;
  final String model;
  final int? statusCode;

  /// Response body, truncated: endpoints put the actionable text here
  /// ("The model `x` does not exist").
  final String? body;
  final Object? error;

  /// One line naming the endpoint, the model and what went wrong, safe to show
  /// in a diagnostic report. The API key is never part of this.
  String describe() {
    final target = '$uri (model: $model)';
    return switch (kind) {
      EmbeddingsFailureKind.httpStatus =>
        'HTTP $statusCode from $target'
            '${body == null || body!.isEmpty ? '' : '\n$body'}',
      EmbeddingsFailureKind.malformedResponse =>
        'The response from $target carried no usable embedding vectors.'
            '${body == null || body!.isEmpty ? '' : '\n$body'}',
      EmbeddingsFailureKind.transport =>
        'Could not reach $target: ${error ?? 'unknown transport error'}',
    };
  }
}

enum EmbeddingsFailureKind { httpStatus, malformedResponse, transport }

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

  /// Why the most recent [embed] call returned null, or null after a success.
  /// Diagnostics read this; production callers keep ignoring it and fall back.
  EmbeddingsFailure? get lastFailure => _lastFailure;

  EmbeddingsFailure? _lastFailure;

  /// Embeds [inputs] with [model]. Returns null on any failure so the caller can
  /// fall back to lexical search; [lastFailure] then explains why.
  Future<EmbeddingsResult?> embed({
    required List<String> inputs,
    required String model,
  }) async {
    if (inputs.isEmpty) {
      _lastFailure = null;
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
        return _fail(
          EmbeddingsFailure(
            kind: EmbeddingsFailureKind.httpStatus,
            uri: embeddingsUri,
            model: model,
            statusCode: response.statusCode,
            body: _truncate(response.body),
          ),
        );
      }
      final decoded = jsonDecode(response.body);
      final parsed = decoded is Map
          ? _parse(Map<String, dynamic>.from(decoded), fallbackModel: model)
          : null;
      if (parsed == null) {
        return _fail(
          EmbeddingsFailure(
            kind: EmbeddingsFailureKind.malformedResponse,
            uri: embeddingsUri,
            model: model,
            statusCode: response.statusCode,
            body: _truncate(response.body),
          ),
        );
      }
      _lastFailure = null;
      return parsed;
    } on Object catch (error) {
      return _fail(
        EmbeddingsFailure(
          kind: EmbeddingsFailureKind.transport,
          uri: embeddingsUri,
          model: model,
          error: error,
        ),
      );
    }
  }

  Null _fail(EmbeddingsFailure failure) {
    _lastFailure = failure;
    return null;
  }

  static String _truncate(String body, {int maxChars = 400}) {
    final normalized = body.trim();
    return normalized.length <= maxChars
        ? normalized
        : '${normalized.substring(0, maxChars)}...';
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
    final headers = Map<String, String>.of(ApiConstants.jsonRequestHeaders);
    final apiKey = _apiKey.trim();
    if (apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    return headers;
  }

  void close() => _client.close();
}
