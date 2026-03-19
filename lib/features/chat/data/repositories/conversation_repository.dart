import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/utils/logger.dart';

import '../../domain/entities/conversation.dart';

/// Provides the Hive box.
final conversationBoxProvider = Provider<Box<String>>((ref) {
  throw UnimplementedError('conversationBoxProvider must be overridden');
});

/// Provides the `ConversationRepository`.
final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  final box = ref.watch(conversationBoxProvider);
  return ConversationRepository(box);
});

/// Repository for storing and loading conversations from Hive.
class ConversationRepository {
  ConversationRepository(this._box);

  final Box<String> _box;

  /// Returns all conversations sorted by most recent update.
  List<Conversation> getAll() {
    final conversations = <Conversation>[];
    for (final key in _box.keys) {
      final json = _box.get(key);
      if (json != null) {
        try {
          final data = jsonDecode(json) as Map<String, dynamic>;
          conversations.add(Conversation.fromJson(data));
        } catch (e) {
          appLog('[ConversationRepository] Failed to parse conversation: $e');
        }
      }
    }
    // Sort by latest update first.
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  /// Returns a conversation by ID.
  Conversation? getById(String id) {
    final json = _box.get(id);
    if (json == null) return null;
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return Conversation.fromJson(data);
    } catch (e) {
      appLog('[ConversationRepository] Failed to parse conversation: $e');
      return null;
    }
  }

  /// Saves a conversation.
  Future<void> save(Conversation conversation) async {
    final json = jsonEncode(conversation.toJson());
    await _box.put(conversation.id, json);
  }

  /// Deletes a conversation.
  Future<void> delete(String id) async {
    await _box.delete(id);
  }

  /// Deletes all conversations.
  Future<void> deleteAll() async {
    await _box.clear();
  }
}
