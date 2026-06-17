import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/datasources/embeddings_client.dart';
import 'package:caverno/features/chat/data/repositories/drift_embedding_store.dart';
import 'package:caverno/features/chat/data/repositories/semantic_search_service.dart';

void main() {
  late AppDatabase db;
  late DriftEmbeddingStore store;

  setUp(() {
    db = AppDatabase.memory();
    store = DriftEmbeddingStore(db);
  });
  tearDown(() async => db.close());

  Future<void> index(String id, List<double> vector) {
    return store.replaceForSource(
      sourceType: 'conversation',
      sourceId: id,
      model: 'm',
      chunks: [EmbeddingChunk(chunkIndex: 0, snippet: id, vector: vector)],
    );
  }

  SemanticSearchService service({
    required EmbedTexts embed,
    Future<List<String>> Function(String)? lexical,
  }) {
    return SemanticSearchService(
      embed: embed,
      store: store,
      lexicalFallback: lexical ?? (_) async => const ['lex'],
    );
  }

  test('ranks conversations by embedding similarity', () async {
    await index('east', [1, 0, 0]);
    await index('north', [0, 1, 0]);

    final svc = service(
      embed: (inputs) async => EmbeddingsResult(
        vectors: const [
          [1, 0, 0],
        ],
        model: 'm',
      ),
    );
    final result = await svc.search('where is east', topK: 5);

    expect(result.mode, HistorySearchMode.semantic);
    expect(result.conversationIds.first, 'east');
  });

  test('dedups multiple chunks of the same conversation', () async {
    await store.replaceForSource(
      sourceType: 'conversation',
      sourceId: 'a',
      model: 'm',
      chunks: [
        EmbeddingChunk(chunkIndex: 0, snippet: 'a0', vector: [1, 0]),
        EmbeddingChunk(chunkIndex: 1, snippet: 'a1', vector: [0.9, 0.1]),
      ],
    );
    final svc = service(
      embed: (inputs) async => EmbeddingsResult(
        vectors: const [
          [1, 0],
        ],
        model: 'm',
      ),
    );
    final result = await svc.search('q');
    expect(result.conversationIds, ['a']);
  });

  test('falls back to lexical FTS when embeddings are unavailable', () async {
    await index('east', [1, 0]);
    final svc = service(
      embed: (_) async => null,
      lexical: (_) async => const ['lexA', 'lexB'],
    );
    final result = await svc.search('anything');
    expect(result.mode, HistorySearchMode.lexical);
    expect(result.conversationIds, ['lexA', 'lexB']);
  });

  test('falls back to lexical when semantic finds nothing', () async {
    // Empty store => no semantic hits.
    final svc = service(
      embed: (inputs) async => EmbeddingsResult(
        vectors: const [
          [1, 0],
        ],
        model: 'm',
      ),
      lexical: (_) async => const ['lexOnly'],
    );
    final result = await svc.search('q');
    expect(result.mode, HistorySearchMode.lexical);
    expect(result.conversationIds, ['lexOnly']);
  });

  test('returns none for an empty query without embedding', () async {
    var embedCalled = false;
    final svc = service(
      embed: (_) async {
        embedCalled = true;
        return null;
      },
    );
    final result = await svc.search('   ');
    expect(result.mode, HistorySearchMode.none);
    expect(result.conversationIds, isEmpty);
    expect(embedCalled, isFalse);
  });
}
