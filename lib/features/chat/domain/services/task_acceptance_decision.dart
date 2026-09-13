import 'dart:convert';

import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/subagent_task.dart';
import 'task_acceptance_audit.dart';
import 'task_delegation_brief_builder.dart';

/// What an acceptance attempt is allowed to do.
sealed class TaskAcceptanceDecision {
  const TaskAcceptanceDecision();
}

/// The attempt is refused, and [result] is what the parent is told.
final class TaskAcceptanceRefusal extends TaskAcceptanceDecision {
  const TaskAcceptanceRefusal(this.result);

  final McpToolResult result;
}

/// The attempt may be written, with exactly this evidence and these premises.
final class TaskAcceptanceContract extends TaskAcceptanceDecision {
  const TaskAcceptanceContract({
    required this.task,
    required this.evidence,
    required this.premises,
  });

  final ConversationWorkflowTask task;
  final List<String> evidence;
  final List<String> premises;
}

/// Decides whether the parent may record an acceptance, and on what.
///
/// Extracted from the notifier so the decision is testable without a turn, and
/// because the notifier library it lived in sits at its size ceiling. The write
/// stays behind: it needs the conversation notifier, and this stays a function
/// of what it is told.
///
/// The order of the grounds is deliberate and is behaviour, not style: a
/// non-parent is refused before anything about the plan is revealed, an unknown
/// id is answered with the ids that exist, and the audit runs last because it is
/// the only ground that depends on what a child actually did.
class TaskAcceptanceDecisionService {
  const TaskAcceptanceDecisionService();

  TaskAcceptanceDecision decide({
    required String toolName,
    required bool isParentTurn,
    required Conversation? conversation,
    required String taskId,
    required String rationale,
    required List<SubagentTask> childrenForConversation,
  }) {
    McpToolResult refuse(String code, Map<String, Object?> detail) =>
        McpToolResult(
          toolName: toolName,
          isSuccess: false,
          result: jsonEncode({
            'ok': false,
            'code': code,
            'result_origin': 'refusal',
            ...detail,
          }),
        );

    // A producer must not grade its own work. The child catalog already omits
    // this tool; this is the same rule at dispatch, for a model that
    // rediscovers the name through tool search.
    if (!isParentTurn) {
      return TaskAcceptanceRefusal(
        refuse('acceptance_not_parent', {
          'required_action':
              'Only Anabasis accepts a result. Report what you produced and '
              'let the parent judge it.',
        }),
      );
    }

    // Trimmed here rather than trusted: the notifier already trims, and a
    // service that depends on its caller having done so is one wrong call site
    // away from accepting a blank reason as a reason.
    final trimmedTaskId = taskId.trim();
    final trimmedRationale = rationale.trim();
    final spec = conversation?.effectiveWorkflowSpec;
    final task = spec?.tasks
        .where((candidate) => candidate.id == trimmedTaskId)
        .firstOrNull;
    if (conversation == null || spec == null || task == null) {
      return TaskAcceptanceRefusal(
        refuse('acceptance_unknown_task', {
          'known_task_ids': spec == null
              ? const <String>[]
              : spec.tasks.map((candidate) => candidate.id).toList(),
          'required_action':
              'Pass an exact workflow_task_id from the saved plan.',
        }),
      );
    }
    if (trimmedRationale.isEmpty) {
      return TaskAcceptanceRefusal(
        refuse('acceptance_rationale_missing', {
          'required_action':
              'Say why this satisfies the goal. An acceptance without a reason '
              'records nothing the next turn can act on.',
        }),
      );
    }

    // Audited against the child that was admitted for this task, which is why
    // the delegation gate records the binding: without it there is no way to
    // tell which result is the one being accepted.
    final children = childrenForConversation
        .where((candidate) => candidate.workflowTaskId == trimmedTaskId)
        .toList(growable: false);
    if (children.isEmpty) {
      return TaskAcceptanceRefusal(
        refuse('acceptance_no_delegated_result', {
          'required_action':
              'Delegate this task and verify the result before accepting it. '
              'There is nothing recorded to accept on.',
        }),
      );
    }

    // Subagent results only, and deliberately so for now: ANA2 PR 2's worktree
    // mapping is not dispatched yet, so no WorktreeAgentTask exists to audit.
    // `auditWorktreeResult` is the other half and is already written -- when
    // worktree delegation is wired, this is the line that has to choose between
    // them, or a worktree child's result refuses as
    // `acceptance_no_delegated_result` despite being the more evidenced kind.
    const audit = TaskAcceptanceAudit();
    final verdict = audit.auditSubagentResult(children.last);
    if (!audit.mayParentAccept(verdict)) {
      return TaskAcceptanceRefusal(
        refuse('acceptance_levels_outstanding', {
          'outstanding': verdict.outstanding
              .map((level) => level.name)
              .toList(growable: false),
          'required_action':
              'Verify what is outstanding before accepting. A rationale cannot '
              'stand in for a check that did not run.',
        }),
      );
    }

    final progress = conversation.executionProgressForTask(task.id);
    return TaskAcceptanceContract(
      task: task,
      evidence: <String>[
        if (progress?.lastValidationCommand.trim().isNotEmpty ?? false)
          progress!.lastValidationCommand.trim(),
        if (children.last.resultSummary.trim().isNotEmpty)
          'child summary recorded',
      ],
      premises: const TaskDelegationBriefBuilder().premisesFor(spec, task),
    );
  }

  McpToolResult writeFailed(String toolName) => McpToolResult(
    toolName: toolName,
    isSuccess: false,
    result: jsonEncode({
      'ok': false,
      'code': 'acceptance_write_failed',
      'result_origin': 'refusal',
      'required_action': 'The conversation could not be updated; retry once.',
    }),
  );

  McpToolResult accepted(String toolName, TaskAcceptanceContract contract) =>
      McpToolResult(
        toolName: toolName,
        isSuccess: true,
        result: jsonEncode({
          'ok': true,
          'accepted_task_id': contract.task.id,
          'evidence': contract.evidence,
          'premises': contract.premises,
        }),
      );
}
