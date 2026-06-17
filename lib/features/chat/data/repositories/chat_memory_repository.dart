import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/utils/logger.dart';

import '../../domain/entities/session_memory.dart';
import 'key_value_store.dart';

final chatMemoryBoxProvider = Provider<Box<String>>((ref) {
  throw UnimplementedError('chatMemoryBoxProvider must be overridden');
});

/// Provides the active chat-memory repository. Defaults to the Hive-backed
/// key/value store; F4 overrides it with the drift-backed store once the
/// database is open.
final chatMemoryRepositoryProvider = Provider<ChatMemoryRepository>((ref) {
  final box = ref.watch(chatMemoryBoxProvider);
  return ChatMemoryRepository(HiveKeyValueStore(box));
});

class MemoryUpsertResult {
  const MemoryUpsertResult({
    required this.addedCount,
    required this.updatedCount,
  });

  final int addedCount;
  final int updatedCount;

  int get totalChanged => addedCount + updatedCount;
}

class ChatMemoryRepository {
  ChatMemoryRepository(this._store);

  /// Convenience for the Hive-backed path (production default and existing
  /// tests that supply a `Box<String>`).
  ChatMemoryRepository.fromBox(Box<String> box)
    : _store = HiveKeyValueStore(box);

  final KeyValueStore _store;

  static const _profileKey = 'profile';
  static const _sessionSummariesKey = 'session_summaries';
  static const _memoriesKey = 'memories';
  static const _memoryReviewQueueKey = 'memory_review_queue';
  static const _memorySuppressionRulesKey = 'memory_suppression_rules';
  static const _memorySuppressionHitCountKey = 'memory_suppression_hit_count';

  UserMemoryProfile loadProfile() {
    if (!_store.isReady) return UserMemoryProfile.empty();
    final raw = _store.get(_profileKey);
    if (raw == null || raw.isEmpty) {
      return UserMemoryProfile.empty();
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return UserMemoryProfile.fromJson(data);
    } catch (e) {
      appLog('[ChatMemoryRepository] Failed to parse profile: $e');
      return UserMemoryProfile.empty();
    }
  }

  Future<void> saveProfile(UserMemoryProfile profile) async {
    await _store.put(_profileKey, jsonEncode(profile.toJson()));
  }

