// ChatNotifier decomposition collaborator: ask-user-question-text-normalization

/// Collapses a set of option labels to their comparable forms, dropping blanks.
Set<String> normalizeAskUserQuestionOptionLabels(Iterable<String> labels) {
  return Set<String>.unmodifiable(
    labels.map(normalizeAskUserQuestionText).where((label) => label.isNotEmpty),
  );
}

/// The comparable form of one question or option label.
///
/// Case and whitespace are presentation, so two spellings of one question are
/// the same question. Nothing else is normalized: an option label can carry a
/// one-time approval token, and folding any more of it away would make two
/// different decisions look identical.
String normalizeAskUserQuestionText(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
