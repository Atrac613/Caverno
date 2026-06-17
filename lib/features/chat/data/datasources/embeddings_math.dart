import 'dart:math' as math;

/// Vector math for LL5 semantic search.
class EmbeddingsMath {
  EmbeddingsMath._();

  /// Cosine similarity in [-1, 1]; returns 0 for a zero-magnitude or
  /// mismatched-length vector so ranking degrades safely instead of throwing.
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i += 1) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }
}
