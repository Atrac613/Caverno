import '../../entities/tool_call_info.dart';
import '../literal_environment_inspection_policy.dart';
import '../literal_shell_words.dart';
import 'pytest_verification_identity.dart';

/// Conservatively tracks state changes between captured verification runs.
abstract final class PytestReplayStatePolicy {
  static bool mayChange(ToolCallInfo call, String? root) {
    if (const {
      'read_file',
      'list_directory',
      'coding_output_feedback',
      'update_goal',
      'coding_continuation_recovery',
    }.contains(call.name)) {
      return false;
    }
    final command = call.arguments['command']?.toString() ?? '';
    if (call.name == 'local_execute_command' &&
        call.arguments['background'] != true) {
      return PytestVerificationIdentity.parse(
                command,
                call.arguments['working_directory']?.toString() ?? root ?? '',
              ) ==
              null &&
          !LiteralEnvironmentInspectionPolicy.applies(
            command,
            allowPackageImports: false,
          );
    }
    if (call.name == 'git_execute_command') {
      final words = LiteralShellWords.parse(command);
      return words == null ||
          !const {'status', 'diff', 'log'}.contains(words.first) ||
          words.any(
            (word) => RegExp(
              r'^--(?:output(?:=|$)|ext-diff$|textconv$)',
            ).hasMatch(word),
          );
    }
    return true;
  }
}
