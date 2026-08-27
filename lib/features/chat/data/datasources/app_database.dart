import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'rag2_drift_schema.dart';

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

/// Per-model token usage, aggregated to one row per local day and dimension
/// tuple. Storing daily sums rather than per-request rows keeps the table tiny
/// (labels are ~20 static constants and roles are 6, so a heavy day is a few
/// hundred rows) and makes every read a plain GROUP BY.
///
/// `endpointId` is part of the key because the model name alone is ambiguous:
/// the same name can be served by the primary endpoint, a LAN mesh host, or a
/// cloud provider, and which one it was decides whether the tokens cost money.
///
/// Detail columns are 0 when the provider omits `prompt_tokens_details` /
/// `completion_tokens_details` (local llama.cpp does), so readers must treat 0
/// as "not reported" rather than "measured as zero".
@DataClassName('ModelUsageDailyRow')
class ModelUsageDaily extends Table {
  /// Local epoch-day, matching `modelUsageDayNumber`.
  IntColumn get dayNumber => integer()();
  TextColumn get model => text()();
  TextColumn get endpointId => text().withDefault(const Constant(''))();

  /// `ModelUsageRole.name`; `'unknown'` marks a call site that never set one.
  TextColumn get role => text().withDefault(const Constant('unknown'))();

  /// The session-log request label, which names a main-loop recovery path
  /// (`'tool-loop exhaustion recovery'`, ...) — not a role.
  TextColumn get label => text().withDefault(const Constant(''))();

  IntColumn get requestCount => integer().withDefault(const Constant(0))();
  IntColumn get errorCount => integer().withDefault(const Constant(0))();

  /// Completions that stopped on `finish_reason == 'length'`.
  IntColumn get truncatedCount => integer().withDefault(const Constant(0))();

  /// Running sum; average latency is `durationMs / requestCount`.
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  IntColumn get promptTokens => integer().withDefault(const Constant(0))();
  IntColumn get completionTokens => integer().withDefault(const Constant(0))();
  IntColumn get totalTokens => integer().withDefault(const Constant(0))();
  IntColumn get cachedPromptTokens =>
      integer().withDefault(const Constant(0))();
  IntColumn get audioPromptTokens => integer().withDefault(const Constant(0))();
  IntColumn get reasoningTokens => integer().withDefault(const Constant(0))();
  IntColumn get audioCompletionTokens =>
      integer().withDefault(const Constant(0))();
  IntColumn get acceptedPredictionTokens =>
      integer().withDefault(const Constant(0))();
  IntColumn get rejectedPredictionTokens =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {
    dayNumber,
    model,
    endpointId,
    role,
    label,
  };
}

/// RAG2 generation-store metadata. Envelope version 1 lives here; AppDatabase
/// schema version 5 only hosts the tables.
@DataClassName('Rag2StoreMetaRow')
class Rag2StoreMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// RAG2 declaration-scoped generation row. Payload reuses the persistence
/// encoder; envelope columns must match that payload on read.
@DataClassName('Rag2GenerationRow')
class Rag2Generations extends Table {
  TextColumn get projectIdentity => text()();
  TextColumn get declarationIdentity => text()();
  TextColumn get schemaName => text()();
  IntColumn get schemaVersion => integer()();
  TextColumn get contract => text()();
  TextColumn get projectId => text()();
  IntColumn get generation => integer()();
  TextColumn get snapshotHash => text()();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {projectIdentity, declarationIdentity};
}

/// One pretokenized RAG2 FTS5 row. Callers supply Dart-side trigram terms;
/// AppDatabase does not tokenize.
final class Rag2ChunkSearchRow {
  const Rag2ChunkSearchRow({
    required this.chunkId,
    required this.objectId,
    required this.content,
  });

  final String chunkId;
  final String objectId;
  final String content;
}

/// Local epoch-day for [timestamp], matching the convention used by the
/// dashboard's activity heatmap so both features bucket a day identically.
int modelUsageDayNumber(DateTime timestamp) {
  final local = timestamp.toLocal();
  return DateTime.utc(
        local.year,
        local.month,
        local.day,
      ).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}

