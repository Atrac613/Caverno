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

@DriftDatabase(tables: [Conversations])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// In-memory database for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}
