import 'dart:convert';
import 'dart:io';

import 'rag2_drift_additive_schema_replay.dart';
import 'rag2_drift_dao_generation_store.dart';
import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_fts5_additive_index_replay.dart';
import 'rag2_storage_replay.dart';

const rag2Fts5AppDatabaseHostContract =
    'rag2-fts5-appdatabase-host-contract-v1';
const rag2Fts5AppDatabaseHostReportSchema =
    'caverno_rag2_fts5_appdatabase_host_report';

Future<void> main(List<String> args) async {
  final options = Rag2Fts5AppDatabaseHostOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_fts5_appdatabase_host_replay.dart '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2Fts5AppDatabaseHostReplay(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 FTS5 AppDatabase host replay failed: $error');
    exitCode = 65;
  }
}

Future<Rag2Fts5AppDatabaseHostReport> runRag2Fts5AppDatabaseHostReplay(
  Rag2Fts5AppDatabaseHostOptions options,
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
  final projectIdentity = rag2ExplicitSourceRootsProjectIdentity(
    fixture.projectId,
  );

  final hostDir = _freshDirectory('${options.storeRoot}/host');
  final hostPath = '${hostDir.path}/caverno.sqlite';
  final seeded = await prepareRag2DriftHost(
    databasePath: hostPath,
    seedEmbedding: true,
  );
  final hostStore = Rag2DriftDaoGenerationStore.open(
    databasePath: hostPath,
    projectId: fixture.projectId,
  );
  final conversationSearchSqlBefore = await rag2SqliteMasterSql(
    hostStore.database,
    'conversation_search',
  );
  final fts5AbsentAfterHostUpgrade = (await rag2SqliteMasterSql(
    hostStore.database,
    rag2ChunkSearchTable,
  )).isEmpty;
  await hostStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  await hostStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
  );
  final applyWithoutIndexLeavesFts5Absent = (await rag2SqliteMasterSql(
    hostStore.database,
    rag2ChunkSearchTable,
  )).isEmpty;
  final backfill = await hostStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
    indexSearch: true,
  );
  final generationAfterBackfill = await hostStore.read(declarationIdentity);
  final indexedIds = await rag2ChunkSearchChunkIds(
    hostStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  final noOpIndexBackfill =
      backfill.decision == 'no_op' &&
      generationAfterBackfill?.generation == 2 &&
      generationAfterBackfill?.snapshot.snapshotHash == updated.snapshotHash &&
      _sameStringSet(indexedIds, {
        for (final chunk in updated.chunks) chunk.chunkId,
      });
  var applyRollbackPreserved = false;
  try {
    await hostStore.apply(
      declarationIdentity: declarationIdentity,
      snapshot: baseline,
      indexSearch: true,
      beforeTxnCommit: () => throw StateError('injected_index_apply_failure'),
    );
  } on StateError catch (error) {
    final generation = await hostStore.read(declarationIdentity);
    applyRollbackPreserved =
        error.message == 'injected_index_apply_failure' &&
        generation?.generation == 2 &&
        generation?.snapshot.snapshotHash == updated.snapshotHash &&
        _sameStringSet(
          indexedIds,
          await rag2ChunkSearchChunkIds(
            hostStore.database,
            projectIdentity: projectIdentity,
            declarationIdentity: declarationIdentity,
          ),
        ) &&
        await rag2ChunkSearchEnvelopeMatches(
          hostStore.database,
          target: rag2Fts5IndexTarget(
            projectId: fixture.projectId,
            declarationIdentity: declarationIdentity,
            generation: generation!,
          ),
          chunkCount: updated.chunks.length,
        );
  }
  final chunkSearchSql = await rag2SqliteMasterSql(
    hostStore.database,
    rag2ChunkSearchTable,
  );
  final conversationSearchSqlAfter = await rag2SqliteMasterSql(
    hostStore.database,
    'conversation_search',
  );
  final matchedChunkCount = await rag2ChunkSearchMatchedCount(
    hostStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
    chunks: updated.chunks,
  );
  final indexedTermsPretokenized = await rag2ChunkSearchTermsMatchPolicy(
    hostStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
    chunks: updated.chunks,
  );
  final conversationSearch = await hostStore.database
      .customSelect('SELECT id, title, body FROM conversation_search')
      .get();
  final schemaVersion = await hostStore.database
      .customSelect('PRAGMA user_version')
      .getSingle();
  final embeddings = await hostStore.database
      .select(hostStore.database.embeddings)
      .get();
  final conversations = await hostStore.database
      .select(hostStore.database.conversations)
      .get();
  final usage = await hostStore.database
      .select(hostStore.database.modelUsageDaily)
      .get();
  await hostStore.close();

  final reopened = Rag2DriftDaoGenerationStore.open(
    databasePath: hostPath,
    projectId: fixture.projectId,
  );
  final reopenedGeneration = await reopened.read(declarationIdentity);
  final reopenedChunkIds = await rag2ChunkSearchChunkIds(
    reopened.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  final envelopeMatchesGeneration =
      reopenedGeneration != null &&
      await rag2ChunkSearchEnvelopeMatches(
        reopened.database,
        target: rag2Fts5IndexTarget(
          projectId: fixture.projectId,
          declarationIdentity: declarationIdentity,
          generation: reopenedGeneration,
        ),
        chunkCount: updated.chunks.length,
      );
  await reopened.close();

  final expectedUpdatedIds = {
    for (final chunk in updated.chunks) chunk.chunkId,
  };
  final generationPreserved =
      reopenedGeneration != null &&
      reopenedGeneration.generation == 2 &&
      reopenedGeneration.snapshot.snapshotHash == updated.snapshotHash;
  final indexSurvivesReopen = _sameStringSet(
    reopenedChunkIds,
    expectedUpdatedIds,
  );
  final writesThroughAppDatabase =
      chunkSearchSql.contains('project_identity') &&
      chunkSearchSql.contains('declaration_identity') &&
      chunkSearchSql.toLowerCase().contains('fts5') &&
      chunkSearchSql.toLowerCase().contains('unicode61');
  final sqliteTokenizerPreserved =
      chunkSearchSql.toLowerCase().contains('unicode61') &&
      conversationSearchSqlAfter.toLowerCase().contains('unicode61') &&
      conversationSearchSqlAfter == conversationSearchSqlBefore;
  final allChunksMatchable =
      matchedChunkCount == updated.chunks.length && updated.chunks.isNotEmpty;
  final applyIndexesLastGeneration = _sameStringSet(
    indexedIds,
    expectedUpdatedIds,
  );
  final embeddingsPreserved =
      embeddings.length == 1 && embeddings.single == seeded;
  final conversationSearchPreserved =
      conversations.length == 1 &&
      conversations.single.id == rag2DriftHostConversationId &&
      conversations.single.title == rag2DriftHostConversationTitle &&
      conversations.single.payload == rag2DriftHostConversationPayload &&
      conversationSearch.length == 1 &&
      conversationSearch.single.read<String>('id') ==
          rag2DriftHostConversationId &&
      conversationSearch.single.read<String>('title') ==
          rag2DriftHostConversationTitle &&
      conversationSearch.single.read<String>('body') ==
          rag2DriftHostSearchBody &&
      usage.length == 1 &&
      usage.single.dayNumber == rag2DriftHostUsageDayNumber &&
      usage.single.model == rag2DriftHostUsageModel &&
      usage.single.totalTokens == rag2DriftHostUsageTokens;
  final appDatabaseSchemaUnchanged =
      schemaVersion.read<int>('user_version') == 5;

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
    indexSearch: true,
  );
  await crashStore.close();
  final recoveredGeneration = await recoverAfterKilledUncommittedDriftDaoWrite(
    fixturePath: options.fixturePath,
    databasePath: crashPath,
    projectId: fixture.projectId,
    declarationIdentity: declarationIdentity,
    indexSearch: true,
  );
  final recovered = Rag2DriftDaoGenerationStore.open(
    databasePath: crashPath,
    projectId: fixture.projectId,
  );
  final recoveredIds = await rag2ChunkSearchChunkIds(
    recovered.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  final crashRecoveredIndex =
      recoveredGeneration?.generation == 1 &&
      recoveredGeneration?.snapshot.snapshotHash == baseline.snapshotHash &&
      _sameStringSet(recoveredIds, {
        for (final chunk in baseline.chunks) chunk.chunkId,
      }) &&
      await rag2ChunkSearchEnvelopeMatches(
        recovered.database,
        target: rag2Fts5IndexTarget(
          projectId: fixture.projectId,
          declarationIdentity: declarationIdentity,
          generation: recoveredGeneration!,
        ),
        chunkCount: baseline.chunks.length,
      );
  await recovered.close();

  final isolateDir = _freshDirectory('${options.storeRoot}/isolate');
  final isolatePath = '${isolateDir.path}/caverno.sqlite';
  await prepareRag2DriftHost(databasePath: isolatePath, seedEmbedding: true);
  final firstSnapshot = await prepareRag2StorageSnapshot(
    fixtureFile: fixtureFile,
    fixture: fixture,
    spec: fixture.snapshots.last,
    projectId: 'persistence-project-a',
  );
  final secondSnapshot = await prepareRag2StorageSnapshot(
    fixtureFile: fixtureFile,
    fixture: fixture,
    spec: fixture.snapshots.first,
    projectId: 'persistence-project-b',
  );
  final firstProject = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: 'persistence-project-a',
  );
  await firstProject.apply(
    declarationIdentity: declarationIdentity,
    snapshot: firstSnapshot,
    indexSearch: true,
  );
  await firstProject.close();
  final secondProject = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: 'persistence-project-b',
  );
  await secondProject.apply(
    declarationIdentity: declarationIdentity,
    snapshot: secondSnapshot,
    indexSearch: true,
  );
  await secondProject.close();
  final isolated = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: 'persistence-project-a',
  );
  final isolatedFirstIds = await rag2ChunkSearchChunkIds(
    isolated.database,
    projectIdentity: rag2ExplicitSourceRootsProjectIdentity(
      'persistence-project-a',
    ),
    declarationIdentity: declarationIdentity,
  );
  final isolatedSecondIds = await rag2ChunkSearchChunkIds(
    isolated.database,
    projectIdentity: rag2ExplicitSourceRootsProjectIdentity(
      'persistence-project-b',
    ),
    declarationIdentity: declarationIdentity,
  );
  await isolated.close();
  final declarationIsolation =
      _sameStringSet(isolatedFirstIds, {
        for (final chunk in firstSnapshot.chunks) chunk.chunkId,
      }) &&
      _sameStringSet(isolatedSecondIds, {
        for (final chunk in secondSnapshot.chunks) chunk.chunkId,
      }) &&
      !_sameStringSet(isolatedFirstIds, isolatedSecondIds);

  final mismatchDir = _freshDirectory('${options.storeRoot}/mismatch');
  final mismatchPath = '${mismatchDir.path}/caverno.sqlite';
  await prepareRag2DriftHost(databasePath: mismatchPath, seedEmbedding: true);
  final mismatchStore = Rag2DriftDaoGenerationStore.open(
    databasePath: mismatchPath,
    projectId: fixture.projectId,
  );
  await mismatchStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
    indexSearch: true,
  );
  final mismatchGeneration = await mismatchStore.read(declarationIdentity);
  await mismatchStore.database.customStatement(
    'UPDATE $rag2ChunkSearchTable SET snapshot_hash = ? '
    'WHERE project_identity = ? AND declaration_identity = ?',
    ['stale-hash', projectIdentity, declarationIdentity],
  );
  final envelopeMismatchRejected = !await rag2ChunkSearchEnvelopeMatches(
    mismatchStore.database,
    target: rag2Fts5IndexTarget(
      projectId: fixture.projectId,
      declarationIdentity: declarationIdentity,
      generation: mismatchGeneration!,
    ),
    chunkCount: updated.chunks.length,
  );
  await mismatchStore.close();

  final report = Rag2Fts5AppDatabaseHostReport(
    fixtureId: fixture.fixtureId,
    declarationIdentity: declarationIdentity,
    reopenedGeneration: reopenedGeneration?.generation ?? 0,
    reopenedSnapshotHash: reopenedGeneration?.snapshot.snapshotHash ?? '',
    indexedChunkCount: indexedIds.length,
    matchedChunkCount: matchedChunkCount,
    fts5AbsentAfterHostUpgrade: fts5AbsentAfterHostUpgrade,
    applyWithoutIndexLeavesFts5Absent: applyWithoutIndexLeavesFts5Absent,
    noOpIndexBackfill: noOpIndexBackfill,
    writesThroughAppDatabase: writesThroughAppDatabase,
    sqliteTokenizerPreserved: sqliteTokenizerPreserved,
    indexedTermsPretokenized: indexedTermsPretokenized,
    applyIndexesLastGeneration: applyIndexesLastGeneration,
    allChunksMatchable: allChunksMatchable,
    applyRollbackPreserved: applyRollbackPreserved,
    crashRecoveredIndex: crashRecoveredIndex,
    envelopeMatchesGeneration: envelopeMatchesGeneration,
    envelopeMismatchRejected: envelopeMismatchRejected,
    declarationIsolation: declarationIsolation,
    indexSurvivesReopen: indexSurvivesReopen,
    generationPreserved: generationPreserved,
    embeddingsPreserved: embeddingsPreserved,
    conversationSearchPreserved: conversationSearchPreserved,
    appDatabaseSchemaUnchanged: appDatabaseSchemaUnchanged,
  );
  final outputDirectory = Directory(options.outDir)
    ..createSync(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_fts5_appdatabase_host.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_fts5_appdatabase_host.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

bool _sameStringSet(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}

Directory _freshDirectory(String path) {
  final directory = Directory(path);
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
  directory.createSync(recursive: true);
  return directory;
}

final class Rag2Fts5AppDatabaseHostOptions {
  const Rag2Fts5AppDatabaseHostOptions({
    required this.fixturePath,
    required this.outDir,
    required this.storeRoot,
  });

  final String fixturePath;
  final String outDir;
  final String storeRoot;

  static Rag2Fts5AppDatabaseHostOptions? parse(List<String> args) {
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
        case '--store-root':
          storeRoot = args[++index];
        default:
          return null;
      }
    }
    if (fixturePath == null || outDir == null) {
      return null;
    }
    return Rag2Fts5AppDatabaseHostOptions(
      fixturePath: fixturePath,
      outDir: outDir,
      storeRoot: storeRoot ?? '$outDir/store',
    );
  }
}

