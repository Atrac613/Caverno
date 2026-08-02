import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_workflow_provenance_merge_service.dart';

void main() {
  const mergeService = ConversationWorkflowProvenanceMergeService();
  const provenanceService = ConversationContractProvenanceService();

  test(
    'adds approved-plan provenance without replacing legacy graph fields',
    () {
      final legacy = _legacyWorkflow();
      final projected = provenanceService.attachApprovedPlanSource(
        workflowSpec: _semanticWorkflow(),
        sourceHash: 'plan-hash',
      );
      final legacyBefore = jsonEncode(legacy.toJson());
      final projectedBefore = jsonEncode(projected.toJson());

      final result = mergeService.merge(
        legacyWorkflowSpec: legacy,
        projectedWorkflowSpec: projected,
      );

      expect(result.isMergeable, isTrue);
      expect(result.blockers, isEmpty);
      final merged = result.workflowSpec!;
      expect(merged.sources.take(2), legacy.sources);
      expect(merged.sources.last, projected.sources.single);
      expect(merged.provenance, hasLength(legacy.provenance.length));
      for (final entry in merged.provenance.indexed) {
        final legacyItem = legacy.provenance[entry.$1];
        final mergedItem = entry.$2;
        expect(
          mergedItem.copyWith(sourceIds: legacyItem.sourceIds),
          legacyItem,
        );
        expect(mergedItem.sourceIds, [
          ...legacyItem.sourceIds,
          projected.sources.single.id,
        ]);
      }
      expect(jsonEncode(legacy.toJson()), legacyBefore);
      expect(jsonEncode(projected.toJson()), projectedBefore);
    },
  );

  test('blocks invalid legacy source and item graphs', () {
    final invalid = _legacyWorkflow().copyWith(
      sources: [..._legacyWorkflow().sources, _legacyWorkflow().sources.first],
      provenance: [
        _legacyWorkflow().provenance.first.copyWith(
          sourceIds: ['missing-source'],
        ),
      ],
    );

    final result = mergeService.merge(
      legacyWorkflowSpec: invalid,
      projectedWorkflowSpec: _projectedWorkflow(),
    );

    expect(
      result.blockers,
      containsAll([
        ConversationWorkflowProvenanceMergeBlocker.invalidLegacySourceGraph,
        ConversationWorkflowProvenanceMergeBlocker.invalidLegacyItemGraph,
      ]),
    );
    expect(result.workflowSpec, isNull);
  });

  test('blocks an approved-plan source ID collision', () {
    final projected = _projectedWorkflow();
    final legacy = _legacyWorkflow().copyWith(
      sources: [
        ..._legacyWorkflow().sources,
        projected.sources.single.copyWith(
          kind: ConversationContractSourceKind.specificationFile,
        ),
      ],
      provenance: _legacyWorkflow().provenance
          .map(
            (item) => item.copyWith(
              sourceIds: [...item.sourceIds, projected.sources.single.id],
            ),
          )
          .toList(growable: false),
    );

    final result = mergeService.merge(
      legacyWorkflowSpec: legacy,
      projectedWorkflowSpec: projected,
    );

    expect(result.blockers, [
      ConversationWorkflowProvenanceMergeBlocker.approvedPlanSourceCollision,
    ]);
  });

  test('blocks mismatched and unmatched legacy items', () {
    final legacyProvenance = _legacyWorkflow().provenance;
    final legacy = _legacyWorkflow().copyWith(
      provenance: [
        legacyProvenance.first.copyWith(
          kind: ConversationContractItemKind.task,
        ),
        ...legacyProvenance.skip(1).take(2),
        const ConversationContractItemProvenance(
          itemId: 'legacy-only',
          kind: ConversationContractItemKind.task,
          sourceIds: ['user-source'],
        ),
      ],
    );

    final result = mergeService.merge(
      legacyWorkflowSpec: legacy,
      projectedWorkflowSpec: _projectedWorkflow(),
    );

    expect(
      result.blockers,
      containsAll([
        ConversationWorkflowProvenanceMergeBlocker.itemKindMismatch,
        ConversationWorkflowProvenanceMergeBlocker.unmatchedLegacyItem,
        ConversationWorkflowProvenanceMergeBlocker
            .projectedItemMissingLegacyProvenance,
      ]),
    );
  });

  test('blocks projected items without legacy provenance', () {
    final legacy = _legacyWorkflow().copyWith(
      sources: [_legacyWorkflow().sources.first],
      provenance: [_legacyWorkflow().provenance.first],
    );

    final result = mergeService.merge(
      legacyWorkflowSpec: legacy,
      projectedWorkflowSpec: _projectedWorkflow(),
    );

    expect(
      result.blockers,
      contains(
        ConversationWorkflowProvenanceMergeBlocker
            .projectedItemMissingLegacyProvenance,
      ),
    );
  });

  test('blocks malformed projected provenance', () {
    final projected = _projectedWorkflow().copyWith(
      provenance: [
        _projectedWorkflow().provenance.first.copyWith(sourceIds: const []),
      ],
    );

    final result = mergeService.merge(
      legacyWorkflowSpec: _legacyWorkflow(),
      projectedWorkflowSpec: projected,
    );

    expect(result.blockers, [
      ConversationWorkflowProvenanceMergeBlocker.invalidProjectedGraph,
    ]);
  });

  test('reconciles documented positional identities one-to-one', () {
    final legacy = _positionalLegacyWorkflow();
    final projected = _positionalProjectedWorkflow();

    final result = mergeService.merge(
      legacyWorkflowSpec: legacy,
      projectedWorkflowSpec: projected,
    );

    expect(result.isMergeable, isTrue);
    final merged = result.workflowSpec!;
    expect(
      merged.provenance.map((item) => item.itemId),
      legacy.provenance.map((item) => item.itemId),
    );
    for (final entry in merged.provenance.indexed) {
      final legacyItem = legacy.provenance[entry.$1];
      expect(entry.$2.copyWith(sourceIds: legacyItem.sourceIds), legacyItem);
      expect(entry.$2.sourceIds.last, projected.sources.single.id);
    }
  });

  test('blocks malformed and out-of-range positional identities', () {
    final legacy = _positionalLegacyWorkflow();
    final malformed = legacy.copyWith(
      provenance: legacy.provenance
          .map(
            (item) => item.itemId == 'constraint:1'
                ? item.copyWith(itemId: 'constraint:not-an-index')
                : item,
          )
          .toList(growable: false),
    );
    final outOfRange = legacy.copyWith(
      provenance: legacy.provenance
          .map(
            (item) => item.itemId == 'constraint:1'
                ? item.copyWith(itemId: 'constraint:99')
                : item,
          )
          .toList(growable: false),
    );

    for (final invalid in [malformed, outOfRange]) {
      final result = mergeService.merge(
        legacyWorkflowSpec: invalid,
        projectedWorkflowSpec: _positionalProjectedWorkflow(),
      );
      expect(
        result.blockers,
        containsAll([
          ConversationWorkflowProvenanceMergeBlocker.unmatchedLegacyItem,
          ConversationWorkflowProvenanceMergeBlocker
              .projectedItemMissingLegacyProvenance,
        ]),
      );
      expect(result.workflowSpec, isNull);
    }
  });

  test('blocks duplicate positional target matches', () {
    final legacy = _positionalLegacyWorkflow();
    final duplicateTarget = legacy.copyWith(
      provenance: legacy.provenance
          .map(
            (item) => item.itemId == 'constraint:1'
                ? item.copyWith(itemId: 'constraint:00')
                : item,
          )
          .toList(growable: false),
    );

    final result = mergeService.merge(
      legacyWorkflowSpec: duplicateTarget,
      projectedWorkflowSpec: _positionalProjectedWorkflow(),
    );

    expect(
      result.blockers,
      containsAll([
        ConversationWorkflowProvenanceMergeBlocker.ambiguousItemIdentity,
        ConversationWorkflowProvenanceMergeBlocker
            .projectedItemMissingLegacyProvenance,
      ]),
    );
    expect(result.workflowSpec, isNull);
  });

  test('blocks semantic workflow drift', () {
    final projected = _positionalProjectedWorkflow();
    final changedTask = projected.tasks.single.copyWith(title: 'Changed task');

    final result = mergeService.merge(
      legacyWorkflowSpec: _positionalLegacyWorkflow(),
      projectedWorkflowSpec: projected.copyWith(tasks: [changedTask]),
    );

    expect(
      result.blockers,
      contains(
        ConversationWorkflowProvenanceMergeBlocker.semanticWorkflowMismatch,
      ),
    );
    expect(result.workflowSpec, isNull);
  });

  test('blocks projected item identity drift', () {
    final projected = _positionalProjectedWorkflow();
    final driftedProvenance = projected.provenance
        .map(
          (item) => item.kind == ConversationContractItemKind.constraint
              ? item.copyWith(itemId: 'constraint:drift')
              : item,
        )
        .toList(growable: false);

    final result = mergeService.merge(
      legacyWorkflowSpec: _positionalLegacyWorkflow(),
      projectedWorkflowSpec: projected.copyWith(provenance: driftedProvenance),
    );

    expect(result.blockers, [
      ConversationWorkflowProvenanceMergeBlocker.invalidProjectedGraph,
    ]);
  });
}

