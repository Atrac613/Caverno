import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:drift/drift.dart';

import 'rag2_drift_additive_schema_replay.dart';
import 'rag2_drift_dao_generation_store.dart';
import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_fts5_additive_index_replay.dart';
import 'rag2_fts5_visibility_drop_replay.dart';
import 'rag2_knowledge_object_replay.dart';
import 'rag2_storage_replay.dart';

const rag2Fts5RebuildReopenContract = 'rag2-fts5-rebuild-reopen-contract-v1';
const rag2Fts5RebuildReopenReportSchema =
    'caverno_rag2_fts5_rebuild_reopen_report';
const _neighborProjectId = 'rag2-fts5-rebuild-neighbor';
const _staleHash = 'stale-hash';

Future<void> main(List<String> args) async {
  final options = Rag2Fts5RebuildReopenOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_fts5_rebuild_reopen_replay.dart '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2Fts5RebuildReopenReplay(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 FTS5 rebuild reopen replay failed: $error');
    exitCode = 65;
  }
}

Future<Rag2Fts5RebuildReopenReport> runRag2Fts5RebuildReopenReplay(
  Rag2Fts5RebuildReopenOptions options,
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
  final neighborSnapshot = await prepareRag2StorageSnapshot(
    fixtureFile: fixtureFile,
    fixture: fixture,
    spec: fixture.snapshots[1],
    projectId: _neighborProjectId,
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
  await _applyIndexedGenerations(
    store: hostStore,
    declarationIdentity: declarationIdentity,
    baseline: baseline,
    updated: updated,
  );
  await hostStore.clearSearchIndex(declarationIdentity: declarationIdentity);
  await hostStore.rebuildSearchIndex(declarationIdentity: declarationIdentity);
  final generationAfterClearRebuild = await hostStore.read(declarationIdentity);
  final rebuiltClearedSlot =
      generationAfterClearRebuild?.generation == 2 &&
      generationAfterClearRebuild != null &&
      await rag2Fts5SlotMatchesGeneration(
        hostStore.database,
        projectId: fixture.projectId,
        declarationIdentity: declarationIdentity,
        generation: generationAfterClearRebuild,
      );

  await hostStore.database.customStatement(
    'UPDATE $rag2ChunkSearchTable SET snapshot_hash = ? '
    'WHERE project_identity = ? AND declaration_identity = ?',
    [_staleHash, projectIdentity, declarationIdentity],
  );
  await hostStore.rebuildSearchIndex(declarationIdentity: declarationIdentity);
  final generationAfterMismatchRebuild = await hostStore.read(
    declarationIdentity,
  );
  final rebuiltMismatchedSlot =
      generationAfterMismatchRebuild?.generation == 2 &&
      generationAfterMismatchRebuild != null &&
      await rag2Fts5SlotMatchesGeneration(
        hostStore.database,
        projectId: fixture.projectId,
        declarationIdentity: declarationIdentity,
        generation: generationAfterMismatchRebuild,
      );
  await hostStore.rebuildSearchIndex(declarationIdentity: declarationIdentity);
  final generationAfterSecondRebuild = await hostStore.read(
    declarationIdentity,
  );
  final rebuildDeterministic =
      generationAfterSecondRebuild?.generation == 2 &&
      generationAfterSecondRebuild != null &&
      await rag2Fts5SlotMatchesGeneration(
        hostStore.database,
        projectId: fixture.projectId,
        declarationIdentity: declarationIdentity,
        generation: generationAfterSecondRebuild,
      );

  await hostStore.database.customStatement(
    'UPDATE $rag2ChunkSearchTable SET snapshot_hash = ? '
    'WHERE project_identity = ? AND declaration_identity = ?',
    [_staleHash, projectIdentity, declarationIdentity],
  );
  var rebuildRollbackPreserved = false;
  try {
    await hostStore.rebuildSearchIndex(
      declarationIdentity: declarationIdentity,
      beforeTxnCommit: () => throw StateError('injected_rebuild_failure'),
    );
  } on StateError catch (error) {
    final generation = await hostStore.read(declarationIdentity);
    final hashes = await _slotSnapshotHashes(
      hostStore.database,
      projectIdentity: projectIdentity,
      declarationIdentity: declarationIdentity,
    );
    rebuildRollbackPreserved =
        error.message == 'injected_rebuild_failure' &&
        generation?.generation == 2 &&
        hashes.length == 1 &&
        hashes.contains(_staleHash);
  }
  await hostStore.rebuildSearchIndex(declarationIdentity: declarationIdentity);

  final conversationSearchSqlAfter = await rag2SqliteMasterSql(
    hostStore.database,
    'conversation_search',
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
  final rebuildReopened =
      reopenedGeneration?.generation == 2 &&
      reopenedGeneration != null &&
      await rag2Fts5SlotMatchesGeneration(
        reopened.database,
        projectId: fixture.projectId,
        declarationIdentity: declarationIdentity,
        generation: reopenedGeneration,
      );
  await reopened.close();
  final sqliteTokenizerPreserved =
      conversationSearchSqlAfter.toLowerCase().contains('unicode61') &&
      conversationSearchSqlAfter == conversationSearchSqlBefore;
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

  final isolateDir = _freshDirectory('${options.storeRoot}/isolate');
  final isolatePath = '${isolateDir.path}/caverno.sqlite';
  await prepareRag2DriftHost(databasePath: isolatePath, seedEmbedding: true);
  final firstProject = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: fixture.projectId,
  );
  await firstProject.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
    indexSearch: true,
  );
  await firstProject.close();
  final neighborStore = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: _neighborProjectId,
  );
  await neighborStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: neighborSnapshot,
    indexSearch: true,
  );
  await neighborStore.close();
  final rebuildTarget = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: fixture.projectId,
  );
  await rebuildTarget.clearSearchIndex(
    declarationIdentity: declarationIdentity,
  );
  await rebuildTarget.rebuildSearchIndex(
    declarationIdentity: declarationIdentity,
  );
  final rebuiltTargetGeneration = await rebuildTarget.read(declarationIdentity);
  final neighborReader = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: _neighborProjectId,
  );
  final neighborGeneration = await neighborReader.read(declarationIdentity);
  final neighborIndexPreserved =
      rebuiltTargetGeneration != null &&
      neighborGeneration != null &&
      await rag2Fts5SlotMatchesGeneration(
        rebuildTarget.database,
        projectId: fixture.projectId,
        declarationIdentity: declarationIdentity,
        generation: rebuiltTargetGeneration,
      ) &&
      await rag2Fts5SlotMatchesGeneration(
        rebuildTarget.database,
        projectId: _neighborProjectId,
        declarationIdentity: declarationIdentity,
        generation: neighborGeneration,
      );
  await rebuildTarget.close();
  await neighborReader.close();

  final missingDir = _freshDirectory('${options.storeRoot}/missing');
  final missingPath = '${missingDir.path}/caverno.sqlite';
  await prepareRag2DriftHost(databasePath: missingPath);
  final missingStore = Rag2DriftDaoGenerationStore.open(
    databasePath: missingPath,
    projectId: fixture.projectId,
  );
  await missingStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
    indexSearch: true,
  );
  await missingStore.drop(declarationIdentity: declarationIdentity);
  await missingStore.rebuildSearchIndex(
    declarationIdentity: declarationIdentity,
  );
  final missingGeneration = await missingStore.read(declarationIdentity);
  final missingIds = await rag2ChunkSearchChunkIds(
    missingStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  final rebuildWithoutGenerationNoOp =
      missingGeneration == null && missingIds.isEmpty;
  await missingStore.close();

  final unindexedDir = _freshDirectory('${options.storeRoot}/unindexed');
  final unindexedPath = '${unindexedDir.path}/caverno.sqlite';
  await prepareRag2DriftHost(databasePath: unindexedPath);
  final unindexedStore = Rag2DriftDaoGenerationStore.open(
    databasePath: unindexedPath,
    projectId: fixture.projectId,
  );
  await unindexedStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  await unindexedStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
  );
  final ftsAbsentBeforeRebuild = (await rag2SqliteMasterSql(
    unindexedStore.database,
    rag2ChunkSearchTable,
  )).isEmpty;
  await unindexedStore.rebuildSearchIndex(
    declarationIdentity: declarationIdentity,
  );
  final unindexedGeneration = await unindexedStore.read(declarationIdentity);
  final rebuildUnindexedCreatesIndex =
      ftsAbsentBeforeRebuild &&
      unindexedGeneration?.generation == 2 &&
      unindexedGeneration != null &&
      await rag2Fts5SlotMatchesGeneration(
        unindexedStore.database,
        projectId: fixture.projectId,
        declarationIdentity: declarationIdentity,
        generation: unindexedGeneration,
      );
  await unindexedStore.close();

  final crashDir = _freshDirectory('${options.storeRoot}/crash');
  final crashPath = '${crashDir.path}/caverno.sqlite';
  await prepareRag2DriftHost(databasePath: crashPath, seedEmbedding: true);
  final crashStore = Rag2DriftDaoGenerationStore.open(
    databasePath: crashPath,
    projectId: fixture.projectId,
  );
  await _applyIndexedGenerations(
    store: crashStore,
    declarationIdentity: declarationIdentity,
    baseline: baseline,
    updated: updated,
  );
  await crashStore.clearSearchIndex(declarationIdentity: declarationIdentity);
  await crashStore.close();
  final recoveredGeneration = await recoverAfterKilledUncommittedDriftDaoWrite(
    fixturePath: options.fixturePath,
    databasePath: crashPath,
    projectId: fixture.projectId,
    declarationIdentity: declarationIdentity,
    rebuildUncommitted: true,
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
  final crashRecoveredAfterRebuild =
      recoveredGeneration?.generation == 2 &&
      recoveredGeneration?.snapshot.snapshotHash == updated.snapshotHash &&
      recoveredIds.isEmpty;
  await recovered.close();

  final report = Rag2Fts5RebuildReopenReport(
    fixtureId: fixture.fixtureId,
    declarationIdentity: declarationIdentity,
    reopenedGeneration: reopenedGeneration?.generation ?? 0,
    rebuiltClearedSlot: rebuiltClearedSlot,
    rebuiltMismatchedSlot: rebuiltMismatchedSlot,
    rebuildDeterministic: rebuildDeterministic,
    rebuildReopened: rebuildReopened,
    rebuildRollbackPreserved: rebuildRollbackPreserved,
    crashRecoveredAfterRebuild: crashRecoveredAfterRebuild,
    neighborIndexPreserved: neighborIndexPreserved,
    rebuildWithoutGenerationNoOp: rebuildWithoutGenerationNoOp,
    rebuildUnindexedCreatesIndex: rebuildUnindexedCreatesIndex,
    sqliteTokenizerPreserved: sqliteTokenizerPreserved,
    embeddingsPreserved: embeddingsPreserved,
    conversationSearchPreserved: conversationSearchPreserved,
    appDatabaseSchemaUnchanged: appDatabaseSchemaUnchanged,
  );
  final outputDirectory = Directory(options.outDir)
    ..createSync(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_fts5_rebuild_reopen.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_fts5_rebuild_reopen.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<void> _applyIndexedGenerations({
  required Rag2DriftDaoGenerationStore store,
  required String declarationIdentity,
  required Rag2KnowledgeSnapshot baseline,
  required Rag2KnowledgeSnapshot updated,
}) async {
  await store.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
    indexSearch: true,
  );
  await store.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
    indexSearch: true,
  );
}

