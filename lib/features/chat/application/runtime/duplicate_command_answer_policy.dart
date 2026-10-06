import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/tool_call_execution_policy.dart';

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
/// The output wins over the prose whenever there is one. That needs no reading
/// of the prose: the model asked to run a command it had already run, so it had
/// not finished answering. The preamble stays in the message above it.
///
/// It is not, however, the first thing to try. Output is the answer only when
/// the turn asked for that output itself; when it is material for an answer
/// the model has yet to write, delivering it ends the turn on raw stdout.
/// Session e3a9f3f0's read-only `/review` re-ran its git inspections because
/// the follow-up no longer carried them, the repeated `git ls-files --others`
/// was discarded, and the review the user asked for came back as the single
/// line `test_watcher.py`. So the caller first spends its one bounded
/// follow-up recovery, which hands the model these same results, and delivers
/// [answerForDuplicateCommands] only when that recovery is spent or yields no
/// usable text. 96e27118 still gets its tag list either way.
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

  /// The answer after the bounded recovery for a duplicate command batch
  /// returned text that the generic recovery gate rejected.
  ///
  /// That gate scores task-completion vocabulary ("complete", "tests
  /// passed"), so a review or any Japanese answer never clears it and the
  /// turn would fall back to raw stdout anyway. The decision here is
  /// structural instead: the recovery was handed the earlier results and
  /// stopped without calling a tool, so any visible text it wrote is its
  /// answer. 96e27118's preamble does not fit that shape; it rode along with a
  /// tool request, and a tool call written inline as text is that same shape.
  /// [previousAnswer] stays the fallback for either, and for empty text.
  String afterRecovery({
    required String recoveryText,
    required String previousAnswer,
  }) {
    if (ContentParser.extractCompletedToolCalls(recoveryText).isNotEmpty ||
        ContentParser.hasIncompleteToolCall(recoveryText)) {
      return previousAnswer;
    }
    final visible = ContentParser.stripModelHistoryArtifacts(recoveryText);
    return visible.isNotEmpty ? recoveryText.trim() : previousAnswer;
  }

  /// [resolve] for a batch of [toolCalls] that all repeat a command which
  /// already succeeded this turn, or null when the batch is not that.
  ///
  /// [recoveredToolResults] is preferred as the source of the earlier output
  /// and [executedToolResults] is the fallback, matching what the loop hands
  /// its duplicate recoveries.
  String? answerForDuplicateCommands({
    required List<ToolCallInfo> toolCalls,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> recoveredToolResults,
    required String visibleAnswer,
    ToolCallExecutionPolicy policy = const ToolCallExecutionPolicy(),
  }) {
    if (!policy.containsOnlyPreviouslySuccessfulCommandToolCalls(
      toolCalls,
      executedToolResults,
    )) {
      return null;
    }
    return resolve(
      previousOutput: policy.previousSuccessfulCommandOutputForDuplicateCalls(
        toolCalls,
        recoveredToolResults.isNotEmpty
            ? recoveredToolResults
            : executedToolResults,
      ),
      visibleAnswer: visibleAnswer,
      mayUsePreviousOutput: policy
          .shouldUsePreviousOutputForDuplicateCommandCalls(toolCalls),
      visibleAnswerLooksPending: looksLikePendingToolAction(visibleAnswer),
    );
  }
}
