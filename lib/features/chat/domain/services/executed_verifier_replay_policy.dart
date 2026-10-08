import 'dart:convert';

import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'coding_command_output_issue_detector.dart';
import 'python/pytest_verification_identity.dart';

/// Captures the actual foreground verifier, removing only recognized wrappers.
abstract final class ExecutedVerifierReplayPolicy {
  static ToolCallInfo? prepare(ToolCallInfo call, McpToolResult result) {
    if (call.name != 'local_execute_command' ||
        call.arguments['background'] == true) {
      return call;
    }
    Map<String, dynamic>? decoded;
    try {
      final value = jsonDecode(result.result);
      if (value is Map<String, dynamic>) decoded = value;
    } on FormatException {
      return call;
    }
    final identity = PytestVerificationIdentity.parse(
      (decoded?['command'] ?? call.arguments['command'])?.toString() ?? '',
      (decoded?['working_directory'] ?? call.arguments['working_directory'])
              ?.toString() ??
          '',
    );
    if (identity == null) return call;
    if (!result.isSuccess || result.outcome?.hasFailingExitCode == true) {
      return null;
    }
    final counts =
        result.outcome?.testOutcome ??
        identity.counts(decoded?['stdout']?.toString() ?? '');
    final evidence = ToolResultInfo(
      id: call.id,
      name: call.name,
      arguments: call.arguments,
      result: result.result,
      outcome: result.outcome,
    );
    if (result.outcome?.hasSucceedingExitCode != true ||
        decoded?['timed_out'] == true ||
        (result.outcome?.processState != null &&
            !result.outcome!.isProcessTerminal) ||
        (result.outcome?.diagnosticErrorCount ?? 0) > 0 ||
        counts == null ||
        counts.passedCount == 0 ||
        counts.failedCount > 0 ||
        const CodingCommandOutputIssueDetector().detect(evidence) != null) {
      return null;
    }
    return ToolCallInfo(
      id: call.id,
      name: call.name,
      arguments: {
        ...call.arguments,
        'command': identity.replayCommand,
        'working_directory': identity.directory,
      },
    );
  }
}
