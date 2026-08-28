import 'dart:convert';
import 'dart:io';

import 'rag2_drift_additive_schema_replay.dart';
import 'rag2_drift_dao_generation_store.dart';
import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_fts5_additive_index_replay.dart';
import 'rag2_knowledge_object_replay.dart';
import 'rag2_lexical_policy_bakeoff.dart';
import 'rag2_storage_replay.dart';

const rag2Fts5HostedQueryProjectionContract =
    'rag2-fts5-hosted-query-projection-contract-v1';
const rag2Fts5HostedQueryProjectionReportSchema =
    'caverno_rag2_fts5_hosted_query_projection_report';
const rag2Fts5UnknownProjectionChunkId = 'kc_unknown_projection_sentinel';
const rag2Fts5MismatchedProjectionObjectId =
    'ko_mismatched_projection_sentinel';
const _neighborProjectId = 'rag2-fts5-query-projection-neighbor';

Future<void> main(List<String> args) async {
  final options = Rag2Fts5HostedQueryProjectionOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_fts5_hosted_query_projection_replay.dart '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2Fts5HostedQueryProjectionReplay(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 FTS5 hosted query projection replay failed: $error');
    exitCode = 65;
  }
}

Future<Rag2Fts5HostedQueryProjectionReport>
runRag2Fts5HostedQueryProjectionReplay(
  Rag2Fts5HostedQueryProjectionOptions options,
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
  final matchIds = await hostStore.querySearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: queryText,
  );
  final generation = await hostStore.read(declarationIdentity);
  final hostHits = await hostStore.projectSearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: queryText,
  );
  final emptyHits = await hostStore.projectSearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: '   ',
  );
  final projectionMatchesPayload = _projectionMatchesPayload(
    hits: hostHits,
    chunks: updated.chunks,
    matchIds: matchIds,
    generation: generation!,
  );
  final projectionOmitsContent = hostHits.every(
    (hit) => !hit.toJson().containsKey('content'),
  );
  final projectionKeepsRepoRelativePaths = hostHits.every((hit) {
    try {
      validateRag2RepoRelativePath(hit.repoRelativePath);
      return true;
    } on FormatException {
      return false;
    }
  });
  final queryProjectsIndexedSlot =
      hostHits.isNotEmpty &&
      expectedHostIds.containsAll([for (final hit in hostHits) hit.chunkId]) &&
      emptyHits.isEmpty &&
      projectionMatchesPayload &&
      projectionOmitsContent &&
      projectionKeepsRepoRelativePaths;

  await hostStore.database.customStatement(
    'INSERT INTO $rag2ChunkSearchTable('
    'project_identity, declaration_identity, generation, snapshot_hash, '
    'chunk_id, object_id, content) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      projectIdentity,
      declarationIdentity,
      generation.generation,
      generation.snapshot.snapshotHash,
      rag2Fts5UnknownProjectionChunkId,
      'ko_unknown_projection_sentinel',
      tokenizeRag2Lexical(queryText, Rag2LexicalPolicy.trigram).join(' '),
    ],
  );
  final idsAfterUnknown = await hostStore.querySearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: queryText,
  );
  final hitsAfterUnknown = await hostStore.projectSearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: queryText,
  );
  final queryRejectsUnknownChunkId =
      idsAfterUnknown.contains(rag2Fts5UnknownProjectionChunkId) &&
      hitsAfterUnknown.isEmpty;
  await hostStore.rebuildSearchIndex(declarationIdentity: declarationIdentity);

  var queryRejectsMismatchedFtsRow = false;
  if (matchIds.isNotEmpty) {
    await hostStore.database.customStatement(
      'UPDATE $rag2ChunkSearchTable SET object_id = ? '
      'WHERE project_identity = ? AND declaration_identity = ? AND chunk_id = ?',
      [
        rag2Fts5MismatchedProjectionObjectId,
        projectIdentity,
        declarationIdentity,
        matchIds.first,
      ],
    );
    final idsAfterObjectMismatch = await hostStore.querySearchIndex(
      declarationIdentity: declarationIdentity,
      queryText: queryText,
    );
    final hitsAfterObjectMismatch = await hostStore.projectSearchIndex(
      declarationIdentity: declarationIdentity,
      queryText: queryText,
    );
    await hostStore.rebuildSearchIndex(
      declarationIdentity: declarationIdentity,
    );
    await hostStore.database.customStatement(
      'UPDATE $rag2ChunkSearchTable SET content = ? '
      'WHERE project_identity = ? AND declaration_identity = ? AND chunk_id = ?',
      [
        '${tokenizeRag2Lexical(queryText, Rag2LexicalPolicy.trigram).join(' ')} extra',
        projectIdentity,
        declarationIdentity,
        matchIds.first,
      ],
    );
    final idsAfterContentMismatch = await hostStore.querySearchIndex(
      declarationIdentity: declarationIdentity,
      queryText: queryText,
    );
    final hitsAfterContentMismatch = await hostStore.projectSearchIndex(
      declarationIdentity: declarationIdentity,
      queryText: queryText,
    );
    queryRejectsMismatchedFtsRow =
        idsAfterObjectMismatch.contains(matchIds.first) &&
        hitsAfterObjectMismatch.isEmpty &&
        idsAfterContentMismatch.contains(matchIds.first) &&
        hitsAfterContentMismatch.isEmpty;
    await hostStore.rebuildSearchIndex(
      declarationIdentity: declarationIdentity,
    );
  }

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
      ![
        for (final hit in hostHits) hit.chunkId,
      ].contains(rag2DriftHostConversationId);
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
  final isolatedHostHits = await hostReader.projectSearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: queryText,
  );
  final isolatedNeighborHits = await neighborReader.projectSearchIndex(
    declarationIdentity: declarationIdentity,
    queryText: queryText,
  );
  final queryIsolatesNeighbor =
      _hitsStayInSlot(
        isolatedHostHits,
        ownIds: expectedHostIds,
        otherIds: expectedNeighborIds,
        projectId: fixture.projectId,
      ) &&
      _hitsStayInSlot(
        isolatedNeighborHits,
        ownIds: expectedNeighborIds,
        otherIds: expectedHostIds,
        projectId: _neighborProjectId,
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
  final missingHits = await missingStore.projectSearchIndex(
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
  await missingStore.close();

  final report = Rag2Fts5HostedQueryProjectionReport(
    fixtureId: fixture.fixtureId,
    declarationIdentity: declarationIdentity,
    hostQueryHitCount: hostHits.length,
    neighborQueryHitCount: isolatedNeighborHits.length,
    queryProjectsIndexedSlot: queryProjectsIndexedSlot,
    queryRejectsUnknownChunkId: queryRejectsUnknownChunkId,
    queryRejectsMismatchedFtsRow: queryRejectsMismatchedFtsRow,
    queryIsolatesNeighbor: queryIsolatesNeighbor,
    queryWithoutIndexLeavesFts5Absent: queryWithoutIndexLeavesFts5Absent,
    sqliteTokenizerPreserved: sqliteTokenizerPreserved,
    embeddingsPreserved: embeddingsPreserved,
    conversationSearchPreserved: conversationSearchPreserved,
    appDatabaseSchemaUnchanged: appDatabaseSchemaUnchanged,
  );
  final outputDirectory = Directory(options.outDir)
    ..createSync(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_fts5_hosted_query_projection.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_fts5_hosted_query_projection.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

bool _projectionMatchesPayload({
  required List<Rag2ProjectedSearchHit> hits,
  required List<Rag2KnowledgeChunk> chunks,
  required List<String> matchIds,
  required Rag2StoredGeneration generation,
}) {
  if (hits.isEmpty || hits.length != matchIds.length) {
    return false;
  }
  final byId = {for (final chunk in chunks) chunk.chunkId: chunk};
  for (var index = 0; index < hits.length; index++) {
    final hit = hits[index];
    final chunk = byId[hit.chunkId];
    if (chunk == null ||
        hit.chunkId != matchIds[index] ||
        hit.objectId != chunk.objectId ||
        hit.locator != chunk.locator ||
        hit.contentHash != chunk.contentHash ||
        hit.projectId != chunk.provenance.projectId ||
        hit.repoRelativePath != chunk.provenance.repoRelativePath ||
        hit.revision != chunk.provenance.revision ||
        hit.lineStart != chunk.provenance.lineStart ||
        hit.lineEnd != chunk.provenance.lineEnd ||
        hit.sourceTrust != chunk.provenance.sourceTrust ||
        hit.generation != generation.generation ||
        hit.snapshotHash != generation.snapshot.snapshotHash) {
      return false;
    }
  }
  return true;
}

bool _hitsStayInSlot(
  List<Rag2ProjectedSearchHit> hits, {
  required Set<String> ownIds,
  required Set<String> otherIds,
  required String projectId,
}) {
  final ids = [for (final hit in hits) hit.chunkId];
  return hits.isNotEmpty &&
      ownIds.containsAll(ids) &&
      ids.toSet().intersection(otherIds).isEmpty &&
      hits.every((hit) => hit.projectId == projectId);
}

Directory _freshDirectory(String path) {
  final directory = Directory(path);
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
  directory.createSync(recursive: true);
  return directory;
}

final class Rag2Fts5HostedQueryProjectionOptions {
  const Rag2Fts5HostedQueryProjectionOptions({
    required this.fixturePath,
    required this.outDir,
    required this.storeRoot,
  });

  final String fixturePath;
  final String outDir;
  final String storeRoot;

  static Rag2Fts5HostedQueryProjectionOptions? parse(List<String> args) {
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
    return Rag2Fts5HostedQueryProjectionOptions(
      fixturePath: fixturePath,
      outDir: outDir,
      storeRoot: storeRoot ?? '$outDir/store',
    );
  }
}

final class Rag2Fts5HostedQueryProjectionReport {
  const Rag2Fts5HostedQueryProjectionReport({
    required this.fixtureId,
    required this.declarationIdentity,
    required this.hostQueryHitCount,
    required this.neighborQueryHitCount,
    required this.queryProjectsIndexedSlot,
    required this.queryRejectsUnknownChunkId,
    required this.queryRejectsMismatchedFtsRow,
    required this.queryIsolatesNeighbor,
    required this.queryWithoutIndexLeavesFts5Absent,
    required this.sqliteTokenizerPreserved,
    required this.embeddingsPreserved,
    required this.conversationSearchPreserved,
    required this.appDatabaseSchemaUnchanged,
  });

  final String fixtureId;
  final String declarationIdentity;
  final int hostQueryHitCount;
  final int neighborQueryHitCount;
  final bool queryProjectsIndexedSlot;
  final bool queryRejectsUnknownChunkId;
  final bool queryRejectsMismatchedFtsRow;
  final bool queryIsolatesNeighbor;
  final bool queryWithoutIndexLeavesFts5Absent;
  final bool sqliteTokenizerPreserved;
  final bool embeddingsPreserved;
  final bool conversationSearchPreserved;
  final bool appDatabaseSchemaUnchanged;

  bool get contractPassed =>
      queryProjectsIndexedSlot &&
      queryRejectsUnknownChunkId &&
      queryRejectsMismatchedFtsRow &&
      queryIsolatesNeighbor &&
      queryWithoutIndexLeavesFts5Absent &&
      sqliteTokenizerPreserved &&
      embeddingsPreserved &&
      conversationSearchPreserved &&
      appDatabaseSchemaUnchanged &&
      hostQueryHitCount > 0 &&
      neighborQueryHitCount > 0;

  Map<String, Object?> toJson() => {
    'schemaName': rag2Fts5HostedQueryProjectionReportSchema,
    'schemaVersion': 1,
    'contract': rag2Fts5HostedQueryProjectionContract,
    'evaluationMode': 'fts5_hosted_query_projection_replay',
    'contractDecision': contractPassed ? 'go' : 'no_go',
    'fts5Decision': contractPassed ? 'go' : 'no_go',
    'retrievalDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'appDatabaseSchemaVersion': 5,
    'fixtureId': fixtureId,
    'declarationIdentity': declarationIdentity,
    'hostQueryHitCount': hostQueryHitCount,
    'neighborQueryHitCount': neighborQueryHitCount,
    'queryProjectsIndexedSlot': queryProjectsIndexedSlot,
    'queryRejectsUnknownChunkId': queryRejectsUnknownChunkId,
    'queryRejectsMismatchedFtsRow': queryRejectsMismatchedFtsRow,
    'queryIsolatesNeighbor': queryIsolatesNeighbor,
    'queryWithoutIndexLeavesFts5Absent': queryWithoutIndexLeavesFts5Absent,
    'sqliteTokenizerPreserved': sqliteTokenizerPreserved,
    'embeddingsPreserved': embeddingsPreserved,
    'conversationSearchPreserved': conversationSearchPreserved,
    'appDatabaseSchemaUnchanged': appDatabaseSchemaUnchanged,
  };

  String toMarkdown() =>
      '# RAG2 FTS5 Hosted Query Projection\n\n'
      '- Contract: `$rag2Fts5HostedQueryProjectionContract`\n'
      '- Contract decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- FTS5 decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Retrieval decision: `not_evaluated`\n'
      '- Production decision: `no_go`\n'
      '- AppDatabase schema version: `5`\n'
      '- Fixture: `$fixtureId`\n'
      '- Declaration identity: `$declarationIdentity`\n'
      '- Host query hit count: `$hostQueryHitCount`\n'
      '- Neighbor query hit count: `$neighborQueryHitCount`\n'
      '- Query projects indexed slot: `$queryProjectsIndexedSlot`\n'
      '- Query rejects unknown chunk id: `$queryRejectsUnknownChunkId`\n'
      '- Query rejects mismatched FTS row: `$queryRejectsMismatchedFtsRow`\n'
      '- Query isolates neighbor: `$queryIsolatesNeighbor`\n'
      '- Query without index leaves FTS5 absent: `$queryWithoutIndexLeavesFts5Absent`\n'
      '- SQLite tokenizer preserved: `$sqliteTokenizerPreserved`\n'
      '- Embeddings preserved: `$embeddingsPreserved`\n'
      '- Conversation search preserved: `$conversationSearchPreserved`\n'
      '- AppDatabase schema unchanged: `$appDatabaseSchemaUnchanged`\n';
}
