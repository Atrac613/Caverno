import '../entities/tool_call_info.dart';
import 'tool_definition_search_service.dart';

/// Reopens project work before a failed check is reduced to a status report.
abstract final class ProjectVerificationRepairPolicy {
  static const recoveryCode = 'project_verification_repair';
  static const _projectTools = {
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
    // Status is deliberately absent at this first diagnosis boundary. Once
    // a project tool returns, the normal loop can record a concrete blocker.
    return calls.isNotEmpty &&
        calls.every(
          (call) => call.name != 'update_goal' && names.contains(call.name),
        );
  }

  static Map<String, dynamic> violation(
    List<ToolCallInfo> calls,
    List<Map<String, dynamic>> offered,
  ) => {
    'code': 'project_verification_repair_protocol_violation',
    'executed': false,
    'allowed_tools': [
      for (final tool in offered)
        ToolDefinitionSearchService.toolNameFromDefinition(tool),
    ],
    'returned_tools': calls.map((call) => call.name).toList(),
    'required_action':
        'Use an offered project tool to diagnose, repair or request the '
        'required execution approval. No status call has run. Report a '
        'concrete blocker after the diagnostic or execution result returns.',
  };

  static const prompt =
      'A captured project verification failed. Use the available project '
      'tools now to diagnose and repair task-related code before ending the '
      'turn. Your first response must call an offered project tool; '
      'update_goal is unavailable at this diagnosis boundary. '
      'Read capturedEvidence.unresolvedVerification for the exact '
      'command, working directory and failure output. If runtimeRepairCommand '
      'is provided, request that full command through the normal execution '
      'gate; it changes only the unavailable Python runtime and preserves '
      'the original verification program. Do not rewrite imports, fixtures '
      'or checks while fixing runtime availability. Inspect the failing '
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
      'Inspect executionBoundary on the captured executions. When network '
      'is denied by macos_workspace_sandbox, a DNS error does not prove '
      'the host or remote service is unavailable. If this task requires '
      'live network verification, request local_execute_command with '
      'execution_scope: host for that verification through the existing '
      'fresh approval gate. Do not bypass approval or automatically rerun '
      'on the host. Preserve the underlying verification and process exit '
      'status; remove output-only wrappers that mask failures. After the '
      'diagnostic or approved execution result returns, the normal tool '
      'loop may report a concrete blocker with update_goal. '
      'If further work requires unavailable credentials, an external service '
      'change or a user decision, call update_goal with completed: false '
      'and blocked_reason naming the observed failure, diagnosis performed '
      'and required external action. Completion still requires successful '
      'verification and a new accepted status report. For an intermediate '
      'subtask, never complete the parent goal; end a verified subtask with '
      'PROJECT_TASK_SUBTASK_DONE. Keep the visible response in the '
      'conversation language.';
}
