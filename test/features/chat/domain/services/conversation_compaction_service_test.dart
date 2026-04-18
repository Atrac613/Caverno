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
      planDocument: '# Plan\n\n## Goal\nShip plan context\n\n- Validate before writing files',
      now: DateTime(2026, 4, 18, 13, 0),
    );

    expect(artifact, isNotNull);
    expect(artifact!.version, ConversationCompactionService.artifactVersion);
    expect(artifact.sourceMessageCount, 16);
    expect(artifact.compactedMessageCount, 8);
    expect(artifact.retainedMessageCount, 8);
    expect(artifact.normalizedSummary, contains('Active plan context'));
    expect(artifact.normalizedSummary, contains('Ship plan context'));
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

  test('buildArtifact preserves tool-heavy turns in the summary', () {
    final messages = List<Message>.generate(16, (index) {
      final isUser = index.isEven;
      return Message(
        id: 'message-$index',
        content: isUser
            ? 'User request $index with enough detail for compaction.'
            : '<tool_call>{"name":"read_file","arguments":{"path":"lib/app.dart"}}</tool_call>',
        role: isUser ? MessageRole.user : MessageRole.assistant,
        timestamp: DateTime(2026, 4, 18, 10, index),
      );
    });

    final artifact = ConversationCompactionService.buildArtifact(
      messages: messages,
    );

    expect(artifact, isNotNull);
    expect(
      artifact!.normalizedSummary,
      contains('Assistant executed tool calls and returned structured results.'),
    );
  });
}
