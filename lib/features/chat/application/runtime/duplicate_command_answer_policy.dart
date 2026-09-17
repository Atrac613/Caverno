/// Which answer a turn owes the user when every tool call it just asked for had
/// already run this turn.
///
/// The loop reaches this point with two candidates: the output those calls
/// produced earlier, and whatever visible text the model wrote alongside the
/// request. Picking between them used to depend on what the visible text read
/// like — `looksLikePendingToolActionResponse` matches English alone ("let me",
/// "I'll", "I need to"), so session 96e27118's Japanese preamble
/// "まず現状のタグとコミット履歴を確認します。" ("I'll check the tags first")
/// scored as a finished answer. The turn re-sent that promise as its result,
/// the append dropped it as already present, and the user watched the assistant
/// announce the work and stop while the tag list it had asked for sat unused.
///
/// The output wins whenever there is one. That needs no reading of the prose:
/// the model asked to run a command it had already run, so it had not finished
/// answering, and the output it asked for is what the turn owes the user. The
/// preamble stays in the message above it.
///
/// The heuristic survives only in the fallback, where there is no output to
/// deliver and the question is the narrower one of whether the visible text can
/// stand alone. A wrong answer there costs a round trip, not the turn.
/// Lives here rather than in `domain/services` because that directory is one of
/// the five roots the RAG2 development declaration freezes at 512 eligible
/// files, and it is already at the ceiling: adding a file there fails
/// `rag2_explicit_source_roots_development_eval_test`.
final class DuplicateCommandAnswerPolicy {
  const DuplicateCommandAnswerPolicy();

  /// Whether [response] reads as a promise to act rather than an answer.
  ///
  /// English only, and knowingly so: it is a trigger, never a judge. Nothing
  /// load-bearing may turn on it — see the note above about what happens to a
  /// Japanese preamble when it does.
  static bool looksLikePendingToolAction(String response) => RegExp(
    r"\b(?:now\s+)?let me\b|\bi (?:will|need to|should|am going to)\b|\bi(?:'ll| will)\b",
  ).hasMatch(response.toLowerCase());

  /// The text to deliver as the turn's answer, or null when neither candidate
  /// can stand as one and the caller should keep looking.
  String? resolve({
    required String previousOutput,
    required String visibleAnswer,
    required bool mayUsePreviousOutput,
    required bool visibleAnswerLooksPending,
  }) {
    if (mayUsePreviousOutput && previousOutput.isNotEmpty) {
      return previousOutput;
    }
    if (visibleAnswer.isNotEmpty && !visibleAnswerLooksPending) {
      return visibleAnswer;
    }
    return null;
  }
}
