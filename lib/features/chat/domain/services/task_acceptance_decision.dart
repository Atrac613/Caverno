import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/subagent_task.dart';
import '../entities/worktree_agent_task.dart';
import 'conversation_task_precondition_refs.dart';
import 'delegated_premise_audit.dart';
import 'task_acceptance_audit.dart';
import 'task_acceptance_payloads.dart';
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
    List<WorktreeAgentTask> worktreeChildren = const <WorktreeAgentTask>[],
  }) {
    McpToolResult refuse(String code, Map<String, Object?> detail) =>
        const TaskAcceptancePayloads().refusal(toolName, code, detail);

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
    // both delegation routes record the binding: without it there is no way to
    // tell which result is the one being accepted.
    final children = childrenForConversation
        .where((candidate) => candidate.workflowTaskId == trimmedTaskId)
        .toList(growable: false);
    final worktrees = worktreeChildren
        .where((candidate) => candidate.workflowTaskId == trimmedTaskId)
        .toList(growable: false);
    if (children.isEmpty && worktrees.isEmpty) {
      return TaskAcceptanceRefusal(
        refuse('acceptance_no_delegated_result', {
          'required_action':
              'Delegate this task and verify the result before accepting it. '
              'There is nothing recorded to accept on.',
        }),
      );
    }

    // A branch still in flight is answered as "wait", not as "verify what is
    // outstanding". Measured across four live runs: the parent accepted early,
    // read a list of outstanding levels that a running child cannot yet satisfy,
    // and delegated again instead of polling. The levels were true and told it
    // the wrong thing to do.
    final running = worktrees
        .where((candidate) => !candidate.isTerminal)
        .lastOrNull;
    if (running != null) {
      return TaskAcceptanceRefusal(
        refuse('acceptance_child_still_running', {
          'task_id': running.id,
          'branch_name': running.branchName,
          'required_action':
              'The branch is still running. Poll get_subagent_result with that '
              'task_id until it is done, then judge what it reports.',
        }),
      );
    }

    // ANA2's contradiction policy, arriving at the moment it decides something.
    // The premises are read from the plan rather than from the child: a task is
    // only delegated once ready, and readiness confirms every assumption edge,
    // so an edge that no longer resolves to a confirmed item is one the user has
    // since declined. Barred rather than cancelled -- the work stands, its
    // promotion past `produced` does not.
    final lapsed = const DelegatedPremiseAudit().lapsed(
      conversation,
      const ConversationTaskPreconditionRefs().declaredAssumptionPremises(
        spec,
        task,
      ),
    );
    if (lapsed.isNotEmpty) {
      return TaskAcceptanceRefusal(
        refuse('acceptance_premise_lapsed', {
          'lapsed_premises': lapsed,
          'required_action':
              'This result rests on an assumption that is no longer confirmed. '
              'Ask the user to settle it before accepting the work.',
        }),
      );
    }

    // A worktree result outranks a subagent one for the same task, because it is
    // the only kind that can pass a level: it carries the verification outcome
    // and the changed files, where a subagent child leaves both inapplicable and
    // the acceptance rests on the parent's word alone.
    const audit = TaskAcceptanceAudit();
    final verdict = worktrees.isNotEmpty
        ? audit.auditWorktreeResult(worktrees.last)
        : audit.auditSubagentResult(children.last);
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
    final worktree = worktrees.isNotEmpty ? worktrees.last : null;
    return TaskAcceptanceContract(
      task: task,
      evidence: <String>[
        if (progress?.lastValidationCommand.trim().isNotEmpty ?? false)
          progress!.lastValidationCommand.trim(),
        // Named rather than counted: an acceptance's evidence line is what the
        // next turn reads instead of redoing the work, so it says which branch
        // and which command, not merely that something was recorded.
        if (worktree != null) ...[
          'worktree branch ${worktree.branchName}',
          if (worktree.verifiedGreen &&
              worktree.verificationCommand.trim().isNotEmpty)
            'verified green: ${worktree.verificationCommand.trim()}',
          if (worktree.changedFiles.isNotEmpty)
            '${worktree.changedFiles.length} changed file(s) recorded',
        ] else if (children.last.resultSummary.trim().isNotEmpty)
          'child summary recorded',
      ],
      premises: const TaskDelegationBriefBuilder().premisesFor(spec, task),
    );
  }

  McpToolResult writeFailed(String toolName) =>
      const TaskAcceptancePayloads().writeFailed(toolName);

  McpToolResult accepted(String toolName, TaskAcceptanceContract contract) =>
      const TaskAcceptancePayloads().accepted(toolName, contract);
}
