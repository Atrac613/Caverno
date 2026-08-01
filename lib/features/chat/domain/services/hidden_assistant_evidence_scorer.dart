/// Scores hidden assistant text for concrete completion evidence.
abstract final class HiddenAssistantEvidenceScorer {
  static int score(String response) {
    final normalized = response.toLowerCase();
    var score = 0;
    if (normalized.contains('complete') || normalized.contains('completed')) {
      score += 2;
    }
    if (normalized.contains('validation passed') ||
        normalized.contains('tests passed') ||
        normalized.contains('was successful')) {
      score += 2;
    }
    if (normalized.contains('next task') ||
        normalized.contains('saved task') ||
        normalized.contains('in the plan')) {
      score += 1;
    }
    return score;
  }
}
