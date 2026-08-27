import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/datasources/rag2_drift_schema.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

import 'rag2_drift_generation_store.dart';
export 'rag2_drift_generation_store.dart';
import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_persistence_reopen_replay.dart';
import 'rag2_storage_replay.dart';

const rag2DriftAdditiveReportSchema =
    'caverno_rag2_drift_additive_schema_report';
const rag2DriftHostLogicalTables = {
  'conversations',
  'chat_memory_entries',
  'embeddings',
  'model_usage_daily',
  'conversation_search',
  'rag2_store_meta',
  'rag2_generations',
};
const rag2DriftHostConversationId = 'c-host-preserve';
const rag2DriftHostConversationTitle = 'kept-title';
const rag2DriftHostConversationPayload = '{"id":"c-host-preserve"}';
const rag2DriftHostSearchBody = 'kept-search-body';
const rag2DriftHostUsageDayNumber = 20000;
const rag2DriftHostUsageModel = 'host-usage-model';
const rag2DriftHostUsageTokens = 7;
const _ll5SentinelSourceId = 'll5-sentinel';
const _ll5SentinelSnippet = 'll5-sentinel-snippet';
const _ll5SentinelVector = [1, 2, 3, 4];

Future<void> main(List<String> args) async {
  final options = Rag2DriftAdditiveSchemaOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_drift_additive_schema_replay.dart '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2DriftAdditiveSchemaReplay(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 Drift additive schema replay failed: $error');
    exitCode = 65;
  }
}

