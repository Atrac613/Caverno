import '../../entities/tool_call_info.dart';
import '../tool_call_execution_policy.dart';
import '../verification/reconciled_command_failure.dart';
import '../verification/verification_metadata_query_policy.dart';

/// Keeps completed progress intact while requesting the next executable action.
final class CodingContinuationRecoveryPromptBuilder {
  const CodingContinuationRecoveryPromptBuilder();

  static const _executionPolicy = ToolCallExecutionPolicy();

  String build({
    required String responsePreview,
    required String lead,
    required String recoveryCode,
    List<ToolResultInfo> executedToolResults = const [],
  }) {
    if (recoveryCode == 'unexecuted_delegation') {
      return [
        lead,
        'Do not claim the task was delegated without a successful tool result.',
        'Previous response: $responsePreview',
      ].join('\n');
    }
    final progressNotice = partialProgressNotice(executedToolResults);
    if (progressNotice != null) {
      return [
        lead,
        progressNotice,
        'Do not restart the task. Reuse settled verification unless later changes require a fresh run.',
        'Use the available tools now to investigate and resolve only the unresolved failure above, then report the final status.',
        'Do not restate the plan and do not answer with future-tense prose.',
        'Previous response: $responsePreview',
      ].join('\n');
    }
    return [
      lead,
      'Treat that response as unexecuted.',
      'Use the available tools now to perform the next concrete coding step.',
      'Prefer read_file, list_directory, or search_files before editing when the target file has not been inspected.',
      'Do not restate the plan and do not answer with future-tense prose.',
      'Previous response: $responsePreview',
    ].join('\n');
  }

  String? partialProgressNotice(List<ToolResultInfo> executedToolResults) {
    if (executedToolResults.isEmpty) {
      return null;
    }
    final current = ReconciledCommandFailure.current(executedToolResults)
        .where((result) => !VerificationMetadataQueryPolicy.appliesTo(result))
        .toList();
    final hasTimeout = current.any(_executionPolicy.toolResultTimedOut);
    final hasFailedExit = current.any(_executionPolicy.toolResultHasFailedExit);
    final hasOtherFailure = current.any(ReconciledCommandFailure.failed);
    if (!hasTimeout && !hasOtherFailure) {
      return null;
    }
    final problems = <String>[
      if (hasTimeout) 'a command timed out before completing',
      if (hasFailedExit) 'a command exited with a non-zero status',
      if (hasOtherFailure && !hasFailedExit)
        'a command reported verification failures',
    ];
    final progressClause =
        executedToolResults.any(_executionPolicy.toolResultHasSuccessfulExit)
        ? 'Some commands in this turn already completed successfully, but '
        : 'In this turn, ';
    return '$progressClause${problems.join(' and ')}.';
  }
}
