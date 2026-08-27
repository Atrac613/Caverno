import 'package:drift/drift.dart';

import 'app_database.dart';
import 'rag2_drift_schema.dart';

/// Drift accessors for the frozen RAG2 generation-row envelope.
///
/// This is not a retrieval index and is not wired into chat, settings, or
/// tools. RAG2 FTS5 is opt-in through [AppDatabase.ensureRag2ChunkSearchTable]
/// and is not created by schema version 5.
final class Rag2DriftGenerationDao {
  Rag2DriftGenerationDao(this.database);

  final AppDatabase database;

  Future<void> beginImmediate() => database.customStatement('BEGIN IMMEDIATE');

  Future<void> commit() => database.customStatement('COMMIT');

  Future<void> rollback() => database.customStatement('ROLLBACK');

  Future<void> ensureHostedSchema() async {
    final tables = await _tableNames();
    if (!tables.contains('rag2_store_meta') ||
        !tables.contains('rag2_generations') ||
        !tables.contains('embeddings')) {
      throw const Rag2DriftSchemaException('unsupported_schema');
    }
    final metadata = {
      for (final row in await database.select(database.rag2StoreMeta).get())
        row.key: row.value,
    };
    if (metadata['schema_name'] != rag2DriftStoreSchema ||
        metadata['schema_version'] != '$rag2DriftStoreSchemaVersion' ||
        metadata['contract'] != rag2DriftAdditiveSchemaContract) {
      throw const Rag2DriftSchemaException('unsupported_schema');
    }
  }

  Future<Rag2GenerationRow?> readGeneration({
    required String projectIdentity,
    required String declarationIdentity,
  }) {
    return (database.select(database.rag2Generations)..where(
          (table) =>
              table.projectIdentity.equals(projectIdentity) &
              table.declarationIdentity.equals(declarationIdentity),
        ))
        .getSingleOrNull();
  }

  Future<void> upsertGeneration(Rag2GenerationsCompanion row) {
    return database.into(database.rag2Generations).insertOnConflictUpdate(row);
  }

  Future<int> deleteGeneration({
    required String projectIdentity,
    required String declarationIdentity,
  }) {
    return (database.delete(database.rag2Generations)..where(
          (table) =>
              table.projectIdentity.equals(projectIdentity) &
              table.declarationIdentity.equals(declarationIdentity),
        ))
        .go();
  }

  Future<Set<String>> _tableNames() async {
    final rows = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    return {for (final row in rows) row.read<String>('name')};
  }
}
