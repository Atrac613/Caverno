import 'unexecuted_final_answer_tool_request_policy.dart';

/// Which final-answer notices the reader has to see, and which only the log
/// needs.
///
/// Every other notice contradicts something the reply asserted -- a file it
/// listed as written that does not exist, a passing-test count the run does not
/// support, a command that exited non-zero under a success claim. Those have to
/// stay in the message: without them a wrong claim is the last word the reader
/// gets.
///
/// The two below are different. They land on replies that are already accurate:
/// the model asked for a tool the final-answer step cannot run, or described a
/// next step it has not taken yet and said so. The tool result carrying the same
/// fact is recorded either way -- `tool_call_not_executed` for the first, the
/// unexecuted command-action result for the second -- so the model keeps its
/// signal and only the reader is spared a paragraph of harness plumbing.
///
/// The next-step notice is the qualified one. When the reply *asserts* it ran
/// the step, the tool results contradict it and the notice replaces the
/// sentence, so that firing stays visible; the service routes only the
/// future-tense shape here.
final class HarnessNoticeVisibility {
  const HarnessNoticeVisibility();

  /// Transform ID for the notice that says a described next step has not run.
  static const unexecutedNextStepTransformId = 'unexecuted_next_step_notice';

  static const _logOnly = <String>{
    UnexecutedFinalAnswerToolRequestPolicy.transformId,
    unexecutedNextStepTransformId,
  };

  /// Whether [transformId] names a notice that belongs in the log alone.
  bool isLogOnly(String? transformId) =>
      transformId != null && _logOnly.contains(transformId);
}
