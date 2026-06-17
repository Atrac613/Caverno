import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/key_value_store.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';

/// In-memory [KeyValueStore] for repository logic tests.
class _MapKeyValueStore implements KeyValueStore {
  final Map<String, String> data = <String, String>{};

  @override
  bool get isReady => true;

  @override
  String? get(String key) => data[key];

  @override
  Future<void> put(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  late _MapKeyValueStore store;
  late ChatMemoryRepository repository;

  setUp(() {
    store = _MapKeyValueStore();
    repository = ChatMemoryRepository(store);
  });

  test(
    'upsertReviewQueue can add the first item into an empty queue',
    () async {
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

      final stored =
          jsonDecode(store.data['memory_review_queue']!) as List<dynamic>;
      expect(stored, hasLength(1));
      expect(
        (stored.single as Map<String, dynamic>)['text'],
        'Remember concise code review summaries.',
      );
    },
  );

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
          jsonDecode(store.data['memory_suppression_rules']!) as List<dynamic>;
      expect(stored, hasLength(1));
      expect(
        (stored.single as Map<String, dynamic>)['textPattern'],
        'release note summaries',
      );
    },
  );
}
