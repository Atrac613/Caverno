import '../entities/conversation_goal.dart';
import '../entities/tool_call_info.dart';
import 'coding/structured_coding_task_recovery_policy.dart';
import 'project_task_step_completion_policy.dart';
import 'project_task_terminal_status.dart';
import 'project_verification_repair_policy.dart';
import 'status_recovery_verification.dart';
import 'turn_finalization_recovery_plan.dart';

/// Selects tools and prompts after the recovery protocol has been decided.
abstract final class FinalizationRecoveryRequest {
  static const _verification = StatusRecoveryVerification();
  static ({List<Map<String, dynamic>> tools, String? code, String? prompt})
  resolve({
    required bool structuredTask,
    required bool structuredStep,
    required bool verificationRepair,
    required List<Map<String, dynamic>> allTools,
    required List<ToolResultInfo> completedResults,
    required ConversationGoal? goal,
    required bool terminalStatusOnly,
    required FinalizationRecoveryToolSelection selection,
    required ProjectTaskTerminalStatus? stepStatus,
  }) {
    final status = structuredTask && !verificationRepair
        ? _verification.request(
            allTools,
            completedResults,
            goal,
            const StructuredCodingTaskRecoveryPolicy(),
            statusOnly: terminalStatusOnly,
          )
        : null;
    final requestTools = verificationRepair
        ? ProjectVerificationRepairPolicy.tools(allTools)
        : status?.tools ?? selection.tools;
    final forcedCode = verificationRepair
        ? ProjectVerificationRepairPolicy.recoveryCode
        : structuredStep
        ? ProjectTaskStepCompletionPolicy.recoveryCode
        : structuredTask
        ? 'structured_coding_task_status'
        : selection.forcedCode;
    final prompt = verificationRepair
        ? ProjectVerificationRepairPolicy.prompt
        : stepStatus == null
        ? status?.prompt
        : const ProjectTaskStepCompletionPolicy().prompt(stepStatus);
    return (tools: requestTools, code: forcedCode, prompt: prompt);
  }
}
