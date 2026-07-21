import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_compaction_service.dart';

void main() {
  String repeatedText(int length) => List.filled(length, 'x').join();

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
      planDocument:
          '# Plan\n\n## Goal\nShip plan context\n\n- Validate before writing files',
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

  test('buildArtifact compacts token-heavy conversations before 14 turns', () {
    final messages = List<Message>.generate(9, (index) {
      return Message(
        id: 'large-message-$index',
        content: 'large context ${repeatedText(3500)}',
        role: index.isEven ? MessageRole.user : MessageRole.assistant,
        timestamp: DateTime(2026, 4, 18, 14, index),
      );
    });

    final artifact = ConversationCompactionService.buildArtifact(
      messages: messages,
    );

    expect(artifact, isNotNull);
    expect(artifact!.compactedMessageCount, 1);
    expect(artifact.retainedMessageCount, 8);
  });

  test('assessTokenPressure reports warning and critical states', () {
    final warning = ConversationCompactionService.assessTokenPressure(
      messages: [
        Message(
          id: 'warning',
          content: repeatedText(20000),
          role: MessageRole.user,
          timestamp: DateTime(2026, 4, 18),
        ),
      ],
    );
    final critical = ConversationCompactionService.assessTokenPressure(
      messages: [
        Message(
          id: 'critical',
          content: repeatedText(26000),
          role: MessageRole.user,
          timestamp: DateTime(2026, 4, 18),
        ),
      ],
    );

    expect(warning.level, ConversationTokenPressureLevel.warning);
    expect(critical.level, ConversationTokenPressureLevel.critical);
  });

  test('estimatePromptTokens includes image attachment cost', () {
    final estimatedTokens = ConversationCompactionService.estimatePromptTokens([
      Message(
        id: 'image',
        content: '',
        role: MessageRole.user,
        timestamp: DateTime(2026, 6, 5),
        imageBase64: 'A' * 4096,
        imageMimeType: 'image/png',
      ),
    ]);

    expect(
      estimatedTokens,
      greaterThanOrEqualTo(
        ConversationCompactionService.imageAttachmentTokenFloor,
      ),
    );
  });

  test('isContextLengthError detects prompt-too-long failures', () {
    expect(
      ConversationCompactionService.isContextLengthError(
        'This model has a maximum context length of 8192 tokens.',
      ),
      isTrue,
    );
    expect(
      ConversationCompactionService.isContextLengthError('Network timeout'),
      isFalse,
    );
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
      contains(
        'Assistant executed tool calls and returned structured results.',
      ),
    );
  });

  test('buildArtifact summarizes rendered tool results before compaction', () {
    final messages = buildMessages(16).toList();
    messages[0] = Message(
      id: 'tool-result',
      content:
          '[Tool: local_execute_command]\n'
          'Arguments: {"command":"flutter test"}\n'
          'Result:\n'
          '{"exit_code":0,"stdout":"all tests passed"}',
      role: MessageRole.user,
      timestamp: DateTime(2026, 7, 21),
    );

    final artifact = ConversationCompactionService.buildArtifact(
      messages: messages,
    );

    expect(artifact, isNotNull);
    expect(
      artifact!.normalizedSummary,
      contains('`flutter test` -> exit 0, 1 output lines'),
    );
    expect(artifact.normalizedSummary, isNot(contains('all tests passed')));
  });
}
