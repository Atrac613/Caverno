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
