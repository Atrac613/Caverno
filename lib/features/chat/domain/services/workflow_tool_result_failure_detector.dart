import '../entities/tool_call_info.dart';
import 'workflow_tool_result_failure_inspection.dart';

export 'workflow_tool_result_failure_inspection.dart'
    show WorkflowToolResultFailureDecision;

final class WorkflowToolResultFailureDetector {
  WorkflowToolResultFailureDetector._();

  static bool containsFailure(List<ToolResultInfo> toolResults) =>
      inspect(toolResults).containsFailure;

  static WorkflowToolResultFailureDecision inspect(
    List<ToolResultInfo> toolResults,
  ) => WorkflowToolResultFailureInspection.inspect(toolResults);
}
