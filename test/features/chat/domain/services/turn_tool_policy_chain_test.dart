import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/anabasis_parent_authority_guard.dart';
import 'package:caverno/features/chat/domain/services/material_assumption_confirmation_gate.dart';
import 'package:caverno/features/chat/domain/services/turn_tool_policy_chain.dart';
import 'package:test/test.dart';

final _mutation = ToolCallInfo(
  id: 'call-write',
  name: 'write_file',
  arguments: const {'path': 'lib/sync/engine.dart', 'content': '// ...'},
);

const _assumed = 'Existing entities have stable UUIDs';

ConversationWorkflowSpec _blockedSpec() {
  return const ConversationWorkflowSpec(
    goal: 'Add iCloud synchronization',
    constraints: [_assumed],
    provenance: [
      ConversationContractItemProvenance(
        itemId: 'constraint:stable-entity-ids',
        kind: ConversationContractItemKind.constraint,
        assumption: true,
        material: true,
      ),
    ],
  );
}

void main() {
  test('the parent is refused before anyone is asked to confirm', () async {
    var asked = 0;
    final chain = TurnToolPolicyChain(
      executingRole: ModelUsageRole.anabasisParent,
      assumptionGate: MaterialAssumptionConfirmationGate(
        currentSpec: _blockedSpec,
        requestConfirmation:
            ({required item, required itemText, required toolName}) async {
              asked++;
              return true;
            },
        persist: (_) async {},
      ),
    );

    final refusal = await chain.evaluate(
      _mutation,
      workspaceMode: WorkspaceMode.coding,
    );

    expect(refusal, isNotNull);
    expect(
      refusal!.errorMessage,
      contains('Anabasis parent'),
      reason: 'The refusal must be the authority one, not the assumption one.',
    );
    expect(
      asked,
      0,
      reason:
          'The parent cannot mutate at all, so asking the user to confirm an '
          'assumption first would raise an approval whose answer changes '
          'nothing — and a confirmation is durable state given for a reason '
          'that never applied.',
    );
  });

  test('a normal turn still reaches the assumption gate', () async {
    var asked = 0;
    final chain = TurnToolPolicyChain(
      executingRole: ModelUsageRole.chat,
      assumptionGate: MaterialAssumptionConfirmationGate(
        currentSpec: _blockedSpec,
        requestConfirmation:
            ({required item, required itemText, required toolName}) async {
              asked++;
              return false;
            },
        persist: (_) async {},
      ),
    );

    final refusal = await chain.evaluate(
      _mutation,
      workspaceMode: WorkspaceMode.coding,
    );

    expect(refusal, isNotNull);
    expect(asked, 1);
  });

  test('nothing blocking returns null', () async {
    final chain = TurnToolPolicyChain(
      executingRole: ModelUsageRole.chat,
      assumptionGate: MaterialAssumptionConfirmationGate(
        currentSpec: () => const ConversationWorkflowSpec(goal: 'Ship it'),
        requestConfirmation:
            ({required item, required itemText, required toolName}) async =>
                true,
        persist: (_) async {},
      ),
    );

    expect(
      await chain.evaluate(_mutation, workspaceMode: WorkspaceMode.coding),
      isNull,
    );
  });

  test('the parent may still inspect while an assumption blocks', () async {
    final chain = TurnToolPolicyChain(
      executingRole: ModelUsageRole.anabasisParent,
      assumptionGate: MaterialAssumptionConfirmationGate(
        currentSpec: _blockedSpec,
        requestConfirmation:
            ({required item, required itemText, required toolName}) async =>
                true,
        persist: (_) async {},
      ),
    );

    final McpToolResult? refusal = await chain.evaluate(
      ToolCallInfo(
        id: 'call-read',
        name: 'read_file',
        arguments: const {'path': 'lib/sync/engine.dart'},
      ),
      workspaceMode: WorkspaceMode.coding,
    );

    expect(
      refusal,
      isNull,
      reason:
          'Investigating is how either block gets cleared, so neither policy '
          'may close that door.',
    );
  });

  test('delegation passes both policies', () async {
    final chain = TurnToolPolicyChain(
      executingRole: ModelUsageRole.anabasisParent,
      assumptionGate: MaterialAssumptionConfirmationGate(
        currentSpec: _blockedSpec,
        requestConfirmation:
            ({required item, required itemText, required toolName}) async =>
                true,
        persist: (_) async {},
      ),
    );

    expect(
      await chain.evaluate(
        ToolCallInfo(
          id: 'call-spawn',
          name: AnabasisParentAuthorityGuard.delegationTools.first,
          arguments: const {'prompt': 'Implement the store'},
        ),
        workspaceMode: WorkspaceMode.coding,
      ),
      isNull,
      reason: 'Delegation is the parent\'s only route to effect.',
    );
  });
}
