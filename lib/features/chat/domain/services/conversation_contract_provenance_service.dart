import '../entities/conversation_workflow.dart';
import 'conversation_plan_hash.dart';

/// Epistemic marks carried by one contract item through the plan document.
///
/// Anabasis ANA0. These are properties of an item, not a separate kind of
/// item: a constraint the model only assumes is still a constraint, and its
/// [ConversationContractProvenanceService.itemId] is unchanged by the marks,
/// so becoming an assumption never changes an item's identity.
class ContractItemMarks {
  const ContractItemMarks({this.assumption = false, this.material = false});

  static const none = ContractItemMarks();

  /// The item is believed rather than established.
  final bool assumption;

  /// Acting on the item while it is wrong would be expensive to undo, so an
  /// unconfirmed assumption blocks execution.
  final bool material;

  bool get isEmpty => !assumption && !material;

  /// Trailing marker written onto a plan-document bullet, empty when plain.
  ///
  /// The plan document is the authoritative middle of the contract and the
  /// user edits it by hand, so the marker is meant to be readable and typable
  /// rather than terse. Only these two forms round-trip; anything else stays
  /// part of the item's own text.
  String get bulletSuffix {
    if (!assumption) return '';
    return material ? ' (assumed, material)' : ' (assumed)';
  }

  /// Splits a plan-document bullet into its text and its marks.
  ///
  /// The marker is stripped before the text is returned, so
  /// [ConversationContractProvenanceService.itemId] hashes the same text
  /// whether or not the item is marked. Marking an item must never change its
  /// identity, or confirming an assumption would not survive a re-derivation.
  static ({String text, ContractItemMarks marks}) parseBullet(String bullet) {
    final trimmed = bullet.trim();
    final match = _bulletMarker.firstMatch(trimmed);
    if (match == null) {
      return (text: trimmed, marks: none);
    }
    return (
      text: trimmed.substring(0, match.start).trim(),
      marks: ContractItemMarks(
        assumption: true,
        material: match.group(1) != null,
      ),
    );
  }

  static final RegExp _bulletMarker = RegExp(
    r'\s*\(\s*assumed\s*(?:,\s*(material)\s*)?\)$',
    caseSensitive: false,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContractItemMarks &&
          other.assumption == assumption &&
          other.material == material;

  @override
  int get hashCode => Object.hash(assumption, material);

  @override
  String toString() =>
      'ContractItemMarks(assumption: $assumption, material: $material)';
}

class ConversationContractProvenanceService {
  const ConversationContractProvenanceService();

  /// Rebuilds provenance against a newly approved plan document.
  ///
  /// [marks], keyed by [itemId], carries the epistemic marks parsed off the
  /// document's bullets. Items absent from the map are plain contract items.
  ///
  /// Note that this replaces sources and provenance wholesale, so any recorded
  /// confirmation is dropped: a re-approved plan starts from unconfirmed. Item
  /// ids are content hashes and therefore stable, so carrying confirmations
  /// across is possible; whether it is correct is a separate decision, since a
  /// materially changed contract arguably should be re-confirmed.
  ConversationWorkflowSpec attachApprovedPlanSource({
    required ConversationWorkflowSpec workflowSpec,
    required String sourceHash,
    Map<String, ContractItemMarks> marks = const {},
  }) {
    final normalizedHash = sourceHash.trim();
    if (!workflowSpec.hasContent || normalizedHash.isEmpty) {
      return workflowSpec;
    }
    final sourceId = 'approved-plan:$normalizedHash';
    return workflowSpec.copyWith(
      sources: [
        ConversationContractSourceReference(
          id: sourceId,
          kind: ConversationContractSourceKind.approvedPlan,
          locator: 'conversation_plan_artifact',
          contentHash: normalizedHash,
        ),
      ],
      provenance: _items(workflowSpec, sourceId: sourceId, marks: marks),
    );
  }

