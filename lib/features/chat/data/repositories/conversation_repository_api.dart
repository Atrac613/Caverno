import '../../domain/entities/conversation.dart';

/// Synchronous, app-facing conversation repository contract used by the chat
/// notifier, settings, and the past-conversation-search tool.
///
/// Reads are synchronous (served from memory); writes return futures. Both the
/// legacy Hive [ConversationRepository] and the F4 drift-backed
/// [CachedDriftConversationRepository] implement this, so the storage backend
/// can be swapped behind `conversationRepositoryProvider` without touching
/// callers.
abstract interface class ConversationRepositoryApi {
  /// All conversations, most recently updated first.
  List<Conversation> getAll();

  Conversation? getById(String id);

  Future<void> save(Conversation conversation);

  Future<void> delete(String id);

  Future<void> deleteAll();

  /// History search: conversations matching [query]. Drift uses FTS5 ranking;
  /// the Hive fallback does an in-memory substring match.
  Future<List<Conversation>> search(String query);
}
