import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../domain/entities/session_memory.dart';

final chatMemoryBoxProvider = Provider<Box<String>>((ref) {
  throw UnimplementedError('chatMemoryBoxProvider must be overridden');
});

final chatMemoryRepositoryProvider = Provider<ChatMemoryRepository>((ref) {
  final box = ref.watch(chatMemoryBoxProvider);
  return ChatMemoryRepository(box);
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
  ChatMemoryRepository(this._box);

  final Box<String> _box;

  static const _profileKey = 'profile';
  static const _sessionSummariesKey = 'session_summaries';
  static const _memoriesKey = 'memories';

  UserMemoryProfile loadProfile() {
    final raw = _box.get(_profileKey);
    if (raw == null || raw.isEmpty) {
      return UserMemoryProfile.empty();
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return UserMemoryProfile.fromJson(data);
    } catch (e) {
      print('[ChatMemoryRepository] Failed to parse profile: $e');
      return UserMemoryProfile.empty();
    }
  }

  Future<void> saveProfile(UserMemoryProfile profile) async {
    await _box.put(_profileKey, jsonEncode(profile.toJson()));
  }

  List<MemorySessionSummary> loadSessionSummaries() {
    final raw = _box.get(_sessionSummariesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw) as List<dynamic>;
      final summaries = data.whereType<Map>().map((entry) {
        return MemorySessionSummary.fromJson(Map<String, dynamic>.from(entry));
      }).toList();
      summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return summaries;
    } catch (e) {
      print('[ChatMemoryRepository] Failed to parse session summaries: $e');
      return [];
    }
  }

  Future<void> upsertSessionSummary(
    MemorySessionSummary summary, {
    int maxItems = 20,
  }) async {
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

    await _box.put(
      _sessionSummariesKey,
      jsonEncode(summaries.map((s) => s.toJson()).toList()),
    );
  }

  List<MemoryEntry> loadMemories() {
    final raw = _box.get(_memoriesKey);
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
      print('[ChatMemoryRepository] Failed to parse memories: $e');
      return [];
    }
  }

  Future<MemoryUpsertResult> addOrUpdateMemories(
    List<MemoryEntry> entries, {
    int maxItems = 300,
  }) async {
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

    await _box.put(
      _memoriesKey,
      jsonEncode(memories.map((m) => m.toJson()).toList()),
    );

    return MemoryUpsertResult(
      addedCount: addedCount,
      updatedCount: updatedCount,
    );
  }

  Future<void> clearAll() async {
    await _box.delete(_profileKey);
    await _box.delete(_sessionSummariesKey);
    await _box.delete(_memoriesKey);
  }

  String _normalize(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