final class Rag2Fts5AppDatabaseHostReport {
  const Rag2Fts5AppDatabaseHostReport({
    required this.fixtureId,
    required this.declarationIdentity,
    required this.reopenedGeneration,
    required this.reopenedSnapshotHash,
    required this.indexedChunkCount,
    required this.matchedChunkCount,
    required this.fts5AbsentAfterHostUpgrade,
    required this.applyWithoutIndexLeavesFts5Absent,
    required this.noOpIndexBackfill,
    required this.writesThroughAppDatabase,
    required this.sqliteTokenizerPreserved,
    required this.indexedTermsPretokenized,
    required this.applyIndexesLastGeneration,
    required this.allChunksMatchable,
    required this.applyRollbackPreserved,
    required this.crashRecoveredIndex,
    required this.envelopeMatchesGeneration,
    required this.envelopeMismatchRejected,
    required this.declarationIsolation,
    required this.indexSurvivesReopen,
    required this.generationPreserved,
    required this.embeddingsPreserved,
    required this.conversationSearchPreserved,
    required this.appDatabaseSchemaUnchanged,
  });

  final String fixtureId;
  final String declarationIdentity;
  final int reopenedGeneration;
  final String reopenedSnapshotHash;
  final int indexedChunkCount;
  final int matchedChunkCount;
  final bool fts5AbsentAfterHostUpgrade;
  final bool applyWithoutIndexLeavesFts5Absent;
  final bool noOpIndexBackfill;
  final bool writesThroughAppDatabase;
  final bool sqliteTokenizerPreserved;
  final bool indexedTermsPretokenized;
  final bool applyIndexesLastGeneration;
  final bool allChunksMatchable;
  final bool applyRollbackPreserved;
  final bool crashRecoveredIndex;
  final bool envelopeMatchesGeneration;
  final bool envelopeMismatchRejected;
  final bool declarationIsolation;
  final bool indexSurvivesReopen;
  final bool generationPreserved;
  final bool embeddingsPreserved;
  final bool conversationSearchPreserved;
  final bool appDatabaseSchemaUnchanged;

