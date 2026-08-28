import 'dart:convert';
import 'dart:io';

import 'rag2_drift_additive_schema_replay.dart';
import 'rag2_drift_dao_generation_store.dart';
import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_fts5_additive_index_replay.dart';
import 'rag2_fts5_visibility_drop_replay.dart';
import 'rag2_storage_replay.dart';

const rag2Fts5HostedQueryContract = 'rag2-fts5-hosted-query-contract-v1';
const rag2Fts5HostedQueryReportSchema = 'caverno_rag2_fts5_hosted_query_report';
const _neighborProjectId = 'rag2-fts5-hosted-query-neighbor';

Future<void> main(List<String> args) async {
  final options = Rag2Fts5HostedQueryOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_fts5_hosted_query_replay.dart '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2Fts5HostedQueryReplay(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 FTS5 hosted query replay failed: $error');
    exitCode = 65;
  }
}

Future<Rag2Fts5HostedQueryReport> runRag2Fts5HostedQueryReplay(
  Rag2Fts5HostedQueryOptions options,
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
  final queryText = updated.chunks.first.content;
  final expectedHostIds = {for (final chunk in updated.chunks) chunk.chunkId};
  final expectedNeighborIds = {
    for (final chunk in neighborSnapshot.chunks) chunk.chunkId,
  };
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
  final hostHits = await hostStore.querySearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: queryText,
  );
  final emptyHits = await hostStore.querySearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: '   ',
  );
  final queryHitsIndexedSlot =
      hostHits.isNotEmpty &&
      expectedHostIds.containsAll(hostHits) &&
      emptyHits.isEmpty &&
      _isSortedByChunkId(hostHits);

  await hostStore.clearSearchIndex(declarationIdentity: declarationIdentity);
  final hitsAfterClear = await hostStore.querySearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: queryText,
  );
  await hostStore.rebuildSearchIndex(declarationIdentity: declarationIdentity);
  final hitsAfterRebuild = await hostStore.querySearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: queryText,
  );
  final generation = await hostStore.read(declarationIdentity);
  final queryHiddenUntilRebuild =
      hitsAfterClear.isEmpty &&
      hitsAfterRebuild.isNotEmpty &&
      expectedHostIds.containsAll(hitsAfterRebuild) &&
      generation != null &&
      await rag2Fts5SlotMatchesGeneration(
        hostStore.database,
        projectId: fixture.projectId,
        declarationIdentity: declarationIdentity,
        generation: generation,
      );

  await hostStore.database.customStatement(
    'UPDATE $rag2ChunkSearchTable SET snapshot_hash = ? '
    'WHERE project_identity = ? AND declaration_identity = ?',
    ['stale-hash', projectIdentity, declarationIdentity],
  );
  final mismatchedHits = await hostStore.querySearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: queryText,
  );
  final queryRejectsMismatchedEnvelope = mismatchedHits.isEmpty;
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
      usage.single.totalTokens == rag2DriftHostUsageTokens &&
      !hostHits.contains(rag2DriftHostConversationId);
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
  final hostReader = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: fixture.projectId,
  );
  final neighborReader = Rag2DriftDaoGenerationStore.open(
    databasePath: isolatePath,
    projectId: _neighborProjectId,
  );
  final isolatedHostHits = await hostReader.querySearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: queryText,
  );
  final isolatedNeighborHits = await neighborReader.querySearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: queryText,
  );
  final queryIsolatesNeighbor =
      _hitsStayInSlot(
        isolatedHostHits,
        ownIds: expectedHostIds,
        otherIds: expectedNeighborIds,
      ) &&
      _hitsStayInSlot(
        isolatedNeighborHits,
        ownIds: expectedNeighborIds,
        otherIds: expectedHostIds,
      );
  await hostReader.close();
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
  );
  final ftsSqlBeforeQuery = await rag2SqliteMasterSql(
    missingStore.database,
    rag2ChunkSearchTable,
  );
  final missingHits = await missingStore.querySearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: queryText,
  );
  final ftsSqlAfterQuery = await rag2SqliteMasterSql(
    missingStore.database,
    rag2ChunkSearchTable,
  );
  final queryWithoutIndexLeavesFts5Absent =
      ftsSqlBeforeQuery.isEmpty &&
      missingHits.isEmpty &&
      ftsSqlAfterQuery.isEmpty;
  await missingStore.drop(declarationIdentity: declarationIdentity);
  final droppedHits = await missingStore.querySearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: queryText,
  );
  final queryAfterDropIsEmpty = droppedHits.isEmpty;
  await missingStore.close();

  final report = Rag2Fts5HostedQueryReport(
    fixtureId: fixture.fixtureId,
    declarationIdentity: declarationIdentity,
    hostQueryHitCount: hostHits.length,
    neighborQueryHitCount: isolatedNeighborHits.length,
    queryHitsIndexedSlot: queryHitsIndexedSlot,
    queryHiddenUntilRebuild: queryHiddenUntilRebuild,
    queryIsolatesNeighbor: queryIsolatesNeighbor,
    queryRejectsMismatchedEnvelope: queryRejectsMismatchedEnvelope,
    queryWithoutIndexLeavesFts5Absent: queryWithoutIndexLeavesFts5Absent,
    queryAfterDropIsEmpty: queryAfterDropIsEmpty,
    sqliteTokenizerPreserved: sqliteTokenizerPreserved,
    embeddingsPreserved: embeddingsPreserved,
    conversationSearchPreserved: conversationSearchPreserved,
    appDatabaseSchemaUnchanged: appDatabaseSchemaUnchanged,
  );
  final outputDirectory = Directory(options.outDir)
    ..createSync(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_fts5_hosted_query.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_fts5_hosted_query.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

bool _hitsStayInSlot(
  List<String> hits, {
  required Set<String> ownIds,
  required Set<String> otherIds,
}) {
  return hits.isNotEmpty &&
      ownIds.containsAll(hits) &&
      hits.toSet().intersection(otherIds).isEmpty;
}

bool _isSortedByChunkId(List<String> hits) {
  if (hits.length < 2) {
    return hits.isNotEmpty;
  }
  for (var index = 1; index < hits.length; index++) {
    if (hits[index - 1].compareTo(hits[index]) > 0) {
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

final class Rag2Fts5HostedQueryOptions {
  const Rag2Fts5HostedQueryOptions({
    required this.fixturePath,
    required this.outDir,
    required this.storeRoot,
  });

  final String fixturePath;
  final String outDir;
  final String storeRoot;

  static Rag2Fts5HostedQueryOptions? parse(List<String> args) {
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
    return Rag2Fts5HostedQueryOptions(
      fixturePath: fixturePath,
      outDir: outDir,
      storeRoot: storeRoot ?? '$outDir/store',
    );
  }
}

final class Rag2Fts5HostedQueryReport {
  const Rag2Fts5HostedQueryReport({
    required this.fixtureId,
    required this.declarationIdentity,
    required this.hostQueryHitCount,
    required this.neighborQueryHitCount,
    required this.queryHitsIndexedSlot,
    required this.queryHiddenUntilRebuild,
    required this.queryIsolatesNeighbor,
    required this.queryRejectsMismatchedEnvelope,
    required this.queryWithoutIndexLeavesFts5Absent,
    required this.queryAfterDropIsEmpty,
    required this.sqliteTokenizerPreserved,
    required this.embeddingsPreserved,
    required this.conversationSearchPreserved,
    required this.appDatabaseSchemaUnchanged,
  });

  final String fixtureId;
  final String declarationIdentity;
  final int hostQueryHitCount;
  final int neighborQueryHitCount;
  final bool queryHitsIndexedSlot;
  final bool queryHiddenUntilRebuild;
  final bool queryIsolatesNeighbor;
  final bool queryRejectsMismatchedEnvelope;
  final bool queryWithoutIndexLeavesFts5Absent;
  final bool queryAfterDropIsEmpty;
  final bool sqliteTokenizerPreserved;
  final bool embeddingsPreserved;
  final bool conversationSearchPreserved;
  final bool appDatabaseSchemaUnchanged;

  bool get contractPassed =>
      queryHitsIndexedSlot &&
      queryHiddenUntilRebuild &&
      queryIsolatesNeighbor &&
      queryRejectsMismatchedEnvelope &&
      queryWithoutIndexLeavesFts5Absent &&
      queryAfterDropIsEmpty &&
      sqliteTokenizerPreserved &&
      embeddingsPreserved &&
      conversationSearchPreserved &&
      appDatabaseSchemaUnchanged &&
      hostQueryHitCount > 0 &&
      neighborQueryHitCount > 0;

  Map<String, Object?> toJson() => {
    'schemaName': rag2Fts5HostedQueryReportSchema,
    'schemaVersion': 1,
    'contract': rag2Fts5HostedQueryContract,
    'evaluationMode': 'fts5_hosted_query_replay',
    'contractDecision': contractPassed ? 'go' : 'no_go',
    'fts5Decision': contractPassed ? 'go' : 'no_go',
    'retrievalDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'appDatabaseSchemaVersion': 5,
    'fixtureId': fixtureId,
    'declarationIdentity': declarationIdentity,
    'hostQueryHitCount': hostQueryHitCount,
    'neighborQueryHitCount': neighborQueryHitCount,
    'queryHitsIndexedSlot': queryHitsIndexedSlot,
    'queryHiddenUntilRebuild': queryHiddenUntilRebuild,
    'queryIsolatesNeighbor': queryIsolatesNeighbor,
    'queryRejectsMismatchedEnvelope': queryRejectsMismatchedEnvelope,
    'queryWithoutIndexLeavesFts5Absent': queryWithoutIndexLeavesFts5Absent,
    'queryAfterDropIsEmpty': queryAfterDropIsEmpty,
    'sqliteTokenizerPreserved': sqliteTokenizerPreserved,
    'embeddingsPreserved': embeddingsPreserved,
    'conversationSearchPreserved': conversationSearchPreserved,
    'appDatabaseSchemaUnchanged': appDatabaseSchemaUnchanged,
  };

  String toMarkdown() =>
      '# RAG2 FTS5 Hosted Query\n\n'
      '- Contract: `$rag2Fts5HostedQueryContract`\n'
      '- Contract decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- FTS5 decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Retrieval decision: `not_evaluated`\n'
      '- Production decision: `no_go`\n'
      '- AppDatabase schema version: `5`\n'
      '- Fixture: `$fixtureId`\n'
      '- Declaration identity: `$declarationIdentity`\n'
      '- Host query hit count: `$hostQueryHitCount`\n'
      '- Neighbor query hit count: `$neighborQueryHitCount`\n'
      '- Query hits indexed slot: `$queryHitsIndexedSlot`\n'
      '- Query hidden until rebuild: `$queryHiddenUntilRebuild`\n'
      '- Query isolates neighbor: `$queryIsolatesNeighbor`\n'
      '- Query rejects mismatched envelope: `$queryRejectsMismatchedEnvelope`\n'
      '- Query without index leaves FTS5 absent: `$queryWithoutIndexLeavesFts5Absent`\n'
      '- Query after drop is empty: `$queryAfterDropIsEmpty`\n'
      '- SQLite tokenizer preserved: `$sqliteTokenizerPreserved`\n'
      '- Embeddings preserved: `$embeddingsPreserved`\n'
      '- Conversation search preserved: `$conversationSearchPreserved`\n'
      '- AppDatabase schema unchanged: `$appDatabaseSchemaUnchanged`\n';
}
