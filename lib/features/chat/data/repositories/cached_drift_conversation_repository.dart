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
  ///
  /// The cache uses [ConversationStore.listForCache] so launching does not
  /// `jsonDecode` every message of every conversation. Opening a thread calls
  /// [refresh] to load the full payload.
  ///
  /// CLI and other headless readers pass [listingOnly] `false` so `show` /
  /// resume see real message bodies without a separate refresh.
  static Future<CachedDriftConversationRepository> hydrate(
    ConversationStore store, {
    bool listingOnly = true,
  }) async {
    final initial = listingOnly
        ? await store.listForCache()
        : await store.getAll();
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
  Future<Conversation?> refresh(String id) async {
    final conversation = await _store.getById(id);
    if (conversation == null) {
      _cache.remove(id);
    } else {
      _cache[id] = conversation;
    }
    return conversation;
  }

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

  @override
  Future<List<Conversation>> search(String query) => _store.search(query);
}
