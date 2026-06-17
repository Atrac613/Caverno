import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/repositories/drift_embedding_store.dart';

void main() {
  late AppDatabase db;
  late DriftEmbeddingStore store;

  setUp(() {
    db = AppDatabase.memory();
    store = DriftEmbeddingStore(db);
  });

  tearDown(() async => db.close());

  EmbeddingChunk chunk(int index, List<double> vector, [String snippet = '']) {
    return EmbeddingChunk(chunkIndex: index, snippet: snippet, vector: vector);
  }

  test('encode/decode round-trips a vector', () {
    final bytes = DriftEmbeddingStore.encodeVector([1.5, -2.0, 0.25]);
    final back = DriftEmbeddingStore.decodeVector(bytes);
    expect(back.length, 3);
    expect(back[0], closeTo(1.5, 1e-6));
    expect(back[1], closeTo(-2.0, 1e-6));
    expect(back[2], closeTo(0.25, 1e-6));
  });

  test('search ranks by cosine similarity, best first', () async {
    await store.replaceForSource(
      sourceType: 'conversation',
      sourceId: 'a',
      model: 'm',
      chunks: [
        chunk(0, [1, 0, 0], 'east'),
        chunk(1, [0, 1, 0], 'north'),
      ],
    );
    await store.replaceForSource(
      sourceType: 'conversation',
      sourceId: 'b',
      model: 'm',
      chunks: [
        chunk(0, [0.9, 0.1, 0], 'almost east'),
      ],
    );

    final results = await store.search(queryVector: [1, 0, 0], topK: 2);
    expect(results, hasLength(2));
    expect(results.first.snippet, 'east'); // exact match scores highest
    expect(results.first.score, closeTo(1, 1e-6));
    expect(results[1].snippet, 'almost east');
  });

  test('topK caps the result count', () async {
    await store.replaceForSource(
      sourceType: 'conversation',
      sourceId: 'a',
      model: 'm',
      chunks: [
        chunk(0, [1, 0]),
        chunk(1, [0.9, 0.1]),
        chunk(2, [0.8, 0.2]),
      ],
    );
    expect(await store.search(queryVector: [1, 0], topK: 1), hasLength(1));
  });

  test('search filters by source type', () async {
    await store.replaceForSource(
      sourceType: 'conversation',
      sourceId: 'a',
      model: 'm',
      chunks: [
        chunk(0, [1, 0], 'conv'),
      ],
    );
    await store.replaceForSource(
      sourceType: 'code',
      sourceId: 'f.dart',
      model: 'm',
      chunks: [
        chunk(0, [1, 0], 'code'),
      ],
    );

    final convOnly = await store.search(
      queryVector: [1, 0],
      sourceType: 'conversation',
    );
    expect(convOnly.map((m) => m.snippet), ['conv']);
  });

  test('replaceForSource re-indexes without duplicating', () async {
    await store.replaceForSource(
      sourceType: 'conversation',
      sourceId: 'a',
      model: 'm',
      chunks: [
        chunk(0, [1, 0], 'old'),
      ],
    );
    await store.replaceForSource(
      sourceType: 'conversation',
      sourceId: 'a',
      model: 'm',
      chunks: [
        chunk(0, [0, 1], 'new'),
      ],
    );
    expect(await store.count(), 1);
    final results = await store.search(queryVector: [0, 1]);
    expect(results.single.snippet, 'new');
  });

  test('deleteForSource and clear remove rows', () async {
    await store.replaceForSource(
      sourceType: 'conversation',
      sourceId: 'a',
      model: 'm',
      chunks: [
        chunk(0, [1, 0]),
      ],
    );
    await store.replaceForSource(
      sourceType: 'conversation',
      sourceId: 'b',
      model: 'm',
      chunks: [
        chunk(0, [0, 1]),
      ],
    );

    await store.deleteForSource(sourceType: 'conversation', sourceId: 'a');
    expect(await store.count(), 1);
    await store.clear();
    expect(await store.count(), 0);
  });
}
