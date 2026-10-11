import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/tool_loop/content_tool_call_partition.dart';
import 'package:caverno/features/chat/presentation/providers/content_tool_turn_state_registry.dart';
import 'package:caverno/features/chat/presentation/providers/tool_dedupe_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'partition uses owner-rooted seen keys without executing or registering results',
    () {
      final registry = ContentToolTurnStateRegistry();
      final a = ChatTurnOwner(conversationId: 'a', interactionGeneration: 1);
      final b = ChatTurnOwner(conversationId: 'b', interactionGeneration: 1);
      final nextA = ChatTurnOwner(
        conversationId: 'a',
        interactionGeneration: 2,
      );
      const content =
          '<tool_use>{"name":"read_file","arguments":{"path":"README.md"}}</tool_use>'
          '<tool_use>{"name":"read_file","arguments":{"path":"/fixture/project/README.md"}}</tool_use>';
      ContentToolCallPartition partition(ChatTurnOwner owner) =>
          ContentToolCallPartition.fromContent(
            content: content,
            advertisedToolNames: {},
            acceptCall: (call) => registry.markSeenCall(
              owner,
              ToolDedupeKeys.toolCall(
                call.name,
                call.arguments,
                projectRoot: '/fixture/project',
              ),
            ),
          );
      registry.begin(a);
      registry.begin(b);
      final first = partition(a);
      expect(first.fresh, hasLength(1));
      expect(first.repeated, hasLength(1));
      expect(registry.snapshot(b)!.seenCallHashes, isEmpty);
      expect(partition(a).fresh, isEmpty);
      expect(partition(b).fresh, hasLength(1));
      registry.dispose(a);
      final disposed = partition(a);
      expect(disposed.fresh, isEmpty);
      expect(disposed.repeated, hasLength(2));
      expect(registry.contains(a), false);
      registry.begin(nextA);
      expect(partition(nextA).fresh, hasLength(1));
      for (final owner in [b, nextA]) {
        expect(registry.snapshot(owner)!.executedCallKeys, isEmpty);
        expect(registry.pendingExecutionCount(owner), 0);
        expect(registry.pendingResultCount(owner), 0);
      }
    },
  );
}