Future<Set<String>> _slotSnapshotHashes(
  AppDatabase database, {
  required String projectIdentity,
  required String declarationIdentity,
}) async {
  final rows = await database
      .customSelect(
        'SELECT DISTINCT snapshot_hash AS snapshot_hash '
        'FROM $rag2ChunkSearchTable '
        'WHERE project_identity = ? AND declaration_identity = ?',
        variables: [
          Variable<String>(projectIdentity),
          Variable<String>(declarationIdentity),
        ],
      )
      .get();
  return {for (final row in rows) row.read<String>('snapshot_hash')};
}

Directory _freshDirectory(String path) {
  final directory = Directory(path);
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
  directory.createSync(recursive: true);
  return directory;
}

final class Rag2Fts5RebuildReopenOptions {
  const Rag2Fts5RebuildReopenOptions({
    required this.fixturePath,
    required this.outDir,
    required this.storeRoot,
  });

  final String fixturePath;
  final String outDir;
  final String storeRoot;

  static Rag2Fts5RebuildReopenOptions? parse(List<String> args) {
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
    return Rag2Fts5RebuildReopenOptions(
      fixturePath: fixturePath,
      outDir: outDir,
      storeRoot: storeRoot ?? '$outDir/store',
    );
  }
}

final class Rag2Fts5RebuildReopenReport {
  const Rag2Fts5RebuildReopenReport({
    required this.fixtureId,
    required this.declarationIdentity,
    required this.reopenedGeneration,
    required this.rebuiltClearedSlot,
    required this.rebuiltMismatchedSlot,
    required this.rebuildDeterministic,
    required this.rebuildReopened,
    required this.rebuildRollbackPreserved,
    required this.crashRecoveredAfterRebuild,
    required this.neighborIndexPreserved,
    required this.rebuildWithoutGenerationNoOp,
    required this.rebuildUnindexedCreatesIndex,
    required this.sqliteTokenizerPreserved,
    required this.embeddingsPreserved,
    required this.conversationSearchPreserved,
    required this.appDatabaseSchemaUnchanged,
  });

