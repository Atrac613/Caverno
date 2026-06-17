import '../../domain/entities/conversation.dart';
import 'conversation_repository_api.dart';
import 'conversation_store.dart';

/// F4 drift-backed [ConversationRepositoryApi] with a synchronous in-memory
/// cache.
///
/// The cache, hydrated once from the drift [ConversationStore] at startup,
/// preserves the synchronous read API the chat notifier and tools rely on,
/// while writes update the cache and write through to SQLite. This lets the
/// conversation store move from Hive to drift as a single provider override,
/// with no caller changes.
class CachedDriftConversationRepository implements ConversationRepositoryApi {
  CachedDriftConversationRepository.fromCache(this._store, this._cache);

  final ConversationStore _store;
  final Map<String, Conversation> _cache;

  /// Builds the repository, hydrating the in-memory cache from [store] so reads
  /// are synchronous. Call once during bootstrap after the database is ready.
  static Future<CachedDriftConversationRepository> hydrate(
    ConversationStore store,
  ) async {
    final initial = await store.getAll();
    return CachedDriftConversationRepository.fromCache(store, {
      for (final conversation in initial) conversation.id: conversation,
    });
  }

  @override
  List<Conversation> getAll() {
    return _cache.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Conversation? getById(String id) => _cache[id];

  @override
  Future<void> save(Conversation conversation) async {
    _cache[conversation.id] = conversation;
    await _store.save(conversation);
  }

  @override
  Future<void> delete(String id) async {
    _cache.remove(id);
    await _store.delete(id);
  }

  @override
  Future<void> deleteAll() async {
    _cache.clear();
    await _store.deleteAll();
  }
}
