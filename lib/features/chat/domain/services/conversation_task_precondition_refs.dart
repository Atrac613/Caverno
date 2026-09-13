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

  /// Every assumption [task] declares an edge to, confirmed or not.
  ///
  /// **The input `DelegatedPremiseAudit` was written for and never given**,
  /// which left ANA2's contradiction policy unreachable: its `lapsed` takes the
  /// premises a child was issued with, nothing supplied them, and the bar in
  /// `mayParentAccept` could only ever be handed an empty list.
  ///
  /// The obvious supply -- record what the child was handed at delegation time
  /// -- needs a field on both child entities threaded through four hops. It is
  /// also unnecessary: a task is only delegated once it is *ready*, and
  /// readiness requires every assumption edge to be confirmed, so at that
  /// moment the declared set and the issued set are the same set. A premise the
  /// user later declines therefore shows up here as a declared edge that no
  /// longer resolves to a confirmed item -- readable from the plan, with
  /// nothing stored.
  ///
  /// What this does not see: an edge *removed* from the task after its child
  /// was delegated. That is the right answer rather than a gap -- the plan no
  /// longer says the task stands on it -- but it is the one case where
  /// "declared now" and "issued then" genuinely differ.
  ///
  /// The sibling of [confirmedItemTextFor] rather than a class of its own,
  /// because the two answer the same question to different audiences: a brief
  /// may carry only confirmed premises, and an acceptance has to see the ones
  /// that lapsed.
  List<String> declaredAssumptionPremises(
    ConversationWorkflowSpec spec,
    ConversationWorkflowTask task,
  ) {
    final premises = <String>[];
    for (final edge in task.preconditions) {
      if (edge.kind != ConversationTaskPreconditionKind.assumption) continue;
      final itemId = itemIdFor(spec, edge.ref);
      if (itemId == null) continue;
      final text = (provenance.itemValueFor(spec, itemId) ?? '').trim();
      if (text.isNotEmpty) premises.add(text);
    }
    return List<String>.unmodifiable(premises);
  }
}
