import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_compaction_service.dart';

void main() {
  List<Message> buildMessages(int count) {
    return List<Message>.generate(count, (index) {
      final isUser = index.isEven;
      return Message(
        id: 'message-$index',
        content:
            '${isUser ? 'User' : 'Assistant'} turn $index with enough detail '
            'to make prompt compaction meaningful for the test suite.',
        role: isUser ? MessageRole.user : MessageRole.assistant,
        timestamp: DateTime(2026, 4, 18, 12, index),
      );
    });
  }

  test('buildArtifact compacts older turns and keeps recent turns verbatim', () {
    final messages = buildMessages(16);

    final artifact = ConversationCompactionService.buildArtifact(
      messages: messages,
      now: DateTime(2026, 4, 18, 13, 0),
    );

    expect(artifact, isNotNull);
    expect(artifact!.compactedMessageCount, 8);
    expect(artifact.retainedMessageCount, 8);
    expect(artifact.normalizedSummary, contains('User: User turn 0'));

    final retained = ConversationCompactionService.retainMessages(
      messages: messages,
      artifact: artifact,
    );
    expect(retained, hasLength(8));
    expect(retained.first.id, 'message-8');
    expect(retained.last.id, 'message-15');
  });

  test('buildArtifact returns null for short conversations', () {
    final artifact = ConversationCompactionService.buildArtifact(
      messages: buildMessages(6),
    );

    expect(artifact, isNull);
  });
}
