import 'dart:convert';

import 'package:path/path.dart' as path;

import '../../entities/tool_call_info.dart';
import '../command_verification_reconciliation.dart';
import '../literal_shell_words.dart';
import '../verification_command_sequence.dart';
import 'pytest_verification_identity.dart';

/// Suggests a fresh full-chain execution; never fabricates a successful result.
abstract final class CompoundPythonRuntimeRepair {
  static String? suggest(ToolResultInfo failed, List<ToolResultInfo> results) {
    if (CommandVerificationReconciliation.scopeOf(
          failed,
        )?.runtimeLaunchFailed !=
        true) {
      return null;
    }
    final original = _payload(failed);
    final recordedDirectory =
        (original?['working_directory'] ??
                failed.arguments['working_directory'] ??
                '')
            .toString();
    final sequence = VerificationCommandSequence.parse(
      (original?['command'] ?? failed.arguments['command'] ?? '').toString(),
      recordedDirectory,
    );
    if (sequence?.runtimeRepairKey == null) return null;
    for (final result in results.reversed) {
      if (CommandVerificationReconciliation.scopeOf(result)?.passed != true) {
        continue;
      }
      final payload = _payload(result);
      final command = (payload?['command'] ?? result.arguments['command'] ?? '')
          .toString();
      final directory =
          (payload?['working_directory'] ??
                  result.arguments['working_directory'] ??
                  '')
              .toString();
      final runner =
          PytestVerificationIdentity.parse(command, directory) ??
          VerificationCommandSequence.parse(command, directory)?.leadingPytest;
      if (runner?.verificationKey != sequence!.leadingPytest!.verificationKey) {
        continue;
      }
      final interpreter = runner!.words.first;
      if (interpreter == 'pytest' ||
          LiteralShellWords.parse(interpreter) == null) {
        continue;
      }
      final repaired = sequence.repairRuntimeWith(interpreter);
      return sequence.directory == path.normalize(recordedDirectory)
          ? repaired
          : 'cd ${LiteralShellWords.quote(sequence.directory)} && $repaired';
    }
    return null;
  }

  static Map? _payload(ToolResultInfo result) {
    try {
      final value = jsonDecode(result.result);
      return value is Map ? value : null;
    } on FormatException {
      return null;
    }
  }
}