  final String fixtureId;
  final String declarationIdentity;
  final int reopenedGeneration;
  final bool rebuiltClearedSlot;
  final bool rebuiltMismatchedSlot;
  final bool rebuildDeterministic;
  final bool rebuildReopened;
  final bool rebuildRollbackPreserved;
  final bool crashRecoveredAfterRebuild;
  final bool neighborIndexPreserved;
  final bool rebuildWithoutGenerationNoOp;
  final bool rebuildUnindexedCreatesIndex;
  final bool sqliteTokenizerPreserved;
  final bool embeddingsPreserved;
  final bool conversationSearchPreserved;
  final bool appDatabaseSchemaUnchanged;

  bool get contractPassed =>
      rebuiltClearedSlot &&
      rebuiltMismatchedSlot &&
      rebuildDeterministic &&
      rebuildReopened &&
      rebuildRollbackPreserved &&
      crashRecoveredAfterRebuild &&
      neighborIndexPreserved &&
      rebuildWithoutGenerationNoOp &&
      rebuildUnindexedCreatesIndex &&
      sqliteTokenizerPreserved &&
      embeddingsPreserved &&
      conversationSearchPreserved &&
      appDatabaseSchemaUnchanged &&
      reopenedGeneration == 2;

  Map<String, Object?> toJson() => {
    'schemaName': rag2Fts5RebuildReopenReportSchema,
    'schemaVersion': 1,
    'contract': rag2Fts5RebuildReopenContract,
    'evaluationMode': 'fts5_rebuild_reopen_replay',
    'contractDecision': contractPassed ? 'go' : 'no_go',
    'fts5Decision': contractPassed ? 'go' : 'no_go',
    'retrievalDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'appDatabaseSchemaVersion': 5,
    'fixtureId': fixtureId,
    'declarationIdentity': declarationIdentity,
    'reopenedGeneration': reopenedGeneration,
    'rebuiltClearedSlot': rebuiltClearedSlot,
    'rebuiltMismatchedSlot': rebuiltMismatchedSlot,
    'rebuildDeterministic': rebuildDeterministic,
    'rebuildReopened': rebuildReopened,
    'rebuildRollbackPreserved': rebuildRollbackPreserved,
    'crashRecoveredAfterRebuild': crashRecoveredAfterRebuild,
    'neighborIndexPreserved': neighborIndexPreserved,
    'rebuildWithoutGenerationNoOp': rebuildWithoutGenerationNoOp,
    'rebuildUnindexedCreatesIndex': rebuildUnindexedCreatesIndex,
    'sqliteTokenizerPreserved': sqliteTokenizerPreserved,
    'embeddingsPreserved': embeddingsPreserved,
    'conversationSearchPreserved': conversationSearchPreserved,
    'appDatabaseSchemaUnchanged': appDatabaseSchemaUnchanged,
  };

