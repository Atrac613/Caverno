import '../entities/subagent_task.dart';
import '../entities/worktree_agent_task.dart';

/// The four questions a result has to answer before it is accepted.
///
/// Cheapest first, and only the ones that apply to a given result count.
enum AcceptanceLevel {
  /// Did the verification command pass?
  mechanical,

  /// Do the artifacts match the claim?
  evidence,

  /// Does this actually satisfy the goal?
  ///
  /// The parent's own judgement. Nothing derives it, and nothing here pretends
  /// to: it is the reason Anabasis exists.
  semantic,

  /// Is this a decision only a person can make?
  user,
}

/// What a child's result has and has not established.
class AcceptanceVerdict {
  const AcceptanceVerdict({
    required this.passed,
    required this.outstanding,
    required this.notApplicable,
  });

  final Set<AcceptanceLevel> passed;
  final Set<AcceptanceLevel> outstanding;

  /// Levels this kind of result cannot answer and is not asked to.
  ///
  /// An inspecting child changes no files, so demanding artifact evidence from
  /// it would make every investigation unacceptable.
  final Set<AcceptanceLevel> notApplicable;

  /// Whether everything that applies has passed.
  ///
  /// False for every result today, because [AcceptanceLevel.semantic] is
  /// nobody's derived value — which is the honest answer while the parent has
  /// no way to record a judgement. ANA3's later slices give it one; this is
  /// what stops "the tests are green" being mistaken for "the goal is met".
  bool get isAccepted => outstanding.isEmpty;
}

/// Audits what a child produced against what it can be shown to have done.
///
/// **A child saying "done" means `produced`. It never means `accepted`.** This
/// is the mechanical half of that rule: levels 1 and 2 are derived from
/// evidence the runners already record, and levels 3 and 4 stay outstanding
/// because nothing derives a judgement or a person's decision.
///
/// Nothing is stored. ANA3's design opens by warning that adding acceptance
/// levels without fixing ownership first reproduces the
/// `ConversationExecutionValidationStatus` problem — three writers, one of them
/// judging prose — at a larger scale. A derived verdict has no writer at all.
class TaskAcceptanceAudit {
  const TaskAcceptanceAudit();

  /// For a worktree child, which is expected to change files and may verify.
  AcceptanceVerdict auditWorktreeResult(WorktreeAgentTask task) {
    final passed = <AcceptanceLevel>{};
    final outstanding = <AcceptanceLevel>{};
    final notApplicable = <AcceptanceLevel>{};

    if (task.verificationCommand.trim().isEmpty) {
      // Nothing was claimed mechanically, so nothing is owed. This is not the
      // same as passing, and keeping the two apart is why the set exists.
      notApplicable.add(AcceptanceLevel.mechanical);
    } else if (task.verifiedGreen) {
      passed.add(AcceptanceLevel.mechanical);
    } else {
      outstanding.add(AcceptanceLevel.mechanical);
    }

    final hasEvidence = task.changedFiles.isNotEmpty;
    if (hasEvidence && !task.changedFileEvidenceTruncated) {
      passed.add(AcceptanceLevel.evidence);
    } else {
      // Truncated evidence is not evidence for this purpose: a partial list
      // cannot show that the artifacts match the claim, only that some of them
      // might.
      outstanding.add(AcceptanceLevel.evidence);
    }

    outstanding.addAll(const [AcceptanceLevel.semantic, AcceptanceLevel.user]);
    return AcceptanceVerdict(
      passed: passed,
      outstanding: outstanding,
      notApplicable: notApplicable,
    );
  }

  /// Whether the parent may record an acceptance for this result right now.
  ///
  /// **The parent supplies level 3 by judging; it cannot supply levels 1 and
  /// 2.** That asymmetry is what "only evidence promotes it to accepted" means
  /// in code: a judgement is the parent's to make and an unrun verification is
  /// not, so a confident rationale cannot stand in for a test that did not
  /// pass or files nobody can see.
  ///
  /// [lapsedPremises] comes from `DelegatedPremiseAudit`. A result produced
  /// under an assumption the user has since declined is barred here rather than
  /// cancelled mid-flight, which is ANA2's contradiction policy arriving at the
  /// moment it decides something.
  bool mayParentAccept(
    AcceptanceVerdict verdict, {
    List<String> lapsedPremises = const <String>[],
  }) {
    if (lapsedPremises.isNotEmpty) return false;
    return !verdict.outstanding.contains(AcceptanceLevel.mechanical) &&
        !verdict.outstanding.contains(AcceptanceLevel.evidence);
  }

  /// For an in-conversation child, which returns a summary and changes nothing.
  ///
  /// `SubagentTask` carries no changed files and no verification result, so
  /// both mechanical and evidence levels are inapplicable rather than failed.
  /// Everything it establishes has to be established by reading what it said,
  /// which is level 3 — the parent's job.
  AcceptanceVerdict auditSubagentResult(SubagentTask task) {
    // A child that reported nothing leaves the parent nothing to judge, so the
    // evidence level is owed rather than inapplicable. Emptiness is the whole
    // test — reading the summary to decide whether it *sounds* substantial
    // would be the kind of prose judgement §10 records as already having cost
    // this codebase a reverted writer.
    final reported = task.resultSummary.trim().isNotEmpty;
    return AcceptanceVerdict(
      passed: const {},
      outstanding: {
        if (!reported) AcceptanceLevel.evidence,
        AcceptanceLevel.semantic,
        AcceptanceLevel.user,
      },
      notApplicable: {
        AcceptanceLevel.mechanical,
        if (reported) AcceptanceLevel.evidence,
      },
    );
  }
}
