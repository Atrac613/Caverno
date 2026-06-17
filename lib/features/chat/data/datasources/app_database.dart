import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Opens the production drift database backed by a SQLite file in the app
/// support directory. F4 bootstrap calls this once; failures fall back to Hive.
Future<AppDatabase> openAppDatabase() async {
  final directory = await getApplicationSupportDirectory();
  final file = File('${directory.path}/caverno.sqlite');
  return AppDatabase(NativeDatabase.createInBackground(file));
}

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

/// LL5: stored embedding vectors for local semantic search. Each row is one
/// embedded chunk of a source (e.g. a conversation), with the vector stored as
/// packed Float32 bytes and a snippet for result display. Similarity ranking is
/// computed in Dart (brute-force cosine) since SQLite has no native vector type.
@DataClassName('EmbeddingRow')
class Embeddings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sourceType => text()();
  TextColumn get sourceId => text()();
  IntColumn get chunkIndex => integer().withDefault(const Constant(0))();
  TextColumn get model => text().withDefault(const Constant(''))();
  IntColumn get dim => integer().withDefault(const Constant(0))();
  BlobColumn get vector => blob()();
  TextColumn get snippet => text().withDefault(const Constant(''))();
  IntColumn get createdAtMs => integer().withDefault(const Constant(0))();
}

@DriftDatabase(tables: [Conversations, ChatMemoryEntries, Embeddings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// In-memory database for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  /// FTS5 virtual table backing conversation history search (F4). It is not a
  /// drift-managed table, so it is created and kept in sync with raw SQL.
  static const _conversationSearchTable = 'conversation_search';

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createConversationSearchTable();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await _createConversationSearchTable();
        await rebuildConversationSearch();
      }
      if (from < 3) {
        await m.createTable(embeddings);
      }
    },
  );

  Future<void> _createConversationSearchTable() async {
    await customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS $_conversationSearchTable '
      "USING fts5(id UNINDEXED, title, body, tokenize='unicode61')",
    );
  }

  /// Inserts or replaces the search index row for a conversation.
  Future<void> indexConversationSearch({
    required String id,
    required String title,
    required String body,
  }) async {
    await customStatement(
      'DELETE FROM $_conversationSearchTable WHERE id = ?',
      [id],
    );
    await customStatement(
      'INSERT INTO $_conversationSearchTable(id, title, body) VALUES (?, ?, ?)',
      [id, title, body],
    );
  }

  Future<void> removeConversationSearch(String id) async {
    await customStatement(
      'DELETE FROM $_conversationSearchTable WHERE id = ?',
      [id],
    );
  }

  Future<void> clearConversationSearch() async {
    await customStatement('DELETE FROM $_conversationSearchTable');
  }

  /// Rebuilds the entire search index from the conversations table. Used by the
  /// v1->v2 upgrade and available as a repair path.
  Future<void> rebuildConversationSearch() async {
    await clearConversationSearch();
    final rows = await select(conversations).get();
    for (final row in rows) {
      await indexConversationSearch(
        id: row.id,
        title: row.title,
        body: _extractSearchBody(row.payload),
      );
    }
  }

  /// Returns conversation ids matching [query], ranked by FTS relevance.
  Future<List<String>> searchConversationIds(String query) async {
    final ftsQuery = _toFtsQuery(query);
    if (ftsQuery.isEmpty) return const [];
    final rows = await customSelect(
      'SELECT id FROM $_conversationSearchTable '
      'WHERE $_conversationSearchTable MATCH ? ORDER BY rank',
      variables: [Variable<String>(ftsQuery)],
      readsFrom: {conversations},
    ).get();
    return [for (final row in rows) row.read<String>('id')];
  }

  static String _extractSearchBody(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final messages = data['messages'];
      if (messages is List) {
        return messages
            .whereType<Map>()
            .map((message) => message['content'])
            .whereType<String>()
            .join('\n');
      }
    } catch (_) {
      // Corrupt payloads are simply not indexed.
    }
    return '';
  }

  /// Turns free text into a safe FTS5 MATCH expression: each whitespace term is
  /// quoted (and embedded quotes doubled) and AND-ed together.
  static String _toFtsQuery(String query) {
    final terms = query
        .split(RegExp(r'\s+'))
        .where((term) => term.trim().isNotEmpty)
        .map((term) => '"${term.replaceAll('"', '""')}"')
        .toList();
    return terms.join(' ');
  }
}
