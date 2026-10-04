import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/tool_call_info.dart';
import 'file_mutation_evidence_policy.dart';
import 'inline_python_verification_contract.dart';
import 'literal_environment_inspection_policy.dart';
import 'masked_inspection_command_policy.dart';
import 'pytest_verification_identity.dart';
import 'shell_exit_status_report.dart';
import 'verification_command_sequence.dart';
import 'verification_scope.dart';

/// Settles earlier invocations only after the same verification actually passes.
abstract final class CommandVerificationReconciliation {
  static List<ToolResultInfo> currentResults(List<ToolResultInfo> results) {
    final staleBackgroundResults = staleBackgroundResultIds(results);
    final successfulScopes = <String>{};
    final successfulInlineContracts = <InlinePythonVerificationContract>[];
    final supersededIds = <String>{};
    for (var index = results.length - 1; index >= 0; index--) {
      final result = results[index];
      final scope = scopeOf(result);
      if (scope == null) continue;
      final inline = scope.inlineContract;
      if (successfulScopes.contains(scope.key) ||
          (inline != null &&
              successfulInlineContracts.any(
                (passed) => passed.covers(inline),
              ))) {
        supersededIds.add(result.id);
      }
      if (scope.passed && !staleBackgroundResults.contains(result.id)) {
        successfulScopes.addAll([scope.key, ...scope.coveredKeys]);
        if (inline != null) successfulInlineContracts.add(inline);
      }
    }
    if (supersededIds.isEmpty) return results;
    final current = <ToolResultInfo>[];
    for (var resultIndex = 0; resultIndex < results.length; resultIndex++) {
      final result = results[resultIndex];
      if (supersededIds.contains(result.id)) continue;
      if (result.name != 'coding_output_feedback') {
        current.add(result);
        continue;
      }
      final decoded = _decode(result.result);
      final issues = decoded?['issues'];
      final diagnostics = decoded?['diagnostics'];
      if (issues is! List ||
          diagnostics is! List ||
          issues.length != diagnostics.length) {
        current.add(result);
        continue;
      }
      final retained = <int>[];
      for (var index = 0; index < issues.length; index++) {
        final issue = issues[index];
        final sourceId = issue is Map ? issue['tool_call_id'] : null;
        final sourceIndex = sourceId == null && issue is Map
            ? results
                  .take(resultIndex)
                  .toList()
                  .lastIndexWhere(
                    (source) =>
                        source.name == issue['tool_name'] &&
                        (_decode(source.result)?['command'] ??
                                source.arguments['command']) ==
                            issue['command'] &&
                        (_decode(source.result)?['working_directory'] ??
                                source.arguments['working_directory']) ==
                            issue['working_directory'],
                  )
            : -1;
        final settled = sourceId is String
            ? supersededIds.contains(sourceId)
            : sourceIndex >= 0 &&
                  supersededIds.contains(results[sourceIndex].id);
        if (!settled) retained.add(index);
      }
      if (retained.length == issues.length) {
        current.add(result);
      } else if (retained.isNotEmpty) {
        current.add(
          ToolResultInfo(
            id: result.id,
            name: result.name,
            arguments: result.arguments,
            result: jsonEncode({
              ...decoded!,
              'issues': [for (final index in retained) issues[index]],
              'diagnostics': [for (final index in retained) diagnostics[index]],
            }),
          ),
        );
      }
    }
    return current;
  }

  static VerificationScope? scopeOf(ToolResultInfo result) =>
      VerificationScope.of(
        result,
        _decode(result.result),
        isVerification: isVerification,
      );

  /// A terminal poll is dated by its dispatch, not by when it was observed.
  static Set<String> staleBackgroundResultIds(List<ToolResultInfo> results) {
    final starts = <String, int>{};
    var latestMutation = -1;
    const mutations = FileMutationEvidencePolicy();
    for (var index = 0; index < results.length; index++) {
      final result = results[index];
      final payload = _decode(result.result);
      if (mutations.isMutationToolName(result.name) &&
          mutations.isSuccessfulResult(result) &&
          result.outcome?.effectiveFileChanged != false &&
          payload?['ok'] != false &&
          (result.outcome?.effectiveFileChanged == true ||
              mutations.pathForResult(result) != null)) {
        latestMutation = index;
      }
      if (result.name == 'process_start') {
        final job = payload?['job_id']?.toString();
        if (job != null && job.isNotEmpty) starts[job] = index;
      }
    }
    if (latestMutation < 0) return const {};
    return {
      for (final result in results)
        if (const {'process_status', 'process_wait'}.contains(result.name) &&
            (starts[(_decode(result.result)?['job_id'] ??
                            result.arguments['job_id'])
                        ?.toString()] ??
                    -1) <=
                latestMutation)
          result.id,
    };
  }

  static bool isVerification(ToolResultInfo result) {
    final name = result.name.trim().toLowerCase();
    if (const {
      'local_execute_command',
      'process_start',
      'process_status',
      'process_wait',
    }.contains(name)) {
      final decoded = _decode(result.result);
      final command = _verificationCommand(result, decoded);
      if (LiteralEnvironmentInspectionPolicy.applies(command) ||
          MaskedInspectionCommandPolicy.applies(command)) {
        return false;
      }
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

  static bool hasFailedFeedback(List<ToolResultInfo> results, int afterIndex) =>
      results.skip(afterIndex + 1).any((result) {
        if (result.name.trim().toLowerCase() != 'coding_output_feedback') {
          return false;
        }
        final decoded = _decode(result.result);
        return decoded?['success'] == false ||
            decoded?['validation_status']?.toString().trim().toLowerCase() ==
                'failed';
      });

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