Future<Rag2DriftAdditiveSchemaReport> runRag2DriftAdditiveSchemaReplay(
  Rag2DriftAdditiveSchemaOptions options,
) async {
  final fixtureFile = File(options.fixturePath);
  final fixture = await Rag2StorageReplayFixture.load(fixtureFile);
  final declarationIdentity = rag2ExplicitSourceRootsDeclarationIdentity(
    fixture.sourceRoots,
  );
  final baseline = await prepareRag2StorageSnapshot(
    fixtureFile: fixtureFile,
    fixture: fixture,
    spec: fixture.snapshots[0],
  );
  final updated = await prepareRag2StorageSnapshot(
    fixtureFile: fixtureFile,
    fixture: fixture,
    spec: fixture.snapshots[1],
  );

  final reopenDir = _freshDirectory('${options.storeRoot}/reopen');
  final reopenPath = '${reopenDir.path}/caverno.sqlite';
  final seeded = await prepareRag2DriftHost(
    databasePath: reopenPath,
    seedEmbedding: true,
  );
  final reopenStore = Rag2DriftGenerationStore(
    databasePath: reopenPath,
    projectId: fixture.projectId,
  );
  await reopenStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  await reopenStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
  );
  reopenStore.close();
  final reopenedHost = await _openAppDatabase(reopenPath);
  final reopenedGeneration = await readRag2GenerationFromAppDatabase(
    database: reopenedHost,
    projectId: fixture.projectId,
    declarationIdentity: declarationIdentity,
  );
  final reopenedHostRows = await _captureHostRows(reopenedHost);
  final schemaVersion = await reopenedHost
      .customSelect('PRAGMA user_version')
      .getSingle();
  final hostSchema = await inspectRag2DriftHostSchema(reopenedHost);
  await reopenedHost.close();
  final noOpStore = Rag2DriftGenerationStore(
    databasePath: reopenPath,
    projectId: fixture.projectId,
  );
  final reopenedNoOp = await noOpStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
  );
  noOpStore.close();
  final embeddingsPreserved = _sameList(reopenedHostRows.embeddings, [seeded]);
  final conversationSearchPreserved =
      reopenedHostRows.conversations.length == 1 &&
      reopenedHostRows.conversations.single.id == rag2DriftHostConversationId &&
      reopenedHostRows.conversations.single.title ==
          rag2DriftHostConversationTitle &&
      reopenedHostRows.conversations.single.payload ==
          rag2DriftHostConversationPayload &&
      _sameList(reopenedHostRows.fts, const [
        (
          id: rag2DriftHostConversationId,
          title: rag2DriftHostConversationTitle,
          body: rag2DriftHostSearchBody,
        ),
      ]) &&
      reopenedHostRows.usage.length == 1 &&
      reopenedHostRows.usage.single.dayNumber == rag2DriftHostUsageDayNumber &&
      reopenedHostRows.usage.single.model == rag2DriftHostUsageModel &&
      reopenedHostRows.usage.single.totalTokens == rag2DriftHostUsageTokens;
  final rag2Fts5Absent =
      hostSchema.onlyConversationSearchFts5 &&
      _sameSet(hostSchema.logicalTables, rag2DriftHostLogicalTables);
  final attestedTextPreserved =
      reopenedGeneration != null &&
      reopenedGeneration.generation == 2 &&
      reopenedGeneration.snapshot.snapshotHash == updated.snapshotHash &&
      reopenedGeneration.snapshot.chunks.any(
        (chunk) => chunk.content.contains('fixture-secret-alpha'),
      ) &&
      reopenedNoOp.decision == 'no_op' &&
      embeddingsPreserved &&
      conversationSearchPreserved &&
      rag2Fts5Absent &&
      schemaVersion.data['user_version'] == 5;

  final crashDir = _freshDirectory('${options.storeRoot}/crash');
  final crashPath = '${crashDir.path}/caverno.sqlite';
  await prepareRag2DriftHost(databasePath: crashPath, seedEmbedding: true);
  final crashStore = Rag2DriftGenerationStore(
    databasePath: crashPath,
    projectId: fixture.projectId,
  );
  await crashStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  crashStore.close();
  final recoveredGeneration = await recoverAfterKilledUncommittedDriftWrite(
    fixturePath: options.fixturePath,
    databasePath: crashPath,
    projectId: fixture.projectId,
    declarationIdentity: declarationIdentity,
  );
  final crashRecovered =
      recoveredGeneration?.generation == 1 &&
      recoveredGeneration?.snapshot.snapshotHash == baseline.snapshotHash;

  final schemaDir = _freshDirectory('${options.storeRoot}/schema');
  final schemaPath = '${schemaDir.path}/caverno.sqlite';
  await prepareRag2DriftHost(databasePath: schemaPath, seedEmbedding: true);
  final schemaStore = Rag2DriftGenerationStore(
    databasePath: schemaPath,
    projectId: fixture.projectId,
  );
  await schemaStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  schemaStore.close();
  final mutated = sqlite3.open(schemaPath);
  mutated.execute(
    "UPDATE rag2_store_meta SET value = '2' WHERE key = 'schema_version'",
  );
  final mutatedVersion = mutated
      .select("SELECT value FROM rag2_store_meta WHERE key = 'schema_version'")
      .first['value'];
  mutated.close();
  var unsupportedSchemaRejected = false;
  final rejectedStore = Rag2DriftGenerationStore(
    databasePath: schemaPath,
    projectId: fixture.projectId,
  );
  try {
    await rejectedStore.read(declarationIdentity);
  } on Rag2PersistenceException catch (error) {
    final check = sqlite3.open(schemaPath);
    final embeddingCheck = AppDatabase(NativeDatabase(File(schemaPath)));
    try {
      final embeddings = await embeddingCheck
          .select(embeddingCheck.embeddings)
          .get();
      unsupportedSchemaRejected =
          error.reason == 'unsupported_schema' &&
          check
                  .select(
                    "SELECT value FROM rag2_store_meta WHERE key = 'schema_version'",
                  )
                  .first['value'] ==
              mutatedVersion &&
          check
                  .select('SELECT generation FROM rag2_generations')
                  .first['generation'] ==
              1 &&
          embeddings.single.sourceId == _ll5SentinelSourceId;
    } finally {
      await embeddingCheck.close();
      check.close();
    }
  } finally {
    rejectedStore.close();
  }

  final isolateDir = _freshDirectory('${options.storeRoot}/isolate');
  final isolatePath = '${isolateDir.path}/caverno.sqlite';
  await prepareRag2DriftHost(databasePath: isolatePath, seedEmbedding: true);
  final firstSnapshot = await prepareRag2StorageSnapshot(
    fixtureFile: fixtureFile,
    fixture: fixture,
    spec: fixture.snapshots[1],
    projectId: 'persistence-project-a',
  );
  final secondSnapshot = await prepareRag2StorageSnapshot(
    fixtureFile: fixtureFile,
    fixture: fixture,
    spec: fixture.snapshots[0],
    projectId: 'persistence-project-b',
  );
  final firstProject = Rag2DriftGenerationStore(
    databasePath: isolatePath,
    projectId: 'persistence-project-a',
  );
  final secondProject = Rag2DriftGenerationStore(
    databasePath: isolatePath,
    projectId: 'persistence-project-b',
  );
  await firstProject.apply(
    declarationIdentity: declarationIdentity,
    snapshot: firstSnapshot,
  );
  firstProject.close();
  await secondProject.apply(
    declarationIdentity: declarationIdentity,
    snapshot: secondSnapshot,
  );
  secondProject.close();
  final isolatedFirst = Rag2DriftGenerationStore(
    databasePath: isolatePath,
    projectId: 'persistence-project-a',
  );
  final isolatedSecond = Rag2DriftGenerationStore(
    databasePath: isolatePath,
    projectId: 'persistence-project-b',
  );
  final firstRead = await isolatedFirst.read(declarationIdentity);
  final secondRead = await isolatedSecond.read(declarationIdentity);
  isolatedFirst.close();
  isolatedSecond.close();
  final declarationIsolation =
      firstRead?.generation == 1 &&
      firstRead?.snapshot.snapshotHash == firstSnapshot.snapshotHash &&
      secondRead?.generation == 1 &&
      secondRead?.snapshot.snapshotHash == secondSnapshot.snapshotHash;

  var foreignSnapshotRejected = false;
  final foreignPath =
      '${_freshDirectory('${options.storeRoot}/foreign').path}/caverno.sqlite';
  await prepareRag2DriftHost(databasePath: foreignPath, seedEmbedding: true);
  final foreignStore = Rag2DriftGenerationStore(
    databasePath: foreignPath,
    projectId: 'persistence-project-a',
  );
  try {
    await foreignStore.apply(
      declarationIdentity: declarationIdentity,
      snapshot: baseline,
    );
  } on Rag2PersistenceException catch (error) {
    foreignSnapshotRejected = error.reason == 'persisted_identity_mismatch';
  } finally {
    foreignStore.close();
  }

  final report = Rag2DriftAdditiveSchemaReport(
    fixtureId: fixture.fixtureId,
    declarationIdentity: declarationIdentity,
    reopenedGeneration: reopenedGeneration?.generation ?? 0,
    reopenedSnapshotHash: reopenedGeneration?.snapshot.snapshotHash ?? '',
    recoveredGeneration: recoveredGeneration?.generation ?? 0,
    recoveredSnapshotHash: recoveredGeneration?.snapshot.snapshotHash ?? '',
    attestedTextPreserved: attestedTextPreserved,
    embeddingsPreserved: embeddingsPreserved,
    conversationSearchPreserved: conversationSearchPreserved,
    rag2Fts5Absent: rag2Fts5Absent,
    crashRecovered: crashRecovered,
    unsupportedSchemaRejected: unsupportedSchemaRejected,
    declarationIsolation: declarationIsolation,
    foreignSnapshotRejected: foreignSnapshotRejected,
  );
  final outputDirectory = Directory(options.outDir)
    ..createSync(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_drift_additive_schema.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_drift_additive_schema.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<EmbeddingRow> prepareRag2DriftHost({
  required String databasePath,
  bool seedEmbedding = true,
}) async {
  File(databasePath).parent.createSync(recursive: true);
  final before = await _openAppDatabase(databasePath);
  if (seedEmbedding) {
    await before
        .into(before.embeddings)
        .insert(
          EmbeddingsCompanion.insert(
            sourceType: 'conversation',
            sourceId: _ll5SentinelSourceId,
            vector: Uint8List.fromList(_ll5SentinelVector),
            snippet: const Value(_ll5SentinelSnippet),
            model: const Value('ll5-sentinel-model'),
            dim: const Value(1),
          ),
        );
  }
  await before
      .into(before.conversations)
      .insert(
        ConversationsCompanion.insert(
          id: rag2DriftHostConversationId,
          payload: rag2DriftHostConversationPayload,
          title: const Value(rag2DriftHostConversationTitle),
        ),
      );
  await before.indexConversationSearch(
    id: rag2DriftHostConversationId,
    title: rag2DriftHostConversationTitle,
    body: rag2DriftHostSearchBody,
  );
  await before
      .into(before.modelUsageDaily)
      .insert(
        ModelUsageDailyCompanion.insert(
          dayNumber: rag2DriftHostUsageDayNumber,
          model: rag2DriftHostUsageModel,
          totalTokens: const Value(rag2DriftHostUsageTokens),
        ),
      );
  await before.customStatement('DROP TABLE IF EXISTS rag2_generations');
  await before.customStatement('DROP TABLE IF EXISTS rag2_store_meta');
  await before.customStatement('PRAGMA user_version = 4');
  final v4 = await _captureHostRows(before);
  await before.close();
  final after = await _openAppDatabase(databasePath);
  final v5 = await _captureHostRows(after);
  final hostSchema = await inspectRag2DriftHostSchema(after);
  await after.close();
  if (!_sameList(v4.embeddings, v5.embeddings) ||
      !_sameList(v4.conversations, v5.conversations) ||
      !_sameList(v4.usage, v5.usage) ||
      !_sameList(v4.fts, v5.fts)) {
    throw StateError('v4-to-v5 host migration rewrote preserved rows');
  }
  if (v4.tableNames.contains('rag2_store_meta') ||
      v4.tableNames.contains('rag2_generations')) {
    throw StateError('v4 host snapshot still contained RAG2 tables');
  }
  if (!_sameSet(v5.tableNames, {
        ...v4.tableNames,
        'rag2_store_meta',
        'rag2_generations',
      }) ||
      !hostSchema.onlyConversationSearchFts5 ||
      !_sameSet(hostSchema.logicalTables, rag2DriftHostLogicalTables)) {
    throw StateError('v4-to-v5 host migration changed unexpected tables');
  }
  if (v5.embeddings.isEmpty) {
    throw StateError('expected the v4-to-v5 host to preserve embeddings');
  }
  return v5.embeddings.single;
}

Future<Rag2StoredGeneration?> readRag2GenerationFromAppDatabase({
  required AppDatabase database,
  required String projectId,
  required String declarationIdentity,
}) async {
  await ensureRag2AppDatabaseStoreMeta(database);
  final projectIdentity = rag2ExplicitSourceRootsProjectIdentity(projectId);
  final row =
      await (database.select(database.rag2Generations)..where(
            (table) =>
                table.projectIdentity.equals(projectIdentity) &
                table.declarationIdentity.equals(declarationIdentity),
          ))
          .getSingleOrNull();
  if (row == null) {
    return null;
  }
  return generationFromRag2GenerationRow(
    row: row,
    projectId: projectId,
    declarationIdentity: declarationIdentity,
  );
}

Future<void> ensureRag2AppDatabaseStoreMeta(AppDatabase database) async {
  final metadata = {
    for (final row in await database.select(database.rag2StoreMeta).get())
      row.key: row.value,
  };
  if (metadata['schema_name'] != rag2DriftStoreSchema ||
      metadata['schema_version'] != '$rag2DriftStoreSchemaVersion' ||
      metadata['contract'] != rag2DriftAdditiveSchemaContract) {
    throw const Rag2PersistenceException('unsupported_schema');
  }
}

Rag2StoredGeneration generationFromRag2GenerationRow({
  required Rag2GenerationRow row,
  required String projectId,
  required String declarationIdentity,
}) {
  final projectIdentity = rag2ExplicitSourceRootsProjectIdentity(projectId);
  if (row.schemaName != rag2DriftStoreSchema ||
      row.schemaVersion != rag2DriftStoreSchemaVersion ||
      row.contract != rag2DriftAdditiveSchemaContract) {
    throw const Rag2PersistenceException('unsupported_schema');
  }
  if (row.projectId != projectId ||
      row.projectIdentity != projectIdentity ||
      row.declarationIdentity != declarationIdentity) {
    throw const Rag2PersistenceException('persisted_identity_mismatch');
  }
  final decoded = decodeRag2PersistedGeneration(
    bytes: row.payload,
    expectedProjectId: projectId,
    expectedDeclarationIdentity: declarationIdentity,
  );
  if (row.generation != decoded.generation) {
    throw const Rag2PersistenceException('persisted_identity_mismatch');
  }
  if (row.snapshotHash != decoded.snapshot.snapshotHash) {
    throw const Rag2PersistenceException('persisted_hash_mismatch');
  }
  return decoded;
}

Future<Rag2DriftHostSchemaInspection> inspectRag2DriftHostSchema(
  AppDatabase database,
) async {
  final master = await database
      .customSelect('SELECT type, name, tbl_name, sql FROM sqlite_master')
      .get();
  final rows = [for (final row in master) Map<String, Object?>.from(row.data)];
  return Rag2DriftHostSchemaInspection(
    logicalTables: _logicalUserTables(rows),
    onlyConversationSearchFts5: _onlyConversationSearchFts5(rows),
  );
}

Future<AppDatabase> _openAppDatabase(String path) async {
  final database = AppDatabase(NativeDatabase(File(path)));
  await database.customSelect('SELECT 1').get();
  return database;
}

Future<_HostRows> _captureHostRows(AppDatabase database) async {
  final embeddings = [...await database.select(database.embeddings).get()]
    ..sort((left, right) => left.id.compareTo(right.id));
  final conversations = [...await database.select(database.conversations).get()]
    ..sort((left, right) => left.id.compareTo(right.id));
  final usage = [...await database.select(database.modelUsageDaily).get()]
    ..sort((left, right) {
      final day = left.dayNumber.compareTo(right.dayNumber);
      if (day != 0) {
        return day;
      }
      return left.model.compareTo(right.model);
    });
  final ftsRows = await database
      .customSelect(
        'SELECT id, title, body FROM conversation_search ORDER BY id',
      )
      .get();
  final tables = await database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      )
      .get();
  return _HostRows(
    embeddings: embeddings,
    conversations: conversations,
    usage: usage,
    fts: [
      for (final row in ftsRows)
        (
          id: row.read<String>('id'),
          title: row.read<String>('title'),
          body: row.read<String>('body'),
        ),
    ],
    tableNames: {for (final row in tables) row.read<String>('name')},
  );
}

