import '../entities/tool_call_info.dart';
import 'coding_command_output_issue_detector.dart';
import 'command_verification_reconciliation.dart';
import 'tool_call_execution_policy.dart';

/// Shares the completion gate's settled command scopes with recovery prompts.
abstract final class ReconciledCommandFailure {
  static const _execution = ToolCallExecutionPolicy();

  static List<ToolResultInfo> current(List<ToolResultInfo> results) =>
      CommandVerificationReconciliation.currentResults(results);

  static bool failed(ToolResultInfo result) =>
      _execution.isCommandExecutionTool(result.name) &&
      (_execution.toolResultHasFailedExit(result) ||
          (result.outcome?.effectiveTestFailedCount ?? 0) > 0 ||
          (result.outcome?.diagnosticErrorCount ?? 0) > 0 ||
          const CodingCommandOutputIssueDetector().detect(result) != null);

  static bool any(List<ToolResultInfo> results) => current(results).any(failed);
}
