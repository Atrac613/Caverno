import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../domain/entities/conversation.dart';

/// Hive Boxを提供するProvider
final conversationBoxProvider = Provider<Box<String>>((ref) {
  throw UnimplementedError('conversationBoxProvider must be overridden');
});

/// ConversationRepositoryを提供するProvider
final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  final box = ref.watch(conversationBoxProvider);
  return ConversationRepository(box);
});

/// 会話をHiveに保存・取得するリポジトリ
class ConversationRepository {
  ConversationRepository(this._box);

  final Box<String> _box;

  /// 全ての会話を取得（更新日時の降順）
  List<Conversation> getAll() {
    final conversations = <Conversation>[];
    for (final key in _box.keys) {
      final json = _box.get(key);
      if (json != null) {
        try {
          final data = jsonDecode(json) as Map<String, dynamic>;
          conversations.add(Conversation.fromJson(data));
        } catch (e) {
          print('[ConversationRepository] Failed to parse conversation: $e');
        }
      }
    }
    // 更新日時の降順でソート
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  /// IDで会話を取得
  Conversation? getById(String id) {
    final json = _box.get(id);
    if (json == null) return null;
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return Conversation.fromJson(data);
    } catch (e) {
      print('[ConversationRepository] Failed to parse conversation: $e');
      return null;
    }
  }

  /// 会話を保存
  Future<void> save(Conversation conversation) async {
    final json = jsonEncode(conversation.toJson());
    await _box.put(conversation.id, json);
  }

  /// 会話を削除
  Future<void> delete(String id) async {
    await _box.delete(id);
  }

  /// 全ての会話を削除
  Future<void> deleteAll() async {
    await _box.clear();
  }
}
