import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/tool_loop/incomplete_content_tool_recovery_plan.dart';
import 'package:caverno/features/chat/presentation/providers/content_tool_turn_state_registry.dart';
import 'package:caverno/features/chat/presentation/providers/tool_dedupe_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('acceptance stays isolated across owners and disposed generations', () {
    final registry = ContentToolTurnStateRegistry();
    final a = ChatTurnOwner(conversationId: 'a', interactionGeneration: 1);
    final b = ChatTurnOwner(conversationId: 'b', interactionGeneration: 1);
    final nextA = ChatTurnOwner(conversationId: 'a', interactionGeneration: 2);
    final input = Message(
      id: 'fixture',
      role: MessageRole.assistant,
      timestamp: DateTime(2026),
      content:
          '<tool_use>{"name":"read_file","arguments":{"path":"README.md"}}',
    );
    IncompleteContentToolRecoveryPlan recover(ChatTurnOwner owner) =>
        IncompleteContentToolRecoveryPlan.assess(
          input,
          acceptCall: (call) => registry.markSeenCall(
            owner,
            ToolDedupeKeys.toolCall(
              call.name,
              call.arguments,
              projectRoot: '/fixture/project',
            ),
          ),
        )!;
    expect(registry.begin(a), true);
    expect(registry.begin(b), true);
    expect(recover(a).recoveredToolCalls, hasLength(1));
    expect(registry.snapshot(b)!.seenCallHashes, isEmpty);
    expect(recover(a).recoveredToolCalls, isEmpty);
    expect(recover(a).pendingResult, isNotNull);
    expect(recover(b).recoveredToolCalls, hasLength(1));
    registry.dispose(a);
    expect(recover(a).recoveredToolCalls, isEmpty);
    expect(registry.contains(a), false);
    expect(registry.begin(a), false);
    expect(registry.begin(nextA), true);
    expect(recover(nextA).recoveredToolCalls, hasLength(1));
    expect(recover(b).recoveredToolCalls, isEmpty);
    expect(registry.pendingResultCount(b), 0);
    expect(registry.pendingExecutionCount(b), 0);
  });
}
