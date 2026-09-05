import '../entities/conversation_workflow.dart';
import 'conversation_contract_provenance_service.dart';

/// Turns a precondition's `ref` into the thing it names (ANA1).
///
/// The planning prompt asks the model for human text — a task's *title*, a
/// constraint's *text* — and it has to. A task id is minted by the parser
/// after the model has already answered, and a contract item's id is a hash of
/// that item's own text. Neither exists at the moment a proposal is written,
/// so a proposal that referenced ids could only ever reference ids it invented.
///
/// Both forms resolve here. The text form is what real plans carry; the id
/// form keeps working for edges typed by hand against a plan that already
/// exists, which is the case ANA1 PR 2a's round trip preserved.
class ConversationTaskPreconditionRefs {
  const ConversationTaskPreconditionRefs({
    this.provenance = const ConversationContractProvenanceService(),
  });

  final ConversationContractProvenanceService provenance;

  /// The task [ref] names, or `null` when nothing names exactly one.
  ///
  /// Two tasks sharing a title resolve to neither. An ambiguous reference
  /// cannot be checked, and picking one would let work start on a premise
  /// nobody established — the same reason an edge pointing nowhere is unmet.
  ConversationWorkflowTask? taskFor(ConversationWorkflowSpec spec, String ref) {
    final target = ref.trim();
    if (target.isEmpty) return null;
    for (final task in spec.tasks) {
      if (task.id.trim() == target) return task;
    }
    final byTitle = spec.tasks
        .where((task) => task.title.trim() == target)
        .toList(growable: false);
    return byTitle.length == 1 ? byTitle.first : null;
  }

  /// The contract item id [ref] names, or `null` when the spec holds no such
  /// item.
  ///
  /// Matching by text cannot be ambiguous the way a title can: an item's id is
  /// a hash of its own normalized text, so two items reading the same already
  /// share one id.
  String? itemIdFor(ConversationWorkflowSpec spec, String ref) {
    final target = ref.trim();
    if (target.isEmpty) return null;
    for (final entry in spec.provenance) {
      if (entry.itemId.trim() == target) return entry.itemId;
    }
    for (final entry in spec.provenance) {
      if (provenance.itemValueFor(spec, entry.itemId)?.trim() == target) {
        return entry.itemId;
      }
    }
    return null;
  }

  /// The text of the confirmed contract item [ref] names, or `null` when
  /// nothing names one or the user has not confirmed it.
  ///
  /// A child is told the premises its task stands on, and only the confirmed
  /// ones: passing an unconfirmed claim as a premise is how an assumption
  /// turns back into a guess one level down.
  String? confirmedItemTextFor(ConversationWorkflowSpec spec, String ref) {
    final itemId = itemIdFor(spec, ref);
    if (itemId == null) return null;
    final isConfirmed = spec.provenance.any(
      (entry) => entry.itemId == itemId && entry.confirmed,
    );
    if (!isConfirmed) return null;
    final text = (provenance.itemValueFor(spec, itemId) ?? ref).trim();
    return text.isEmpty ? null : text;
  }
}
