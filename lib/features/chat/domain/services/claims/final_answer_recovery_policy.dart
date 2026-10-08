enum FinalAnswerRecoveryReason {
  lengthTruncated('length_truncated'),
  excessiveRepetition('excessive_repetition');

  const FinalAnswerRecoveryReason(this.logToken);

  final String logToken;
}

/// Decides whether a tool-result final answer needs one concise replacement.
///
/// Provider-confirmed truncation is always recoverable. Repetition detection
/// is intentionally conservative: it only considers long responses with the
/// same substantial non-code line repeated several times.
class FinalAnswerRecoveryPolicy {
  const FinalAnswerRecoveryPolicy({
    this.minimumResponseCharacters = 1000,
    this.minimumRepeatedLineCharacters = 24,
    this.repeatedLineThreshold = 4,
  });

  static const int maxRetryTokens = 2048;
  static const double retryTemperature = 0.1;

  final int minimumResponseCharacters;
  final int minimumRepeatedLineCharacters;
  final int repeatedLineThreshold;

  FinalAnswerRecoveryReason? recoveryReason({
    required String content,
    String? finishReason,
  }) {
    if (_isTruncated(finishReason)) {
      return FinalAnswerRecoveryReason.lengthTruncated;
    }
    if (_hasExcessiveRepetition(content)) {
      return FinalAnswerRecoveryReason.excessiveRepetition;
    }
    return null;
  }

  String buildRetryPrompt(FinalAnswerRecoveryReason reason) {
    final failureDescription = switch (reason) {
      FinalAnswerRecoveryReason.lengthTruncated =>
        'was cut off at the output-token limit',
      FinalAnswerRecoveryReason.excessiveRepetition =>
        'contained excessive repeated content',
    };
    return '''
The previous final-answer attempt $failureDescription. Return one replacement final answer using only the verified tool results already provided.

Keep the answer concise (at most 400 words). State the outcome, material verification evidence, and any blocker or remaining work. Do not include internal reasoning, an implementation plan, future tool actions, code listings, tool calls, or repeated content.
'''
        .trim();
  }

  bool _isTruncated(String? finishReason) {
    switch (finishReason?.trim().toLowerCase()) {
      case 'length':
      case 'max_tokens':
      case 'max_output_tokens':
        return true;
    }
    return false;
  }

  bool _hasExcessiveRepetition(String content) {
    if (content.length < minimumResponseCharacters) {
      return false;
    }

    final counts = <String, int>{};
    String? activeFence;
    var nonFencedCharacters = 0;
    var repeatedLineDetected = false;
    for (final rawLine in content.split('\n')) {
      final trimmed = rawLine.trim();
      final fence = _fenceMarker(trimmed);
      if (fence != null) {
        activeFence = activeFence == null
            ? fence
            : activeFence == fence
            ? null
            : activeFence;
        continue;
      }
      if (activeFence != null) {
        continue;
      }
      nonFencedCharacters += rawLine.length + 1;

      final normalized = trimmed.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      if (normalized.length < minimumRepeatedLineCharacters ||
          !_hasSubstantiveCharacter(normalized)) {
        continue;
      }
      final count = (counts[normalized] ?? 0) + 1;
      if (count >= repeatedLineThreshold) {
        repeatedLineDetected = true;
      }
      counts[normalized] = count;
    }
    return nonFencedCharacters >= minimumResponseCharacters &&
        repeatedLineDetected;
  }

  bool _hasSubstantiveCharacter(String line) {
    return RegExp(r'[a-z0-9]').hasMatch(line) ||
        line.runes.any((rune) => rune > 0x7f);
  }

  String? _fenceMarker(String line) {
    if (line.startsWith('```')) {
      return '```';
    }
    if (line.startsWith('~~~')) {
      return '~~~';
    }
    return null;
  }
}
