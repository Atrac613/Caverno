import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'coding_command_output_issue_detector.dart';
import 'file_mutation_evidence_policy.dart';
import 'local_command/shell_exit_status_report.dart';
import 'python/compound_python_runtime_repair.dart';
import 'python/inline_python_verification_contract.dart';
import 'tool_call_execution_policy.dart';
import 'unresolved_verification_failure.dart';

/// Summarizes what a turn changed and ran for a structured status request.
///
/// The status request asks the model to judge completion from "the captured
/// change and execution evidence", but it carries only the tail the read
/// carry keeps. In session 1d76c878 that tail was four file reads: the three
/// test files the turn wrote and its passing `pytest -q` were gone, so the
/// model set out to verify instead of reporting, and the turn ended with no
/// status. The summary states the facts the request depends on, whatever the
/// carry kept.
final class StructuredTaskStatusEvidence {
  const StructuredTaskStatusEvidence();

  static const _mutationPolicy = FileMutationEvidencePolicy();
  static const _executionPolicy = ToolCallExecutionPolicy();
  static const maxListedChanges = 20;
  static const maxCommandChars = 200;
  static const maxOutputTailChars = 600;
  static const maxFailedCommandChars = 12000;

  /// [feedback] with the summary of [results] added as `capturedEvidence`.
  ToolResultInfo attachTo(
    ToolResultInfo feedback,
    List<ToolResultInfo> results,
  ) {
    final summary = summarize(results);
    if (summary == null) return feedback;
    final decoded = jsonDecode(feedback.result);
    if (decoded is! Map<String, dynamic>) return feedback;
    return feedback.withResult(
      jsonEncode({...decoded, 'capturedEvidence': summary}),
    );
  }

  /// A JSON-ready summary, or null when the turn neither changed a file nor
  /// finished a command.
  Map<String, dynamic>? summarize(List<ToolResultInfo> results) {
    final changedPaths = <String>[];
    var latestChangeIndex = -1;
    var latestExecutionIndex = -1;
    for (var index = 0; index < results.length; index++) {
      final result = results[index];
      final paths = _changedPaths(result);
      if (paths.isNotEmpty) {
        latestChangeIndex = index;
        for (final path in paths) {
          changedPaths
            ..remove(path)
            ..add(path);
        }
      } else if (_isVerificationExecution(result)) {
        latestExecutionIndex = index;
      }
    }
    if (changedPaths.isEmpty && latestExecutionIndex < 0) return null;
    const failures = UnresolvedVerificationFailure();
    final unresolvedFailure = failures.describe(results);
    final failedVerification = failures.latest(results);
    return {
      'fileChanges': changedPaths.length <= maxListedChanges
          ? changedPaths
          : changedPaths.sublist(changedPaths.length - maxListedChanges),
      if (latestExecutionIndex >= 0) ...{
        'latestExecution': _describeExecution(results[latestExecutionIndex]),
        'latestExecutionFollowsLatestChange':
            latestExecutionIndex > latestChangeIndex,
      },
      'unresolvedVerificationFailure': ?unresolvedFailure,
      if (failedVerification != null)
        'unresolvedVerification': _describeFailedVerification(
          failedVerification,
          results,
        ),
    };
  }

  List<String> _changedPaths(ToolResultInfo result) {
    if (!_mutationPolicy.isMutationToolName(result.name) ||
        !_mutationPolicy.isSuccessfulResult(result)) {
      return const [];
    }
    final typed = result.outcome?.fileMutations ?? const [];
    if (typed.isNotEmpty) {
      return [
        for (final mutation in typed)
          if (mutation.changed == true) mutation.path,
      ];
    }
    if (result.outcome?.isNoOpMutation == true) return const [];
    final path = _mutationPolicy.pathForResult(result);
    return path == null || path.isEmpty ? const [] : [path];
  }

