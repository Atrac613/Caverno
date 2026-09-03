import '../entities/conversation_workflow.dart';

// ChatNotifier decomposition collaborator: material-contract-assumption-arming

/// Decides which blocking assumptions [MaterialContractAssumptionGuard] is
/// allowed to refuse on.
///
/// ANA0 ships the assumption producer in **shadow**: marks are written onto
/// contract items and projected, but no mutation is refused yet. The guard is
/// already wired into the tool-loop guard chain and already refuses while
/// `assumption && material && !confirmed`, while no production path can call
/// `ConversationContractProvenanceService.confirmMaterialAssumption`. Arming it
/// before that confirmation surface exists refuses every mutation in the
/// conversation permanently, with the tool loop burning on verbatim retries.
///
/// Until this file existed the shadow was true only by accident: no producer
/// wrote `assumption: true`, so the list the guard received happened to be
/// empty. `ContractItemMarks.parseBullet` ended that — a user typing
/// `(assumed, material)` onto a plan-document bullet is a producer, and it
/// reaches the guard through the same feed site. The shadow is stated here
/// rather than left to that coincidence.
///
/// ANA0 PR 4 builds the confirm surface, then arms the guard by returning
/// [ConversationWorkflowSpec.blockingAssumptions] from [armed] and unskipping
/// the canary's reachability assertion. This is the one place that changes.
abstract final class MaterialContractAssumptionArming {
  /// The assumptions the guard may refuse on: none while ANA0 runs in shadow.
  static List<ConversationContractItemProvenance> armed(
    ConversationWorkflowSpec spec,
  ) => const <ConversationContractItemProvenance>[];
}