  /// Records the user's confirmation of a material contract assumption.
  ///
  /// Anabasis ANA0, see `docs/ANABASIS_ORCHESTRATOR_ARCHITECTURE.md` §7. The
  /// confirmation is written as a *source*, not only as a flag, so the
  /// provenance graph can later answer why an item was treated as known.
  /// Three steps, in order: append a
  /// [ConversationContractSourceKind.userConfirmedAssumption] reference, link
  /// its id into the item's `sourceIds`, then set `confirmed`.
  ///
  /// Only the user may call this. A model must never confirm its own
  /// assumption — that is the whole point of
  /// [ConversationContractItemProvenance.blocksExecution].
  ///
  /// Returns the spec unchanged when [itemId] names nothing, names an item
  /// that is not an assumption, or names one that is already confirmed, so
  /// repeated confirmation is idempotent rather than duplicating sources.
  ConversationWorkflowSpec confirmMaterialAssumption({
    required ConversationWorkflowSpec workflowSpec,
    required String itemId,
    String locator = '',
  }) {
    final normalizedItemId = itemId.trim();
    if (normalizedItemId.isEmpty) {
      return workflowSpec;
    }

    final index = workflowSpec.provenance.indexWhere(
      (item) => item.itemId == normalizedItemId,
    );
    if (index < 0) {
      return workflowSpec;
    }

    final item = workflowSpec.provenance[index];
    if (!item.assumption || item.confirmed) {
      return workflowSpec;
    }

    final sourceId = confirmationSourceId(normalizedItemId);
    final sources = [...workflowSpec.sources];
    if (!sources.any((source) => source.id == sourceId)) {
      sources.add(
        ConversationContractSourceReference(
          id: sourceId,
          kind: ConversationContractSourceKind.userConfirmedAssumption,
          locator: locator.trim(),
        ),
      );
    }

    final provenance = [...workflowSpec.provenance];
    provenance[index] = item.copyWith(
      sourceIds: item.sourceIds.contains(sourceId)
          ? item.sourceIds
          : [...item.sourceIds, sourceId],
      confirmed: true,
    );

    return workflowSpec.copyWith(sources: sources, provenance: provenance);
  }

  /// Deterministic id for the confirmation source of [itemId].
  ///
  /// Stable so confirming twice is a no-op, and so a confirmation survives any
  /// path that re-derives provenance while keeping item ids.
  String confirmationSourceId(String itemId) => 'user-confirmed:${itemId.trim()}';

  String itemId({
    required ConversationContractItemKind kind,
    required String value,
  }) {
    if (kind == ConversationContractItemKind.goal) return 'goal';
    final normalized = value.trim().toLowerCase();
    return '${kind.name}:${computeConversationPlanHash(normalized)}';
  }

  /// Whether an epistemic mark means anything on an item of [kind].
  ///
  /// Anabasis ANA0 PR 3d. An open question is already unasserted: asking about
  /// something says you do not know it, so marking it as an assumption claims
  /// nothing the item did not already say. Marks belong on what the plan
  /// *asserts*.
  ///
  /// This is enforced here rather than only in the prompt because it is not a
  /// style preference. `ConversationContractItemProvenance.blocksExecution`
  /// does not look at `kind`, so a marked open question blocks workspace
  /// mutation exactly as a marked constraint would — and a plan is normally
  /// blocked *by* an open question, not until one is confirmed. The 36-request
  /// ANA0 PR 3c run measured the model doing this on four of its five material
  /// marks, so the wording alone is not enough.
  static bool marksApplyTo(ConversationContractItemKind kind) =>
      kind != ConversationContractItemKind.openQuestion;

  List<ConversationContractItemProvenance> _items(
    ConversationWorkflowSpec spec, {
    required String sourceId,
    Map<String, ContractItemMarks> marks = const {},
  }) {
    final items = <ConversationContractItemProvenance>[];
    ConversationContractItemProvenance entry({
      required String id,
      required ConversationContractItemKind kind,
    }) {
      final itemMarks = marksApplyTo(kind)
          ? (marks[id] ?? ContractItemMarks.none)
          : ContractItemMarks.none;
      return ConversationContractItemProvenance(
        itemId: id,
        kind: kind,
        sourceIds: [sourceId],
        assumption: itemMarks.assumption,
        material: itemMarks.material,
      );
    }

    if (spec.goal.trim().isNotEmpty) {
      items.add(entry(id: 'goal', kind: ConversationContractItemKind.goal));
    }
    void addItems(Iterable<String> values, ConversationContractItemKind kind) {
      for (final value in values) {
        if (value.trim().isEmpty) continue;
        items.add(entry(id: itemId(kind: kind, value: value), kind: kind));
      }
    }

    addItems(spec.constraints, ConversationContractItemKind.constraint);
    addItems(
      spec.acceptanceCriteria,
      ConversationContractItemKind.acceptanceCriterion,
    );
    addItems(spec.openQuestions, ConversationContractItemKind.openQuestion);
    for (final task in spec.tasks) {
      final taskId = task.id.trim();
      items.add(
        entry(
          id: taskId.isEmpty
              ? itemId(
                  kind: ConversationContractItemKind.task,
                  value: task.title,
                )
              : 'task:$taskId',
          kind: ConversationContractItemKind.task,
        ),
      );
    }
    return items;
  }
}