final class Rag2DriftAdditiveSchemaOptions {
  const Rag2DriftAdditiveSchemaOptions({
    required this.fixturePath,
    required this.outDir,
    required this.storeRoot,
  });

  final String fixturePath;
  final String outDir;
  final String storeRoot;

  static Rag2DriftAdditiveSchemaOptions? parse(List<String> args) {
    String? fixturePath;
    String? outDir;
    String? storeRoot;
    for (var index = 0; index < args.length; index++) {
      if (index + 1 >= args.length) {
        return null;
      }
      switch (args[index]) {
        case '--fixture':
          fixturePath = args[++index];
        case '--out-dir':
          outDir = args[++index];
        case '--store-dir':
          storeRoot = args[++index];
        default:
          return null;
      }
    }
    if (fixturePath == null || outDir == null) {
      return null;
    }
    return Rag2DriftAdditiveSchemaOptions(
      fixturePath: fixturePath,
      outDir: outDir,
      storeRoot: storeRoot ?? '$outDir/store',
    );
  }
}

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

bool _sameSet<T>(Set<T> left, Set<T> right) {
  return left.length == right.length && left.containsAll(right);
}

Set<String> _logicalUserTables(List<Map<String, Object?>> master) {
  return {
    for (final row in master)
      if (row['type'] == 'table' && row['name'] is String)
        if (!(row['name'] as String).startsWith('sqlite_') &&
            !(row['name'] as String).startsWith('conversation_search_'))
          row['name'] as String,
  };
}