ConversationWorkflowSpec _semanticWorkflow() {
  return const ConversationWorkflowSpec(
    goal: 'Preserve legacy provenance',
    constraints: ['Keep existing sources'],
    acceptanceCriteria: ['Add the approved plan source'],
    tasks: [ConversationWorkflowTask(id: 'task-1', title: 'Merge provenance')],
  );
}

ConversationWorkflowSpec _projectedWorkflow() {
  return const ConversationContractProvenanceService().attachApprovedPlanSource(
    workflowSpec: _semanticWorkflow(),
    sourceHash: 'plan-hash',
  );
}

ConversationWorkflowSpec _legacyWorkflow() {
  final projectedProvenance = _projectedWorkflow().provenance;
  return _semanticWorkflow().copyWith(
    sources: const [
      ConversationContractSourceReference(
        id: 'user-source',
        kind: ConversationContractSourceKind.userMessage,
      ),
      ConversationContractSourceReference(
        id: 'spec-source',
        kind: ConversationContractSourceKind.specificationFile,
      ),
    ],
    provenance: projectedProvenance
        .map(
          (item) => switch (item.kind) {
            ConversationContractItemKind.goal => item.copyWith(
              sourceIds: const ['user-source'],
              assumption: true,
              material: true,
              confirmed: true,
              clarificationQuestion: 'Keep this metadata intact?',
            ),
            ConversationContractItemKind.task => item.copyWith(
              sourceIds: const ['user-source'],
            ),
            _ => item.copyWith(sourceIds: const ['spec-source']),
          },
        )
        .toList(growable: false),
  );
}

