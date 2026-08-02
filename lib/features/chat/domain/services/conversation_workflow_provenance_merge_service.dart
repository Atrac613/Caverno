import '../entities/conversation_workflow.dart';
import 'conversation_contract_provenance_service.dart';

enum ConversationWorkflowProvenanceMergeBlocker {
  invalidLegacySourceGraph,
  invalidLegacyItemGraph,
  invalidProjectedGraph,
  semanticWorkflowMismatch,
  approvedPlanSourceCollision,
  itemKindMismatch,
  ambiguousItemIdentity,
  unmatchedLegacyItem,
  projectedItemMissingLegacyProvenance,
}

final class ConversationWorkflowProvenanceMergeResult {
  const ConversationWorkflowProvenanceMergeResult({
    required this.blockers,
    this.workflowSpec,
  });

  final List<ConversationWorkflowProvenanceMergeBlocker> blockers;
  final ConversationWorkflowSpec? workflowSpec;

  bool get isMergeable => blockers.isEmpty && workflowSpec != null;
}

final class ConversationWorkflowProvenanceMergeService {
  const ConversationWorkflowProvenanceMergeService();

  ConversationWorkflowProvenanceMergeResult merge({
    required ConversationWorkflowSpec legacyWorkflowSpec,
    required ConversationWorkflowSpec projectedWorkflowSpec,
  }) {
    final blockers = <ConversationWorkflowProvenanceMergeBlocker>{};
    final legacySourceIds = _validateLegacySources(
      legacyWorkflowSpec,
      blockers,
    );
    _validateLegacyItems(legacyWorkflowSpec, legacySourceIds, blockers);
    final projectedGraph = _validateProjectedGraph(
      projectedWorkflowSpec,
      blockers,
    );
    if (blockers.isNotEmpty || projectedGraph == null) {
      return _blocked(blockers);
    }

    if (_withoutProvenance(legacyWorkflowSpec) !=
        _withoutProvenance(projectedWorkflowSpec)) {
      blockers.add(
        ConversationWorkflowProvenanceMergeBlocker.semanticWorkflowMismatch,
      );
    }
    if (legacySourceIds.contains(projectedGraph.source.id)) {
      blockers.add(
        ConversationWorkflowProvenanceMergeBlocker.approvedPlanSourceCollision,
      );
    }
    final matchedProjectedItemIds = <String>{};
    for (final legacyItem in legacyWorkflowSpec.provenance) {
      final projectedItem = _resolveProjectedItem(legacyItem, projectedGraph);
      if (projectedItem == null) {
        blockers.add(
          ConversationWorkflowProvenanceMergeBlocker.unmatchedLegacyItem,
        );
      } else if (projectedItem.kind != legacyItem.kind) {
        blockers.add(
          ConversationWorkflowProvenanceMergeBlocker.itemKindMismatch,
        );
      } else if (!matchedProjectedItemIds.add(projectedItem.itemId)) {
        blockers.add(
          ConversationWorkflowProvenanceMergeBlocker.ambiguousItemIdentity,
        );
      }
    }
    for (final projectedItem in projectedWorkflowSpec.provenance) {
      if (!matchedProjectedItemIds.contains(projectedItem.itemId)) {
        blockers.add(
          ConversationWorkflowProvenanceMergeBlocker
              .projectedItemMissingLegacyProvenance,
        );
      }
    }
    if (blockers.isNotEmpty) {
      return _blocked(blockers);
    }

    final mergedProvenance = legacyWorkflowSpec.provenance
        .map(
          (item) => item.copyWith(
            sourceIds: [...item.sourceIds, projectedGraph.source.id],
          ),
        )
        .toList(growable: false);
    return ConversationWorkflowProvenanceMergeResult(
      blockers: const [],
      workflowSpec: projectedWorkflowSpec.copyWith(
        sources: [...legacyWorkflowSpec.sources, projectedGraph.source],
        provenance: mergedProvenance,
      ),
    );
  }

  ConversationContractItemProvenance? _resolveProjectedItem(
    ConversationContractItemProvenance legacyItem,
    _ProjectedGraph projectedGraph,
  ) {
    final exactMatch = projectedGraph.itemsById[legacyItem.itemId];
    if (exactMatch != null) return exactMatch;

    final positionalIndex = switch (legacyItem.kind) {
      ConversationContractItemKind.constraint => _legacyPositionalIndex(
        legacyItem.itemId,
        prefix: 'constraint:',
      ),
      ConversationContractItemKind.acceptanceCriterion =>
        _legacyPositionalIndex(legacyItem.itemId, prefix: 'acceptance:'),
      _ => null,
    };
    if (positionalIndex == null) return null;
    final projectedItems = projectedGraph.itemsByKind[legacyItem.kind]!;
    if (positionalIndex >= projectedItems.length) return null;
    return projectedItems[positionalIndex];
  }

  int? _legacyPositionalIndex(String itemId, {required String prefix}) {
    if (!itemId.startsWith(prefix)) return null;
    final suffix = itemId.substring(prefix.length);
    if (!RegExp(r'^\d+$').hasMatch(suffix)) return null;
    return int.tryParse(suffix);
  }

