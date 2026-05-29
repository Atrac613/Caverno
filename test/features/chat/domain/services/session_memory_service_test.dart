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
  int suppressionHitCount = 0;

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
    summaries.removeWhere(
      (item) => item.conversationId == summary.conversationId,
    );
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

  @override
  int loadSuppressionHitCount() => suppressionHitCount;

  @override
  Future<void> incrementSuppressionHitCount(int count) async {
    suppressionHitCount += count;
  }
}

void main() {
  test(
    'queues low-confidence memories for review and stores stable memories directly',
    () async {
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
    },
  );

  test(
    'tracks suppression hits and preserves source ids in memory artifacts',
    () async {
      final repository = _InMemoryChatMemoryRepository();
      final service = SessionMemoryService(repository);
      await repository.addSuppressionRule(
        MemorySuppressionRule(
          id: 'rule-1',
          textPattern: 'release note summaries',
          createdAt: DateTime(2026, 4, 18, 10, 45),
        ),
      );

      final result = await service.updateFromConversation(
        conversationId: 'conversation-2',
        messages: [
          Message(
            id: 'message-2',
            content: 'Remember both my review and release note preferences.',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 18, 11, 0),
          ),
        ],
        draft: const MemoryExtractionDraft(
          summary: 'The user described review and release note preferences.',
          openLoops: [],
          persona: [],
          preferences: [],
          doNot: [],
          entries: [
            MemoryDraftEntry(
              text: 'The user prefers concise code review summaries.',
              type: 'preference',
              confidence: 0.9,
              importance: 0.8,
            ),
            MemoryDraftEntry(
              text: 'The user prefers short release note summaries.',
              type: 'preference',
              confidence: 0.86,
              importance: 0.6,
            ),
            MemoryDraftEntry(
              text: 'The user may want changelog links included.',
              type: 'topic',
              confidence: 0.42,
              importance: 0.3,
            ),
          ],
        ),
      );

      final snapshot = service.loadSnapshot();

      expect(result.addedMemoryCount, 1);
      expect(result.queuedReviewCount, 1);
      expect(result.suppressedCandidateCount, 1);
      expect(snapshot.suppressionHitCount, 1);
      expect(repository.memories.single.sourceConversationId, 'conversation-2');
      expect(
        repository.reviewQueue.single.sourceConversationId,
        'conversation-2',
      );
    },
  );

  test('drops draft open loops covered by the latest assistant answer', () async {
    final repository = _InMemoryChatMemoryRepository();
    final service = SessionMemoryService(repository);

    await service.updateFromConversation(
      conversationId: 'conversation-3',
      messages: [
        Message(
          id: 'message-3',
          content:
              'Investigate session log e42da492-acc6-419e-9c6f-66dcb82ba13d.jsonl and identify why the LLM conversation stopped.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 5, 28, 0, 42),
        ),
        Message(
          id: 'message-4',
          content:
              'Session log e42da492-acc6-419e-9c6f-66dcb82ba13d.jsonl analysis results: the final response completed normally with finishReason stop.',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 5, 28, 0, 49),
        ),
      ],
      draft: const MemoryExtractionDraft(
        summary: 'User investigated a session log interruption.',
        openLoops: [
          'Identify specific reason for conversation interruption in session log e42da492-acc6-419e-9c6f-66dcb82ba13d.jsonl',
        ],
        persona: [],
        preferences: [],
        doNot: [],
        entries: [],
      ),
    );

    expect(repository.summaries.single.openLoops, isEmpty);
  });

  test('drops generic log interruption loops after a concrete answer', () async {
    final repository = _InMemoryChatMemoryRepository();
    final service = SessionMemoryService(repository);

    await service.updateFromConversation(
      conversationId: 'conversation-4',
      messages: [
        Message(
          id: 'message-5',
          content:
              'Investigate the coding session log and identify why the LLM conversation stopped.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 5, 28, 14, 54),
        ),
        Message(
          id: 'message-6',
          content:
              'Conclusion: the verified trigger is an incomplete `<tool_call>` emitted near Entry 16. The log contains no transport error, so server timeout remains unverified.',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 5, 28, 15, 2),
        ),
      ],
      draft: const MemoryExtractionDraft(
        summary: 'User investigated a coding session log interruption.',
        openLoops: [
          'Identify the specific root cause of the conversation interruption based on analyzed entries.',
        ],
        persona: [],
        preferences: [],
        doNot: [],
        entries: [],
      ),
    );

    expect(repository.summaries.single.openLoops, isEmpty);
  });

  test('labels recent summaries as historical context', () {
    final repository = _InMemoryChatMemoryRepository();
    repository.summaries.add(
      MemorySessionSummary(
        conversationId: 'previous-conversation',
        summary:
            'Investigation identified native byte processing as the root cause.',
        openLoops: const ['Verify Android native implementation'],
        updatedAt: DateTime(2026, 5, 28, 12),
      ),
    );
    final service = SessionMemoryService(repository);

    final context = service.buildPromptContext(
      currentUserInput:
          'Continue from the previous Android BLE data investigation.',
      currentConversationId: 'current-conversation',
      now: DateTime(2026, 5, 28, 13),
    );

    expect(context, isNotNull);
    expect(context!, contains('[Recent Session Summaries]'));
    expect(context, contains('historical context from prior turns'));
    expect(context, contains('prior assistant hypotheses'));
    expect(context, contains('verify them against the current request'));
    expect(
      context,
      contains(
        'Investigation identified native byte processing as the root cause.',
      ),
    );
  });

  test('omits task memories for prompts without explicit history reference', () {
    final repository = _InMemoryChatMemoryRepository();
    repository.profile = UserMemoryProfile(
      persona: const [],
      preferences: const ['The user prefers concise answers.'],
      doNot: const [],
      updatedAt: DateTime(2026, 5, 28, 12),
    );
    repository.summaries.add(
      MemorySessionSummary(
        conversationId: 'previous-conversation',
        summary:
            'Investigated EulaAgreementPreferenceProvider Riverpod wiring.',
        openLoops: const ['Choose a SettingsNotifier refactor direction'],
        updatedAt: DateTime(2026, 5, 28, 12),
      ),
    );
    repository.memories.add(
      MemoryEntry(
        id: 'memory-1',
        text: 'The prior session discussed EULA agreement preferences.',
        type: MemoryEntryType.topic,
        confidence: 0.9,
        importance: 0.9,
        updatedAt: DateTime(2026, 5, 28, 12),
        sourceConversationId: 'previous-conversation',
      ),
    );
    final service = SessionMemoryService(repository);

    final context = service.buildPromptContext(
      currentUserInput:
          'Before you continue, call the ask_user_question tool exactly once.',
      currentConversationId: 'current-conversation',
      now: DateTime(2026, 5, 28, 13),
    );

    expect(context, isNotNull);
    expect(context, contains('[Known User Profile]'));
    expect(context, isNot(contains('[Recent Session Summaries]')));
    expect(context, isNot(contains('[Retrieved Memories]')));
    expect(context, isNot(contains('EulaAgreementPreferenceProvider')));
  });
}
