import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/conversation_search_tool.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';

Conversation _conversation(
  String id, {
  required String title,
  required List<({MessageRole role, String content})> messages,
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  return Conversation(
    id: id,
    title: title,
    messages: [
      for (var i = 0; i < messages.length; i += 1)
        Message(
          id: '$id-$i',
          content: messages[i].content,
          role: messages[i].role,
          timestamp: now,
        ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  const tool = ConversationSearchTool();

  final conversations = [
    _conversation(
      'a',
      title: 'Flutter routing',
      messages: const [
        (role: MessageRole.user, content: 'How do I set up go_router?'),
        (role: MessageRole.assistant, content: 'Use GoRouter with routes.'),
      ],
    ),
    _conversation(
      'b',
      title: 'Coffee',
      messages: const [
        (role: MessageRole.user, content: 'Best pour-over ratio?'),
        (role: MessageRole.assistant, content: 'Try 1:16 coffee to water.'),
      ],
    ),
  ];

  test(
    'keyword path returns matching conversations ranked by overlap',
    () async {
      final result = await tool.run(
        arguments: const {'query': 'go_router'},
        conversations: conversations,
      );
      expect(result, contains('Flutter routing'));
      expect(result, isNot(contains('Coffee')));
    },
  );

  test('returns an error for an empty query', () async {
    final result = await tool.run(
      arguments: const {'query': '   '},
      conversations: conversations,
    );
    expect(result, startsWith('Error:'));
  });

  test('reports no matches when nothing contains the keywords', () async {
    final result = await tool.run(
      arguments: const {'query': 'kubernetes'},
      conversations: conversations,
    );
    expect(result, contains('No matching conversations'));
  });

  test(
    'semantic ranker drives ordering and surfaces ranked ids first',
    () async {
      final result = await tool.run(
        arguments: const {'query': 'coffee'},
        conversations: conversations,
        // Force "b" first even though both are returned.
        semanticRanker: (query, topK) async => ['b', 'a'],
      );
      final bIndex = result.indexOf('Coffee');
      final aIndex = result.indexOf('Flutter routing');
      expect(bIndex, greaterThanOrEqualTo(0));
      expect(aIndex, greaterThanOrEqualTo(0));
      expect(bIndex, lessThan(aIndex));
    },
  );

  test(
    'falls back to keyword search when the ranker returns nothing',
    () async {
      var called = false;
      final result = await tool.run(
        arguments: const {'query': 'go_router'},
        conversations: conversations,
        semanticRanker: (query, topK) async {
          called = true;
          return const [];
        },
      );
      expect(called, isTrue);
      expect(result, contains('Flutter routing'));
    },
  );
}
