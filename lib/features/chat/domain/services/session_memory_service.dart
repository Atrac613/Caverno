import 'package:uuid/uuid.dart';

import '../../data/repositories/chat_memory_repository.dart';
import '../entities/message.dart';
import '../entities/session_memory.dart';

enum MemoryGenerationMethod { ruleBased, llm }

class MemoryDraftEntry {
  const MemoryDraftEntry({
    required this.text,
    required this.type,
    required this.confidence,
    required this.importance,
    this.ttlDays,
  });

  final String text;
  final String type;
  final double confidence;
  final double importance;
  final int? ttlDays;
}

class MemoryExtractionDraft {
  const MemoryExtractionDraft({
    required this.summary,
    required this.openLoops,
    required this.persona,
    required this.preferences,
    required this.doNot,
    required this.entries,
  });

  final String summary;
  final List<String> openLoops;
  final List<String> persona;
  final List<String> preferences;
  final List<String> doNot;
  final List<MemoryDraftEntry> entries;

  bool get hasProfileUpdate =>
      persona.isNotEmpty || preferences.isNotEmpty || doNot.isNotEmpty;

  bool get isEmpty =>
      summary.trim().isEmpty &&
      openLoops.isEmpty &&
      !hasProfileUpdate &&
      entries.isEmpty;
}

class SessionMemoryService {
  SessionMemoryService(this._repository);

  final ChatMemoryRepository _repository;
  final _uuid = const Uuid();

