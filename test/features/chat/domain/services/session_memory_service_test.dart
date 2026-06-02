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

  test('drops one-off lookup and artifact facts from LLM draft memories', () async {
    final repository = _InMemoryChatMemoryRepository();
    final service = SessionMemoryService(repository);

    final result = await service.updateFromConversation(
      conversationId: 'conversation-weather',
      messages: [
        Message(
          id: 'message-weather-user',
          content:
              'Create a Tokyo weather report for 2026-06-03 and save it as Markdown.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 6, 2, 12, 9),
        ),
        Message(
          id: 'message-weather-assistant',
          content:
              'Saved the report to /Users/example/tmp/tokyo_weather_2026-06-03.md. The forecast is Heavy Rain.',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 6, 2, 12, 10),
        ),
      ],
      draft: const MemoryExtractionDraft(
        summary:
            'Retrieved Tokyo weather and saved the Markdown report for the user.',
        openLoops: [],
        persona: [],
        preferences: [],
        doNot: [],
        entries: [
          MemoryDraftEntry(
            text:
                'Tokyo weather on 2026-06-03: Heavy Rain, Max 19.7C, Min 16.4C, Precipitation Probability 87%, Max Wind Speed 19.5 km/h.',
            type: 'fact',
            confidence: 1.0,
            importance: 0.9,
            ttlDays: 365,
          ),
          MemoryDraftEntry(
            text:
                'Weather report for Tokyo on 2026-06-03 saved to /Users/example/tmp/tokyo_weather_2026-06-03.md.',
            type: 'fact',
            confidence: 1.0,
            importance: 0.8,
            ttlDays: 365,
          ),
          MemoryDraftEntry(
            text:
                'Tokyo weather forecast for 2026-06-03: Heavy Rain, 16.5°C-19.7°C, 210.7mm precipitation, max wind 19.9 km/h.',
            type: 'fact',
            confidence: 0.95,
            importance: 0.8,
            ttlDays: 1,
          ),
        ],
      ),
    );

    expect(result.addedMemoryCount, 0);
    expect(result.queuedReviewCount, 0);
    expect(repository.memories, isEmpty);
    expect(repository.reviewQueue, isEmpty);
    expect(repository.summaries.single.summary, contains('Tokyo weather'));
  });

  test(
    'keeps lookup-like facts when the user explicitly asks to remember them',
    () async {
      final repository = _InMemoryChatMemoryRepository();
      final service = SessionMemoryService(repository);

      final result = await service.updateFromConversation(
        conversationId: 'conversation-remember-weather',
        messages: [
          Message(
            id: 'message-remember-user',
            content:
                'Remember that Tokyo weather on 2026-06-03 was Heavy Rain.',
            role: MessageRole.user,
            timestamp: DateTime(2026, 6, 2, 12, 9),
          ),
        ],
        draft: const MemoryExtractionDraft(
          summary: 'User explicitly asked to remember a weather fact.',
          openLoops: [],
          persona: [],
          preferences: [],
          doNot: [],
          entries: [
            MemoryDraftEntry(
              text: 'Tokyo weather on 2026-06-03 was Heavy Rain.',
              type: 'fact',
              confidence: 0.95,
              importance: 0.9,
            ),
          ],
        ),
      );

      expect(result.addedMemoryCount, 1);
      expect(repository.memories.single.text, contains('Heavy Rain'));
    },
  );

  test('deduplicates semantically similar profile draft updates', () async {
    final repository = _InMemoryChatMemoryRepository();
    repository.profile = UserMemoryProfile(
      persona: const [
        'Prefers automatic progression to the next pending task unless blockers occur',
        'Prefers automatic progression to next pending task unless blockers occur',
      ],
      preferences: const [
        'Prefers implementation plans with actionable tasks and validation steps',
      ],
      doNot: const [
        'Do not ask for redundant natural language permission for file changes',
        'Do not ask for redundant natural language permission for file changes or command execution once approved',
      ],
      updatedAt: DateTime(2026, 6, 2, 10),
    );
    final service = SessionMemoryService(repository);

    final result = await service.updateFromConversation(
      conversationId: 'conversation-profile-dedupe',
      messages: [
        Message(
          id: 'message-profile-user',
          content: 'Update the remembered coding workflow preferences.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 6, 2, 12),
        ),
      ],
      now: DateTime(2026, 6, 2, 12, 1),
      draft: const MemoryExtractionDraft(
        summary: 'User continued a coding workflow preference discussion.',
        openLoops: [],
        persona: [
          'Prefers automatic progression to the next pending task unless blockers or changes occur',
        ],
        preferences: [
          'Prefers implementation plans with actionable tasks, target files, and validation steps',
        ],
        doNot: [
          'Do not ask for redundant natural language permission for file changes or command executions once approved',
        ],
        entries: [],
      ),
    );

    expect(result.profileUpdated, isTrue);
    expect(repository.profile.persona, hasLength(1));
    expect(
      repository.profile.persona.single,
      'Prefers automatic progression to the next pending task unless blockers or changes occur',
    );
    expect(repository.profile.preferences, hasLength(1));
    expect(
      repository.profile.preferences.single,
      'Prefers implementation plans with actionable tasks, target files, and validation steps',
    );
    expect(repository.profile.doNot, hasLength(1));
    expect(
      repository.profile.doNot.single,
      'Do not ask for redundant natural language permission for file changes or command executions once approved',
    );
  });

  test('deduplicates token-subset profile draft updates', () async {
    final repository = _InMemoryChatMemoryRepository();
    repository.profile = UserMemoryProfile(
      persona: const [
        'Prefers implementation plans with actionable tasks, target files, and validation steps',
        'Prefers actionable implementation plans with validation steps',
        'Developer working on Flutter BLE applications',
      ],
      preferences: const [
        'Starts with high-value tasks and explains small change policies before implementation',
        'Starts with high-value tasks',
      ],
      doNot: const [],
      updatedAt: DateTime(2026, 6, 2, 10),
    );
    final service = SessionMemoryService(repository);

    final result = await service.updateFromConversation(
      conversationId: 'conversation-profile-token-subset',
      messages: [
        Message(
          id: 'message-profile-token-subset-user',
          content: 'Update the remembered coding workflow preferences.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 6, 2, 12),
        ),
      ],
      draft: const MemoryExtractionDraft(
        summary: 'User continued a coding workflow preference discussion.',
        openLoops: [],
        persona: [
          'Prefers implementation plans with actionable tasks, target files, and validation steps',
        ],
        preferences: [
          'Starts with high-value tasks and explains small change policies before implementation',
        ],
        doNot: [],
        entries: [],
      ),
    );

    expect(result.profileUpdated, isTrue);
    expect(repository.profile.persona, [
      'Prefers implementation plans with actionable tasks, target files, and validation steps',
      'Developer working on Flutter BLE applications',
    ]);
    expect(repository.profile.preferences, [
      'Starts with high-value tasks and explains small change policies before implementation',
    ]);
  });

  test('deduplicates stored profile before prompt context injection', () {
    final repository = _InMemoryChatMemoryRepository();
    repository.profile = UserMemoryProfile(
      persona: const [
        'Prefers automatic progression to the next pending task unless blockers or changes occur',
        'Treats file/command execution approvals as sufficient permission without needing redundant natural and language confirmation',
        'Prefers implementation plans with actionable tasks, target files, and validation steps',
        'Developer working on Flutter BLE applications',
        'Prefers actionable implementation plans with validation steps',
        'Treats file/command execution approvals as sufficient permission without redundant confirmation',
      ],
      preferences: const [
        'Prefers starting with high-value tasks and explaining small change policies before implementation',
        'Wants review of work against acceptance criteria to call/call out gaps, risks, or missing validation first',
        "Uses specific 'saved workflow' for coding threads",
        'Starts with high-value tasks and explains small change policies',
        'Starts with high-value tasks',
        'Prefers automatic progression to next pending task unless blockers occur',
        'Prefers implementation plans with actionable tasks, target files, and validation steps',
        'Treats file/command execution approvals as sufficient permission without redundant confirmation',
      ],
      doNot: const [
        'Do not ask for redundant natural language permission for file changes or command executions once approved',
      ],
      updatedAt: DateTime(2026, 6, 2, 10),
    );
    final service = SessionMemoryService(repository);

    final loadedProfile = service.loadProfile();
    expect(loadedProfile.persona, [
      'Prefers automatic progression to the next pending task unless blockers or changes occur',
      'Treats file/command execution approvals as sufficient permission without needing redundant natural and language confirmation',
      'Prefers implementation plans with actionable tasks, target files, and validation steps',
      'Developer working on Flutter BLE applications',
    ]);
    expect(loadedProfile.preferences, [
      'Prefers starting with high-value tasks and explaining small change policies before implementation',
      'Wants review of work against acceptance criteria to call/call out gaps, risks, or missing validation first',
      "Uses specific 'saved workflow' for coding threads",
    ]);
    expect(loadedProfile.doNot, [
      'Do not ask for redundant natural language permission for file changes or command executions once approved',
    ]);

    final context = service.buildPromptContext(
      currentUserInput: 'Continue the coding workflow from the previous task.',
      currentConversationId: 'current-conversation',
      now: DateTime(2026, 6, 2, 12),
    );

    expect(context, isNotNull);
    expect(
      RegExp('Prefers automatic progression').allMatches(context!).length,
      1,
    );
    expect(RegExp('implementation plans').allMatches(context).length, 1);
    expect(RegExp('high-value tasks').allMatches(context).length, 1);
    expect(
      RegExp('file/command execution approvals').allMatches(context).length,
      1,
    );
    expect(repository.profile.persona, hasLength(6));
    expect(repository.profile.preferences, hasLength(8));
  });

  test('keeps distinct profile draft preferences', () async {
    final repository = _InMemoryChatMemoryRepository();
    repository.profile = UserMemoryProfile(
      persona: const [],
      preferences: const ['Prefers concise answers'],
      doNot: const [],
      updatedAt: DateTime(2026, 6, 2, 10),
    );
    final service = SessionMemoryService(repository);

    await service.updateFromConversation(
      conversationId: 'conversation-profile-distinct',
      messages: [
        Message(
          id: 'message-distinct-user',
          content: 'Remember another response style preference.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 6, 2, 12),
        ),
      ],
      draft: const MemoryExtractionDraft(
        summary: 'User described another response style preference.',
        openLoops: [],
        persona: [],
        preferences: ['Prefers detailed implementation plans'],
        doNot: [],
        entries: [],
      ),
    );

    expect(repository.profile.preferences, [
      'Prefers concise answers',
      'Prefers detailed implementation plans',
    ]);
  });

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