  List<MemorySessionSummary> loadSessionSummaries() {
    if (!_store.isReady) return [];
    final raw = _store.get(_sessionSummariesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw) as List<dynamic>;
      final summaries = data.whereType<Map>().map((entry) {
        return MemorySessionSummary.fromJson(Map<String, dynamic>.from(entry));
      }).toList();
      summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return summaries;
    } catch (e) {
      appLog('[ChatMemoryRepository] Failed to parse session summaries: $e');
      return [];
    }
  }

  Future<void> upsertSessionSummary(
    MemorySessionSummary summary, {
    int maxItems = 20,
  }) async {
    if (!_store.isReady) return;
    final summaries = loadSessionSummaries();
    final existingIndex = summaries.indexWhere(
      (s) => s.conversationId == summary.conversationId,
    );

    if (existingIndex >= 0) {
      summaries[existingIndex] = summary;
    } else {
      summaries.add(summary);
    }

    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (summaries.length > maxItems) {
      summaries.removeRange(maxItems, summaries.length);
    }

    await _store.put(
      _sessionSummariesKey,
      jsonEncode(summaries.map((s) => s.toJson()).toList()),
    );
  }

  List<MemoryEntry> loadMemories() {
    if (!_store.isReady) return [];
    final raw = _store.get(_memoriesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw) as List<dynamic>;
      final memories = data.whereType<Map>().map((entry) {
        return MemoryEntry.fromJson(Map<String, dynamic>.from(entry));
      }).toList();
      memories.removeWhere((m) => m.isExpired);
      memories.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return memories;
    } catch (e) {
      appLog('[ChatMemoryRepository] Failed to parse memories: $e');
      return [];
    }
  }

  Future<MemoryUpsertResult> addOrUpdateMemories(
    List<MemoryEntry> entries, {
    int maxItems = 300,
  }) async {
    if (!_store.isReady) {
      return const MemoryUpsertResult(addedCount: 0, updatedCount: 0);
    }
    final memories = loadMemories();
    var addedCount = 0;
    var updatedCount = 0;

    for (final entry in entries) {
      final normalized = _normalize(entry.text);
      if (normalized.isEmpty) continue;

      final existingIndex = memories.indexWhere((m) {
        return _normalize(m.text) == normalized;
      });

      if (existingIndex >= 0) {
        final current = memories[existingIndex];
        memories[existingIndex] = current.copyWith(
          type: entry.type,
          confidence: entry.confidence > current.confidence
              ? entry.confidence
              : current.confidence,
          importance: entry.importance > current.importance
              ? entry.importance
              : current.importance,
          updatedAt: entry.updatedAt,
          sourceConversationId: entry.sourceConversationId,
          expiresAt: entry.expiresAt,
        );
        updatedCount++;
      } else {
        memories.add(entry);
        addedCount++;
      }
    }

    memories.removeWhere((m) => m.isExpired);
    memories.sort((a, b) {
      final importanceOrder = b.importance.compareTo(a.importance);
      if (importanceOrder != 0) return importanceOrder;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    if (memories.length > maxItems) {
      memories.removeRange(maxItems, memories.length);
    }

    await _store.put(
      _memoriesKey,
      jsonEncode(memories.map((m) => m.toJson()).toList()),
    );

    return MemoryUpsertResult(
      addedCount: addedCount,
      updatedCount: updatedCount,
    );
  }

  Future<void> deleteMemoryEntry(String id) async {
    if (!_store.isReady) return;
    final memories = loadMemories()
        .where((memory) => memory.id != id)
        .toList(growable: false);
    await _store.put(
      _memoriesKey,
      jsonEncode(memories.map((memory) => memory.toJson()).toList()),
    );
  }

  List<MemoryReviewItem> loadReviewQueue() {
    if (!_store.isReady) return <MemoryReviewItem>[];
    final raw = _store.get(_memoryReviewQueueKey);
    if (raw == null || raw.isEmpty) return <MemoryReviewItem>[];
    try {
      final data = jsonDecode(raw) as List<dynamic>;
      final items = data
          .whereType<Map>()
          .map((entry) {
            return MemoryReviewItem.fromJson(Map<String, dynamic>.from(entry));
          })
          .toList(growable: true);
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    } catch (e) {
      appLog('[ChatMemoryRepository] Failed to parse review queue: $e');
      return <MemoryReviewItem>[];
    }
  }

  Future<void> upsertReviewQueue(
    List<MemoryReviewItem> items, {
    int maxItems = 100,
  }) async {
    if (!_store.isReady || items.isEmpty) return;
    final queue = loadReviewQueue();

    for (final item in items) {
      final normalized = _normalize(item.text);
      if (normalized.isEmpty) continue;
      final index = queue.indexWhere((entry) {
        return _normalize(entry.text) == normalized;
      });
      if (index >= 0) {
        queue[index] = item;
      } else {
        queue.add(item);
      }
    }

    queue.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (queue.length > maxItems) {
      queue.removeRange(maxItems, queue.length);
    }

    await _store.put(
      _memoryReviewQueueKey,
      jsonEncode(queue.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> removeReviewQueueItem(String id) async {
    if (!_store.isReady) return;
    final queue = loadReviewQueue()
        .where((item) => item.id != id)
        .toList(growable: false);
    await _store.put(
      _memoryReviewQueueKey,
      jsonEncode(queue.map((item) => item.toJson()).toList()),
    );
  }

  List<MemorySuppressionRule> loadSuppressionRules() {
    if (!_store.isReady) return <MemorySuppressionRule>[];
    final raw = _store.get(_memorySuppressionRulesKey);
    if (raw == null || raw.isEmpty) return <MemorySuppressionRule>[];
    try {
      final data = jsonDecode(raw) as List<dynamic>;
      final rules = data
          .whereType<Map>()
          .map((entry) {
            return MemorySuppressionRule.fromJson(
              Map<String, dynamic>.from(entry),
            );
          })
          .toList(growable: true);
      rules.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return rules;
    } catch (e) {
      appLog('[ChatMemoryRepository] Failed to parse suppression rules: $e');
      return <MemorySuppressionRule>[];
    }
  }

  Future<void> addSuppressionRule(
    MemorySuppressionRule rule, {
    int maxItems = 200,
  }) async {
    if (!_store.isReady || rule.normalizedPattern.isEmpty) return;
    final rules = loadSuppressionRules();
    final existingIndex = rules.indexWhere((item) {
      return item.normalizedPattern == rule.normalizedPattern;
    });
    if (existingIndex >= 0) {
      rules[existingIndex] = rule;
    } else {
      rules.add(rule);
    }
    rules.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (rules.length > maxItems) {
      rules.removeRange(maxItems, rules.length);
    }
    await _store.put(
      _memorySuppressionRulesKey,
      jsonEncode(rules.map((item) => item.toJson()).toList()),
    );
  }

  int loadSuppressionHitCount() {
    if (!_store.isReady) return 0;
    final raw = _store.get(_memorySuppressionHitCountKey);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<void> incrementSuppressionHitCount(int count) async {
    if (!_store.isReady || count <= 0) return;
    final current = loadSuppressionHitCount();
    await _store.put(
      _memorySuppressionHitCountKey,
      (current + count).toString(),
    );
  }

  Future<void> clearAll() async {
    await _store.delete(_profileKey);
    await _store.delete(_sessionSummariesKey);
    await _store.delete(_memoriesKey);
    await _store.delete(_memoryReviewQueueKey);
    await _store.delete(_memorySuppressionRulesKey);
    await _store.delete(_memorySuppressionHitCountKey);
  }

  String _normalize(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
