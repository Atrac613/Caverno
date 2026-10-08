import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../entities/tool_call_info.dart';
import '../local_command/literal_environment_inspection_policy.dart';
import '../local_command/masked_inspection_command_policy.dart';
import '../local_command/shell_exit_status_report.dart';
import '../python/literal_python_stdin_verification.dart';
import '../python/pytest_verification_identity.dart';
import 'verification_command_sequence.dart';
import 'verification_metadata_query_policy.dart';

/// Classifies and decodes a verification invocation without settling prior results.
abstract final class VerificationInvocationEvidence {
  static bool isVerification(ToolResultInfo result) {
    final name = result.name.trim().toLowerCase();
    if (const {
      'local_execute_command',
      'process_start',
      'process_status',
      'process_wait',
    }.contains(name)) {
      if ((result.outcome?.effectiveTestFailedCount ?? 0) > 0 ||
          (result.outcome?.diagnosticErrorCount ?? 0) > 0) {
        return true;
      }
      final decoded = _decode(result.result);
      final command = _verificationCommand(result, decoded);
      if (VerificationMetadataQueryPolicy.appliesTo(result) ||
          LiteralEnvironmentInspectionPolicy.applies(command) ||
          MaskedInspectionCommandPolicy.applies(command)) {
        return false;
      }
      if (LiteralPythonStdinVerification.applies(command)) return true;
      final directory =
          (decoded?['working_directory'] ??
                  result.arguments['working_directory'])
              ?.toString() ??
          '';
      if (PytestVerificationIdentity.parse(command, directory) != null ||
          VerificationCommandSequence.parse(command, directory) != null) {
        return true;
      }
      if (ShellExitStatusReport.parse(
            (decoded?['command'] ?? result.arguments['command'])?.toString() ??
                '',
          ) !=
          null) {
        return const ToolCapabilityClassifier()
                .classify(
                  'local_execute_command',
                  arguments: {'command': command},
                )
                .commandEffect ==
            ToolCommandEffect.verification;
      }
      if (name != 'local_execute_command' && command.isNotEmpty) {
        return const ToolCapabilityClassifier()
                .classify(
                  'local_execute_command',
                  arguments: {'command': command},
                )
                .commandEffect ==
            ToolCommandEffect.verification;
      }
    }
    if (name == 'local_execute_command' || name == 'git_execute_command') {
      return const ToolCapabilityClassifier()
              .classify(result.name, arguments: result.arguments)
              .commandEffect ==
          ToolCommandEffect.verification;
    }
    return const {
      'analyze_project',
      'run_tests',
      'process_start',
      'process_wait',
    }.contains(name);
  }

  static ToolTestOutcome? testOutcome(ToolResultInfo result) {
    if (result.outcome?.testOutcome case final ToolTestOutcome outcome) {
      return outcome;
    }
    final decoded = _decode(result.result);
    final command = _verificationCommand(result, decoded);
    final directory =
        (decoded?['working_directory'] ?? result.arguments['working_directory'])
            ?.toString() ??
        '';
    final runner =
        PytestVerificationIdentity.parse(command, directory) ??
        VerificationCommandSequence.parse(command, directory)?.terminalPytest;
    final stdout =
        (decoded?['stdout'] ?? decoded?['stdout_tail'])?.toString() ?? '';
    final report = ShellExitStatusReport.parse(
      (decoded?['command'] ?? result.arguments['command'])?.toString() ?? '',
    );
    return runner?.counts(report?.commandOutput(stdout) ?? stdout);
  }

  static bool requiresCompoundRunnerCounts(ToolResultInfo result) {
    final decoded = _decode(result.result);
    return VerificationCommandSequence.parse(
          _verificationCommand(result, decoded),
          (decoded?['working_directory'] ??
                      result.arguments['working_directory'])
                  ?.toString() ??
              '',
        )?.terminalPytest !=
        null;
  }

  static String _verificationCommand(
    ToolResultInfo result,
    Map<String, dynamic>? decoded,
  ) {
    final command =
        (decoded?['command'] ?? result.arguments['command'])?.toString() ?? '';
    return ShellExitStatusReport.parse(command)?.command ?? command;
  }

  static Map<String, dynamic>? _decode(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
