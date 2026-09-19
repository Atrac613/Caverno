/// Tells a reply that was cut off mid-thought apart from one that is finished.
///
/// A follow-up that returns `finish_reason: length` with reasoning and no
/// visible answer is not an answer. The model was still working and the
/// generation ran out, so ending the tool loop there reads a harness limit as
/// the model's decision.
///
/// Session 99587346 is the case. After `edit_file` bumped the version, the next
/// reply spent all 8,192 completion tokens reasoning, ended on "Let me write
/// the release notes file now.", and produced no visible text and no tool call.
/// The loop logged it as a final text response and stopped at iteration 9 of
/// 12, with the release notes, the commit and the tag never written. The two
/// runs before it peaked at 553 and 2,769 completion tokens, so the cap was
/// only reachable once carried results made the reasoning longer.
final class TruncatedReasoningContinuation {
  const TruncatedReasoningContinuation();

  /// How many times one turn may ask a cut-off reply to carry on.
  ///
  /// One: a second truncation in a row means the reasoning does not fit, which
  /// is a budget question rather than something to retry into.
  static const int maxContinuationsPerTurn = 1;

  /// Whether [content] is a reply the generation cut off before it acted.
  ///
  /// [content] is the raw reply, reasoning included, because that is what makes
  /// the difference visible: everything here is thinking and none of it is an
  /// answer.
  bool isCutOffBeforeAnswer({
    required String? finishReason,
    required String content,
    required bool hasToolCalls,
  }) {
    if (hasToolCalls) return false;
    if (finishReason?.trim().toLowerCase() != 'length') return false;
    return visibleText(content).isEmpty;
  }

  /// The reply with any reasoning block removed.
  ///
  /// An unterminated block means the cut landed inside it, so nothing after it
  /// survived and there is no visible text at all.
  String visibleText(String content) {
    const closing = '</think>';
    final index = content.lastIndexOf(closing);
    if (index < 0) {
      return content.contains('<think>') ? '' : content.trim();
    }
    return content.substring(index + closing.length).trim();
  }

  /// What to tell the model so it resumes rather than restates.
  ///
  /// It names the limit, because a model that cannot see why its last reply
  /// vanished tends to plan the same work again from the top.
  String continuationPrompt() =>
      'Your previous reply reached the generation token limit while you were '
      'still reasoning, so none of it was delivered and no tool ran. Continue '
      'from where you were: make the next tool call now, without restating the '
      'plan or repeating work whose results you already have.';
}