  Set<String> _validateLegacySources(
    ConversationWorkflowSpec workflowSpec,
    Set<ConversationWorkflowProvenanceMergeBlocker> blockers,
  ) {
    final sourceIds = workflowSpec.sources
        .map((source) => source.id.trim())
        .toList(growable: false);
    final uniqueSourceIds = sourceIds.where((id) => id.isNotEmpty).toSet();
    if (sourceIds.isEmpty ||
        sourceIds.any((id) => id.isEmpty) ||
        uniqueSourceIds.length != sourceIds.length) {
      blockers.add(
        ConversationWorkflowProvenanceMergeBlocker.invalidLegacySourceGraph,
      );
    }
    return uniqueSourceIds;
  }

  Map<String, ConversationContractItemProvenance> _validateLegacyItems(
    ConversationWorkflowSpec workflowSpec,
    Set<String> sourceIds,
    Set<ConversationWorkflowProvenanceMergeBlocker> blockers,
  ) {
    final items = <String, ConversationContractItemProvenance>{};
    final referencedSourceIds = <String>{};
    var invalid = workflowSpec.provenance.isEmpty;
    for (final item in workflowSpec.provenance) {
      final itemId = item.itemId.trim();
      final itemSourceIds = item.sourceIds
          .map((sourceId) => sourceId.trim())
          .toList(growable: false);
      final uniqueItemSourceIds = itemSourceIds
          .where((sourceId) => sourceId.isNotEmpty)
          .toSet();
      if (itemId.isEmpty ||
          items.containsKey(itemId) ||
          itemSourceIds.isEmpty ||
          itemSourceIds.any((sourceId) => sourceId.isEmpty) ||
          uniqueItemSourceIds.length != itemSourceIds.length ||
          !sourceIds.containsAll(uniqueItemSourceIds)) {
        invalid = true;
      }
      items[itemId] = item;
      referencedSourceIds.addAll(uniqueItemSourceIds);
    }
    if (!referencedSourceIds.containsAll(sourceIds)) {
      invalid = true;
    }
    if (invalid) {
      blockers.add(
        ConversationWorkflowProvenanceMergeBlocker.invalidLegacyItemGraph,
      );
    }
    return items;
  }

  _ProjectedGraph? _validateProjectedGraph(
    ConversationWorkflowSpec workflowSpec,
    Set<ConversationWorkflowProvenanceMergeBlocker> blockers,
  ) {
    final approvedSources = workflowSpec.sources
        .where(
          (source) =>
              source.kind == ConversationContractSourceKind.approvedPlan,
        )
        .toList(growable: false);
    if (workflowSpec.sources.length != 1 || approvedSources.length != 1) {
      blockers.add(
        ConversationWorkflowProvenanceMergeBlocker.invalidProjectedGraph,
      );
      return null;
    }
    final source = approvedSources.single;
    final sourceId = source.id.trim();
    final itemIds = <String>{};
    final itemsById = <String, ConversationContractItemProvenance>{};
    var invalid = sourceId.isEmpty || workflowSpec.provenance.isEmpty;
    for (final item in workflowSpec.provenance) {
      final itemId = item.itemId.trim();
      if (itemId.isEmpty ||
          !itemIds.add(itemId) ||
          item.sourceIds.length != 1 ||
          item.sourceIds.single.trim() != sourceId) {
        invalid = true;
      }
      itemsById[itemId] = item;
    }
    final semanticWorkflowSpec = _withoutProvenance(workflowSpec);
    final expectedProvenance = const ConversationContractProvenanceService()
        .attachApprovedPlanSource(
          workflowSpec: semanticWorkflowSpec,
          sourceHash: 'identity-validation',
        )
        .provenance;
    if (expectedProvenance.length != workflowSpec.provenance.length) {
      invalid = true;
    } else {
      for (final entry in expectedProvenance.indexed) {
        final actual = workflowSpec.provenance[entry.$1];
        final expected = entry.$2;
        if (actual.itemId != expected.itemId || actual.kind != expected.kind) {
          invalid = true;
        }
      }
    }
    if (invalid) {
      blockers.add(
        ConversationWorkflowProvenanceMergeBlocker.invalidProjectedGraph,
      );
      return null;
    }
    return _ProjectedGraph(
      source: source,
      itemsById: itemsById,
      itemsByKind: {
        for (final kind in ConversationContractItemKind.values)
          kind: workflowSpec.provenance
              .where((item) => item.kind == kind)
              .toList(growable: false),
      },
    );
  }

  ConversationWorkflowSpec _withoutProvenance(
    ConversationWorkflowSpec workflowSpec,
  ) {
    return workflowSpec.copyWith(
      sources: const <ConversationContractSourceReference>[],
      provenance: const <ConversationContractItemProvenance>[],
    );
  }

  ConversationWorkflowProvenanceMergeResult _blocked(
    Set<ConversationWorkflowProvenanceMergeBlocker> blockers,
  ) {
    return ConversationWorkflowProvenanceMergeResult(
      blockers: ConversationWorkflowProvenanceMergeBlocker.values
          .where(blockers.contains)
          .toList(growable: false),
    );
  }
}

final class _ProjectedGraph {
  const _ProjectedGraph({
    required this.source,
    required this.itemsById,
    required this.itemsByKind,
  });

  final ConversationContractSourceReference source;
  final Map<String, ConversationContractItemProvenance> itemsById;
  final Map<
    ConversationContractItemKind,
    List<ConversationContractItemProvenance>
  >
  itemsByKind;
}
