import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:drift/drift.dart';

import 'rag2_drift_additive_schema_replay.dart';
import 'rag2_drift_dao_generation_store.dart';
import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_fts5_additive_index_replay.dart';
import 'rag2_knowledge_object_replay.dart';
import 'rag2_storage_replay.dart';

const rag2Fts5IncrementalIndexContract =
    'rag2-fts5-incremental-index-contract-v1';
const rag2Fts5IncrementalIndexReportSchema =
    'caverno_rag2_fts5_incremental_index_report';
const _sentinelProjectId = 'rag2-fts5-incremental-sentinel';

Future<void> main(List<String> args) async {
  final options = Rag2Fts5IncrementalIndexOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_fts5_incremental_index_replay.dart '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2Fts5IncrementalIndexReplay(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 FTS5 incremental index replay failed: $error');
    exitCode = 65;
  }
}

Future<Rag2Fts5IncrementalIndexReport> runRag2Fts5IncrementalIndexReplay(
  Rag2Fts5IncrementalIndexOptions options,
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
  final sentinelSnapshot = await prepareRag2StorageSnapshot(
    fixtureFile: fixtureFile,
    fixture: fixture,
    spec: fixture.snapshots[0],
    projectId: _sentinelProjectId,
  );
  final projectIdentity = rag2ExplicitSourceRootsProjectIdentity(
    fixture.projectId,
  );
  final delta = Rag2KnowledgeReplayDelta.compare(baseline, updated);
  final expectedUnchanged = {
    for (final chunkId in delta.unchangedChunkIds) chunkId,
  };

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
  final first = await hostStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
    indexSearch: true,
  );
  final emptySlotFullReplace =
      first.decision == 'applied' &&
      first.generation == 1 &&
      (await rag2ChunkSearchChunkIds(
            hostStore.database,
            projectIdentity: projectIdentity,
            declarationIdentity: declarationIdentity,
          )).length ==
          baseline.chunks.length;
  await hostStore.close();

  final sentinelStore = Rag2DriftDaoGenerationStore.open(
    databasePath: hostPath,
    projectId: _sentinelProjectId,
  );
  await sentinelStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: sentinelSnapshot,
    indexSearch: true,
  );
  await sentinelStore.close();

  final indexedStore = Rag2DriftDaoGenerationStore.open(
    databasePath: hostPath,
    projectId: fixture.projectId,
  );
  final generation1Rowids = await rag2ChunkSearchRowids(
    indexedStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  final generation1Contents = await rag2ChunkSearchContents(
    indexedStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  final replacement = await indexedStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
    indexSearch: true,
  );
  final generation2Rowids = await rag2ChunkSearchRowids(
    indexedStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  final generation2Contents = await rag2ChunkSearchContents(
    indexedStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  final indexedIds = await rag2ChunkSearchChunkIds(
    indexedStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  final unchangedRowidsPreserved =
      expectedUnchanged.isNotEmpty &&
      expectedUnchanged.every(
        (chunkId) =>
            generation1Rowids[chunkId] != null &&
            generation1Rowids[chunkId] == generation2Rowids[chunkId],
      );
  final unchangedContentPreserved = expectedUnchanged.every(
    (chunkId) =>
        generation1Contents[chunkId] != null &&
        generation1Contents[chunkId] == generation2Contents[chunkId],
  );
  final removedChunksAbsent = delta.removedChunkIds.every(
    (chunkId) => !indexedIds.contains(chunkId),
  );
  final addedChunksPresent = delta.addedChunkIds.every(indexedIds.contains);
  var applyRollbackPreserved = false;
  try {
    await indexedStore.apply(
      declarationIdentity: declarationIdentity,
      snapshot: baseline,
      indexSearch: true,
      beforeTxnCommit: () => throw StateError('injected_index_apply_failure'),
    );
  } on StateError catch (error) {
    final generation = await indexedStore.read(declarationIdentity);
    final rolledBackRowids = await rag2ChunkSearchRowids(
      indexedStore.database,
      projectIdentity: projectIdentity,
      declarationIdentity: declarationIdentity,
    );
    applyRollbackPreserved =
        error.message == 'injected_index_apply_failure' &&
        generation?.generation == 2 &&
        generation?.snapshot.snapshotHash == updated.snapshotHash &&
        _sameIntMap(generation2Rowids, rolledBackRowids);
  }
  final chunkSearchSql = await rag2SqliteMasterSql(
    indexedStore.database,
    rag2ChunkSearchTable,
  );
  final conversationSearchSqlAfter = await rag2SqliteMasterSql(
    indexedStore.database,
    'conversation_search',
  );
  final matchedChunkCount = await rag2ChunkSearchMatchedCount(
    indexedStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
    chunks: updated.chunks,
  );
  final indexedTermsPretokenized = await rag2ChunkSearchTermsMatchPolicy(
    indexedStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
    chunks: updated.chunks,
  );
  final conversationSearch = await indexedStore.database
      .customSelect('SELECT id, title, body FROM conversation_search')
      .get();
  final schemaVersion = await indexedStore.database
      .customSelect('PRAGMA user_version')
      .getSingle();
  final embeddings = await indexedStore.database
      .select(indexedStore.database.embeddings)
      .get();
  final conversations = await indexedStore.database
      .select(indexedStore.database.conversations)
      .get();
  final usage = await indexedStore.database
      .select(indexedStore.database.modelUsageDaily)
      .get();
  await indexedStore.close();

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
  final reopenedRowids = await rag2ChunkSearchRowids(
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
  final indexSurvivesReopen =
      _sameStringSet(reopenedChunkIds, expectedUpdatedIds) &&
      _sameIntMap(generation2Rowids, reopenedRowids);
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
  final deltaCountsMatchFixture =
      replacement.decision == 'applied' &&
      replacement.delta.unchangedChunkIds.length ==
          fixture.expected.retainedChunkCount -
              fixture.expected.metadataUpdatedChunkCount &&
      replacement.delta.metadataUpdatedChunkIds.length ==
          fixture.expected.metadataUpdatedChunkCount &&
      replacement.delta.removedChunkIds.length ==
          fixture.expected.removedChunkCount &&
      replacement.delta.addedChunkIds.length ==
          fixture.expected.addedChunkCount;

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
  final crashGeneration1Rowids = await rag2ChunkSearchRowids(
    crashStore.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  await crashStore.close();
  final crashSentinel = Rag2DriftDaoGenerationStore.open(
    databasePath: crashPath,
    projectId: _sentinelProjectId,
  );
  await crashSentinel.apply(
    declarationIdentity: declarationIdentity,
    snapshot: sentinelSnapshot,
    indexSearch: true,
  );
  await crashSentinel.close();
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
  final recoveredRowids = await rag2ChunkSearchRowids(
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
      _sameIntMap(crashGeneration1Rowids, recoveredRowids) &&
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

  final report = Rag2Fts5IncrementalIndexReport(
    fixtureId: fixture.fixtureId,
    declarationIdentity: declarationIdentity,
    reopenedGeneration: reopenedGeneration?.generation ?? 0,
    reopenedSnapshotHash: reopenedGeneration?.snapshot.snapshotHash ?? '',
    indexedChunkCount: indexedIds.length,
    matchedChunkCount: matchedChunkCount,
    unchangedChunkCount: replacement.delta.unchangedChunkIds.length,
    metadataUpdatedChunkCount: replacement.delta.metadataUpdatedChunkIds.length,
    removedChunkCount: replacement.delta.removedChunkIds.length,
    addedChunkCount: replacement.delta.addedChunkIds.length,
    emptySlotFullReplace: emptySlotFullReplace,
    unchangedRowidsPreserved: unchangedRowidsPreserved,
    unchangedContentPreserved: unchangedContentPreserved,
    removedChunksAbsent: removedChunksAbsent,
    addedChunksPresent: addedChunksPresent,
    deltaCountsMatchFixture: deltaCountsMatchFixture,
    sqliteTokenizerPreserved: sqliteTokenizerPreserved,
    indexedTermsPretokenized: indexedTermsPretokenized,
    applyIndexesLastGeneration: applyIndexesLastGeneration,
    allChunksMatchable: allChunksMatchable,
    applyRollbackPreserved: applyRollbackPreserved,
    crashRecoveredIndex: crashRecoveredIndex,
    envelopeMatchesGeneration: envelopeMatchesGeneration,
    indexSurvivesReopen: indexSurvivesReopen,
    generationPreserved: generationPreserved,
    embeddingsPreserved: embeddingsPreserved,
    conversationSearchPreserved: conversationSearchPreserved,
    appDatabaseSchemaUnchanged: appDatabaseSchemaUnchanged,
  );
  final outputDirectory = Directory(options.outDir)
    ..createSync(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_fts5_incremental_index.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_fts5_incremental_index.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<Map<String, int>> rag2ChunkSearchRowids(
  AppDatabase database, {
  required String projectIdentity,
  required String declarationIdentity,
}) async {
  final rows = await database
      .customSelect(
        'SELECT rowid, chunk_id FROM $rag2ChunkSearchTable '
        'WHERE project_identity = ? AND declaration_identity = ?',
        variables: [
          Variable<String>(projectIdentity),
          Variable<String>(declarationIdentity),
        ],
      )
      .get();
  return {
    for (final row in rows)
      row.read<String>('chunk_id'): row.read<int>('rowid'),
  };
}

Future<Map<String, String>> rag2ChunkSearchContents(
  AppDatabase database, {
  required String projectIdentity,
  required String declarationIdentity,
}) async {
  final rows = await database
      .customSelect(
        'SELECT chunk_id, content FROM $rag2ChunkSearchTable '
        'WHERE project_identity = ? AND declaration_identity = ?',
        variables: [
          Variable<String>(projectIdentity),
          Variable<String>(declarationIdentity),
        ],
      )
      .get();
  return {
    for (final row in rows)
      row.read<String>('chunk_id'): row.read<String>('content'),
  };
}

bool _sameStringSet(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}

bool _sameIntMap(Map<String, int> left, Map<String, int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

Directory _freshDirectory(String path) {
  final directory = Directory(path);
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
  directory.createSync(recursive: true);
  return directory;
}

final class Rag2Fts5IncrementalIndexOptions {
  const Rag2Fts5IncrementalIndexOptions({
    required this.fixturePath,
    required this.outDir,
    required this.storeRoot,
  });

  final String fixturePath;
  final String outDir;
  final String storeRoot;

  static Rag2Fts5IncrementalIndexOptions? parse(List<String> args) {
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
    return Rag2Fts5IncrementalIndexOptions(
      fixturePath: fixturePath,
      outDir: outDir,
      storeRoot: storeRoot ?? '$outDir/store',
    );
  }
}

final class Rag2Fts5IncrementalIndexReport {
  const Rag2Fts5IncrementalIndexReport({
    required this.fixtureId,
    required this.declarationIdentity,
    required this.reopenedGeneration,
    required this.reopenedSnapshotHash,
    required this.indexedChunkCount,
    required this.matchedChunkCount,
    required this.unchangedChunkCount,
    required this.metadataUpdatedChunkCount,
    required this.removedChunkCount,
    required this.addedChunkCount,
    required this.emptySlotFullReplace,
    required this.unchangedRowidsPreserved,
    required this.unchangedContentPreserved,
    required this.removedChunksAbsent,
    required this.addedChunksPresent,
    required this.deltaCountsMatchFixture,
    required this.sqliteTokenizerPreserved,
    required this.indexedTermsPretokenized,
    required this.applyIndexesLastGeneration,
    required this.allChunksMatchable,
    required this.applyRollbackPreserved,
    required this.crashRecoveredIndex,
    required this.envelopeMatchesGeneration,
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
  final int unchangedChunkCount;
  final int metadataUpdatedChunkCount;
  final int removedChunkCount;
  final int addedChunkCount;
  final bool emptySlotFullReplace;
  final bool unchangedRowidsPreserved;
  final bool unchangedContentPreserved;
  final bool removedChunksAbsent;
  final bool addedChunksPresent;
  final bool deltaCountsMatchFixture;
  final bool sqliteTokenizerPreserved;
  final bool indexedTermsPretokenized;
  final bool applyIndexesLastGeneration;
  final bool allChunksMatchable;
  final bool applyRollbackPreserved;
  final bool crashRecoveredIndex;
  final bool envelopeMatchesGeneration;
  final bool indexSurvivesReopen;
  final bool generationPreserved;
  final bool embeddingsPreserved;
  final bool conversationSearchPreserved;
  final bool appDatabaseSchemaUnchanged;

  bool get contractPassed =>
      emptySlotFullReplace &&
      unchangedRowidsPreserved &&
      unchangedContentPreserved &&
      removedChunksAbsent &&
      addedChunksPresent &&
      deltaCountsMatchFixture &&
      sqliteTokenizerPreserved &&
      indexedTermsPretokenized &&
      applyIndexesLastGeneration &&
      allChunksMatchable &&
      applyRollbackPreserved &&
      crashRecoveredIndex &&
      envelopeMatchesGeneration &&
      indexSurvivesReopen &&
      generationPreserved &&
      embeddingsPreserved &&
      conversationSearchPreserved &&
      appDatabaseSchemaUnchanged &&
      reopenedGeneration == 2 &&
      indexedChunkCount > 0 &&
      matchedChunkCount == indexedChunkCount &&
      unchangedChunkCount == 2 &&
      metadataUpdatedChunkCount == 2 &&
      removedChunkCount == 1 &&
      addedChunkCount == 1;

  Map<String, Object?> toJson() => {
    'schemaName': rag2Fts5IncrementalIndexReportSchema,
    'schemaVersion': 1,
    'contract': rag2Fts5IncrementalIndexContract,
    'evaluationMode': 'fts5_incremental_index_replay',
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
    'unchangedChunkCount': unchangedChunkCount,
    'metadataUpdatedChunkCount': metadataUpdatedChunkCount,
    'removedChunkCount': removedChunkCount,
    'addedChunkCount': addedChunkCount,
    'emptySlotFullReplace': emptySlotFullReplace,
    'unchangedRowidsPreserved': unchangedRowidsPreserved,
    'unchangedContentPreserved': unchangedContentPreserved,
    'removedChunksAbsent': removedChunksAbsent,
    'addedChunksPresent': addedChunksPresent,
    'deltaCountsMatchFixture': deltaCountsMatchFixture,
    'sqliteTokenizerPreserved': sqliteTokenizerPreserved,
    'indexedTermsPretokenized': indexedTermsPretokenized,
    'applyIndexesLastGeneration': applyIndexesLastGeneration,
    'allChunksMatchable': allChunksMatchable,
    'applyRollbackPreserved': applyRollbackPreserved,
    'crashRecoveredIndex': crashRecoveredIndex,
    'envelopeMatchesGeneration': envelopeMatchesGeneration,
    'indexSurvivesReopen': indexSurvivesReopen,
    'generationPreserved': generationPreserved,
    'embeddingsPreserved': embeddingsPreserved,
    'conversationSearchPreserved': conversationSearchPreserved,
    'appDatabaseSchemaUnchanged': appDatabaseSchemaUnchanged,
  };

  String toMarkdown() =>
      '# RAG2 FTS5 Incremental Index\n\n'
      '- Contract: `$rag2Fts5IncrementalIndexContract`\n'
      '- Contract decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- FTS5 decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Retrieval decision: `not_evaluated`\n'
      '- Production decision: `no_go`\n'
      '- AppDatabase schema version: `5`\n'
      '- Fixture: `$fixtureId`\n'
      '- Declaration identity: `$declarationIdentity`\n'
      '- Reopened generation / hash: `$reopenedGeneration` / `$reopenedSnapshotHash`\n'
      '- Indexed / matched chunk count: `$indexedChunkCount` / `$matchedChunkCount`\n'
      '- Unchanged / metadata-updated / removed / added: `$unchangedChunkCount` / `$metadataUpdatedChunkCount` / `$removedChunkCount` / `$addedChunkCount`\n'
      '- Empty slot full replace: `$emptySlotFullReplace`\n'
      '- Unchanged rowids preserved: `$unchangedRowidsPreserved`\n'
      '- Unchanged content preserved: `$unchangedContentPreserved`\n'
      '- Removed chunks absent: `$removedChunksAbsent`\n'
      '- Added chunks present: `$addedChunksPresent`\n'
      '- Delta counts match fixture: `$deltaCountsMatchFixture`\n'
      '- SQLite tokenizer preserved: `$sqliteTokenizerPreserved`\n'
      '- Indexed terms pretokenized: `$indexedTermsPretokenized`\n'
      '- Apply indexes last generation: `$applyIndexesLastGeneration`\n'
      '- All chunks matchable: `$allChunksMatchable`\n'
      '- Apply rollback preserved: `$applyRollbackPreserved`\n'
      '- Crash recovered index: `$crashRecoveredIndex`\n'
      '- Envelope matches generation: `$envelopeMatchesGeneration`\n'
      '- Index survives reopen: `$indexSurvivesReopen`\n'
      '- Generation preserved: `$generationPreserved`\n'
      '- Embeddings preserved: `$embeddingsPreserved`\n'
      '- Conversation search preserved: `$conversationSearchPreserved`\n'
      '- AppDatabase schema unchanged: `$appDatabaseSchemaUnchanged`\n';
}
