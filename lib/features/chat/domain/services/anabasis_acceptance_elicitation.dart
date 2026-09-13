import '../entities/subagent_task.dart';
import '../entities/worktree_agent_task.dart';
import 'task_acceptance_audit.dart';

/// One delegated result whose only outstanding level is the parent's judgement.
class AcceptanceElicitationCandidate {
  const AcceptanceElicitationCandidate({
    required this.workflowTaskId,
    required this.childId,
    required this.title,
    required this.evidence,
  });

  final String workflowTaskId;
  final String childId;
  final String title;

  /// What the derivable levels rested on, named so the turn does not have to
  /// re-gather it before it can judge.
  final List<String> evidence;
}

enum AcceptanceElicitationEligibility {
  /// The turn that just ended was not the parent's, so an acceptance is not
  /// its business.
  notParentTurn,

  /// Nothing is finished, everything finished is already accepted, or what is
  /// finished still owes a level the parent cannot supply.
  noJudgeableResult,

  /// Every judgeable result has already been put to the parent once.
  alreadyElicited,

  eligible,
}

/// What one acceptance-elicitation decision produced.
typedef AcceptanceElicitationPlan = ({
  AcceptanceElicitationEligibility eligibility,
  List<AcceptanceElicitationCandidate> candidates,
});

/// Decides whether a settled parent turn owes one more turn, and about what.
///
/// **Why this exists, measured.** The eleventh worktree run had everything the
/// milestone was waiting for: the child came back `verified: true` with one
/// changed file, and the parent polled it four times, read the files and checked
/// the branch with git — then reported its judgement in prose and let the turn
/// settle. The tool was reachable (the acceptance scenario had already called
/// and recorded it), the evidence was in hand, and the time was there. What was
/// missing was a turn with nothing else to do.
///
/// That is the `update_goal` shape exactly, and `GoalCompletionElicitationPrompt`
/// is the precedent: the local model does not volunteer a bookkeeping call and
/// makes it reliably when a turn asks for nothing else. The remedy is a nudge,
/// not a repair.
///
/// **Only results the parent may actually accept are elicited.** A turn whose
/// single available tool would refuse the call is worse than no turn: it spends
/// a generation to tell the parent to go and verify something, with no tool to
/// verify it with. So the audit runs here too, and a result still owing the
/// mechanical or evidence level is left to an ordinary turn that can go and get
/// it.
class AnabasisAcceptanceElicitation {
  const AnabasisAcceptanceElicitation();

  static const audit = TaskAcceptanceAudit();

  AcceptanceElicitationPlan decide({
    required bool isParentTurn,
    required List<WorktreeAgentTask> worktreeChildren,
    required List<SubagentTask> children,
    required Set<String> acceptedTaskIds,
    required Set<String> alreadyElicitedTaskIds,
  }) {
    if (!isParentTurn) {
      return (
        eligibility: AcceptanceElicitationEligibility.notParentTurn,
        candidates: const <AcceptanceElicitationCandidate>[],
      );
    }

    final judgeable = <String, AcceptanceElicitationCandidate>{};

    // Subagent children first, so a worktree result for the same task overwrites
    // them below. That is `TaskAcceptanceDecisionService`'s rule arriving one
    // turn earlier: the worktree result is the only kind that can pass a level,
    // and eliciting against the weaker of the two would describe evidence the
    // write path will not use.
    for (final child in children) {
      if (!child.isTerminal) continue;
      final taskId = child.workflowTaskId.trim();
      if (taskId.isEmpty || acceptedTaskIds.contains(taskId)) continue;
      if (!audit.mayParentAccept(audit.auditSubagentResult(child))) continue;
      judgeable[taskId] = AcceptanceElicitationCandidate(
        workflowTaskId: taskId,
        childId: child.id,
        title: child.description.trim().isEmpty
            ? 'Delegated work'
            : child.description.trim(),
        evidence: const <String>['child summary recorded'],
      );
    }

    for (final child in worktreeChildren) {
      final taskId = child.workflowTaskId.trim();
      if (taskId.isEmpty || acceptedTaskIds.contains(taskId)) continue;
      // A branch still in flight is not judgeable and must not be elicited: the
      // write path answers that case with "poll until it is done", which is
      // advice this turn has no tool to take.
      if (!child.isTerminal) {
        judgeable.remove(taskId);
        continue;
      }
      if (!audit.mayParentAccept(audit.auditWorktreeResult(child))) {
        judgeable.remove(taskId);
        continue;
      }
      judgeable[taskId] = AcceptanceElicitationCandidate(
        workflowTaskId: taskId,
        childId: child.id,
        title: child.title.trim().isEmpty
            ? 'Delegated work'
            : child.title.trim(),
        evidence: <String>[
          'worktree branch ${child.branchName}',
          if (child.verifiedGreen &&
              child.verificationCommand.trim().isNotEmpty)
            'verified green: ${child.verificationCommand.trim()}',
          if (child.changedFiles.isNotEmpty)
            '${child.changedFiles.length} changed file(s) recorded',
        ],
      );
    }

    if (judgeable.isEmpty) {
      return (
        eligibility: AcceptanceElicitationEligibility.noJudgeableResult,
        candidates: const <AcceptanceElicitationCandidate>[],
      );
    }

    final unelicited = judgeable.values
        .where(
          (candidate) =>
              !alreadyElicitedTaskIds.contains(candidate.workflowTaskId),
        )
        .toList(growable: false);
    if (unelicited.isEmpty) {
      return (
        eligibility: AcceptanceElicitationEligibility.alreadyElicited,
        candidates: const <AcceptanceElicitationCandidate>[],
      );
    }

    return (
      eligibility: AcceptanceElicitationEligibility.eligible,
      candidates: unelicited,
    );
  }
}

