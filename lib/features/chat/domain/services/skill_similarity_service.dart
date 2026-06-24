import '../entities/skill.dart';

/// A skill judged similar to a candidate save, with its similarity [score]
/// (0..1, higher = more similar).
class SkillSimilarityMatch {
  const SkillSimilarityMatch({required this.skill, required this.score});

  final Skill skill;
  final double score;
}

/// Offline lexical duplicate/near-duplicate detection for skill authoring.
///
/// Compares a candidate skill (name + description + whenToUse) against existing
/// skills using token Jaccard similarity plus compact-substring containment on
/// the name. It is deterministic and needs no embeddings endpoint, so it works
/// offline; semantic (embeddings) similarity can layer on top later.
class SkillSimilarityService {
  /// Minimum similarity (the stronger of the name and description signals) for
  /// a candidate to be reported as similar.
  static const double defaultThreshold = 0.5;

  /// Returns existing skills similar to the candidate, strongest first. An
  /// exact (normalized) name match is intentionally excluded — that is handled
  /// as an in-place update by the caller, not a duplicate.
  ///
  /// Overall similarity is the stronger of two signals, so either a similar
  /// name or a similar purpose (description/whenToUse) is enough to flag a
  /// near-duplicate.
  static List<SkillSimilarityMatch> findSimilar({
    required String name,
    String description = '',
    String whenToUse = '',
    required List<Skill> existing,
    double threshold = defaultThreshold,
  }) {
    final candidateName = name.trim().toLowerCase();
    final nameTokens = _tokenize(name);
    final compactName = _compact(name);
    final candidateContext = <String>{
      ..._tokenize(description),
      ..._tokenize(whenToUse),
    };
    if (nameTokens.isEmpty && compactName.isEmpty) {
      return const <SkillSimilarityMatch>[];
    }

    final matches = <SkillSimilarityMatch>[];
    for (final skill in existing) {
      // Skip the exact-name case; the caller updates that skill in place.
      if (skill.normalizedName.toLowerCase() == candidateName) {
        continue;
      }
      final nameScore = _nameSimilarity(nameTokens, compactName, skill);
      final contextScore = _jaccard(candidateContext, {
        ..._tokenize(skill.normalizedDescription),
        ..._tokenize(skill.normalizedWhenToUse),
      });
      final score = nameScore > contextScore ? nameScore : contextScore;
      if (score >= threshold) {
        matches.add(SkillSimilarityMatch(skill: skill, score: score));
      }
    }
    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches;
  }

  static double _nameSimilarity(
    Set<String> candidateTokens,
    String candidateCompact,
    Skill other,
  ) {
    final otherTokens = _tokenize(other.normalizedName);
    final otherCompact = _compact(other.normalizedName);
    final jaccard = _jaccard(candidateTokens, otherTokens);
    final contained =
        candidateCompact.length >= 3 &&
        otherCompact.length >= 3 &&
        (candidateCompact.contains(otherCompact) ||
            otherCompact.contains(candidateCompact));
    if (contained && jaccard < 0.85) {
      return 0.85;
    }
    return jaccard;
  }

  static double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) {
      return 0;
    }
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    return union == 0 ? 0 : intersection / union;
  }

  // Keep ASCII alphanumerics and CJK (hiragana/katakana/kanji); split on the
  // rest. CJK has no spaces, so it collapses into compact substrings that the
  // containment check still catches.
  static final RegExp _separator = RegExp(
    r'[^a-z0-9぀-ヿ一-鿿]+',
  );

  static Set<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .split(_separator)
        .where((token) => token.length >= 2)
        .toSet();
  }

  static String _compact(String text) {
    return text.toLowerCase().replaceAll(_separator, '');
  }
}
