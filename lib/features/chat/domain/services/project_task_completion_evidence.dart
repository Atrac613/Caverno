import '../entities/tool_call_info.dart';
import 'tool_result_prompt_builder.dart';

/// Mechanical prerequisites for the implementation stage of a project task.
final class ProjectTaskCompletionEvidence {
  const ProjectTaskCompletionEvidence();

  List<String> gaps({
    required List<ToolResultInfo> toolResults,
    required ToolResultCompletionEvidence evidence,
  }) {
    final lastChange = toolResults.lastIndexWhere(
      (result) =>
          result.outcome?.fileMutations.any(
            (change) => change.changed == true,
          ) ==
          true,
    );
    final verified =
        lastChange >= 0 &&
        evidence.hasSuccessfulExecutionVerification &&
        toolResults.skip(lastChange + 1).any((result) {
          if (!const {
            'local_execute_command',
            'run_tests',
            'run_python_script',
            'process_status',
            'process_wait',
          }.contains(result.name)) {
            return false;
          }
          final outcome = result.outcome;
          return outcome?.hasSucceedingExitCode == true &&
              (outcome!.effectiveTestFailedCount ?? 0) == 0 &&
              (outcome.diagnosticErrorCount ?? 0) == 0 &&
              (outcome.processState == null || outcome.isProcessTerminal);
        });
    return [
      if (lastChange < 0)
        'The project task has no captured file-change evidence in this turn.',
      if (!verified)
        'The project task needs successful execution verification after its latest change.',
    ];
  }
}
