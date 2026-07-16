import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_mutation_coordinator.dart';
import 'package:caverno/features/chat/data/repositories/key_value_store.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';

/// In-memory [KeyValueStore] for repository logic tests.
class _MapKeyValueStore implements KeyValueStore {
  final Map<String, String> data = <String, String>{};
  var refreshCount = 0;

  @override
  bool get isReady => true;

  @override
  String? get(String key) => data[key];

  @override
  Future<void> refresh(Iterable<String> keys) async {
    refreshCount += 1;
  }

  @override
  Future<void> put(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

class _CountingMutationCoordinator implements ChatMemoryMutationCoordinator {
  var runCount = 0;

  @override
  Future<T> run<T>(Future<T> Function() mutation) {
    runCount += 1;
    return mutation();
  }
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

  test('nested mutations share one refresh-and-merge boundary', () async {
    final coordinator = _CountingMutationCoordinator();
    repository = ChatMemoryRepository(store, mutationCoordinator: coordinator);

    await repository.runAtomicMutation<void>(() async {
      await repository.upsertSessionSummary(
        MemorySessionSummary(
          conversationId: 'conversation-1',
          summary: 'First summary',
          openLoops: const <String>[],
          updatedAt: DateTime.utc(2026, 7, 16, 6),
        ),
      );
      await repository.incrementSuppressionHitCount(2);
    });

    expect(coordinator.runCount, 1);
    expect(store.refreshCount, 1);
    expect(repository.loadSessionSummaries(), hasLength(1));
    expect(repository.loadSuppressionHitCount(), 2);
  });
}
