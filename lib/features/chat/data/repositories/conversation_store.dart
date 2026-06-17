import '../../domain/entities/conversation.dart';

/// Storage-agnostic contract for persisting conversations.
///
/// F4 introduces this seam so the conversation store can move from Hive to
/// drift/SQLite without touching callers. Methods are asynchronous because the
/// SQLite-backed implementation is async; the legacy Hive repository remains a
/// separate synchronous class until callers are migrated to this interface.
abstract interface class ConversationStore {
  /// All conversations, most recently updated first.
  Future<List<Conversation>> getAll();

  Future<Conversation?> getById(String id);

  Future<void> save(Conversation conversation);

  Future<void> delete(String id);

  Future<void> deleteAll();

  /// Full-text history search: conversations matching [query], ranked by
  /// relevance.
  Future<List<Conversation>> search(String query);
}
