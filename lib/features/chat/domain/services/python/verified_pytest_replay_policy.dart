import 'dart:convert';

import '../../entities/mcp_tool_entity.dart';
import '../../entities/tool_call_info.dart';
import '../coding/coding_command_output_issue_detector.dart';
import '../duplicate_tool_result_reuse_payload.dart';
import '../executed_verifier_replay_policy.dart';
import 'pytest_replay_state_policy.dart';
import 'pytest_verification_identity.dart';

/// Reuses a later passing verifier when a turn returns to its failed runner.
/// Changed state, a later failure, and unknown command syntax prevent reuse.
abstract final class VerifiedPytestReplayPolicy {
  static McpToolResult? reuse({
    required ToolCallInfo call,
    required List<ToolResultInfo> results,
    required List<ToolCallInfo> pendingCalls,
    required String? projectRoot,
  }) {
    if (call.name != 'local_execute_command' ||
        call.arguments['background'] == true) {
      return null;
    }
    final requested = PytestVerificationIdentity.parse(
      call.arguments['command']?.toString() ?? '',
      call.arguments['working_directory']?.toString() ?? projectRoot ?? '',
    );
    if (requested == null ||
        pendingCalls.any(
          (pending) =>
              pending.id != call.id &&
              PytestReplayStatePolicy.mayChange(pending, projectRoot),
        )) {
      return null;
    }
    for (var index = results.length - 1; index >= 0; index--) {
      final result = results[index];
      final outcome = result.outcome;
      if (outcome?.fileMutations.any((change) => change.changed == true) ==
              true ||
          (outcome?.processState != null && !outcome!.isProcessTerminal)) {
        return null;
      }
      final identity = _identity(result, projectRoot);
      if (identity?.key != requested.key) {
        if (PytestReplayStatePolicy.mayChange(_call(result), projectRoot)) {
          return null;
        }
        continue;
      }
      if (_failed(result)) return null;
      if (result.arguments['background'] == true) return null;
      final verified = ExecutedVerifierReplayPolicy.prepare(
        ToolCallInfo(
          id: result.id,
          name: result.name,
          arguments: {
            ...result.arguments,
            'working_directory': identity!.directory,
          },
        ),
        McpToolResult(
          toolName: result.name,
          result: result.result,
          outcome: result.outcome,
          isSuccess: true,
        ),
      );
      if (verified == null) return null;
      if (identity.words.first == requested.words.first) continue;
      final priorFailure = results.take(index).toList().lastIndexWhere((prior) {
        final previous = _identity(prior, projectRoot);
        return previous?.key == requested.key &&
            previous!.words.first == requested.words.first &&
            _failed(prior);
      });
      if (priorFailure < 0 ||
          results
              .skip(priorFailure + 1)
              .take(index - priorFailure - 1)
              .any(
                (between) =>
                    PytestReplayStatePolicy.mayChange(
                      _call(between),
                      projectRoot,
                    ) ||
                    between.outcome?.fileMutations.any(
                          (change) => change.changed == true,
                        ) ==
                        true,
              ) ||
          _changedReadsAfter(index, results)) {
        return null;
      }
      final reused =
          jsonDecode(
                DuplicateToolResultReusePayload().build(
                  result,
                  currentToolCallId: call.id,
                ),
              )
              as Map<String, dynamic>;
      return McpToolResult(
        toolName: call.name,
        isSuccess: true,
        outcome: result.outcome,
        result: jsonEncode({
          ...reused,
          'code': 'verified_pytest_result_reused',
          'requested_command': call.arguments['command'],
          'instruction':
              'This runner previously failed and the same checks '
              'subsequently passed with the captured runner. No state change '
              'was observed. Reuse this verification result; the requested '
              'command was not executed again.',
        }),
      );
    }
    return null;
  }

  static bool _changedReadsAfter(
    int verifiedIndex,
    List<ToolResultInfo> results,
  ) {
    final hashes = <String, String>{};
    for (var index = 0; index < results.length; index++) {
      final result = results[index];
      final read = result.outcome?.readOutcome;
      if (result.name == 'read_file' && read == null && index > verifiedIndex) {
        return true;
      }
      if (read == null) continue;
      if (index > verifiedIndex &&
          hashes.containsKey(read.path) &&
          hashes[read.path] != read.contentHash) {
        return true;
      }
      hashes[read.path] = read.contentHash;
    }
    return false;
  }

  static bool _failed(ToolResultInfo result) =>
      result.outcome?.hasFailingExitCode == true ||
      (result.outcome?.effectiveTestFailedCount ?? 0) > 0 ||
      const CodingCommandOutputIssueDetector().detect(result) != null;

  static ToolCallInfo _call(ToolResultInfo result) => ToolCallInfo(
    id: result.id,
    name: result.name,
    arguments: result.arguments,
  );

  static PytestVerificationIdentity? _identity(
    ToolResultInfo result,
    String? root,
  ) {
    if (result.name != 'local_execute_command') return null;
    try {
      final decoded = jsonDecode(result.result);
      if (decoded is! Map) return null;
      return PytestVerificationIdentity.parse(
        (decoded['command'] ?? result.arguments['command'])?.toString() ?? '',
        (decoded['working_directory'] ?? result.arguments['working_directory'])
                ?.toString() ??
            root ??
            '',
      );
    } on FormatException {
      return null;
    }
  }
}
