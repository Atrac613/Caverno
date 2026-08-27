import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/datasources/rag2_drift_schema.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

import 'rag2_drift_additive_schema_replay.dart';
import 'rag2_drift_dao_generation_store.dart';
import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_persistence_reopen_replay.dart';
import 'rag2_storage_replay.dart';

const rag2DriftDaoGenerationStoreReportSchema =
    'caverno_rag2_drift_dao_generation_store_report';

Future<void> main(List<String> args) async {
  final options = Rag2DriftDaoGenerationStoreOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_drift_dao_generation_store_replay.dart '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2DriftDaoGenerationStoreReplay(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 Drift DAO generation-store replay failed: $error');
    exitCode = 65;
  }
}

Future<Rag2DriftDaoGenerationStoreReport> runRag2DriftDaoGenerationStoreReplay(
  Rag2DriftDaoGenerationStoreOptions options,
) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
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
  final reopenStore = Rag2DriftDaoGenerationStore.open(
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
  await reopenStore.close();
  final reopenedHost = AppDatabase(NativeDatabase(File(reopenPath)));
  await reopenedHost.customSelect('SELECT 1').get();
  final reopenedGeneration = await readRag2GenerationFromAppDatabase(
    database: reopenedHost,
    projectId: fixture.projectId,
    declarationIdentity: declarationIdentity,
  );
  final schemaVersion = await reopenedHost
      .customSelect('PRAGMA user_version')
      .getSingle();
  final hostSchema = await inspectRag2DriftHostSchema(reopenedHost);
  final embeddings = await reopenedHost.select(reopenedHost.embeddings).get();
  final conversations = await reopenedHost
      .select(reopenedHost.conversations)
      .get();
  final usage = await reopenedHost.select(reopenedHost.modelUsageDaily).get();
  final search = await reopenedHost
      .customSelect('SELECT id, title, body FROM conversation_search')
      .get();
  await reopenedHost.close();
  final noOpStore = Rag2DriftDaoGenerationStore.open(
    databasePath: reopenPath,
    projectId: fixture.projectId,
  );
  final reopenedNoOp = await noOpStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
  );
  await noOpStore.close();
  final embeddingsPreserved =
      embeddings.length == 1 && embeddings.single == seeded;
  final conversationSearchPreserved =
      conversations.length == 1 &&
      conversations.single.id == rag2DriftHostConversationId &&
      conversations.single.title == rag2DriftHostConversationTitle &&
      conversations.single.payload == rag2DriftHostConversationPayload &&
      search.length == 1 &&
      search.single.read<String>('id') == rag2DriftHostConversationId &&
      search.single.read<String>('title') == rag2DriftHostConversationTitle &&
      search.single.read<String>('body') == rag2DriftHostSearchBody &&
      usage.length == 1 &&
      usage.single.dayNumber == rag2DriftHostUsageDayNumber &&
      usage.single.model == rag2DriftHostUsageModel &&
      usage.single.totalTokens == rag2DriftHostUsageTokens;
  final rag2Fts5Absent =
      hostSchema.onlyConversationSearchFts5 &&
      hostSchema.logicalTables.containsAll(rag2DriftHostLogicalTables) &&
      hostSchema.logicalTables.length == rag2DriftHostLogicalTables.length;
  final writesThroughDrift =
      reopenedGeneration != null &&
      reopenedGeneration.generation == 2 &&
      reopenedGeneration.snapshot.snapshotHash == updated.snapshotHash;
  final attestedTextPreserved =
      writesThroughDrift &&
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
  final crashStore = Rag2DriftDaoGenerationStore.open(
    databasePath: crashPath,
    projectId: fixture.projectId,
  );
  await crashStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  await crashStore.close();
  final recoveredGeneration = await recoverAfterKilledUncommittedDriftDaoWrite(
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
  final schemaStore = Rag2DriftDaoGenerationStore.open(
    databasePath: schemaPath,
    projectId: fixture.projectId,
  );
  await schemaStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  await schemaStore.close();
  final mutated = sqlite3.open(schemaPath);
  mutated.execute(
    "UPDATE rag2_store_meta SET value = '2' WHERE key = 'schema_version'",
  );
  final mutatedVersion = mutated
      .select("SELECT value FROM rag2_store_meta WHERE key = 'schema_version'")
      .first['value'];
  mutated.close();
  var unsupportedSchemaRejected = false;
  final rejectedStore = Rag2DriftDaoGenerationStore.open(
    databasePath: schemaPath,
    projectId: fixture.projectId,
  );
  try {
    await rejectedStore.read(declarationIdentity);
  } on Rag2PersistenceException catch (error) {
    final check = sqlite3.open(schemaPath);
    final embeddingCheck = AppDatabase(NativeDatabase(File(schemaPath)));
    try {
      final embeddingRows = await embeddingCheck
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
          embeddingRows.single.sourceId == seeded.sourceId;
    } finally {
      await embeddingCheck.close();
      check.close();
    }
  } finally {
    await rejectedStore.close();
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
  final firstProject = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: 'persistence-project-a',
  );
  await firstProject.apply(
    declarationIdentity: declarationIdentity,
    snapshot: firstSnapshot,
  );
  await firstProject.close();
  final secondProject = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: 'persistence-project-b',
  );
  await secondProject.apply(
    declarationIdentity: declarationIdentity,
    snapshot: secondSnapshot,
  );
  await secondProject.close();
  final isolatedFirst = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: 'persistence-project-a',
  );
  final isolatedSecond = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: 'persistence-project-b',
  );
  final firstRead = await isolatedFirst.read(declarationIdentity);
  final secondRead = await isolatedSecond.read(declarationIdentity);
  await isolatedFirst.close();
  await isolatedSecond.close();
  final declarationIsolation =
      firstRead?.generation == 1 &&
      firstRead?.snapshot.snapshotHash == firstSnapshot.snapshotHash &&
      secondRead?.generation == 1 &&
      secondRead?.snapshot.snapshotHash == secondSnapshot.snapshotHash;

  var foreignSnapshotRejected = false;
  final foreignPath =
      '${_freshDirectory('${options.storeRoot}/foreign').path}/caverno.sqlite';
  await prepareRag2DriftHost(databasePath: foreignPath, seedEmbedding: true);
  final foreignStore = Rag2DriftDaoGenerationStore.open(
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
    await foreignStore.close();
  }

  final rollbackDir = _freshDirectory('${options.storeRoot}/rollback');
  final rollbackPath = '${rollbackDir.path}/caverno.sqlite';
  await prepareRag2DriftHost(databasePath: rollbackPath, seedEmbedding: true);
  final rollbackStore = Rag2DriftDaoGenerationStore.open(
    databasePath: rollbackPath,
    projectId: fixture.projectId,
  );
  await rollbackStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  await rollbackStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
  );
  final beforeFailure = await rollbackStore.read(declarationIdentity);
  final injectedFailure = await rollbackStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
    beforeCommit: (_) => throw StateError('injected_apply_failure'),
  );
  final afterFailure = await rollbackStore.read(declarationIdentity);
  await rollbackStore.close();
  final applyRollbackPreserved =
      injectedFailure.decision == 'rolled_back' &&
      beforeFailure != null &&
      afterFailure != null &&
      afterFailure.generation == beforeFailure.generation &&
      afterFailure.snapshot.snapshotHash ==
          beforeFailure.snapshot.snapshotHash &&
      afterFailure.generation == 2 &&
      afterFailure.snapshot.snapshotHash == updated.snapshotHash;

  final concurrentDir = _freshDirectory('${options.storeRoot}/concurrent');
  final concurrentPath = '${concurrentDir.path}/caverno.sqlite';
  await prepareRag2DriftHost(databasePath: concurrentPath, seedEmbedding: true);
  await Future.wait([
    applyRag2DriftDaoSnapshotInChild(
      fixturePath: options.fixturePath,
      databasePath: concurrentPath,
      snapshotIndex: 0,
    ),
    applyRag2DriftDaoSnapshotInChild(
      fixturePath: options.fixturePath,
      databasePath: concurrentPath,
      snapshotIndex: 1,
    ),
  ]);
  final concurrentStore = Rag2DriftDaoGenerationStore.open(
    databasePath: concurrentPath,
    projectId: fixture.projectId,
  );
  final concurrentGeneration = await concurrentStore.read(declarationIdentity);
  await concurrentStore.close();
  final concurrentWritersSerialized =
      concurrentGeneration != null &&
      concurrentGeneration.generation == 2 &&
      (concurrentGeneration.snapshot.snapshotHash == baseline.snapshotHash ||
          concurrentGeneration.snapshot.snapshotHash == updated.snapshotHash);

  final report = Rag2DriftDaoGenerationStoreReport(
    fixtureId: fixture.fixtureId,
    declarationIdentity: declarationIdentity,
    reopenedGeneration: reopenedGeneration?.generation ?? 0,
    reopenedSnapshotHash: reopenedGeneration?.snapshot.snapshotHash ?? '',
    recoveredGeneration: recoveredGeneration?.generation ?? 0,
    recoveredSnapshotHash: recoveredGeneration?.snapshot.snapshotHash ?? '',
    attestedTextPreserved: attestedTextPreserved,
    writesThroughDrift: writesThroughDrift,
    embeddingsPreserved: embeddingsPreserved,
    conversationSearchPreserved: conversationSearchPreserved,
    rag2Fts5Absent: rag2Fts5Absent,
    crashRecovered: crashRecovered,
    unsupportedSchemaRejected: unsupportedSchemaRejected,
    declarationIsolation: declarationIsolation,
    foreignSnapshotRejected: foreignSnapshotRejected,
    applyRollbackPreserved: applyRollbackPreserved,
    concurrentWritersSerialized: concurrentWritersSerialized,
  );
  final outputDirectory = Directory(options.outDir)
    ..createSync(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_drift_dao_generation_store.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_drift_dao_generation_store.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

final class Rag2DriftDaoGenerationStoreOptions {
  const Rag2DriftDaoGenerationStoreOptions({
    required this.fixturePath,
    required this.outDir,
    required this.storeRoot,
  });

  final String fixturePath;
  final String outDir;
  final String storeRoot;

  static Rag2DriftDaoGenerationStoreOptions? parse(List<String> args) {
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
    return Rag2DriftDaoGenerationStoreOptions(
      fixturePath: fixturePath,
      outDir: outDir,
      storeRoot: storeRoot ?? '$outDir/store',
    );
  }
}

Directory _freshDirectory(String path) {
  final directory = Directory(path);
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
  directory.createSync(recursive: true);
  return directory;
}

final class Rag2DriftDaoGenerationStoreReport {
  const Rag2DriftDaoGenerationStoreReport({
    required this.fixtureId,
    required this.declarationIdentity,
    required this.reopenedGeneration,
    required this.reopenedSnapshotHash,
    required this.recoveredGeneration,
    required this.recoveredSnapshotHash,
    required this.attestedTextPreserved,
    required this.writesThroughDrift,
    required this.embeddingsPreserved,
    required this.conversationSearchPreserved,
    required this.rag2Fts5Absent,
    required this.crashRecovered,
    required this.unsupportedSchemaRejected,
    required this.declarationIsolation,
    required this.foreignSnapshotRejected,
    required this.applyRollbackPreserved,
    required this.concurrentWritersSerialized,
  });

  final String fixtureId;
  final String declarationIdentity;
  final int reopenedGeneration;
  final String reopenedSnapshotHash;
  final int recoveredGeneration;
  final String recoveredSnapshotHash;
  final bool attestedTextPreserved;
  final bool writesThroughDrift;
  final bool embeddingsPreserved;
  final bool conversationSearchPreserved;
  final bool rag2Fts5Absent;
  final bool crashRecovered;
  final bool unsupportedSchemaRejected;
  final bool declarationIsolation;
  final bool foreignSnapshotRejected;
  final bool applyRollbackPreserved;
  final bool concurrentWritersSerialized;

  bool get contractPassed =>
      attestedTextPreserved &&
      writesThroughDrift &&
      embeddingsPreserved &&
      conversationSearchPreserved &&
      rag2Fts5Absent &&
      crashRecovered &&
      unsupportedSchemaRejected &&
      declarationIsolation &&
      foreignSnapshotRejected &&
      applyRollbackPreserved &&
      concurrentWritersSerialized &&
      reopenedGeneration == 2 &&
      recoveredGeneration == 1;

  Map<String, Object?> toJson() => {
    'schemaName': rag2DriftDaoGenerationStoreReportSchema,
    'schemaVersion': 1,
    'contract': rag2DriftDaoGenerationStoreContract,
    'evaluationMode': 'drift_dao_generation_store_replay',
    'contractDecision': contractPassed ? 'go' : 'no_go',
    'driftDaoDecision': contractPassed ? 'go' : 'no_go',
    'rowContract': rag2DriftAdditiveSchemaContract,
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
    'writesThroughDrift': writesThroughDrift,
    'embeddingsPreserved': embeddingsPreserved,
    'conversationSearchPreserved': conversationSearchPreserved,
    'rag2Fts5Absent': rag2Fts5Absent,
    'crashRecovered': crashRecovered,
    'unsupportedSchemaRejected': unsupportedSchemaRejected,
    'declarationIsolation': declarationIsolation,
    'foreignSnapshotRejected': foreignSnapshotRejected,
    'applyRollbackPreserved': applyRollbackPreserved,
    'concurrentWritersSerialized': concurrentWritersSerialized,
  };

  String toMarkdown() =>
      '# RAG2 Drift DAO Generation Store\n\n'
      '- Contract: `$rag2DriftDaoGenerationStoreContract`\n'
      '- Contract decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Drift DAO decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Row contract: `$rag2DriftAdditiveSchemaContract`\n'
      '- FTS5 decision: `not_selected`\n'
      '- Retrieval decision: `not_evaluated`\n'
      '- Production decision: `no_go`\n'
      '- AppDatabase schema version: `5`\n'
      '- Fixture: `$fixtureId`\n'
      '- Declaration identity: `$declarationIdentity`\n'
      '- Reopened generation / hash: `$reopenedGeneration` / `$reopenedSnapshotHash`\n'
      '- Recovered generation / hash: `$recoveredGeneration` / `$recoveredSnapshotHash`\n'
      '- Writes through Drift: `$writesThroughDrift`\n'
      '- Attested text preserved: `$attestedTextPreserved`\n'
      '- Embeddings preserved: `$embeddingsPreserved`\n'
      '- Conversation search preserved: `$conversationSearchPreserved`\n'
      '- RAG2 FTS5 absent: `$rag2Fts5Absent`\n'
      '- Crash recovered: `$crashRecovered`\n'
      '- Unsupported schema rejected: `$unsupportedSchemaRejected`\n'
      '- Declaration isolation: `$declarationIsolation`\n'
      '- Foreign snapshot rejected: `$foreignSnapshotRejected`\n'
      '- Apply rollback preserved: `$applyRollbackPreserved`\n'
      '- Concurrent writers serialized: `$concurrentWritersSerialized`\n';
}