  bool get contractPassed =>
      fts5AbsentAfterHostUpgrade &&
      applyWithoutIndexLeavesFts5Absent &&
      noOpIndexBackfill &&
      writesThroughAppDatabase &&
      sqliteTokenizerPreserved &&
      indexedTermsPretokenized &&
      applyIndexesLastGeneration &&
      allChunksMatchable &&
      applyRollbackPreserved &&
      crashRecoveredIndex &&
      envelopeMatchesGeneration &&
      envelopeMismatchRejected &&
      declarationIsolation &&
      indexSurvivesReopen &&
      generationPreserved &&
      embeddingsPreserved &&
      conversationSearchPreserved &&
      appDatabaseSchemaUnchanged &&
      reopenedGeneration == 2 &&
      indexedChunkCount > 0 &&
      matchedChunkCount == indexedChunkCount;

  Map<String, Object?> toJson() => {
    'schemaName': rag2Fts5AppDatabaseHostReportSchema,
    'schemaVersion': 1,
    'contract': rag2Fts5AppDatabaseHostContract,
    'evaluationMode': 'fts5_appdatabase_host_replay',
    'contractDecision': contractPassed ? 'go' : 'no_go',
    'fts5Decision': contractPassed ? 'go' : 'no_go',
    'retrievalDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'appDatabaseSchemaVersion': 5,
    'fixtureId': fixtureId,
    'declarationIdentity': declarationIdentity,
    'reopenedGeneration': reopenedGeneration,
    'reopenedSnapshotHash': reopenedSnapshotHash,
    'indexedChunkCount': indexedChunkCount,
    'matchedChunkCount': matchedChunkCount,
    'fts5AbsentAfterHostUpgrade': fts5AbsentAfterHostUpgrade,
    'applyWithoutIndexLeavesFts5Absent': applyWithoutIndexLeavesFts5Absent,
    'noOpIndexBackfill': noOpIndexBackfill,
    'writesThroughAppDatabase': writesThroughAppDatabase,
    'sqliteTokenizerPreserved': sqliteTokenizerPreserved,
    'indexedTermsPretokenized': indexedTermsPretokenized,
    'applyIndexesLastGeneration': applyIndexesLastGeneration,
    'allChunksMatchable': allChunksMatchable,
    'applyRollbackPreserved': applyRollbackPreserved,
    'crashRecoveredIndex': crashRecoveredIndex,
    'envelopeMatchesGeneration': envelopeMatchesGeneration,
    'envelopeMismatchRejected': envelopeMismatchRejected,
    'declarationIsolation': declarationIsolation,
    'indexSurvivesReopen': indexSurvivesReopen,
    'generationPreserved': generationPreserved,
    'embeddingsPreserved': embeddingsPreserved,
    'conversationSearchPreserved': conversationSearchPreserved,
    'appDatabaseSchemaUnchanged': appDatabaseSchemaUnchanged,
  };

