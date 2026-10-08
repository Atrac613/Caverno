import '../entities/tool_call_info.dart';
import 'python/pytest_verification_identity.dart';

// ChatNotifier decomposition collaborator: verifier-replay-candidate-policy

/// Accepts literal foreground verifiers and ranks captured candidates.
final class VerifierReplayCandidatePolicy {
  const VerifierReplayCandidatePolicy();

  static final RegExp _shellControl = RegExp(r'[\r\n;&|`<>]|\$\(');
  static final RegExp _verifierNamed = RegExp(r'(^|[/_-])verif(y|ier)');

  /// Accepts foreground commands with known literal verification syntax.
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
    if (isPytest(toolCall)) return true;
    if (command.isEmpty || _shellControl.hasMatch(command)) {
      return false;
    }
    return true;
  }

  bool isPytest(ToolCallInfo call) =>
      call.name == 'local_execute_command' &&
      PytestVerificationIdentity.parse(
            call.arguments['command']?.toString() ?? '',
            call.arguments['working_directory']?.toString() ?? '',
          ) !=
          null;

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
