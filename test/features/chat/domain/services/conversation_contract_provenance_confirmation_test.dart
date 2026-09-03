import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/material_contract_assumption_guard.dart';
import 'package:test/test.dart';

const _service = ConversationContractProvenanceService();
const _guard = MaterialContractAssumptionGuard();

const _itemId = 'constraint:stable-entity-ids';

final _mutationCall = ToolCallInfo(
  id: 'call-write',
  name: 'write_file',
  arguments: const {'path': 'lib/sync/engine.dart', 'content': '// ...'},
);

ConversationWorkflowSpec _spec({
  bool assumption = true,
  bool material = true,
  bool confirmed = false,
}) {
  return ConversationWorkflowSpec(
    goal: 'Add iCloud synchronization',
    constraints: const ['Existing entities have stable UUIDs'],
    sources: const [
      ConversationContractSourceReference(
        id: 'approved-plan:deadbeef',
        kind: ConversationContractSourceKind.approvedPlan,
        locator: 'conversation_plan_artifact',
        contentHash: 'deadbeef',
      ),
    ],
    provenance: [
      ConversationContractItemProvenance(
        itemId: _itemId,
        kind: ConversationContractItemKind.constraint,
        sourceIds: const ['approved-plan:deadbeef'],
        assumption: assumption,
        material: material,
        confirmed: confirmed,
        clarificationQuestion: 'Do existing entities have stable UUIDs?',
      ),
    ],
  );
}

void main() {
  group('confirmMaterialAssumption', () {
    test('performs the three steps from the design', () {
      final confirmed = _service.confirmMaterialAssumption(
        workflowSpec: _spec(),
        itemId: _itemId,
        locator: 'message:m-42',
      );

      final source = confirmed.sources.singleWhere(
        (entry) =>
            entry.kind ==
            ConversationContractSourceKind.userConfirmedAssumption,
      );
      expect(source.id, _service.confirmationSourceId(_itemId));
      expect(source.locator, 'message:m-42');

      final item = confirmed.provenance.single;
      expect(item.sourceIds, contains(source.id));
      expect(item.confirmed, isTrue);
    });

    test('unblocks the guard end to end', () {
      final blocked = _spec();
      expect(
        _guard.evaluate(
          _mutationCall,
          workspaceMode: WorkspaceMode.coding,
          blockingAssumptions: blocked.blockingAssumptions,
        ),
        isNotNull,
      );

      final confirmed = _service.confirmMaterialAssumption(
        workflowSpec: blocked,
        itemId: _itemId,
      );

      expect(confirmed.blockingAssumptions, isEmpty);
      expect(
        _guard.evaluate(
          _mutationCall,
          workspaceMode: WorkspaceMode.coding,
          blockingAssumptions: confirmed.blockingAssumptions,
        ),
        isNull,
      );
    });

    test('preserves the original sources and the rest of the contract', () {
      final blocked = _spec();
      final confirmed = _service.confirmMaterialAssumption(
        workflowSpec: blocked,
        itemId: _itemId,
      );

      expect(confirmed.sources, containsAll(blocked.sources));
      expect(confirmed.goal, blocked.goal);
      expect(confirmed.constraints, blocked.constraints);
      expect(
        confirmed.provenance.single.sourceIds,
        containsAll(blocked.provenance.single.sourceIds),
        reason: 'Confirmation adds provenance; it must not replace it.',
      );
    });

    test('is idempotent', () {
      final once = _service.confirmMaterialAssumption(
        workflowSpec: _spec(),
        itemId: _itemId,
      );
      final twice = _service.confirmMaterialAssumption(
        workflowSpec: once,
        itemId: _itemId,
      );

      expect(twice, once);
      expect(twice.sources, hasLength(2));
      expect(twice.provenance.single.sourceIds, hasLength(2));
    });

    test('ignores an unknown item id', () {
      final spec = _spec();
      expect(
        _service.confirmMaterialAssumption(
          workflowSpec: spec,
          itemId: 'constraint:not-present',
        ),
        spec,
      );
      expect(
        _service.confirmMaterialAssumption(workflowSpec: spec, itemId: '  '),
        spec,
      );
    });

    test('ignores an item that is not an assumption', () {
      final spec = _spec(assumption: false);
      expect(
        _service.confirmMaterialAssumption(workflowSpec: spec, itemId: _itemId),
        spec,
        reason:
            'Confirming a plain contract item is meaningless: only an '
            'assumption carries the question the confirmation answers.',
      );
    });

    test('confirms a non-material assumption too', () {
      final confirmed = _service.confirmMaterialAssumption(
        workflowSpec: _spec(material: false),
        itemId: _itemId,
      );

      expect(
        confirmed.provenance.single.confirmed,
        isTrue,
        reason:
            'material decides whether the assumption blocks execution, not '
            'whether the user is allowed to settle it.',
      );
    });
  });

  group('known limitation — re-deriving the contract erases confirmations', () {
    test('attachApprovedPlanSource drops a recorded confirmation', () {
      final confirmed = _service.confirmMaterialAssumption(
        workflowSpec: _spec(),
        itemId: _itemId,
      );
      expect(confirmed.blockingAssumptions, isEmpty);

      final rederived = _service.attachApprovedPlanSource(
        workflowSpec: confirmed,
        sourceHash: 'cafebabe',
      );

      expect(
        rederived.sources.any(
          (source) =>
              source.kind ==
              ConversationContractSourceKind.userConfirmedAssumption,
        ),
        isFalse,
        reason:
            'attachApprovedPlanSource replaces sources wholesale and rebuilds '
            'provenance from the spec text, so a re-approved plan starts from '
            'unconfirmed. Recorded here as a known property rather than a '
            'surprise: item ids are content hashes and therefore stable, so '
            'carrying confirmations across a re-derivation is possible. '
            'Whether it is correct is a separate decision — a materially '
            'changed contract arguably should be re-confirmed. See ANA0 '
            'follow-up in docs/roadmap.md.',
      );
    });
  });
}
