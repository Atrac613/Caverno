import '../entities/conversation_workflow.dart';

// ChatNotifier decomposition collaborator: material-contract-assumption-arming

/// Decides which blocking assumptions [MaterialContractAssumptionGuard] is
/// allowed to refuse on.
///
/// ANA0 shipped the assumption producer in shadow first: marks were written
/// onto contract items and projected, and this returned an empty list so that
/// nothing was refused. The reason was an ordering constraint the track calls
/// non-negotiable — the guard refuses `assumption && material && !confirmed`,
/// and arming it before a user could confirm anything would have refused every
/// mutation in the conversation permanently, with the tool loop burning on
/// verbatim retries.
///
/// PR 4b-2 built that way out, so this now returns the spec's own blocking
/// assumptions. It stays a named policy rather than collapsing into
/// `spec.blockingAssumptions` at the call site: this is the one place that
/// decides whether the guard acts, and the shape that made the shadow possible
/// is the shape that makes a future scope restriction possible too.
///
/// The list only reaches the guard through
/// [MaterialAssumptionConfirmationGate], which raises the confirmation and
/// re-evaluates. A refusal with no way to answer it is the hazard ANA0 recorded
/// twice; the canary asserts that path rather than trusting it.
abstract final class MaterialContractAssumptionArming {
  /// The assumptions the guard may refuse on.
  static List<ConversationContractItemProvenance> armed(
    ConversationWorkflowSpec spec,
  ) => spec.blockingAssumptions;
}
