import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_compaction_artifact.dart';
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

  String renderedToolResult(String path, int payloadLength) {
    return '[Tool: read_file]\n'
        'Arguments: {"path":"$path"}\n'
        'Result:\n'
        '{"path":"$path","content":"${repeatedText(payloadLength)}"}';
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

  test('message-count floor behaves unchanged even when forced', () {
    final messages = buildMessages(
      ConversationCompactionService.recentMessagesToKeep,
    );

    final artifact = ConversationCompactionService.buildArtifact(
      messages: messages,
      force: true,
    );
    final retained = ConversationCompactionService.retainMessages(
      messages: messages,
      artifact: artifact,
    );

    expect(artifact, isNull);
    expect(retained, orderedEquals(messages));
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

  test('retained tail degrades older tool results beyond the token budget', () {
    final messages = buildMessages(16).toList();
    for (var index = 8; index < messages.length; index++) {
      messages[index] = messages[index].copyWith(
        content: renderedToolResult('lib/file_$index.dart', 1200),
      );
    }

    final artifact = ConversationCompactionService.buildArtifact(
      messages: messages,
    );
    final retained = ConversationCompactionService.retainMessages(
      messages: messages,
      artifact: artifact,
    );

    expect(artifact, isNotNull);
    expect(retained, hasLength(8));
    expect(
      ConversationCompactionService.estimatePromptTokens(retained),
      lessThan(
        ConversationCompactionService.estimatePromptTokens(messages.sublist(8)),
      ),
    );
    expect(retained.first.content, contains('[read_file]'));
    expect(retained.first.content, isNot(contains(repeatedText(1200))));
    expect(retained.last.content, messages.last.content);
    expect(
      retained.map((message) => message.id),
      orderedEquals(messages.sublist(8).map((message) => message.id)),
    );
    expect(
      retained.map((message) => message.role),
      orderedEquals(messages.sublist(8).map((message) => message.role)),
    );
    expect(
      retained.map((message) => Message.fromJson(message.toJson())),
      orderedEquals(retained),
    );
  });

  test('single oversized tool result remains degraded and nonempty', () {
    final messages = buildMessages(16).toList();
    messages[15] = messages[15].copyWith(
      content: renderedToolResult('lib/oversized.dart', 12000),
    );

    final artifact = ConversationCompactionService.buildArtifact(
      messages: messages,
    );
    final retained = ConversationCompactionService.retainMessages(
      messages: messages,
      artifact: artifact,
    );

    expect(artifact, isNotNull);
    expect(retained, hasLength(8));
    expect(retained.last.id, messages.last.id);
    expect(retained.last.content, isNotEmpty);
    expect(retained.last.content, contains('[read_file]'));
    expect(retained.last.content, isNot(contains(repeatedText(12000))));
  });

  test('ordinary prose beyond the tail budget remains verbatim', () {
    final messages = buildMessages(16).toList();
    for (var index = 8; index < messages.length; index++) {
      messages[index] = messages[index].copyWith(
        content: 'Prose turn $index ${repeatedText(1600)}',
      );
    }

    final artifact = ConversationCompactionService.buildArtifact(
      messages: messages,
    );
    final retained = ConversationCompactionService.retainMessages(
      messages: messages,
      artifact: artifact,
    );

    expect(artifact, isNotNull);
    expect(retained, orderedEquals(messages.sublist(8)));
    expect(artifact!.retainedMessageContentOverrides, isEmpty);
  });

  test('malformed tool results beyond the budget remain verbatim', () {
    final messages = buildMessages(16).toList();
    for (var index = 8; index < messages.length; index++) {
      messages[index] = messages[index].copyWith(
        content:
            '[Tool: read_file]\n'
            'Arguments: {"path":"lib/file_$index.dart"}\n'
            'Malformed payload ${repeatedText(1600)}',
      );
    }

    final artifact = ConversationCompactionService.buildArtifact(
      messages: messages,
    );
    final retained = ConversationCompactionService.retainMessages(
      messages: messages,
      artifact: artifact,
    );

    expect(artifact, isNotNull);
    expect(retained, orderedEquals(messages.sublist(8)));
    expect(artifact!.retainedMessageContentOverrides, isEmpty);
  });

  test('compaction artifact round-trips retained content overrides', () {
    final artifact = ConversationCompactionArtifact(
      version: ConversationCompactionService.artifactVersion,
      summary: 'Earlier context',
      sourceMessageCount: 16,
      compactedMessageCount: 8,
      retainedMessageCount: 8,
      retainedMessageContentOverrides: const {
        'message-8': '[read_file] lib/app.dart -> 120 content chars',
      },
      estimatedPromptTokens: 6400,
      updatedAt: DateTime(2026, 7, 21),
    );

    final restored = ConversationCompactionArtifact.fromJson(artifact.toJson());

    expect(restored, artifact);
  });

  test('legacy compaction artifacts deserialize without overrides', () {
    final restored = ConversationCompactionArtifact.fromJson({
      'version': 2,
      'summary': 'Earlier context',
      'sourceMessageCount': 16,
      'compactedMessageCount': 8,
      'retainedMessageCount': 8,
      'estimatedPromptTokens': 6400,
      'updatedAt': '2026-07-21T00:00:00.000',
    });

    expect(restored.version, 2);
    expect(restored.retainedMessageContentOverrides, isEmpty);
  });
}
