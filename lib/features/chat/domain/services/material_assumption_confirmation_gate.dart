import '../../../../core/types/workspace_mode.dart';
import '../entities/conversation_workflow.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'conversation_contract_provenance_service.dart';
import 'material_contract_assumption_arming.dart';
import 'material_contract_assumption_guard.dart';

// ChatNotifier decomposition collaborator: material-assumption-confirmation-gate

/// Asks the user about a material assumption at the moment it blocks a
/// mutation, and lets the tool call through once they confirm it.
///
/// ANA0 PR 4b-2. The guard alone can only refuse; the refusal names a
/// clarification question and hopes the model asks it, which puts the way out
/// of the block behind the model's willingness to stop and ask. This raises the
/// question itself, at the refusal site, because that is the only surface with
/// no dead end: a plan-review affordance leaves a blocked run with nowhere to
/// answer.
///
/// Three properties are load-bearing, and each of them is a bug that was
/// specified out rather than found:
///
/// * **The blocking list is read per call, not once per batch.** A confirmation
///   answered while a batch is running has to be visible to the next call in
///   that same batch, or the run stays blocked by an assumption the user has
///   already disposed of.
/// * **An item is asked about at most once per gate.** If a confirmation fails
///   to clear its item — a stale id, a revision that replaced the contract —
///   re-asking would spin, and a spinning approval dialog is worse than a
///   refusal the model can read.
/// * **Declining refuses.** It does not defer and it does not confirm: the
///   assumption stays unconfirmed, and the mutation stays blocked, which is
///   what `ConversationContractItemProvenance.blocksExecution` means.
final class MaterialAssumptionConfirmationGate {
  MaterialAssumptionConfirmationGate({
    required this.currentSpec,
    required this.requestConfirmation,
    required this.persist,
    this.provenance = const ConversationContractProvenanceService(),
    this.guard = const MaterialContractAssumptionGuard(),
  });

  /// The owning conversation's spec as it is *now*.
  final ConversationWorkflowSpec Function() currentSpec;

  /// Raises the confirmation and waits for the user. `false` for both a
  /// decline and a turn that ended before it was answered.
  final Future<bool> Function({
    required ConversationContractItemProvenance item,
    required String itemText,
    required String toolName,
  })
  requestConfirmation;

  /// Persists the confirmed spec onto the owning conversation.
  final Future<void> Function(ConversationWorkflowSpec spec) persist;

  final ConversationContractProvenanceService provenance;
  final MaterialContractAssumptionGuard guard;

  final Set<String> _asked = <String>{};

  /// The refusal to return for [toolCall], or `null` once nothing blocks it.
  Future<McpToolResult?> evaluate(
    ToolCallInfo toolCall, {
    required WorkspaceMode workspaceMode,
  }) async {
    while (true) {
      final spec = currentSpec();
      final blocking = MaterialContractAssumptionArming.armed(spec);
      final refusal = guard.evaluate(
        toolCall,
        workspaceMode: workspaceMode,
        blockingAssumptions: blocking,
      );
      if (refusal == null) return null;

      final unasked = blocking.where((item) => !_asked.contains(item.itemId));
      if (unasked.isEmpty) return refusal;

      final item = unasked.first;
      _asked.add(item.itemId);
      final confirmed = await requestConfirmation(
        item: item,
        itemText: provenance.itemValueFor(spec, item.itemId) ?? item.itemId,
        toolName: toolCall.name,
      );
      if (!confirmed) return refusal;

      await persist(
        provenance.confirmMaterialAssumption(
          workflowSpec: currentSpec(),
          itemId: item.itemId,
        ),
      );
    }
  }
}