bool _onlyConversationSearchFts5(List<Map<String, Object?>> master) {
  for (final row in master) {
    final sql = row['sql'];
    if (sql is! String || !sql.toLowerCase().contains('fts5')) {
      continue;
    }
    if ((row['tbl_name'] ?? row['name']) != 'conversation_search') {
      return false;
    }
  }
  return true;
}

final class _HostRows {
  const _HostRows({
    required this.embeddings,
    required this.conversations,
    required this.usage,
    required this.fts,
    required this.tableNames,
  });

  final List<EmbeddingRow> embeddings;
  final List<ConversationRow> conversations;
  final List<ModelUsageDailyRow> usage;
  final List<({String id, String title, String body})> fts;
  final Set<String> tableNames;
}

final class Rag2DriftHostSchemaInspection {
  const Rag2DriftHostSchemaInspection({
    required this.logicalTables,
    required this.onlyConversationSearchFts5,
  });

  final Set<String> logicalTables;
  final bool onlyConversationSearchFts5;
}

Directory _freshDirectory(String path) {
  final directory = Directory(path);
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
  directory.createSync(recursive: true);
  return directory;
}

final class Rag2DriftAdditiveSchemaReport {
  const Rag2DriftAdditiveSchemaReport({
    required this.fixtureId,
    required this.declarationIdentity,
    required this.reopenedGeneration,
    required this.reopenedSnapshotHash,
    required this.recoveredGeneration,
    required this.recoveredSnapshotHash,
    required this.attestedTextPreserved,
    required this.embeddingsPreserved,
    required this.conversationSearchPreserved,
    required this.rag2Fts5Absent,
    required this.crashRecovered,
    required this.unsupportedSchemaRejected,
    required this.declarationIsolation,
    required this.foreignSnapshotRejected,
  });

