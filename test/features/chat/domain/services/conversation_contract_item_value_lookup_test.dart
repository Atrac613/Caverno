import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:test/test.dart';

/// ANA0 PR 4: the confirm surface has to show the user what it is asking them
/// to confirm, and the provenance record it is raised from carries only a
/// hashed id. These pin the inverse lookup to the same id definition the
/// forward one uses, because two definitions of an item id would show the
/// wrong item's text under the right item's question.
const _service = ConversationContractProvenanceService();

final _spec = ConversationWorkflowSpec(
  goal: 'Add iCloud synchronization',
  constraints: const ['Existing entities have stable UUIDs'],
  acceptanceCriteria: const ['A conflicting edit keeps both revisions'],
  openQuestions: const ['Which conflict policy does the user expect?'],
  tasks: const [
    ConversationWorkflowTask(id: 'sync-1', title: 'Model the change feed'),
    ConversationWorkflowTask(id: '', title: 'Backfill existing rows'),
  ],
);

void main() {
  group('itemValueFor', () {
    test('answers with the text behind a hashed id, per kind', () {
      for (final entry in {
        ConversationContractItemKind.constraint:
            'Existing entities have stable UUIDs',
        ConversationContractItemKind.acceptanceCriterion:
            'A conflicting edit keeps both revisions',
        ConversationContractItemKind.openQuestion:
            'Which conflict policy does the user expect?',
      }.entries) {
        final id = _service.itemId(kind: entry.key, value: entry.value);
        expect(
          _service.itemValueFor(_spec, id),
          entry.value,
          reason:
              'A mark can land on any asserted kind, so the lookup that '
              'renders it must cover the same set.',
        );
      }
    });

    test('answers for the goal and for both task id shapes', () {
      expect(
        _service.itemValueFor(_spec, 'goal'),
        'Add iCloud synchronization',
      );
      expect(
        _service.itemValueFor(_spec, 'task:sync-1'),
        'Model the change feed',
      );
      expect(
        _service.itemValueFor(
          _spec,
          _service.itemId(
            kind: ConversationContractItemKind.task,
            value: 'Backfill existing rows',
          ),
        ),
        'Backfill existing rows',
        reason:
            'A task without an id falls back to hashing its title, and the '
            'lookup has to follow the same fallback.',
      );
    });

    test('returns null rather than guessing when the item is gone', () {
      expect(
        _service.itemValueFor(
          _spec,
          _service.itemId(
            kind: ConversationContractItemKind.constraint,
            value: 'A constraint that was edited away',
          ),
        ),
        isNull,
        reason:
            'A revision can drop an item while a confirmation for it is '
            'still outstanding; showing the wrong text would be worse than '
            'showing none.',
      );
      expect(_service.itemValueFor(_spec, '  '), isNull);
    });

    test('is unaffected by the marks on the item', () {
      const value = 'Existing entities have stable UUIDs';
      final id = _service.itemId(
        kind: ConversationContractItemKind.constraint,
        value: value,
      );
      final marked = _spec.copyWith(
        provenance: [
          ConversationContractItemProvenance(
            itemId: id,
            kind: ConversationContractItemKind.constraint,
            assumption: true,
            material: true,
          ),
        ],
      );

      expect(
        _service.itemValueFor(marked, id),
        value,
        reason:
            'Marking never changes an item id (ANA0 PR 3a), so the lookup '
            'must not depend on provenance at all.',
      );
    });
  });
}
