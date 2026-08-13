import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/utils/logger.dart';

/// SearXNG search client.
class SearxngClient {
  SearxngClient({required this.baseUrl, this.timeout = defaultTimeout});

  /// `http.get` has no timeout of its own, and the tool loop has no wall-clock
  /// guard, so an unreachable search endpoint used to hold a turn open
  /// indefinitely. Web search is the tool most likely to be reached for while
  /// the uplink is down, which is exactly when it can never answer.
  static const Duration defaultTimeout = Duration(seconds: 20);

  final String baseUrl;
  final Duration timeout;

  /// Runs a web search.
  Future<SearxngSearchResult> search({
    required String query,
    int maxResults = 5,
  }) async {
    appLog('[SearXNG] Search query: $query');

    final uri = Uri.parse(
      baseUrl,
    ).replace(path: '/search', queryParameters: {'q': query, 'format': 'json'});

    appLog('[SearXNG] Request URL: $uri');

    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(
          timeout,
          onTimeout: () => throw TimeoutException(
            'SearXNG did not respond within ${timeout.inSeconds}s at $baseUrl.',
          ),
        );

    appLog('[SearXNG] Response status: ${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception('SearXNG search failed: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (json['results'] as List<dynamic>? ?? [])
        .take(maxResults)
        .map((r) => SearxngResult.fromJson(r as Map<String, dynamic>))
        .toList();

    appLog('[SearXNG] Search results: ${results.length} items');

    return SearxngSearchResult(
      query: json['query'] as String? ?? query,
      results: results,
    );
  }

  /// Returns search results as plain text for the LLM.
  Future<String> searchAsText({
    required String query,
    int maxResults = 5,
  }) async {
    final result = await search(query: query, maxResults: maxResults);

    if (result.results.isEmpty) {
      return 'No search results found.';
    }

    final buffer = StringBuffer();
    buffer.writeln('Search results for "$query":\n');

    for (var i = 0; i < result.results.length; i++) {
      final r = result.results[i];
      buffer.writeln('${i + 1}. ${r.title}');
      buffer.writeln('   URL: ${r.url}');
      if (r.content.isNotEmpty) {
        buffer.writeln('   ${r.content}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }
}

/// Search result collection.
class SearxngSearchResult {
  SearxngSearchResult({required this.query, required this.results});

  final String query;
  final List<SearxngResult> results;
}

/// Individual search result entry.
class SearxngResult {
  SearxngResult({
    required this.title,
    required this.url,
    required this.content,
    this.publishedDate,
  });

  factory SearxngResult.fromJson(Map<String, dynamic> json) {
    return SearxngResult(
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      content: json['content'] as String? ?? '',
      publishedDate: json['publishedDate'] as String?,
    );
  }

  final String title;
  final String url;
  final String content;
  final String? publishedDate;
}
