import '../entities/tool_call_info.dart';
import 'goal_update_ack.dart';
import 'tool_definition_search_service.dart';

/// Reopens project work before a failed check is reduced to a status report.
abstract final class ProjectVerificationRepairPolicy {
  static const recoveryCode = 'project_verification_repair';
  static const _projectTools = {
    'update_goal',
    'read_file',
    'list_directory',
    'search_files',
    'write_file',
    'edit_file',
    'local_execute_command',
    'run_tests',
  };

  static List<Map<String, dynamic>> tools(
    List<Map<String, dynamic>> available,
  ) => available
      .where(
        (tool) => _projectTools.contains(
          ToolDefinitionSearchService.toolNameFromDefinition(tool),
        ),
      )
      .toList(growable: false);

  static bool accepts(
    List<ToolCallInfo> calls,
    List<Map<String, dynamic>> offered,
  ) {
    final names = offered
        .map(ToolDefinitionSearchService.toolNameFromDefinition)
        .toSet();
    return calls.isNotEmpty &&
        calls.every((call) {
          if (!names.contains(call.name)) return false;
          if (call.name != 'update_goal') return true;
          final input = GoalUpdateInput.fromArguments(call.arguments);
          // The failed check is still open at this request boundary. A new
          // completion report follows the repair's captured verification.
          return input.isValid && !input.completed;
        });
  }

  static const prompt =
      'A captured project verification failed. Use the available project '
      'tools now to diagnose and repair task-related code before ending the '
      'turn. Read capturedEvidence.unresolvedVerification for the exact '
      'command, working directory and failure output. Inspect the failing '
      'code and request destination, establish the cause from evidence, '
      'apply an authorized repair, then rerun the same failed verification '
      'chain including its prerequisite checks. Repeating unchanged failed '
      'commands or passing unrelated tests does not resolve the failure. '
      'Do not drop or weaken checks, suppress errors or mask the failing '
      'process exit status. Preserve user settings, credentials and product '
      'choices; do not invent replacements. A DNS or HTTP error alone does '
      'not prove that a placeholder setting caused it. Inspect the request '
      'construction and captured response before claiming an external '
      'blocker. Use existing tool approval and project containment rules. '
      'If further work requires unavailable credentials, an external service '
      'change or a user decision, call update_goal with completed: false '
      'and blocked_reason naming the observed failure, diagnosis performed '
      'and required external action. Completion still requires successful '
      'verification and a new accepted status report. For an intermediate '
      'subtask, never complete the parent goal; end a verified subtask with '
      'PROJECT_TASK_SUBTASK_DONE. Keep the visible response in the '
      'conversation language.';
}
