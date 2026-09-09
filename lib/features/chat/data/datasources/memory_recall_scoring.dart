import '../../domain/entities/session_memory.dart';

/// Jaccard similarity over character bigrams, used by recall_memory.
class ScoredMemoryMatch {
  ScoredMemoryMatch({required this.memory, required this.score});

  final MemoryEntry memory;
  final double score;
}

Set<String> memoryTextBiGrams(String text) {
  final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (normalized.isEmpty) return const {};
  if (normalized.length == 1) return {normalized};
  final grams = <String>{};
  for (var i = 0; i < normalized.length - 1; i++) {
    grams.add(normalized.substring(i, i + 2));
  }
  return grams;
}
