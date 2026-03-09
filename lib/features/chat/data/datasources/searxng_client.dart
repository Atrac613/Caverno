import 'dart:convert';

import 'package:http/http.dart' as http;

/// SearXNG search client.
class SearxngClient {
  SearxngClient({required this.baseUrl});

  final String baseUrl;

  /// Runs a web search.
  Future<SearxngSearchResult> search({
    required String query,
    int maxResults = 5,
  }) async {
    print('[SearXNG] 検索クエリ: $query');

    final uri = Uri.parse(
      baseUrl,
    ).replace(path: '/search', queryParameters: {'q': query, 'format': 'json'});

    print('[SearXNG] Request URL: $uri');

    final response = await http.get(
      uri,
      headers: {'Accept': 'application/json'},
    );

    print('[SearXNG] Response status: ${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception('SearXNG search failed: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (json['results'] as List<dynamic>? ?? [])
        .take(maxResults)
        .map((r) => SearxngResult.fromJson(r as Map<String, dynamic>))
        .toList();

    print('[SearXNG] 検索結果: ${results.length}件');

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
    try {
      final result = await search(query: query, maxResults: maxResults);

      if (result.results.isEmpty) {
        return '検索結果が見つかりませんでした。';
      }

      final buffer = StringBuffer();
      buffer.writeln('「$query」の検索結果:\n');

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
    } catch (e) {
      print('[SearXNG] エラー: $e');
      return '検索エラー: $e';
    }
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
