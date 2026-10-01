import 'package:caverno_content_protocol/caverno_content_protocol.dart';

/// A tool-loop response that ended inside the model's reasoning: no visible
/// answer and no tool call.
///
/// The loop read it as the turn's end and asked for a tools-free final answer,
/// which could only describe the work as unfinished. In session 78578870 this
/// happened twice in one subtask turn while the model was drafting multi-file
/// edits, and the farm workflow stopped; 13 such stops were found across 12 of
/// the 150 most recent coding sessions. Detection is mechanical, judging no
/// prose, so it also applies to project-task turns that skip prose recovery.
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
