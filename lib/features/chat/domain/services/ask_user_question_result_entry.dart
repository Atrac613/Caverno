import '../entities/mcp_tool_entity.dart';

/// One recorded answer together with the options it was offered alongside.
///
/// The offered set is stored, not just the picked label, because a verdict
/// that must not be spoofable by the wording of one option needs the whole
/// set: an answer reporting only what the user picked cannot show that the
/// same marker was also attached to the option they were declining.
final class CachedAskUserQuestionResult {
  CachedAskUserQuestionResult({
    required String question,
    required Iterable<String> optionLabels,
    required this.result,
  }) : normalizedQuestion = normalizeAskUserQuestionText(question),
       optionLabels = normalizeAskUserQuestionOptionLabels(optionLabels);

  final String normalizedQuestion;
  final Set<String> optionLabels;
  final McpToolResult result;
}

Set<String> normalizeAskUserQuestionOptionLabels(Iterable<String> labels) {
  return Set<String>.unmodifiable(
    labels.map(normalizeAskUserQuestionText).where((label) => label.isNotEmpty),
  );
}

String normalizeAskUserQuestionText(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
