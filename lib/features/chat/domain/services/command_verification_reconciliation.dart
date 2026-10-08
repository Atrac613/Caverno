import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/tool_call_info.dart';
import 'file_mutation_evidence_policy.dart';
import 'python/inline_python_verification_contract.dart';
import 'reconciled_verification_feedback.dart';
import 'verification_invocation_evidence.dart';
import 'verification_scope.dart';

/// Settles earlier invocations only after the same verification actually passes.
///
/// Output-guardrail feedback on a command that is not a verification -- an
/// environment probe or a dependency install -- stays visible to the model but
/// never blocks: no later pass can settle it, so it would block for the rest of
/// the turn. In session 17398f84 two such issues, from `import pytest` and a
/// `pip install ...; echo "exit=$?"`, kept rejecting a verified subtask and
/// sent the model linting unrelated code for an hour.
abstract final class CommandVerificationReconciliation {
  static List<ToolResultInfo> currentResults(List<ToolResultInfo> results) {
    final staleBackgroundResults = staleBackgroundResultIds(results);
    final successfulScopes = <String>{};
    final successfulInlineContracts = <InlinePythonVerificationContract>[];
    final successfulRuntimeRepairs = <String>{};
    final supersededIds = <String>{};
    for (var index = results.length - 1; index >= 0; index--) {
      final result = results[index];
      final scope = scopeOf(result);
      if (scope == null) continue;
      final inline = scope.inlineContract;
      if (successfulScopes.contains(scope.key) ||
          (scope.projectEnvKey != null &&
              successfulScopes.contains(scope.projectEnvKey)) ||
          (scope.runtimeLaunchFailed &&
              successfulRuntimeRepairs.contains(scope.runtimeRepairKey)) ||
          (inline != null &&
              successfulInlineContracts.any(
                (passed) => passed.covers(inline),
              ))) {
        supersededIds.add(result.id);
      }
      if (scope.passed && !staleBackgroundResults.contains(result.id)) {
        successfulScopes.addAll([scope.key, ...scope.coveredKeys]);
        if (scope.runtimeRepairKey != null) {
          successfulRuntimeRepairs.add(scope.runtimeRepairKey!);
        }
        if (inline != null) successfulInlineContracts.add(inline);
      }
    }
    final advisorySourceIds = {
      for (final result in results)
        if (!isVerification(result)) result.id,
    };
    if (supersededIds.isEmpty &&
        !results.any((result) => result.name == 'coding_output_feedback')) {
      return results;
    }
    return ReconciledVerificationFeedback.filter(
      results,
      supersededIds,
      advisorySourceIds,
    );
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

  static bool isVerification(ToolResultInfo result) =>
      VerificationInvocationEvidence.isVerification(result);

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

  static ToolTestOutcome? testOutcome(ToolResultInfo result) =>
      VerificationInvocationEvidence.testOutcome(result);

  static bool requiresCompoundRunnerCounts(ToolResultInfo result) =>
      VerificationInvocationEvidence.requiresCompoundRunnerCounts(result);

  static Map<String, dynamic>? _decode(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
