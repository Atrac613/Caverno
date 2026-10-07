import '../entities/mcp_tool_entity.dart';
import 'ask_user_question_text_normalization.dart';

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
    Iterable<String> selectedLabels = const [],
  }) : normalizedQuestion = normalizeAskUserQuestionText(question),
       optionLabels = normalizeAskUserQuestionOptionLabels(optionLabels),
       selectedLabels = normalizeAskUserQuestionOptionLabels(selectedLabels);

  final String normalizedQuestion;
  final Set<String> optionLabels;

  /// The options the answer picked, empty for a cancellation or free text.
  /// Read by `AskUserQuestionReusePolicy`, which explains why reuse needs it.
  final Set<String> selectedLabels;
  final McpToolResult result;
}