@DriftDatabase(
  tables: [
    Conversations,
    ChatMemoryEntries,
    Embeddings,
    ModelUsageDaily,
    Rag2StoreMeta,
    Rag2Generations,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// In-memory database for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  /// FTS5 virtual table backing conversation history search (F4). It is not a
  /// drift-managed table, so it is created and kept in sync with raw SQL.
  static const _conversationSearchTable = 'conversation_search';

  /// Isolated RAG2 chunk FTS5. Created on demand; not part of schema version 5.
  static const rag2ChunkSearchTable = 'rag2_chunk_search';
  static const rag2ChunkSearchTokenizer = 'unicode61';

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createConversationSearchTable();
      await _seedRag2StoreMeta();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await _createConversationSearchTable();
        await rebuildConversationSearch();
      }
      if (from < 3) {
        await m.createTable(embeddings);
      }
      if (from < 4) {
        await m.createTable(modelUsageDaily);
      }
      if (from < 5) {
        await _addRag2TablesIfMissing(m);
      }
    },
  );

  Future<void> _addRag2TablesIfMissing(Migrator m) async {
    final tables = await _sqliteTableNames();
    final hasMeta = tables.contains('rag2_store_meta');
    final hasGenerations = tables.contains('rag2_generations');
    if (hasMeta != hasGenerations) {
      throw const Rag2DriftSchemaException('unsupported_schema');
    }
    if (hasMeta && hasGenerations) {
      await _requireCurrentRag2StoreMeta();
      return;
    }
    await m.createTable(rag2StoreMeta);
    await m.createTable(rag2Generations);
    await _seedRag2StoreMeta();
  }

  Future<Set<String>> _sqliteTableNames() async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ).get();
    return {for (final row in rows) row.read<String>('name')};
  }

  Future<void> _requireCurrentRag2StoreMeta() async {
    final metadata = await _rag2StoreMetaValues();
    if (metadata['schema_name'] != rag2DriftStoreSchema ||
        metadata['schema_version'] != '$rag2DriftStoreSchemaVersion' ||
        metadata['contract'] != rag2DriftAdditiveSchemaContract) {
      throw const Rag2DriftSchemaException('unsupported_schema');
    }
  }

  Future<Map<String, String>> _rag2StoreMetaValues() async {
    final rows = await customSelect(
      'SELECT key, value FROM rag2_store_meta',
    ).get();
    return {
      for (final row in rows)
        row.read<String>('key'): row.read<String>('value'),
    };
  }

  Future<void> _seedRag2StoreMeta() async {
    await customStatement(
      'INSERT INTO rag2_store_meta(key, value) '
      'VALUES (?, ?), (?, ?), (?, ?)',
      [
        'schema_name',
        rag2DriftStoreSchema,
        'schema_version',
        '$rag2DriftStoreSchemaVersion',
        'contract',
        rag2DriftAdditiveSchemaContract,
      ],
    );
  }

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

  /// Creates `rag2_chunk_search` beside conversation-search. This is not a
  /// schema version 5 migration and does not rewrite conversation-search rows.
  Future<void> ensureRag2ChunkSearchTable() {
    return customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS $rag2ChunkSearchTable USING fts5('
      'project_identity UNINDEXED, declaration_identity UNINDEXED, '
      'generation UNINDEXED, snapshot_hash UNINDEXED, '
      'chunk_id UNINDEXED, object_id UNINDEXED, content, '
      'tokenize=$rag2ChunkSearchTokenizer)',
    );
  }

  /// Replaces one project/declaration slot.
  ///
  /// Owns `BEGIN IMMEDIATE` / `COMMIT` unless [inTransaction] is true. A
  /// mid-write failure then rolls back to the previous slot instead of
  /// leaving an empty or partial index. DELETE is scoped to the target
  /// project and declaration identities.
  Future<void> writeRag2ChunkSearchIndex({
    required String projectIdentity,
    required String declarationIdentity,
    required int generation,
    required String snapshotHash,
    required List<Rag2ChunkSearchRow> rows,
    void Function()? beforeCommit,
    bool inTransaction = false,
  }) async {
    if (inTransaction) {
      await _replaceRag2ChunkSearchRows(
        projectIdentity: projectIdentity,
        declarationIdentity: declarationIdentity,
        generation: generation,
        snapshotHash: snapshotHash,
        rows: rows,
      );
      return;
    }
    var settled = false;
    await customStatement('BEGIN IMMEDIATE');
    try {
      await ensureRag2ChunkSearchTable();
      await _replaceRag2ChunkSearchRows(
        projectIdentity: projectIdentity,
        declarationIdentity: declarationIdentity,
        generation: generation,
        snapshotHash: snapshotHash,
        rows: rows,
      );
      beforeCommit?.call();
      await customStatement('COMMIT');
      settled = true;
    } on Object {
      if (!settled) {
        try {
          await customStatement('ROLLBACK');
        } on Object {
          // The connection may already have rolled back.
        }
      }
      rethrow;
    }
  }

  Future<void> _replaceRag2ChunkSearchRows({
    required String projectIdentity,
    required String declarationIdentity,
    required int generation,
    required String snapshotHash,
    required List<Rag2ChunkSearchRow> rows,
  }) async {
    await customStatement(
      'DELETE FROM $rag2ChunkSearchTable '
      'WHERE project_identity = ? AND declaration_identity = ?',
      [projectIdentity, declarationIdentity],
    );
    for (final row in rows) {
      await customStatement(
        'INSERT INTO $rag2ChunkSearchTable('
        'project_identity, declaration_identity, generation, snapshot_hash, '
        'chunk_id, object_id, content) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          projectIdentity,
          declarationIdentity,
          generation,
          snapshotHash,
          row.chunkId,
          row.objectId,
          row.content,
        ],
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
