import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';

class _MockMemoryBox extends Mock implements Box<String> {}

class _InMemoryChatMemoryRepository extends ChatMemoryRepository {
  _InMemoryChatMemoryRepository() : super(_MockMemoryBox());

  UserMemoryProfile profile = UserMemoryProfile.empty();
  final List<MemorySessionSummary> summaries = [];
  final List<MemoryEntry> memories = [];
  final List<MemoryReviewItem> reviewQueue = [];
  final List<MemorySuppressionRule> suppressionRules = [];

  @override
  UserMemoryProfile loadProfile() => profile;

  @override
  Future<void> saveProfile(UserMemoryProfile profile) async {
    this.profile = profile;
  }

  @override
  List<MemorySessionSummary> loadSessionSummaries() => List.of(summaries);

  @override
  Future<void> upsertSessionSummary(
    MemorySessionSummary summary, {
    int maxItems = 20,
  }) async {
    summaries.removeWhere((item) => item.conversationId == summary.conversationId);
    summaries.add(summary);
  }

  @override
  List<MemoryEntry> loadMemories() => List.of(memories);

  @override
  Future<MemoryUpsertResult> addOrUpdateMemories(
    List<MemoryEntry> entries, {
    int maxItems = 300,
  }) async {
    var addedCount = 0;
    var updatedCount = 0;
    for (final entry in entries) {
      final index = memories.indexWhere((item) => item.text == entry.text);
      if (index >= 0) {
        memories[index] = entry;
        updatedCount++;
      } else {
        memories.add(entry);
        addedCount++;
      }
    }
    return MemoryUpsertResult(
      addedCount: addedCount,
      updatedCount: updatedCount,
    );
  }

  @override
  Future<void> deleteMemoryEntry(String id) async {
    memories.removeWhere((item) => item.id == id);
  }

  @override
  List<MemoryReviewItem> loadReviewQueue() => List.of(reviewQueue);

  @override
  Future<void> upsertReviewQueue(
    List<MemoryReviewItem> items, {
    int maxItems = 100,
  }) async {
    for (final item in items) {
      reviewQueue.removeWhere((existing) => existing.text == item.text);
      reviewQueue.add(item);
    }
  }

  @override
  Future<void> removeReviewQueueItem(String id) async {
    reviewQueue.removeWhere((item) => item.id == id);
  }

  @override
  List<MemorySuppressionRule> loadSuppressionRules() =>
      List.of(suppressionRules);

  @override
  Future<void> addSuppressionRule(
    MemorySuppressionRule rule, {
    int maxItems = 200,
  }) async {
    suppressionRules.removeWhere(
      (item) => item.normalizedPattern == rule.normalizedPattern,
    );
    suppressionRules.add(rule);
  }
}

void main() {
  test('queues low-confidence memories for review and stores stable memories directly', () async {
    final repository = _InMemoryChatMemoryRepository();
    final service = SessionMemoryService(repository);

    final result = await service.updateFromConversation(
      conversationId: 'conversation-1',
      messages: [
        Message(
          id: 'message-1',
          content: 'Remember that I prefer concise code review summaries.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 4, 18, 10, 0),
        ),
      ],
      draft: const MemoryExtractionDraft(
        summary: 'User discussed code review preferences.',
        openLoops: [],
        persona: [],
        preferences: [],
        doNot: [],
        entries: [
          MemoryDraftEntry(
            text: 'The user prefers concise code review summaries.',
            type: 'preference',
            confidence: 0.92,
            importance: 0.9,
          ),
          MemoryDraftEntry(
            text: 'The user may care about short release note summaries.',
            type: 'topic',
            confidence: 0.45,
            importance: 0.4,
          ),
        ],
      ),
    );

    expect(result.addedMemoryCount, 1);
    expect(result.queuedReviewCount, 1);
    expect(repository.memories, hasLength(1));
    expect(repository.reviewQueue, hasLength(1));
    expect(
      repository.memories.single.text,
      'The user prefers concise code review summaries.',
    );
  });
}
