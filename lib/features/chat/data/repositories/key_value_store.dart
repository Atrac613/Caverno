import 'package:hive_flutter/hive_flutter.dart';

import 'drift_chat_memory_store.dart';

/// Synchronous string key/value contract backing [ChatMemoryRepository].
///
/// Reads are synchronous (served from memory); writes return futures. F4 swaps
/// the backend from Hive to drift behind this interface without touching the
/// repository's logic. Implementations are safe to call when not ready: reads
/// return null and writes are no-ops, so callers need no closed-store handling.
abstract interface class KeyValueStore {
  bool get isReady;
  String? get(String key);
  Future<void> put(String key, String value);
  Future<void> delete(String key);
}

/// Hive-backed [KeyValueStore], preserving the prior closed-box safety: a box
/// that has been closed mid-operation is treated as empty/no-op rather than
/// throwing.
class HiveKeyValueStore implements KeyValueStore {
  HiveKeyValueStore(this._box);

  final Box<String> _box;

  @override
  bool get isReady => _box.isOpen;

  @override
  String? get(String key) {
    if (!_box.isOpen) return null;
    try {
      return _box.get(key);
    } on HiveError catch (error) {
      if (_isClosed(error)) return null;
      rethrow;
    }
  }

  @override
  Future<void> put(String key, String value) async {
    if (!_box.isOpen) return;
    try {
      await _box.put(key, value);
    } on HiveError catch (error) {
      if (_isClosed(error)) return;
      rethrow;
    }
  }

  @override
  Future<void> delete(String key) async {
    if (!_box.isOpen) return;
    try {
      await _box.delete(key);
    } on HiveError catch (error) {
      if (_isClosed(error)) return;
      rethrow;
    }
  }

  bool _isClosed(HiveError error) =>
      error.message.toLowerCase().contains('already been closed');
}

/// F4 drift-backed [KeyValueStore] with a synchronous in-memory cache hydrated
/// from the drift chat-memory table at startup; writes update the cache and
/// write through to SQLite.
class CachedDriftKeyValueStore implements KeyValueStore {
  CachedDriftKeyValueStore.fromCache(this._store, this._cache);

  final DriftChatMemoryStore _store;
  final Map<String, String> _cache;

  static Future<CachedDriftKeyValueStore> hydrate(
    DriftChatMemoryStore store,
  ) async {
    final entries = await store.getAll();
    return CachedDriftKeyValueStore.fromCache(store, {...entries});
  }

  @override
  bool get isReady => true;

  @override
  String? get(String key) => _cache[key];

  @override
  Future<void> put(String key, String value) async {
    _cache[key] = value;
    await _store.setValue(key, value);
  }

  @override
  Future<void> delete(String key) async {
    _cache.remove(key);
    await _store.deleteValue(key);
  }
}
