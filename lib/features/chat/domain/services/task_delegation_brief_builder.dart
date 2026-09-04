import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';
import 'conversation_contract_provenance_service.dart';
import 'conversation_task_readiness.dart';

/// Where a delegated task should run.
///
/// The two runners differ in **isolation, verification and evidence**, not in
/// capability, and that is what decides the mapping rather than the size of
/// the task:
///
/// * `SubagentTask` returns `resultSummary`, `output` and `error`. It carries
///   no changed-file evidence, no verification result, and no worktree — it
///   runs where the parent runs.
/// * `WorktreeAgentTask` carries `branchName` / `worktreePath`,
///   `verificationCommand` / `verifiedGreen`, and `changedFiles`.
///
/// ANA3's rule is that a child saying "done" means `produced`, never
/// `accepted`, and that only evidence promotes it. A subagent has no evidence
/// to offer, and two subagents editing the same workspace would corrupt each
/// other's work. So work that changes the workspace goes to a worktree.
enum TaskDelegationRunner { subagent, worktree }

/// One ready task, with the premises a child needs in order to do it.
class TaskDelegationBrief {
  const TaskDelegationBrief({
    required this.task,
    required this.premises,
    required this.runner,
  });

  final ConversationWorkflowTask task;

  /// The confirmed assumptions this task depends on, in the plan's own words.
  final List<String> premises;

  final TaskDelegationRunner runner;
}

/// Chooses what may be delegated, and what a child has to be told.
///
/// This answers the design's open question — *how does a child inherit the
/// parent's confirmed assumptions without re-sending the whole contract?* —
/// and it is only answerable because ANA1 added precondition edges.
/// `spawn_subagent`'s child cannot see the conversation, so anything it needs
/// must be in its prompt; without edges there is no basis for choosing which
/// assumptions matter, and the only safe option is all of them, which is the
/// re-send the question was trying to avoid. An edge names exactly the ones
/// this task stands on.
///
/// No execution machinery: this decides *what* may be delegated and *what to
/// say*, never who runs it.
class TaskDelegationBriefBuilder {
  const TaskDelegationBriefBuilder({
    this.readiness = const ConversationTaskReadinessResolver(),
    this.provenance = const ConversationContractProvenanceService(),
  });

  final ConversationTaskReadinessResolver readiness;
  final ConversationContractProvenanceService provenance;

  /// Briefs for every task that could be handed to a child right now.
  ///
  /// A task is a candidate when its preconditions all hold and it is not
  /// already finished or running. Readiness stays derived, so this list is a
  /// view of the graph rather than a queue that could disagree with it.
  List<TaskDelegationBrief> candidates(Conversation conversation) {
    final spec = conversation.effectiveWorkflowSpec;
    return <TaskDelegationBrief>[
      for (final task in spec.tasks)
        if (_isDelegatable(conversation, task))
          TaskDelegationBrief(
            task: task,
            premises: _premisesFor(spec, task),
            runner: runnerFor(task),
          ),
    ];
  }

  /// Which runner [task] belongs to.
  ///
  /// **A worktree is the default, and the asymmetry is why.** Sending changing
  /// work to a subagent by mistake costs isolation and evidence: two children
  /// editing one workspace corrupt each other, and there is nothing for the
  /// parent to accept on. Sending inspection to a worktree by mistake costs
  /// one worktree's overhead. Only one of those two errors is recoverable.
  ///
  /// A task routes to a subagent only when it declares neither a file to change
  /// nor a command to verify — the task's own statement about itself, not a
  /// guess read off its title. Guessing from prose is what the
  /// heuristic-removal track exists to stop.
  TaskDelegationRunner runnerFor(ConversationWorkflowTask task) {
    final touchesFiles = task.targetFiles.any((path) => path.trim().isNotEmpty);
    final verifies = task.validationCommand.trim().isNotEmpty;
    return touchesFiles || verifies
        ? TaskDelegationRunner.worktree
        : TaskDelegationRunner.subagent;
  }

  bool _isDelegatable(
    Conversation conversation,
    ConversationWorkflowTask task,
  ) {
    if (task.title.trim().isEmpty) return false;
    final status =
        conversation.executionProgressForTask(task.id)?.status ?? task.status;
    // `blocked` is excluded for a different reason than the other two: a
    // blocker is a fact someone recorded, and readiness cannot see it.
    if (status != ConversationWorkflowTaskStatus.pending) return false;
    return readiness.resolve(conversation, task).isReady;
  }

  /// The confirmed assumptions [task] declares an edge to.
  ///
  /// Only the confirmed ones: an unconfirmed assumption would still be holding
  /// the task, so a task that reaches here has none outstanding. Handing a
  /// child an assumption it cannot check, without saying it was confirmed by
  /// the user, is how a premise turns back into a guess one level down.
  List<String> _premisesFor(
    ConversationWorkflowSpec spec,
    ConversationWorkflowTask task,
  ) {
    final premises = <String>[];
    for (final edge in task.preconditions) {
      if (edge.kind != ConversationTaskPreconditionKind.assumption) continue;
      final ref = edge.ref.trim();
      final item = spec.provenance
          .where((entry) => entry.itemId == ref && entry.confirmed)
          .firstOrNull;
      if (item == null) continue;
      final text = provenance.itemValueFor(spec, ref) ?? ref;
      if (text.trim().isNotEmpty) premises.add(text.trim());
    }
    return List<String>.unmodifiable(premises);
  }
}
