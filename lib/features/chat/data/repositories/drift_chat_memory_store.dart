import '../datasources/app_database.dart';

/// F4 drift-backed key/value access for chat memory sections.
///
/// Each chat-memory section is stored as a JSON-string value under a stable
/// key, matching the legacy Hive layout so the rich [ChatMemoryRepository]
/// logic can sit on top unchanged once it is wired to a KV backend.
class DriftChatMemoryStore {
  DriftChatMemoryStore(this._db);

  final AppDatabase _db;

  Future<String?> getValue(String key) async {
    final row = await (_db.select(
      _db.chatMemoryEntries,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<Map<String, String>> getAll() async {
    final rows = await _db.select(_db.chatMemoryEntries).get();
    return {for (final row in rows) row.key: row.value};
  }

  Future<void> setValue(String key, String value) async {
    await _db
        .into(_db.chatMemoryEntries)
        .insertOnConflictUpdate(
          ChatMemoryEntriesCompanion.insert(key: key, value: value),
        );
  }

  Future<void> deleteValue(String key) async {
    await (_db.delete(
      _db.chatMemoryEntries,
    )..where((t) => t.key.equals(key))).go();
  }
}