  String toMarkdown() =>
      '# RAG2 FTS5 Rebuild Reopen\n\n'
      '- Contract: `$rag2Fts5RebuildReopenContract`\n'
      '- Contract decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- FTS5 decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Retrieval decision: `not_evaluated`\n'
      '- Production decision: `no_go`\n'
      '- AppDatabase schema version: `5`\n'
      '- Fixture: `$fixtureId`\n'
      '- Declaration identity: `$declarationIdentity`\n'
      '- Reopened generation: `$reopenedGeneration`\n'
      '- Rebuilt cleared slot: `$rebuiltClearedSlot`\n'
      '- Rebuilt mismatched slot: `$rebuiltMismatchedSlot`\n'
      '- Rebuild deterministic: `$rebuildDeterministic`\n'
      '- Rebuild reopened: `$rebuildReopened`\n'
      '- Rebuild rollback preserved: `$rebuildRollbackPreserved`\n'
      '- Crash recovered after rebuild: `$crashRecoveredAfterRebuild`\n'
      '- Neighbor index preserved: `$neighborIndexPreserved`\n'
      '- Rebuild without generation no-op: `$rebuildWithoutGenerationNoOp`\n'
      '- Rebuild unindexed creates index: `$rebuildUnindexedCreatesIndex`\n'
      '- SQLite tokenizer preserved: `$sqliteTokenizerPreserved`\n'
      '- Embeddings preserved: `$embeddingsPreserved`\n'
      '- Conversation search preserved: `$conversationSearchPreserved`\n'
      '- AppDatabase schema unchanged: `$appDatabaseSchemaUnchanged`\n';
}