  final String fixtureId;
  final String declarationIdentity;
  final int reopenedGeneration;
  final String reopenedSnapshotHash;
  final int recoveredGeneration;
  final String recoveredSnapshotHash;
  final bool attestedTextPreserved;
  final bool embeddingsPreserved;
  final bool conversationSearchPreserved;
  final bool rag2Fts5Absent;
  final bool crashRecovered;
  final bool unsupportedSchemaRejected;
  final bool declarationIsolation;
  final bool foreignSnapshotRejected;

  bool get contractPassed =>
      attestedTextPreserved &&
      embeddingsPreserved &&
      conversationSearchPreserved &&
      rag2Fts5Absent &&
      crashRecovered &&
      unsupportedSchemaRejected &&
      declarationIsolation &&
      foreignSnapshotRejected &&
      reopenedGeneration == 2 &&
      recoveredGeneration == 1;

  Map<String, Object?> toJson() => {
    'schemaName': rag2DriftAdditiveReportSchema,
    'schemaVersion': 1,
    'contract': rag2DriftAdditiveSchemaContract,
    'evaluationMode': 'drift_additive_schema_replay',
    'contractDecision': contractPassed ? 'go' : 'no_go',
    'driftAdditiveDecision': contractPassed ? 'go' : 'no_go',
    'fts5Decision': 'not_selected',
    'retrievalDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'appDatabaseSchemaVersion': 5,
    'fixtureId': fixtureId,
    'declarationIdentity': declarationIdentity,
    'reopenedGeneration': reopenedGeneration,
    'reopenedSnapshotHash': reopenedSnapshotHash,
    'recoveredGeneration': recoveredGeneration,
    'recoveredSnapshotHash': recoveredSnapshotHash,
    'attestedTextPreserved': attestedTextPreserved,
    'embeddingsPreserved': embeddingsPreserved,
    'conversationSearchPreserved': conversationSearchPreserved,
    'rag2Fts5Absent': rag2Fts5Absent,
    'crashRecovered': crashRecovered,
    'unsupportedSchemaRejected': unsupportedSchemaRejected,
    'declarationIsolation': declarationIsolation,
    'foreignSnapshotRejected': foreignSnapshotRejected,
  };

