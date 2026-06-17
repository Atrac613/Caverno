import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../datasources/app_database.dart';
import '../datasources/embeddings_math.dart';

/// One embedded chunk to store for a source.
class EmbeddingChunk {
  const EmbeddingChunk({
    required this.chunkIndex,
    required this.snippet,
    required this.vector,
  });

  final int chunkIndex;
  final String snippet;
  final List<double> vector;
}

/// A semantic-search hit, ranked by cosine similarity.
class EmbeddingMatch {
  const EmbeddingMatch({
    required this.sourceType,
    required this.sourceId,
    required this.chunkIndex,
    required this.snippet,
    required this.score,
  });

  final String sourceType;
  final String sourceId;
  final int chunkIndex;
  final String snippet;
  final double score;
}

/// LL5 drift-backed vector store. Vectors are packed Float32 blobs; similarity
/// search is brute-force cosine in Dart (fine at local history scale), filtered
/// by source type and ranked descending.
class DriftEmbeddingStore {
  DriftEmbeddingStore(this._db);

  final AppDatabase _db;

  /// Replaces all stored chunks for a source with [chunks] (re-index safe).
  Future<void> replaceForSource({
    required String sourceType,
    required String sourceId,
    required List<EmbeddingChunk> chunks,
    required String model,
    DateTime Function() clock = DateTime.now,
  }) async {
    final now = clock().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await deleteForSource(sourceType: sourceType, sourceId: sourceId);
      for (final chunk in chunks) {
        await _db
            .into(_db.embeddings)
            .insert(
              EmbeddingsCompanion.insert(
                sourceType: sourceType,
                sourceId: sourceId,
                chunkIndex: Value(chunk.chunkIndex),
                model: Value(model),
                dim: Value(chunk.vector.length),
                vector: encodeVector(chunk.vector),
                snippet: Value(chunk.snippet),
                createdAtMs: Value(now),
              ),
            );
      }
    });
  }

  Future<void> deleteForSource({
    required String sourceType,
    required String sourceId,
  }) async {
    await (_db.delete(_db.embeddings)..where(
          (t) => t.sourceType.equals(sourceType) & t.sourceId.equals(sourceId),
        ))
        .go();
  }

  Future<void> clear() async => _db.delete(_db.embeddings).go();

  Future<int> count() async {
    final rows = await _db.select(_db.embeddings).get();
    return rows.length;
  }

  /// Returns the [topK] chunks most similar to [queryVector], optionally
  /// restricted to [sourceType], best score first. Mismatched-dimension or
  /// zero-magnitude rows score 0 (via cosine) and fall to the bottom.
  Future<List<EmbeddingMatch>> search({
    required List<double> queryVector,
    int topK = 10,
    String? sourceType,
  }) async {
    if (queryVector.isEmpty || topK <= 0) return const [];
    final query = _db.select(_db.embeddings);
    if (sourceType != null) {
      query.where((t) => t.sourceType.equals(sourceType));
    }
    final rows = await query.get();
    final matches = [
      for (final row in rows)
        EmbeddingMatch(
          sourceType: row.sourceType,
          sourceId: row.sourceId,
          chunkIndex: row.chunkIndex,
          snippet: row.snippet,
          score: EmbeddingsMath.cosineSimilarity(
            queryVector,
            decodeVector(row.vector),
          ),
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return matches.length > topK ? matches.sublist(0, topK) : matches;
  }

  /// Packs a vector into Float32 bytes for blob storage.
  static Uint8List encodeVector(List<double> vector) {
    return Float32List.fromList(vector).buffer.asUint8List();
  }

  /// Decodes Float32 blob bytes back into a vector. Copies first to guarantee
  /// 4-byte alignment regardless of the source buffer offset.
  static List<double> decodeVector(Uint8List bytes) {
    final copy = Uint8List.fromList(bytes);
    return copy.buffer
        .asFloat32List()
        .map((value) => value.toDouble())
        .toList();
  }
}
