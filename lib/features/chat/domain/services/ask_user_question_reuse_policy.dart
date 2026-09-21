import '../entities/mcp_tool_entity.dart';
import 'ask_user_question_result_entry.dart';
import 'ask_user_question_text_normalization.dart';

// ChatNotifier decomposition collaborator: ask-user-question-reuse-policy

/// Picks the recorded answer, if any, that can serve a repeated question.
///
/// Reuse exists to stop a model looping on one decision from prompting the
/// user again and again inside a turn. What it must not do is hand back an
/// answer that no longer describes a choice the user made.
final class AskUserQuestionReusePolicy {
  const AskUserQuestionReusePolicy();

  /// The most recent entry that can answer [question] with [optionLabels].
  McpToolResult? findReusable({
    required List<CachedAskUserQuestionResult> entries,
    required String question,
    required Iterable<String> optionLabels,
  }) {
    if (entries.isEmpty) return null;

    final normalizedQuestion = normalizeAskUserQuestionText(question);
    final normalizedLabels = normalizeAskUserQuestionOptionLabels(optionLabels);
    for (final entry in entries.reversed) {
      if (entry.normalizedQuestion != normalizedQuestion) continue;
      if (!_answerStillOnOffer(entry, normalizedLabels)) continue;
      return entry.result;
    }

    if (normalizedLabels.isEmpty) return null;
    for (final entry in entries.reversed) {
      final canReuseAcrossWording =
          entry.result.isSuccess &&
          (entry.optionLabels.length > 1 || normalizedLabels.length > 1) &&
          entry.optionLabels.intersection(normalizedLabels).isNotEmpty;
      if (canReuseAcrossWording &&
          _answerStillOnOffer(entry, normalizedLabels)) {
        return entry.result;
      }
    }
    return null;
  }

  /// Whether the option [entry]'s answer picked is still among those offered.
  ///
  /// Replaying an answer whose option is gone hands back a choice the user
  /// cannot be said to have made. Session fb19ce5e (2026-09-20, gen-13) shows
  /// the cost: three production release approvals with byte-identical question
  /// text and a one-time token in the option label, rotated after the first
  /// release succeeded. Matching on question text alone replayed the answer
  /// naming the spent token, so no answer the user was able to give would
  /// satisfy the gate -- six release attempts and three approval prompts on an
  /// approval that could never land.
  ///
  /// Both paths are checked because the looser one is the fall-through for
  /// whatever the question-text path rejects: two asks differing only in a
  /// rotating token still share their cancel label, and that overlap alone is
  /// all cross-wording reuse asks for.
  ///
  /// An entry that recorded no selection names no option to check, so a
  /// cancellation, a free-text reply, and a question asked with no options all
  /// keep matching on the question as before. That still suppresses the
  /// re-prompt while the model loops on one decision, which is the point.
  bool _answerStillOnOffer(
    CachedAskUserQuestionResult entry,
    Set<String> normalizedLabels,
  ) {
    if (entry.selectedLabels.isEmpty) return true;
    if (normalizedLabels.isEmpty) return true;
    return entry.selectedLabels.intersection(normalizedLabels).isNotEmpty;
  }
}
