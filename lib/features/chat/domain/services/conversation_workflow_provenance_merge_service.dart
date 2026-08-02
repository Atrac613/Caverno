import '../entities/conversation_workflow.dart';

enum ConversationWorkflowProvenanceMergeBlocker {
  invalidLegacySourceGraph,
  invalidLegacyItemGraph,
  invalidProjectedGraph,
  approvedPlanSourceCollision,
  itemKindMismatch,
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
    final legacyItems = _validateLegacyItems(
      legacyWorkflowSpec,
      legacySourceIds,
      blockers,
    );
    final projectedGraph = _validateProjectedGraph(
      projectedWorkflowSpec,
      blockers,
    );
    if (blockers.isNotEmpty || projectedGraph == null) {
      return _blocked(blockers);
    }

    if (legacySourceIds.contains(projectedGraph.source.id)) {
      blockers.add(
        ConversationWorkflowProvenanceMergeBlocker.approvedPlanSourceCollision,
      );
    }
    final projectedItems = {
      for (final item in projectedWorkflowSpec.provenance) item.itemId: item,
    };
    for (final legacyItem in legacyWorkflowSpec.provenance) {
      final projectedItem = projectedItems[legacyItem.itemId];
      if (projectedItem == null) {
        blockers.add(
          ConversationWorkflowProvenanceMergeBlocker.unmatchedLegacyItem,
        );
      } else if (projectedItem.kind != legacyItem.kind) {
        blockers.add(
          ConversationWorkflowProvenanceMergeBlocker.itemKindMismatch,
        );
      }
    }
    for (final projectedItem in projectedWorkflowSpec.provenance) {
      if (!legacyItems.containsKey(projectedItem.itemId)) {
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
    var invalid = sourceId.isEmpty || workflowSpec.provenance.isEmpty;
    for (final item in workflowSpec.provenance) {
      final itemId = item.itemId.trim();
      if (itemId.isEmpty ||
          !itemIds.add(itemId) ||
          item.sourceIds.length != 1 ||
          item.sourceIds.single.trim() != sourceId) {
        invalid = true;
      }
    }
    if (invalid) {
      blockers.add(
        ConversationWorkflowProvenanceMergeBlocker.invalidProjectedGraph,
      );
      return null;
    }
    return _ProjectedGraph(source: source);
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
  const _ProjectedGraph({required this.source});

  final ConversationContractSourceReference source;
}
