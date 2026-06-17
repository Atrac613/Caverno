import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

/// F4: conversations stored in SQLite via drift.
///
/// The authoritative conversation data stays a JSON blob in [payload]
/// (`Conversation.toJson`), so the migration is lossless and the entity schema
/// is unchanged. `title`, `createdAtMs`, and `updatedAtMs` are denormalized
/// columns for fast listing/sorting and as the basis for FTS5 history search in
/// a later slice.
@DataClassName('ConversationRow')
class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  IntColumn get createdAtMs => integer().withDefault(const Constant(0))();
  IntColumn get updatedAtMs => integer().withDefault(const Constant(0))();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// F4: chat memory as a key/value table.
///
/// The legacy Hive store kept the six chat-memory sections (profile, session
/// summaries, memories, review queue, suppression rules, suppression hit count)
/// as JSON-string blobs under fixed keys. Mirroring that as a KV table keeps the
/// migration lossless and the rich repository logic (dedup, capping, sorting)
/// unchanged; normalization into per-row tables can come later.
@DataClassName('ChatMemoryEntryRow')
class ChatMemoryEntries extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [Conversations, ChatMemoryEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// In-memory database for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}