  /// Commands that reached an exit status, excluding git: `git status` is
  /// inspection, not verification.
  bool _isVerificationExecution(ToolResultInfo result) {
    final name = result.name.trim().toLowerCase();
    if (name == 'git_execute_command' || name == 'process_start') return false;
    return _executionPolicy.toolResultHasSuccessfulExit(result) ||
        _executionPolicy.toolResultHasFailedExit(result);
  }

  Map<String, dynamic> _describeExecution(ToolResultInfo result) {
    final decoded = _executionPolicy.tryDecodeMap(result.result);
    final command =
        decoded?['command']?.toString() ??
        _executionPolicy.toolCommandArgument(result.arguments) ??
        result.name;
    final outputIssue = const CodingCommandOutputIssueDetector().detect(result);
    final report = ShellExitStatusReport.parse(command);
    final reportedExit = report?.exitCode(
      (decoded?['stdout'] ?? decoded?['stdout_tail'])?.toString() ?? '',
    );
    return {
      'tool': result.name,
      'command': _clip(command, maxCommandChars, keepEnd: false),
      'succeeded':
          _executionPolicy.toolResultHasSuccessfulExit(result) &&
          decoded?['timed_out'] != true &&
          (result.outcome?.effectiveTestFailedCount ?? 0) == 0 &&
          (result.outcome?.diagnosticErrorCount ?? 0) == 0 &&
          outputIssue == null &&
          (report == null || reportedExit == 0),
      if (result.outcome?.exitCode != null)
        'exitCode': result.outcome!.exitCode,
      'reportedExitCode': ?reportedExit,
      if (decoded?['execution_boundary'] is Map)
        'executionBoundary': decoded!['execution_boundary'],
      if (outputIssue != null) 'failureReason': outputIssue.summary,
      'outputTail': _clip(_output(result), maxOutputTailChars, keepEnd: true),
    };
  }

  Map<String, dynamic> _describeFailedVerification(
    ToolResultInfo result,
    List<ToolResultInfo> results,
  ) {
    final decoded = _executionPolicy.tryDecodeMap(result.result);
    final command =
        decoded?['command']?.toString() ??
        _executionPolicy.toolCommandArgument(result.arguments) ??
        result.name;
    final directory =
        (decoded?['working_directory'] ?? result.arguments['working_directory'])
            ?.toString() ??
        '';
    return {
      ..._describeExecution(result),
      'toolCallId': result.id,
      // The short gap preview cannot identify or reconstruct a long inline
      // verifier. Keep its literal source beside the latest passing check.
      'command': command.length <= maxFailedCommandChars
          ? command
          : '${command.substring(0, maxFailedCommandChars - 3)}...',
      'commandTruncated': command.length > maxFailedCommandChars,
      'workingDirectory': directory,
      if (CompoundPythonRuntimeRepair.suggest(result, results)
          case final String repair)
        if (repair.length <= maxFailedCommandChars)
          'runtimeRepairCommand': repair,
      'repairableInlineFixture':
          InlinePythonVerificationContract.parse(command, directory) != null,
      if (decoded?['stdout_truncated'] == true ||
          decoded?['stderr_truncated'] == true)
        'outputTruncated': true,
    };
  }

  String _output(ToolResultInfo result) {
    try {
      final decoded = jsonDecode(result.result);
      if (decoded is Map<String, dynamic>) {
        final parts = [
          for (final key in const ['stdout', 'stderr', 'output'])
            if (decoded[key] is String &&
                (decoded[key] as String).trim().isNotEmpty)
              (decoded[key] as String).trim(),
        ];
        if (parts.isNotEmpty) return parts.join('\n');
      }
    } catch (_) {
      // Plain-text results are summarized as they are.
    }
    return result.result.trim();
  }

  String _clip(String text, int limit, {required bool keepEnd}) {
    if (text.length <= limit) return text;
    return keepEnd
        ? '...${text.substring(text.length - limit)}'
        : '${text.substring(0, limit)}...';
  }
}
