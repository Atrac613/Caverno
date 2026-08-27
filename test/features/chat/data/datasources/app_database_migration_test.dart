import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/datasources/rag2_drift_schema.dart';

void main() {
  late Directory tempDir;
  late File databaseFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('caverno_migration_test');
    databaseFile = File('${tempDir.path}/caverno.sqlite');
  });

  tearDown(() async => tempDir.delete(recursive: true));

  AppDatabase open() => AppDatabase(NativeDatabase(databaseFile));

  test('upgrading from v3 creates the model usage table', () async {
    // Simulate a database written by the previous release: the table does not
    // exist yet and the recorded schema version is still 3.
    final before = open();
    await before.customStatement('DROP TABLE IF EXISTS model_usage_daily');
    await before.customStatement('PRAGMA user_version = 3');
    await before.close();

    final after = open();
    addTearDown(after.close);

    // Forces the migration to run.
    final rows = await after.select(after.modelUsageDaily).get();
    expect(rows, isEmpty);

    final version = await after.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 5);
  });

  test('an upgraded database accepts usage rows', () async {
    final before = open();
    await before.customStatement('DROP TABLE IF EXISTS model_usage_daily');
    await before.customStatement('PRAGMA user_version = 3');
    await before.close();

    final after = open();
    addTearDown(after.close);

    await after
        .into(after.modelUsageDaily)
        .insert(
          ModelUsageDailyCompanion.insert(
            dayNumber: modelUsageDayNumber(DateTime(2026, 8, 8)),
            model: 'model-a',
            totalTokens: const Value(120),
          ),
        );

    final rows = await after.select(after.modelUsageDaily).get();
    expect(rows.single.totalTokens, 120);
    expect(rows.single.role, 'unknown', reason: 'the column default applies');
  });

  test('existing conversations survive the upgrade', () async {
    final before = open();
    await before
        .into(before.conversations)
        .insert(
          ConversationsCompanion.insert(
            id: 'c1',
            payload: '{"id":"c1"}',
            title: const Value('Kept'),
          ),
        );
    await before.customStatement('DROP TABLE IF EXISTS model_usage_daily');
    await before.customStatement('PRAGMA user_version = 3');
    await before.close();

    final after = open();
    addTearDown(after.close);

    final conversations = await after.select(after.conversations).get();
    expect(conversations.single.title, 'Kept');
  });

  test('upgrading from v4 keeps embedding rows and adds RAG2 tables', () async {
    final before = open();
    await before
        .into(before.embeddings)
        .insert(
          EmbeddingsCompanion.insert(
            sourceType: 'conversation',
            sourceId: 'll5-sentinel',
            vector: Uint8List.fromList(const [1, 2, 3, 4]),
            snippet: const Value('ll5-sentinel-snippet'),
            model: const Value('ll5-sentinel-model'),
            dim: const Value(1),
          ),
        );
    await before.customStatement('DROP TABLE IF EXISTS rag2_generations');
    await before.customStatement('DROP TABLE IF EXISTS rag2_store_meta');
    await before.customStatement('PRAGMA user_version = 4');
    await before.close();

    final after = open();
    addTearDown(after.close);
    final embeddings = await after.select(after.embeddings).get();
    final meta = await after.select(after.rag2StoreMeta).get();
    final generations = await after.select(after.rag2Generations).get();
    final version = await after.customSelect('PRAGMA user_version').getSingle();

    expect(embeddings.single.sourceId, 'll5-sentinel');
    expect(embeddings.single.snippet, 'll5-sentinel-snippet');
    expect(embeddings.single.vector, Uint8List.fromList(const [1, 2, 3, 4]));
    expect(generations, isEmpty);
    expect(
      {for (final row in meta) row.key: row.value}['schema_name'],
      rag2DriftStoreSchema,
    );
    expect(version.data['user_version'], 5);

    final rag2Search = await after
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE name = 'rag2_chunk_search'",
        )
        .get();
    expect(rag2Search, isEmpty);
    await after.ensureRag2ChunkSearchTable();
    final created = await after
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE name = 'rag2_chunk_search'",
        )
        .get();
    expect(created, isNotEmpty);
    expect(created.single.read<String>('sql').toLowerCase(), contains('fts5'));
    expect(
      (await after.select(after.embeddings).get()).single.sourceId,
      'll5-sentinel',
    );
  });

  test(
    'refuses generation rows without metadata and leaves version 4',
    () async {
      final before = open();
      await before
          .into(before.rag2Generations)
          .insert(
            Rag2GenerationsCompanion.insert(
              projectIdentity: 'orphan-project',
              declarationIdentity: 'orphan-declaration',
              schemaName: rag2DriftStoreSchema,
              schemaVersion: rag2DriftStoreSchemaVersion,
              contract: rag2DriftAdditiveSchemaContract,
              projectId: 'orphan-project',
              generation: 1,
              snapshotHash: 'orphan-hash',
              payload: '{}',
            ),
          );
      await before.customStatement('DROP TABLE IF EXISTS rag2_store_meta');
      await before.customStatement('PRAGMA user_version = 4');
      await before.close();

      final after = open();
      await expectLater(
        after.customSelect('SELECT 1').get(),
        throwsA(
          isA<Rag2DriftSchemaException>().having(
            (error) => error.reason,
            'reason',
            'unsupported_schema',
          ),
        ),
      );
      await after.close();

      final check = sqlite3.open(databaseFile.path);
      addTearDown(check.close);
      expect(check.select('PRAGMA user_version').first['user_version'], 4);
      final tables = check
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row['name'] as String)
          .toSet();
      expect(tables.contains('rag2_generations'), isTrue);
      expect(tables.contains('rag2_store_meta'), isFalse);
      expect(
        check
            .select(
              'SELECT snapshot_hash FROM rag2_generations '
              "WHERE project_identity = 'orphan-project'",
            )
            .first['snapshot_hash'],
        'orphan-hash',
      );
    },
  );
}
