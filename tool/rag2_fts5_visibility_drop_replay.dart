import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/app_database.dart';

import 'rag2_drift_additive_schema_replay.dart';
import 'rag2_drift_dao_generation_store.dart';
import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_fts5_additive_index_replay.dart';
import 'rag2_storage_replay.dart';

const rag2Fts5VisibilityDropContract = 'rag2-fts5-visibility-drop-contract-v1';
const rag2Fts5VisibilityDropReportSchema =
    'caverno_rag2_fts5_visibility_drop_report';
const _neighborProjectId = 'rag2-fts5-visibility-neighbor';

Future<void> main(List<String> args) async {
  final options = Rag2Fts5VisibilityDropOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_fts5_visibility_drop_replay.dart '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2Fts5VisibilityDropReplay(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 FTS5 visibility drop replay failed: $error');
    exitCode = 65;
  }
}

Future<Rag2Fts5VisibilityDropReport> runRag2Fts5VisibilityDropReplay(
  Rag2Fts5VisibilityDropOptions options,
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
  await hostStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
    indexSearch: true,
  );
  await hostStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
    indexSearch: true,
  );
  await hostStore.clearSearchIndex(declarationIdentity: declarationIdentity);
  final generationAfterClear = await hostStore.read(declarationIdentity);
  final idsAfterClear = await rag2ChunkSearchChunkIds(
    hostStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  final matchedAfterClear = await rag2ChunkSearchMatchedCount(
    hostStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
    chunks: updated.chunks,
  );
  final clearHidesIndex =
      generationAfterClear?.generation == 2 &&
      generationAfterClear?.snapshot.snapshotHash == updated.snapshotHash &&
      idsAfterClear.isEmpty &&
      matchedAfterClear == 0;
  final reenable = await hostStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
    indexSearch: true,
  );
  final restoredGeneration = await hostStore.read(declarationIdentity);
  final clearThenIndexedApplyRestores =
      reenable.decision == 'no_op' &&
      restoredGeneration != null &&
      await rag2Fts5SlotMatchesGeneration(
        hostStore.database,
        projectId: fixture.projectId,
        declarationIdentity: declarationIdentity,
        generation: restoredGeneration,
      );
  var dropRollbackPreserved = false;
  try {
    await hostStore.drop(
      declarationIdentity: declarationIdentity,
      beforeTxnCommit: () => throw StateError('injected_drop_failure'),
    );
  } on StateError catch (error) {
    final generation = await hostStore.read(declarationIdentity);
    dropRollbackPreserved =
        error.message == 'injected_drop_failure' &&
        generation != null &&
        generation.generation == 2 &&
        generation.snapshot.snapshotHash == updated.snapshotHash &&
        await rag2Fts5SlotMatchesGeneration(
          hostStore.database,
          projectId: fixture.projectId,
          declarationIdentity: declarationIdentity,
          generation: generation,
        );
  }
  await hostStore.drop(declarationIdentity: declarationIdentity);
  final generationAfterDrop = await hostStore.read(declarationIdentity);
  final idsAfterDrop = await rag2ChunkSearchChunkIds(
    hostStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  final matchedAfterDrop = await rag2ChunkSearchMatchedCount(
    hostStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
    chunks: updated.chunks,
  );
  final dropRemovesGenerationAndIndex =
      generationAfterDrop == null &&
      idsAfterDrop.isEmpty &&
      matchedAfterDrop == 0;
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
  final reopenedIds = await rag2ChunkSearchChunkIds(
    reopened.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  await reopened.close();
  final dropSurvivesReopen = reopenedGeneration == null && reopenedIds.isEmpty;
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
  final dropper = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: fixture.projectId,
  );
  await dropper.drop(declarationIdentity: declarationIdentity);
  await dropper.close();
  final isolated = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: fixture.projectId,
  );
  final isolatedDroppedIds = await rag2ChunkSearchChunkIds(
    isolated.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  final isolatedDroppedGeneration = await isolated.read(declarationIdentity);
  final neighborReader = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: _neighborProjectId,
  );
  final neighborGeneration = await neighborReader.read(declarationIdentity);
  final neighborIndexPreserved =
      isolatedDroppedGeneration == null &&
      isolatedDroppedIds.isEmpty &&
      neighborGeneration != null &&
      await rag2Fts5SlotMatchesGeneration(
        isolated.database,
        projectId: _neighborProjectId,
        declarationIdentity: declarationIdentity,
        generation: neighborGeneration,
      );
  await isolated.close();
  await neighborReader.close();

  final unindexedDir = _freshDirectory('${options.storeRoot}/unindexed');
  final unindexedPath = '${unindexedDir.path}/caverno.sqlite';
  await prepareRag2DriftHost(databasePath: unindexedPath);
  final unindexedStore = Rag2DriftDaoGenerationStore.open(
    databasePath: unindexedPath,
    projectId: fixture.projectId,
  );
  await unindexedStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
  );
  await unindexedStore.drop(declarationIdentity: declarationIdentity);
  final unindexedGeneration = await unindexedStore.read(declarationIdentity);
  final dropWithoutIndexLeavesFts5Absent =
      unindexedGeneration == null &&
      (await rag2SqliteMasterSql(
        unindexedStore.database,
        rag2ChunkSearchTable,
      )).isEmpty;
  await unindexedStore.close();

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
  await crashStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
    indexSearch: true,
  );
  await crashStore.close();
  final recoveredGeneration = await recoverAfterKilledUncommittedDriftDaoWrite(
    fixturePath: options.fixturePath,
    databasePath: crashPath,
    projectId: fixture.projectId,
    declarationIdentity: declarationIdentity,
    dropUncommitted: true,
  );
  final recovered = Rag2DriftDaoGenerationStore.open(
    databasePath: crashPath,
    projectId: fixture.projectId,
  );
  final crashRecoveredAfterDrop =
      recoveredGeneration != null &&
      recoveredGeneration.generation == 2 &&
      recoveredGeneration.snapshot.snapshotHash == updated.snapshotHash &&
      await rag2Fts5SlotMatchesGeneration(
        recovered.database,
        projectId: fixture.projectId,
        declarationIdentity: declarationIdentity,
        generation: recoveredGeneration,
      );
  await recovered.close();

  final report = Rag2Fts5VisibilityDropReport(
    fixtureId: fixture.fixtureId,
    declarationIdentity: declarationIdentity,
    reopenedGeneration: reopenedGeneration?.generation ?? 0,
    clearHidesIndex: clearHidesIndex,
    clearThenIndexedApplyRestores: clearThenIndexedApplyRestores,
    dropRemovesGenerationAndIndex: dropRemovesGenerationAndIndex,
    dropRollbackPreserved: dropRollbackPreserved,
    crashRecoveredAfterDrop: crashRecoveredAfterDrop,
    neighborIndexPreserved: neighborIndexPreserved,
    dropWithoutIndexLeavesFts5Absent: dropWithoutIndexLeavesFts5Absent,
    dropSurvivesReopen: dropSurvivesReopen,
    sqliteTokenizerPreserved: sqliteTokenizerPreserved,
    embeddingsPreserved: embeddingsPreserved,
    conversationSearchPreserved: conversationSearchPreserved,
    appDatabaseSchemaUnchanged: appDatabaseSchemaUnchanged,
  );
  final outputDirectory = Directory(options.outDir)
    ..createSync(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_fts5_visibility_drop.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_fts5_visibility_drop.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

bool _sameStringSet(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}

Future<bool> rag2Fts5SlotMatchesGeneration(
  AppDatabase database, {
  required String projectId,
  required String declarationIdentity,
  required Rag2StoredGeneration generation,
}) async {
  final chunks = generation.snapshot.chunks;
  final projectIdentity = rag2ExplicitSourceRootsProjectIdentity(projectId);
  final ids = await rag2ChunkSearchChunkIds(
    database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  return chunks.isNotEmpty &&
      _sameStringSet(ids, {for (final chunk in chunks) chunk.chunkId}) &&
      await rag2ChunkSearchEnvelopeMatches(
        database,
        target: rag2Fts5IndexTarget(
          projectId: projectId,
          declarationIdentity: declarationIdentity,
          generation: generation,
        ),
        chunkCount: chunks.length,
      ) &&
      await rag2ChunkSearchTermsMatchPolicy(
        database,
        projectIdentity: projectIdentity,
        declarationIdentity: declarationIdentity,
        chunks: chunks,
      ) &&
      await rag2ChunkSearchMatchedCount(
            database,
            projectIdentity: projectIdentity,
            declarationIdentity: declarationIdentity,
            chunks: chunks,
          ) ==
          chunks.length;
}

Directory _freshDirectory(String path) {
  final directory = Directory(path);
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
  directory.createSync(recursive: true);
  return directory;
}

final class Rag2Fts5VisibilityDropOptions {
  const Rag2Fts5VisibilityDropOptions({
    required this.fixturePath,
    required this.outDir,
    required this.storeRoot,
  });

  final String fixturePath;
  final String outDir;
  final String storeRoot;

  static Rag2Fts5VisibilityDropOptions? parse(List<String> args) {
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
    return Rag2Fts5VisibilityDropOptions(
      fixturePath: fixturePath,
      outDir: outDir,
      storeRoot: storeRoot ?? '$outDir/store',
    );
  }
}

final class Rag2Fts5VisibilityDropReport {
  const Rag2Fts5VisibilityDropReport({
    required this.fixtureId,
    required this.declarationIdentity,
    required this.reopenedGeneration,
    required this.clearHidesIndex,
    required this.clearThenIndexedApplyRestores,
    required this.dropRemovesGenerationAndIndex,
    required this.dropRollbackPreserved,
    required this.crashRecoveredAfterDrop,
    required this.neighborIndexPreserved,
    required this.dropWithoutIndexLeavesFts5Absent,
    required this.dropSurvivesReopen,
    required this.sqliteTokenizerPreserved,
    required this.embeddingsPreserved,
    required this.conversationSearchPreserved,
    required this.appDatabaseSchemaUnchanged,
  });

  final String fixtureId;
  final String declarationIdentity;
  final int reopenedGeneration;
  final bool clearHidesIndex;
  final bool clearThenIndexedApplyRestores;
  final bool dropRemovesGenerationAndIndex;
  final bool dropRollbackPreserved;
  final bool crashRecoveredAfterDrop;
  final bool neighborIndexPreserved;
  final bool dropWithoutIndexLeavesFts5Absent;
  final bool dropSurvivesReopen;
  final bool sqliteTokenizerPreserved;
  final bool embeddingsPreserved;
  final bool conversationSearchPreserved;
  final bool appDatabaseSchemaUnchanged;

  bool get contractPassed =>
      clearHidesIndex &&
      clearThenIndexedApplyRestores &&
      dropRemovesGenerationAndIndex &&
      dropRollbackPreserved &&
      crashRecoveredAfterDrop &&
      neighborIndexPreserved &&
      dropWithoutIndexLeavesFts5Absent &&
      dropSurvivesReopen &&
      sqliteTokenizerPreserved &&
      embeddingsPreserved &&
      conversationSearchPreserved &&
      appDatabaseSchemaUnchanged &&
      reopenedGeneration == 0;

  Map<String, Object?> toJson() => {
    'schemaName': rag2Fts5VisibilityDropReportSchema,
    'schemaVersion': 1,
    'contract': rag2Fts5VisibilityDropContract,
    'evaluationMode': 'fts5_visibility_drop_replay',
    'contractDecision': contractPassed ? 'go' : 'no_go',
    'fts5Decision': contractPassed ? 'go' : 'no_go',
    'retrievalDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'appDatabaseSchemaVersion': 5,
    'fixtureId': fixtureId,
    'declarationIdentity': declarationIdentity,
    'reopenedGeneration': reopenedGeneration,
    'clearHidesIndex': clearHidesIndex,
    'clearThenIndexedApplyRestores': clearThenIndexedApplyRestores,
    'dropRemovesGenerationAndIndex': dropRemovesGenerationAndIndex,
    'dropRollbackPreserved': dropRollbackPreserved,
    'crashRecoveredAfterDrop': crashRecoveredAfterDrop,
    'neighborIndexPreserved': neighborIndexPreserved,
    'dropWithoutIndexLeavesFts5Absent': dropWithoutIndexLeavesFts5Absent,
    'dropSurvivesReopen': dropSurvivesReopen,
    'sqliteTokenizerPreserved': sqliteTokenizerPreserved,
    'embeddingsPreserved': embeddingsPreserved,
    'conversationSearchPreserved': conversationSearchPreserved,
    'appDatabaseSchemaUnchanged': appDatabaseSchemaUnchanged,
  };

  String toMarkdown() =>
      '# RAG2 FTS5 Visibility Drop\n\n'
      '- Contract: `$rag2Fts5VisibilityDropContract`\n'
      '- Contract decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- FTS5 decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Retrieval decision: `not_evaluated`\n'
      '- Production decision: `no_go`\n'
      '- AppDatabase schema version: `5`\n'
      '- Fixture: `$fixtureId`\n'
      '- Declaration identity: `$declarationIdentity`\n'
      '- Reopened generation: `$reopenedGeneration`\n'
      '- Clear hides index: `$clearHidesIndex`\n'
      '- Clear then indexed apply restores: `$clearThenIndexedApplyRestores`\n'
      '- Drop removes generation and index: `$dropRemovesGenerationAndIndex`\n'
      '- Drop rollback preserved: `$dropRollbackPreserved`\n'
      '- Crash recovered after drop: `$crashRecoveredAfterDrop`\n'
      '- Neighbor index preserved: `$neighborIndexPreserved`\n'
      '- Drop without index leaves FTS5 absent: `$dropWithoutIndexLeavesFts5Absent`\n'
      '- Drop survives reopen: `$dropSurvivesReopen`\n'
      '- SQLite tokenizer preserved: `$sqliteTokenizerPreserved`\n'
      '- Embeddings preserved: `$embeddingsPreserved`\n'
      '- Conversation search preserved: `$conversationSearchPreserved`\n'
      '- AppDatabase schema unchanged: `$appDatabaseSchemaUnchanged`\n';
}
