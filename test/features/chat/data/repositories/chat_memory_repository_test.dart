import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';

class _MockMemoryBox extends Mock implements Box<String> {}

void main() {
  late _MockMemoryBox box;
  late Map<String, String> store;
  late ChatMemoryRepository repository;

  setUp(() {
    box = _MockMemoryBox();
    store = <String, String>{};
    repository = ChatMemoryRepository(box);

    when(() => box.isOpen).thenReturn(true);
    when(() => box.get(any())).thenAnswer((invocation) {
      final key = invocation.positionalArguments[0] as String;
      return store[key];
    });
    when(() => box.put(any(), any())).thenAnswer((invocation) async {
      final key = invocation.positionalArguments[0] as String;
      final value = invocation.positionalArguments[1] as String;
      store[key] = value;
    });
    when(() => box.delete(any())).thenAnswer((invocation) async {
      final key = invocation.positionalArguments[0] as String;
      store.remove(key);
    });
  });

  test('upsertReviewQueue can add the first item into an empty queue', () async {
    await repository.upsertReviewQueue([
      MemoryReviewItem(
        id: 'review-1',
        text: 'Remember concise code review summaries.',
        type: MemoryEntryType.preference,
        confidence: 0.4,
        importance: 0.5,
        createdAt: DateTime(2026, 4, 18, 12, 0),
        sourceConversationId: 'conversation-1',
      ),
    ]);

    final stored = jsonDecode(store['memory_review_queue']!) as List<dynamic>;
    expect(stored, hasLength(1));
    expect(
      (stored.single as Map<String, dynamic>)['text'],
      'Remember concise code review summaries.',
    );
  });

  test(
    'addSuppressionRule can add the first rule into an empty collection',
    () async {
      await repository.addSuppressionRule(
        MemorySuppressionRule(
          id: 'rule-1',
          textPattern: 'release note summaries',
          createdAt: DateTime(2026, 4, 18, 12, 5),
        ),
      );

      final stored =
          jsonDecode(store['memory_suppression_rules']!) as List<dynamic>;
      expect(stored, hasLength(1));
      expect(
        (stored.single as Map<String, dynamic>)['textPattern'],
        'release note summaries',
      );
    },
  );
}
