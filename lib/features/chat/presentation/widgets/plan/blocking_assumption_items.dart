import '../../../domain/entities/conversation_workflow.dart';
import '../../../domain/services/plan/conversation_contract_provenance_service.dart';

const _provenance = ConversationContractProvenanceService();

/// The subset of [items] whose mark blocks execution.
///
/// Provenance carries an `itemId` and a kind but not the item's text, so the
/// match runs in the direction `ContractItemListSection` resolves a mark: hash
/// each candidate and look for it among the blocking ids.
///
/// A free function rather than a static on either widget, because the summary
/// and the sheet both need the same subset from a spec alone, and neither is
/// the other's owner.
List<String> blockingAssumptionItems({
  required ConversationWorkflowSpec spec,
  required ConversationContractItemKind kind,
  required List<String> items,
}) {
  final blockingIds = spec.blockingAssumptions
      .map((item) => item.itemId)
      .toSet();
  if (blockingIds.isEmpty) return const <String>[];
  return items
      .map((item) => item.trim())
      .where(
        (item) =>
            item.isNotEmpty &&
            blockingIds.contains(_provenance.itemId(kind: kind, value: item)),
      )
      .toList(growable: false);
}
