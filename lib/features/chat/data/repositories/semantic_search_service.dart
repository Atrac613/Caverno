import '../datasources/embeddings_client.dart';
import 'drift_embedding_store.dart';
import 'semantic_indexing_service.dart';

/// How a history search result was produced.
enum HistorySearchMode {
  /// Ranked by embedding similarity.
  semantic,

  /// Lexical FTS fallback (no embeddings endpoint, or semantic found nothing).
  lexical,

  /// Empty query.
  none,
}

class HistorySearchResult {
  const HistorySearchResult({
    required this.mode,
    required this.conversationIds,
  });

  const HistorySearchResult.empty()
    : mode = HistorySearchMode.none,
      conversationIds = const [];

  final HistorySearchMode mode;

  /// Matching conversation ids, ranked best-first.
  final List<String> conversationIds;
}

/// LL5 history search: embeds the query and ranks conversations by stored
/// embedding similarity, falling back to lexical FTS when embeddings are
/// unavailable or produce no hit. Returns conversation ids (best chunk per
/// conversation) for the caller to hydrate.
class SemanticSearchService {
  SemanticSearchService({
    required this.embed,
    required this.store,
    required this.lexicalFallback,
  });

  final EmbedTexts embed;
  final DriftEmbeddingStore store;

  /// Lexical FTS fallback: returns matching conversation ids for a query.
  final Future<List<String>> Function(String query) lexicalFallback;

  Future<HistorySearchResult> search(String query, {int topK = 10}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const HistorySearchResult.empty();

    final embedded = await embed([trimmed]);
    if (embedded == null || embedded.vectors.isEmpty) {
      return HistorySearchResult(
        mode: HistorySearchMode.lexical,
        conversationIds: await lexicalFallback(trimmed),
      );
    }

    // Over-fetch chunks, then collapse to the best chunk per conversation.
    final matches = await store.search(
      queryVector: embedded.vectors.first,
      topK: topK * 4,
      sourceType: SemanticIndexingService.sourceType,
    );
    final seen = <String>{};
    final ids = <String>[];
    for (final match in matches) {
      if (match.score <= 0) continue;
      if (seen.add(match.sourceId)) ids.add(match.sourceId);
      if (ids.length >= topK) break;
    }

    if (ids.isEmpty) {
      return HistorySearchResult(
        mode: HistorySearchMode.lexical,
        conversationIds: await lexicalFallback(trimmed),
      );
    }
    return HistorySearchResult(
      mode: HistorySearchMode.semantic,
      conversationIds: ids,
    );
  }
}