/// The one-shot prompt that asks the parent to settle a result it has verified.
///
/// The wording follows `GoalCompletionElicitationPrompt` and differs in one
/// structural way, because the tools differ: `update_goal` can report that work
/// remains, and `accept_task` records acceptance and nothing else. So declining
/// has to be spelled out as *not calling the tool*, or the only available action
/// is the accepting one and the probe is leading. A false acceptance is the
/// expensive direction — it closes the task on the parent's word.
abstract final class AnabasisAcceptanceElicitationPrompt {
  static String build({
    required String languageCode,
    required List<AcceptanceElicitationCandidate> candidates,
  }) {
    final normalized = languageCode.trim().isEmpty ? 'en' : languageCode.trim();
    final plural = candidates.length == 1 ? 'result' : 'results';
    return [
      // Addressed, because the parent's authority is carried by the address and
      // accept_task is refused for any other turn. The handle is what makes
      // this the parent speaking rather than a turn about the parent.
      '@anabasis A delegated $plural finished and is waiting on your '
          'judgement. The mechanical and evidence levels are already settled '
          'for what is listed below, so there is nothing left to check: what '
          'is missing is whether the work satisfies the goal, which only you '
          'decide.',
      '',
      'Awaiting your judgement:',
      for (final candidate in candidates)
        '- ${candidate.title} — accept_task workflow_task_id: '
            '${candidate.workflowTaskId} — evidence: '
            '${candidate.evidence.isEmpty ? 'none recorded' : candidate.evidence.join(', ')}',
      '',
      'Record the judgement now by calling accept_task, the only tool '
          'available this turn:',
      '- workflow_task_id — exactly as listed above.',
      '- rationale — why this satisfies the goal, in your own words.',
      '',
      'If it does not satisfy the goal, do not call the tool: say in one '
          'sentence what is missing, and the task stays open for another '
          'attempt. Declining is a real answer here. accept_task records '
          'acceptance and nothing else, so accepting work you have not '
          'checked is the expensive direction — it closes the task on your '
          'word alone.',
      '',
      'Answering in prose when you do accept leaves the judgement unrecorded, '
          'and the result comes back to you unresolved.',
      '',
      'Keep any visible text to one short sentence.',
      '',
      'Keep the visible response language aligned with language code '
          '"$normalized".',
    ].join('\n');
  }
}

/// Which delegated results have already been put to the parent, by conversation.
///
/// One elicitation per result, and the reason is the loop it prevents: a parent
/// that declines leaves the result exactly as eligible as it was, so an
/// unguarded trigger would ask again at the end of the turn it just spent
/// answering. Declining is a real answer and has to stick.
class AnabasisAcceptanceElicitationLedger {
  final Map<String, Set<String>> _elicitedByConversation =
      <String, Set<String>>{};

  Set<String> elicitedFor(String conversationId) =>
      _elicitedByConversation[conversationId] ?? const <String>{};

  void recordElicited({
    required String conversationId,
    required Iterable<String> workflowTaskIds,
  }) => _elicitedByConversation
      .putIfAbsent(conversationId, () => <String>{})
      .addAll(workflowTaskIds);

  void clear() => _elicitedByConversation.clear();
}