  String toMarkdown() =>
      '# RAG2 FTS5 AppDatabase Host\n\n'
      '- Contract: `$rag2Fts5AppDatabaseHostContract`\n'
      '- Contract decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- FTS5 decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Retrieval decision: `not_evaluated`\n'
      '- Production decision: `no_go`\n'
      '- AppDatabase schema version: `5`\n'
      '- Fixture: `$fixtureId`\n'
      '- Declaration identity: `$declarationIdentity`\n'
      '- Reopened generation / hash: `$reopenedGeneration` / `$reopenedSnapshotHash`\n'
      '- Indexed / matched chunk count: `$indexedChunkCount` / `$matchedChunkCount`\n'
      '- FTS5 absent after host upgrade: `$fts5AbsentAfterHostUpgrade`\n'
      '- Apply without index leaves FTS5 absent: `$applyWithoutIndexLeavesFts5Absent`\n'
      '- No-op index backfill: `$noOpIndexBackfill`\n'
      '- Writes through AppDatabase: `$writesThroughAppDatabase`\n'
      '- SQLite tokenizer preserved: `$sqliteTokenizerPreserved`\n'
      '- Indexed terms pretokenized: `$indexedTermsPretokenized`\n'
      '- Apply indexes last generation: `$applyIndexesLastGeneration`\n'
      '- All chunks matchable: `$allChunksMatchable`\n'
      '- Apply rollback preserved: `$applyRollbackPreserved`\n'
      '- Crash recovered index: `$crashRecoveredIndex`\n'
      '- Envelope matches generation: `$envelopeMatchesGeneration`\n'
      '- Envelope mismatch rejected: `$envelopeMismatchRejected`\n'
      '- Declaration isolation: `$declarationIsolation`\n'
      '- Index survives reopen: `$indexSurvivesReopen`\n'
      '- Generation preserved: `$generationPreserved`\n'
      '- Embeddings preserved: `$embeddingsPreserved`\n'
      '- Conversation search preserved: `$conversationSearchPreserved`\n'
      '- AppDatabase schema unchanged: `$appDatabaseSchemaUnchanged`\n';
}