  String? buildPromptContext({
    required String currentUserInput,
    required String currentConversationId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final profile = _repository.loadProfile();
    final summaries = _repository
        .loadSessionSummaries()
        .where((summary) => summary.conversationId != currentConversationId)
        .take(3)
        .toList();

    final scored = _scoreMemories(
      currentUserInput: currentUserInput,
      currentConversationId: currentConversationId,
      now: timestamp,
    );
    final topMemories = scored.take(6).toList();

    if (profile.isEmpty && summaries.isEmpty && topMemories.isEmpty) {
      return null;
    }

    final buffer = StringBuffer();
    if (!profile.isEmpty) {
      buffer.writeln('[Known User Profile]');
      for (final item in profile.persona) {
        buffer.writeln('- Persona: $item');
      }
      for (final item in profile.preferences) {
        buffer.writeln('- Preference: $item');
      }
      for (final item in profile.doNot) {
        buffer.writeln('- DoNot: $item');
      }
      buffer.writeln();
    }

    if (summaries.isNotEmpty) {
      buffer.writeln('[Recent Session Summaries]');
      for (final summary in summaries) {
        buffer.writeln('- ${summary.summary}');
        if (summary.openLoops.isNotEmpty) {
          for (final loop in summary.openLoops.take(2)) {
            buffer.writeln('  - Open loop: $loop');
          }
        }
      }
      buffer.writeln();
    }

    if (topMemories.isNotEmpty) {
      buffer.writeln('[Retrieved Memories]');
      for (final scoredMemory in topMemories) {
        final label = scoredMemory.score >= 0.75
            ? 'high'
            : scoredMemory.score >= 0.5
            ? 'medium'
            : 'low/hypothesis';
        buffer.writeln('- ($label) ${scoredMemory.memory.text}');
      }
    }

    return buffer.toString().trim();
  }

  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
  }) async {
    final timestamp = now ?? DateTime.now();
    final normalizedMessages = messages.where((m) => !m.isStreaming).toList();
    final userMessages = normalizedMessages.where((m) {
      return m.role == MessageRole.user && m.content.trim().isNotEmpty;
    }).toList();

    if (userMessages.isEmpty) return const MemoryUpdateResult.none();

    final summary = draft == null || draft.summary.trim().isEmpty
        ? _buildSessionSummary(
            conversationId: conversationId,
            messages: normalizedMessages,
            userMessages: userMessages,
            now: timestamp,
          )
        : MemorySessionSummary(
            conversationId: conversationId,
            summary: _truncate(_normalizeSentence(draft.summary), 160),
            openLoops: draft.openLoops
                .map(_normalizeSentence)
                .where((loop) => loop.isNotEmpty)
                .take(3)
                .map((loop) => _truncate(loop, 80))
                .toList(),
            updatedAt: timestamp,
          );
    await _repository.upsertSessionSummary(summary);
    var addedMemoryCount = 0;
    var updatedMemoryCount = 0;
    var profileUpdated = false;
    var generationMethod = MemoryGenerationMethod.ruleBased;

    final extracted = draft != null && draft.entries.isNotEmpty
        ? _buildMemoriesFromDraft(
            conversationId: conversationId,
            draft: draft,
            now: timestamp,
          )
        : _extractMemories(
            conversationId: conversationId,
            userMessages: userMessages,
            now: timestamp,
          );
    if (extracted.isNotEmpty) {
      if (draft != null) {
        generationMethod = MemoryGenerationMethod.llm;
      }
      final upsertResult = await _repository.addOrUpdateMemories(extracted);
      addedMemoryCount = upsertResult.addedCount;
      updatedMemoryCount = upsertResult.updatedCount;
      if (draft != null && draft.hasProfileUpdate) {
        profileUpdated = await _mergeProfileFromDraft(draft, timestamp);
      } else {
        profileUpdated = await _mergeProfile(extracted, timestamp);
      }
    } else if (draft != null && draft.hasProfileUpdate) {
      generationMethod = MemoryGenerationMethod.llm;
      profileUpdated = await _mergeProfileFromDraft(draft, timestamp);
    }

    return MemoryUpdateResult(
      summaryUpdated: true,
      addedMemoryCount: addedMemoryCount,
      updatedMemoryCount: updatedMemoryCount,
      profileUpdated: profileUpdated,
      generationMethod: generationMethod,
    );
  }

  Future<void> saveProfileFromText({
    required String personaText,
    required String preferencesText,
    required String doNotText,
    DateTime? now,
  }) async {
    final profile = UserMemoryProfile(
      persona: _splitLines(personaText),
      preferences: _splitLines(preferencesText),
      doNot: _splitLines(doNotText),
      updatedAt: now ?? DateTime.now(),
    );
    await _repository.saveProfile(profile);
  }

  Future<void> clearAll() {
    return _repository.clearAll();
  }

  UserMemoryProfile loadProfile() {
    return _repository.loadProfile();
  }

  MemorySnapshot loadSnapshot() {
    final profile = _repository.loadProfile();
    final summaries = _repository.loadSessionSummaries();
    final memories = _repository.loadMemories();
    DateTime? lastUpdatedAt = profile.isEmpty ? null : profile.updatedAt;

    for (final summary in summaries) {
      if (lastUpdatedAt == null || summary.updatedAt.isAfter(lastUpdatedAt)) {
        lastUpdatedAt = summary.updatedAt;
      }
    }
    for (final memory in memories) {
      if (lastUpdatedAt == null || memory.updatedAt.isAfter(lastUpdatedAt)) {
        lastUpdatedAt = memory.updatedAt;
      }
    }

    return MemorySnapshot(
      profile: profile,
      summaryCount: summaries.length,
      memoryCount: memories.length,
      lastUpdatedAt: lastUpdatedAt,
    );
  }

  List<_ScoredMemory> _scoreMemories({
    required String currentUserInput,
    required String currentConversationId,
    required DateTime now,
  }) {
    final query = currentUserInput.trim();
    if (query.isEmpty) return const [];

    final memories = _repository.loadMemories().where((memory) {
      return !memory.isExpired &&
          memory.sourceConversationId != currentConversationId;
    }).toList();

    final scored = memories
        .map((memory) {
          final similarity = _semanticSimilarity(query, memory.text);
          final recency = _recencyScore(memory.updatedAt, now);
          final importance = memory.importance.clamp(0.0, 1.0);
          final score = 0.55 * similarity + 0.25 * recency + 0.20 * importance;
          return _ScoredMemory(memory: memory, score: score);
        })
        .where((entry) {
          return entry.score >= 0.2;
        })
        .toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  MemorySessionSummary _buildSessionSummary({
    required String conversationId,
    required List<Message> messages,
    required List<Message> userMessages,
    required DateTime now,
  }) {
    final firstUser = _normalizeSentence(userMessages.first.content);
    final lastUser = _normalizeSentence(userMessages.last.content);
    final summary = firstUser == lastUser
        ? 'User topic: ${_truncate(firstUser, 80)}'
        : 'User topic: ${_truncate(firstUser, 60)} / Recent topic: ${_truncate(lastUser, 60)}';

    final openLoops = <String>[];
    final assistantMessages = messages.where((m) {
      return m.role == MessageRole.assistant && m.content.trim().isNotEmpty;
    }).toList();
    if (assistantMessages.isNotEmpty) {
      final lastAssistant = _normalizeSentence(assistantMessages.last.content);
      if (lastAssistant.contains('?') || lastAssistant.contains('？')) {
        openLoops.add(_truncate(lastAssistant, 80));
      }
    }

    return MemorySessionSummary(
      conversationId: conversationId,
      summary: summary,
      openLoops: openLoops,
      updatedAt: now,
    );
  }

  List<MemoryEntry> _extractMemories({
    required String conversationId,
    required List<Message> userMessages,
    required DateTime now,
  }) {
    final entries = <MemoryEntry>[];
    final seen = <String>{};
    final latestMessages = userMessages.length > 8
        ? userMessages.sublist(userMessages.length - 8)
        : userMessages;

    for (final message in latestMessages) {
      final text = _normalizeSentence(message.content);
      if (text.isEmpty) continue;

      if (_looksLikePreference(text)) {
        final memoryText = 'Response style preference: ${_truncate(text, 120)}';
        if (seen.add(memoryText)) {
          entries.add(
            MemoryEntry(
              id: _uuid.v4(),
              text: memoryText,
              type: MemoryEntryType.preference,
              confidence: 0.85,
              importance: 0.9,
              updatedAt: now,
              sourceConversationId: conversationId,
            ),
          );
        }
      }

      if (_looksLikePersona(text)) {
        final memoryText = 'User attribute: ${_truncate(text, 120)}';
        if (seen.add(memoryText)) {
          entries.add(
            MemoryEntry(
              id: _uuid.v4(),
              text: memoryText,
              type: MemoryEntryType.persona,
              confidence: 0.75,
              importance: 0.8,
              updatedAt: now,
              sourceConversationId: conversationId,
            ),
          );
        }
      }

      if (_looksLikeFact(text)) {
        final memoryText = 'Fact: ${_truncate(text, 280)}';
        if (seen.add(memoryText)) {
          entries.add(
            MemoryEntry(
              id: _uuid.v4(),
              text: memoryText,
              type: MemoryEntryType.fact,
              confidence: 0.8,
              importance: 0.85,
              updatedAt: now,
              sourceConversationId: conversationId,
            ),
          );
        }
      }
    }

    final firstTopic = _normalizeSentence(userMessages.first.content);
    final lastTopic = _normalizeSentence(userMessages.last.content);
    if (firstTopic.isNotEmpty) {
      entries.add(
        MemoryEntry(
          id: _uuid.v4(),
          text: 'Interest topic: ${_truncate(firstTopic, 120)}',
          type: MemoryEntryType.topic,
          confidence: 0.65,
          importance: 0.6,
          updatedAt: now,
          sourceConversationId: conversationId,
          expiresAt: now.add(const Duration(days: 90)),
        ),
      );
    }
    if (lastTopic.isNotEmpty && firstTopic != lastTopic) {
      entries.add(
        MemoryEntry(
          id: _uuid.v4(),
          text: 'Recent interest: ${_truncate(lastTopic, 120)}',
          type: MemoryEntryType.topic,
          confidence: 0.7,
          importance: 0.7,
          updatedAt: now,
          sourceConversationId: conversationId,
          expiresAt: now.add(const Duration(days: 90)),
        ),
      );
    }

    return entries;
  }

  List<MemoryEntry> _buildMemoriesFromDraft({
    required String conversationId,
    required MemoryExtractionDraft draft,
    required DateTime now,
  }) {
    final entries = <MemoryEntry>[];
    for (final entry in draft.entries) {
      final text = _normalizeSentence(entry.text);
      if (text.isEmpty) continue;

      final type = _parseMemoryEntryType(entry.type);
      final ttlDays = entry.ttlDays;
      DateTime? expiresAt;
      if (ttlDays != null && ttlDays > 0) {
        final safeDays = ttlDays.clamp(1, 365);
        expiresAt = now.add(Duration(days: safeDays));
      } else if (type == MemoryEntryType.topic) {
        expiresAt = now.add(const Duration(days: 90));
      }

      final maxLen = type == MemoryEntryType.fact ? 300 : 140;
      entries.add(
        MemoryEntry(
          id: _uuid.v4(),
          text: _truncate(text, maxLen),
          type: type,
          confidence: entry.confidence.clamp(0.0, 1.0),
          importance: entry.importance.clamp(0.0, 1.0),
          updatedAt: now,
          sourceConversationId: conversationId,
          expiresAt: expiresAt,
        ),
      );
    }
    return entries;
  }

  MemoryEntryType _parseMemoryEntryType(String rawType) {
    final normalized = rawType.trim().toLowerCase();
    switch (normalized) {
      case 'preference':
        return MemoryEntryType.preference;
      case 'persona':
        return MemoryEntryType.persona;
      case 'constraint':
        return MemoryEntryType.constraint;
      case 'fact':
        return MemoryEntryType.fact;
      case 'topic':
      default:
        return MemoryEntryType.topic;
    }
  }

  Future<bool> _mergeProfile(List<MemoryEntry> extracted, DateTime now) async {
    final current = _repository.loadProfile();
    final persona = <String>[...current.persona];
    final preferences = <String>[...current.preferences];
    var changed = false;

    for (final entry in extracted) {
      if (entry.type == MemoryEntryType.preference) {
        final line = _extractProfileText(entry.text, 'Response style preference:');
        if (line.isNotEmpty && !preferences.contains(line)) {
          preferences.add(line);
          changed = true;
        }
      } else if (entry.type == MemoryEntryType.persona) {
        final line = _extractProfileText(entry.text, 'User attribute:');
        if (line.isNotEmpty && !persona.contains(line)) {
          persona.add(line);
          changed = true;
        }
      }
    }

    if (!changed) return false;

    final nextProfile = current.copyWith(
      persona: _trimList(persona, 12),
      preferences: _trimList(preferences, 16),
      updatedAt: now,
    );
    await _repository.saveProfile(nextProfile);
    return true;
  }

  Future<bool> _mergeProfileFromDraft(
    MemoryExtractionDraft draft,
    DateTime now,
  ) async {
    final current = _repository.loadProfile();
    final persona = <String>[...current.persona];
    final preferences = <String>[...current.preferences];
    final doNot = <String>[...current.doNot];
    var changed = false;

    for (final item in draft.persona.map(_normalizeSentence)) {
      if (item.isNotEmpty && !persona.contains(item)) {
        persona.add(item);
        changed = true;
      }
    }
    for (final item in draft.preferences.map(_normalizeSentence)) {
      if (item.isNotEmpty && !preferences.contains(item)) {
        preferences.add(item);
        changed = true;
      }
    }
    for (final item in draft.doNot.map(_normalizeSentence)) {
      if (item.isNotEmpty && !doNot.contains(item)) {
        doNot.add(item);
        changed = true;
      }
    }

    if (!changed) return false;

    final nextProfile = current.copyWith(
      persona: _trimList(persona, 12),
      preferences: _trimList(preferences, 16),
      doNot: _trimList(doNot, 16),
      updatedAt: now,
    );
    await _repository.saveProfile(nextProfile);
    return true;
  }

  double _semanticSimilarity(String query, String text) {
    final queryTokens = _biGrams(query);
    final textTokens = _biGrams(text);
    if (queryTokens.isEmpty || textTokens.isEmpty) return 0;

    final intersection = queryTokens.intersection(textTokens).length;
    final union = queryTokens.union(textTokens).length;
    if (union == 0) return 0;
    return intersection / union;
  }

  double _recencyScore(DateTime updatedAt, DateTime now) {
    final ageDays = now.difference(updatedAt).inDays;
    if (ageDays <= 0) return 1.0;
    if (ageDays >= 90) return 0.0;
    return 1 - (ageDays / 90);
  }

  Set<String> _biGrams(String text) {
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return const {};
    if (normalized.length == 1) return {normalized};

    final grams = <String>{};
    for (var i = 0; i < normalized.length - 1; i++) {
      grams.add(normalized.substring(i, i + 2));
    }
    return grams;
  }

  bool _looksLikePreference(String text) {
    return RegExp(
      r'(短く|簡潔|要点|結論から|箇条書き|ステップ|コード|実装|サンプル|日本語|英語|丁寧|フランク|理由|根拠|詳しく)',
    ).hasMatch(text);
  }

  bool _looksLikePersona(String text) {
    return RegExp(r'(私は|ぼくは|僕は|仕事|職業|エンジニア|デザイナー|学生|PM|マネージャー)').hasMatch(text);
  }

  bool _looksLikeFact(String text) {
    return RegExp(
      r'(\d+円|\d+ドル|\$\d|\d+kg|\d+g|\d+ml|\d+リットル|\d+個|\d+枚|\d+本|\d+台|\d+回|買った|購入|契約|決めた|予約|申し込|登録|支払|paid|bought|purchased|cost|price|\d+\s*yen)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  List<String> _splitLines(String text) {
    return text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  List<String> _trimList(List<String> values, int maxLength) {
    if (values.length <= maxLength) return values;
    return values.sublist(values.length - maxLength);
  }

  String _extractProfileText(String text, String prefix) {
    if (!text.startsWith(prefix)) return '';
    return text.substring(prefix.length).trim();
  }

  String _normalizeSentence(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}

class _ScoredMemory {
  _ScoredMemory({required this.memory, required this.score});

  final MemoryEntry memory;
  final double score;
}

class MemoryUpdateResult {
  const MemoryUpdateResult({
    required this.summaryUpdated,
    required this.addedMemoryCount,
    required this.updatedMemoryCount,
    required this.profileUpdated,
    required this.generationMethod,
  });

  const MemoryUpdateResult.none()
    : summaryUpdated = false,
      addedMemoryCount = 0,
      updatedMemoryCount = 0,
      profileUpdated = false,
      generationMethod = MemoryGenerationMethod.ruleBased;

  final bool summaryUpdated;
  final int addedMemoryCount;
  final int updatedMemoryCount;
  final bool profileUpdated;
  final MemoryGenerationMethod generationMethod;

  int get changedMemoryCount => addedMemoryCount + updatedMemoryCount;
  bool get hasAnyUpdate =>
      summaryUpdated || profileUpdated || changedMemoryCount > 0;
}

class MemorySnapshot {
  const MemorySnapshot({
    required this.profile,
    required this.summaryCount,
    required this.memoryCount,
    required this.lastUpdatedAt,
  });

  final UserMemoryProfile profile;
  final int summaryCount;
  final int memoryCount;
  final DateTime? lastUpdatedAt;
}
