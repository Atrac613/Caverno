import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/conversation.dart';
import '../datasources/app_database.dart';
import 'conversation_store.dart';

/// F4 drift-backed [ConversationStore]: persists conversations to SQLite,
/// keeping the authoritative entity as a JSON payload while denormalizing the
/// title and timestamps into columns for ordering and (later) FTS search.
class DriftConversationRepository implements ConversationStore {
  DriftConversationRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<Conversation>> getAll() async {
    final query = _db.select(_db.conversations)
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAtMs)]);
    final rows = await query.get();
    return [for (final row in rows) ?_decode(row)];
  }

  @override
  Future<Conversation?> getById(String id) async {
    final row = await (_db.select(
      _db.conversations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _decode(row);
  }

  @override
  Future<void> save(Conversation conversation) async {
    await _db
        .into(_db.conversations)
        .insertOnConflictUpdate(_toCompanion(conversation));
    await _db.indexConversationSearch(
      id: conversation.id,
      title: conversation.title,
      body: _searchBody(conversation),
    );
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.conversations)..where((t) => t.id.equals(id))).go();
    await _db.removeConversationSearch(id);
  }

  @override
  Future<void> deleteAll() async {
    await _db.delete(_db.conversations).go();
    await _db.clearConversationSearch();
  }

  /// F4 history full-text search: returns conversations matching [query],
  /// ranked by FTS relevance.
  Future<List<Conversation>> search(String query) async {
    final ids = await _db.searchConversationIds(query);
    final results = <Conversation>[];
    for (final id in ids) {
      final conversation = await getById(id);
      if (conversation != null) results.add(conversation);
    }
    return results;
  }

  String _searchBody(Conversation conversation) {
    return conversation.messages.map((message) => message.content).join('\n');
  }

  ConversationsCompanion _toCompanion(Conversation conversation) {
    return ConversationsCompanion.insert(
      id: conversation.id,
      title: Value(conversation.title),
      createdAtMs: Value(conversation.createdAt.millisecondsSinceEpoch),
      updatedAtMs: Value(conversation.updatedAt.millisecondsSinceEpoch),
      payload: jsonEncode(conversation.toJson()),
    );
  }

  Conversation? _decode(ConversationRow row) {
    try {
      final data = jsonDecode(row.payload) as Map<String, dynamic>;
      return Conversation.fromJson(data);
    } catch (e) {
      appLog('[DriftConversationRepository] Failed to parse conversation: $e');
      return null;
    }
  }
}
