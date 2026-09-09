import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_checkpoint_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records a checkpoint on the last non-streaming message', () {
    final now = DateTime(2026, 9, 8, 22);
    final conversation = Conversation(
      id: 'c1',
      title: 'Thread',
      messages: [
        Message(
          id: 'm1',
          content: 'Hello',
          role: MessageRole.user,
          timestamp: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
      workspaceMode: WorkspaceMode.chat,
    );

    final recorded = ConversationCheckpointRecorder.record(
      conversation,
      now: now,
    );

    expect(recorded.checkpoints, hasLength(1));
    expect(recorded.checkpoints.single.messageId, 'm1');
    expect(recorded.checkpoints.single.messageCount, 1);
  });
}