  String toMarkdown() =>
      '# RAG2 Drift Additive Schema\n\n'
      '- Contract: `$rag2DriftAdditiveSchemaContract`\n'
      '- Contract decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Drift additive decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- FTS5 decision: `not_selected`\n'
      '- Retrieval decision: `not_evaluated`\n'
      '- Production decision: `no_go`\n'
      '- AppDatabase schema version: `5`\n'
      '- Fixture: `$fixtureId`\n'
      '- Declaration identity: `$declarationIdentity`\n'
      '- Reopened generation / hash: `$reopenedGeneration` / `$reopenedSnapshotHash`\n'
      '- Recovered generation / hash: `$recoveredGeneration` / `$recoveredSnapshotHash`\n'
      '- Attested text preserved: `$attestedTextPreserved`\n'
      '- Embeddings preserved: `$embeddingsPreserved`\n'
      '- Conversation search preserved: `$conversationSearchPreserved`\n'
      '- RAG2 FTS5 absent: `$rag2Fts5Absent`\n'
      '- Crash recovered: `$crashRecovered`\n'
      '- Unsupported schema rejected: `$unsupportedSchemaRejected`\n'
      '- Declaration isolation: `$declarationIsolation`\n'
      '- Foreign snapshot rejected: `$foreignSnapshotRejected`\n';
}
