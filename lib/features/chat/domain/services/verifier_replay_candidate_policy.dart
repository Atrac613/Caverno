import '../entities/tool_call_info.dart';

// ChatNotifier decomposition collaborator: verifier-replay-candidate-policy

/// Decides which executed tool call may be replayed as a verifier, and how
/// strong a candidate it is.
///
/// After a turn mutates files without verifying them, the loop replays the
/// verifier the model already ran rather than inventing one. Replaying is
/// re-executing a command the user approved earlier, so the rules are narrow on
/// purpose: a backgrounded command never finished, and a command carrying shell
/// control characters can do more the second time than the text suggests —
/// `dart test && rm -rf build` is not a verifier.
final class VerifierReplayCandidatePolicy {
  const VerifierReplayCandidatePolicy();

  static final RegExp _shellControl = RegExp(r'[\r\n;&|`<>]|\$\(');
  static final RegExp _verifierNamed = RegExp(r'(^|[/_-])verif(y|ier)');

  /// Whether [toolCall] is shaped like something safe to run again.
  ///
  /// `run_tests` always is: it takes no free-form command. A local command
  /// qualifies only when it ran in the foreground and is a single plain
  /// command.
  bool isEligible(ToolCallInfo toolCall) {
    final name = toolCall.name.trim().toLowerCase();
    if (name == 'run_tests') {
      return true;
    }
    if (name != 'local_execute_command' ||
        toolCall.arguments['background'] == true) {
      return false;
    }
    final command = (toolCall.arguments['command'] as String? ?? '').trim();
    if (command.isEmpty || _shellControl.hasMatch(command)) {
      return false;
    }
    return true;
  }

  /// How strongly [toolCall] should be preferred when several are eligible.
  ///
  /// A dedicated test run outranks an arbitrary command, and a command that
  /// names itself a verifier is treated as one.
  int priority(ToolCallInfo toolCall) {
    if (toolCall.name.trim().toLowerCase() == 'run_tests') {
      return 2;
    }
    final command = (toolCall.arguments['command'] as String? ?? '')
        .toLowerCase();
    return _verifierNamed.hasMatch(command) ? 2 : 1;
  }
}

/// The policy holds no state, so callers share one instance.
const verifierReplayCandidatePolicy = VerifierReplayCandidatePolicy();
