import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../model_routing/chat_request_thinking_policy.dart';

/// A tool-loop response that ended inside the model's reasoning: no visible
/// answer and no tool call.
///
/// The loop read it as the turn's end and asked for a tools-free final answer,
/// which could only describe the work as unfinished. In session 78578870 this
/// happened twice in one subtask turn while the model was drafting multi-file
/// edits, and the farm workflow stopped; 13 such stops were found across 12 of
/// the 150 most recent coding sessions. Detection is mechanical, judging no
/// prose, so it also applies to project-task turns that skip prose recovery.
///
/// A streamed reply's content omits its reasoning, so the caller restores it
/// with `ChatCompletionResult.orReasoning`. Until it did, this never fired
/// outside tests: session 8ca9fb5b stopped twice this way on a build that
/// carried the recovery.
final class ReasoningOnlyStop {
  const ReasoningOnlyStop();

  static const recoveryCode = 'reasoning_only_stop';

  bool matches(String rawResponse) {
    final segments = ContentParser.parse(rawResponse).segments;
    return segments.any((segment) => segment.type == ContentType.thinking) &&
        !segments.any(
          (segment) =>
              segment.type == ContentType.toolCall ||
              segment.type == ContentType.toolResult,
        ) &&
        ContentParser.stripModelHistoryArtifacts(rawResponse).isEmpty;
  }

  /// Sends a recovery request, with thinking off when [recoveryCode] is this
  /// recovery's.
  ///
  /// A retry with the same settings stops at the same point. In session
  /// be9dbba9 the stop and its recovery reasoned 947 and 946 tokens and ended
  /// on the same words; a replay of that request stopped inside its reasoning
  /// again, and the same request without thinking returned a tool call in 9 s.
  /// All 16 such stops in the corpus end mid-sentence: the generation is cut
  /// inside the reasoning, so only a request that cannot reason avoids it.
  static Future<T> send<T>(String recoveryCode, Future<T> Function() request) =>
      recoveryCode == ReasoningOnlyStop.recoveryCode
      ? ChatRequestThinkingPolicy.runWithoutThinking(request)
      : request();

  static const label = 'reasoning-only stop recovery';
  static const reason =
      'The assistant ended its response inside its reasoning, with no visible '
      'answer and no tool call.';
  static const requiredAction =
      'Issue the next tool call now. If the work is already done, give the '
      'final answer instead.';
  static const lead =
      'The previous assistant response contained only reasoning: no visible '
      'answer and no tool call was issued. Continue the work.';
}