ConversationWorkflowSpec _positionalSemanticWorkflow() {
  return const ConversationWorkflowSpec(
    goal: 'Reconcile positional identities',
    constraints: ['Keep the first source', 'Keep the second source'],
    acceptanceCriteria: ['Preserve metadata', 'Reject ambiguity'],
    tasks: [
      ConversationWorkflowTask(id: 'task-positional', title: 'Reconcile IDs'),
    ],
  );
}

ConversationWorkflowSpec _positionalProjectedWorkflow() {
  return const ConversationContractProvenanceService().attachApprovedPlanSource(
    workflowSpec: _positionalSemanticWorkflow(),
    sourceHash: 'positional-plan-hash',
  );
}

ConversationWorkflowSpec _positionalLegacyWorkflow() {
  var constraintIndex = 0;
  var acceptanceIndex = 0;
  final legacyItems = _positionalProjectedWorkflow().provenance
      .map((item) {
        return switch (item.kind) {
          ConversationContractItemKind.constraint => item.copyWith(
            itemId: 'constraint:${constraintIndex++}',
            sourceIds: const ['spec-source'],
          ),
          ConversationContractItemKind.acceptanceCriterion => item.copyWith(
            itemId: 'acceptance:${acceptanceIndex++}',
            sourceIds: const ['spec-source'],
          ),
          _ => item.copyWith(sourceIds: const ['user-source']),
        };
      })
      .toList(growable: false);
  return _positionalSemanticWorkflow().copyWith(
    sources: const [
      ConversationContractSourceReference(
        id: 'user-source',
        kind: ConversationContractSourceKind.userMessage,
      ),
      ConversationContractSourceReference(
        id: 'spec-source',
        kind: ConversationContractSourceKind.specificationFile,
      ),
    ],
    provenance: [
      legacyItems.last,
      legacyItems[4],
      legacyItems.first,
      legacyItems[1],
      legacyItems[3],
      legacyItems[2],
    ],
  );
}
