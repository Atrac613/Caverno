import '../entities/conversation.dart';
import 'conversation_contract_provenance_service.dart';

/// Whether the premises a child was sent out with still hold.
///
/// ANA2's open question, answered as a policy rather than case by case: what
/// happens to a running child when an assumption it depended on is
/// contradicted mid-flight — continue, cancel, invalidate, or restart?
///
/// **The answer is invalidate. The child is not stopped; its result is barred
/// from acceptance.** This is a judgement, not a measurement, and the argument
/// is the ownership rule ANA3 states: a child saying "done" means `produced`,
/// and only evidence promotes it to `accepted`. A premise that has lapsed is
/// missing evidence, so the promotion is what must fail — not the work.
///
/// Cancelling would throw away a partial result that is mostly unrelated to the
/// premise: a worktree child leaves a branch, and an inspecting child leaves
/// findings. Restarting is a decision that belongs to the user *after* the
/// assumption is settled again, not to a policy running while it is unsettled.
/// Continuing without a bar is the only option that is simply wrong, because it
/// ends with unverifiable work being accepted.
///
/// Contradiction is not hypothetical. A user who can confirm an assumption
/// (ANA0 PR 4b-2) can decline one, and re-approving a plan rebuilds provenance
/// wholesale, so a confirmed item comes back unconfirmed.
class DelegatedPremiseAudit {
  const DelegatedPremiseAudit({
    this.provenance = const ConversationContractProvenanceService(),
  });

  final ConversationContractProvenanceService provenance;

  /// The premises in [issuedPremises] that no longer hold.
  ///
  /// Matched by the claim's own text rather than by item id, because the id is
  /// a hash of that text: an edit that rewrites the claim changes the id, and
  /// treating that as "the same premise, still confirmed" would carry a
  /// confirmation across a change of meaning.
  List<String> lapsed(Conversation conversation, List<String> issuedPremises) {
    final spec = conversation.effectiveWorkflowSpec;
    final confirmed = <String>{
      for (final item in spec.provenance)
        if (item.confirmed)
          (provenance.itemValueFor(spec, item.itemId) ?? '').trim(),
    }..remove('');

    return <String>[
      for (final premise in issuedPremises)
        if (!confirmed.contains(premise.trim())) premise,
    ];
  }

  /// Whether a child's result may be promoted past `produced`.
  bool mayAcceptResult(
    Conversation conversation,
    List<String> issuedPremises,
  ) => lapsed(conversation, issuedPremises).isEmpty;
}
