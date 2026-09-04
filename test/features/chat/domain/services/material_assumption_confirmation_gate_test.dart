import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/material_assumption_confirmation_gate.dart';
import 'package:caverno/features/chat/domain/services/material_contract_assumption_guard.dart';
import 'package:test/test.dart';

const _service = ConversationContractProvenanceService();

final _mutation = ToolCallInfo(
  id: 'call-write',
  name: 'write_file',
  arguments: const {'path': 'lib/sync/engine.dart', 'content': '// ...'},
);

final _inspection = ToolCallInfo(
  id: 'call-read',
  name: 'read_file',
  arguments: const {'path': 'lib/sync/engine.dart'},
);

String _idFor(String constraint) => _service.itemId(
  kind: ConversationContractItemKind.constraint,
  value: constraint,
);

ConversationWorkflowSpec _spec({
  List<String> constraints = const ['Existing entities have stable UUIDs'],
  Set<String> confirmed = const {},
}) {
  return ConversationWorkflowSpec(
    goal: 'Add iCloud synchronization',
    constraints: constraints,
    provenance: [
      for (final constraint in constraints)
        ConversationContractItemProvenance(
          itemId: _idFor(constraint),
          kind: ConversationContractItemKind.constraint,
          assumption: true,
          material: true,
          confirmed: confirmed.contains(constraint),
          clarificationQuestion: 'Is "$constraint" actually true?',
        ),
    ],
  );
}

/// Drives the gate with a spec the test can move underneath it, which is the
/// only way to assert the property that matters: the blocking list is read
/// again on every call rather than captured once per batch.
class _Host {
  _Host(this.spec, {this.answer = true, this.persistTakesEffect = true});

  ConversationWorkflowSpec spec;
  bool answer;
  bool persistTakesEffect;
  final List<String> asked = <String>[];
  final List<String> askedText = <String>[];

  MaterialAssumptionConfirmationGate get gate =>
      MaterialAssumptionConfirmationGate(
        currentSpec: () => spec,
        requestConfirmation:
            ({required item, required itemText, required toolName}) async {
              asked.add(item.itemId);
              askedText.add(itemText);
              return answer;
            },
        persist: (next) async {
          if (persistTakesEffect) spec = next;
        },
      );
}

void main() {
  group('nothing to ask about', () {
    test('an unmarked contract lets the mutation through', () async {
      final host = _Host(const ConversationWorkflowSpec(goal: 'Ship it'));

      expect(
        await host.gate.evaluate(
          _mutation,
          workspaceMode: WorkspaceMode.coding,
        ),
        isNull,
      );
      expect(host.asked, isEmpty);
    });

    test('inspection is never blocked, so it is never asked about', () async {
      final host = _Host(_spec());

      expect(
        await host.gate.evaluate(
          _inspection,
          workspaceMode: WorkspaceMode.coding,
        ),
        isNull,
        reason: 'Investigating the assumption is the way out of the block.',
      );
      expect(host.asked, isEmpty);
    });

    test('a chat workspace is out of scope', () async {
      final host = _Host(_spec());

      expect(
        await host.gate.evaluate(_mutation, workspaceMode: WorkspaceMode.chat),
        isNull,
      );
      expect(host.asked, isEmpty);
    });
  });

  group('asking', () {
    test(
      'confirming clears the block and lets the same call through',
      () async {
        final host = _Host(_spec());
        final gate = host.gate;

        expect(
          await gate.evaluate(_mutation, workspaceMode: WorkspaceMode.coding),
          isNull,
          reason:
              'The gate re-evaluates after the answer; a confirmation that '
              'only takes effect on the next tool call has not unblocked '
              'anything.',
        );
        expect(host.asked, [_idFor('Existing entities have stable UUIDs')]);
        expect(
          host.askedText,
          ['Existing entities have stable UUIDs'],
          reason:
              'The surface shows the claim, not the hash that identifies it.',
        );
        expect(host.spec.blockingAssumptions, isEmpty);
      },
    );

    test('declining refuses, and records nothing', () async {
      final host = _Host(_spec(), answer: false);

      final refusal = await host.gate.evaluate(
        _mutation,
        workspaceMode: WorkspaceMode.coding,
      );

      expect(refusal, isNotNull);
      expect(
        refusal!.result,
        contains(MaterialContractAssumptionGuard.blockedCode),
      );
      expect(
        host.spec.blockingAssumptions,
        hasLength(1),
        reason:
            'A decline is not a deferral and not a confirmation: the '
            'assumption stays unconfirmed and the mutation stays refused.',
      );
    });

    test(
      'every blocking assumption is asked about, not just the first',
      () async {
        final host = _Host(
          _spec(
            constraints: const ['UUIDs are stable', 'The API is versioned'],
          ),
        );

        expect(
          await host.gate.evaluate(
            _mutation,
            workspaceMode: WorkspaceMode.coding,
          ),
          isNull,
        );
        expect(host.asked, hasLength(2));
      },
    );
  });

  group('the properties that keep it from spinning or going stale', () {
    test(
      'a confirmation that does not clear its item is not re-asked',
      () async {
        final host = _Host(_spec(), persistTakesEffect: false);

        final refusal = await host.gate.evaluate(
          _mutation,
          workspaceMode: WorkspaceMode.coding,
        );

        expect(
          refusal,
          isNotNull,
          reason:
              'With the item still blocking, the only safe answer is the '
              'refusal the model can read.',
        );
        expect(
          host.asked,
          hasLength(1),
          reason:
              'Re-asking would spin, and a dialog that reopens forever is '
              'worse than a refused tool call.',
        );
      },
    );

    test(
      'a confirmation answered elsewhere is visible to the next call',
      () async {
        final host = _Host(_spec(), answer: false);
        final gate = host.gate;

        expect(
          await gate.evaluate(_mutation, workspaceMode: WorkspaceMode.coding),
          isNotNull,
        );

        // The user answers on another surface — the watch, or a second thread —
        // while the batch is still running.
        host.spec = _spec(
          confirmed: const {'Existing entities have stable UUIDs'},
        );

        expect(
          await gate.evaluate(_mutation, workspaceMode: WorkspaceMode.coding),
          isNull,
          reason:
              'Capturing the blocking list once per batch would keep every '
              'later call in that batch blocked by an assumption the user has '
              'already disposed of.',
        );
        expect(host.asked, hasLength(1));
      },
    );
  });
}
