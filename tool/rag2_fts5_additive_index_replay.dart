import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:drift/drift.dart';

import 'rag2_drift_additive_schema_replay.dart';
import 'rag2_drift_dao_generation_store.dart';
import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_knowledge_object_replay.dart';
import 'rag2_lexical_policy_bakeoff.dart';
import 'rag2_storage_replay.dart';

const rag2Fts5AdditiveIndexContract = 'rag2-fts5-additive-index-contract-v1';
const rag2Fts5AdditiveIndexReportSchema =
    'caverno_rag2_fts5_additive_index_report';
const rag2ChunkSearchTable = 'rag2_chunk_search';
const rag2Fts5SqliteTokenizer = 'unicode61';
const rag2Fts5LexicalPolicyId = 'trigram_or_idf';

Future<void> main(List<String> args) async {
  final options = Rag2Fts5AdditiveIndexOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_fts5_additive_index_replay.dart '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2Fts5AdditiveIndexReplay(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 FTS5 additive index replay failed: $error');
    exitCode = 65;
  }
}

Future<Rag2Fts5AdditiveIndexReport> runRag2Fts5AdditiveIndexReplay(
  Rag2Fts5AdditiveIndexOptions options,
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

  final indexDir = _freshDirectory('${options.storeRoot}/index');
  final indexPath = '${indexDir.path}/caverno.sqlite';
  final seeded = await prepareRag2DriftHost(
    databasePath: indexPath,
    seedEmbedding: true,
  );
  final store = Rag2DriftDaoGenerationStore.open(
    databasePath: indexPath,
    projectId: fixture.projectId,
  );
  final conversationSearchSqlBefore = await rag2SqliteMasterSql(
    store.database,
    'conversation_search',
  );
  await createRag2ChunkSearchTable(store.database);
  await store.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  final baselineGeneration = await store.read(declarationIdentity);
  await replaceRag2ChunkSearchIndex(
    store.database,
    target: rag2Fts5IndexTarget(
      projectId: fixture.projectId,
      declarationIdentity: declarationIdentity,
      generation: baselineGeneration!,
    ),
    chunks: baseline.chunks,
  );
  final baselineIndexedIds = await rag2ChunkSearchChunkIds(
    store.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  await store.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
  );
  final updatedGeneration = await store.read(declarationIdentity);
  final updatedTarget = rag2Fts5IndexTarget(
    projectId: fixture.projectId,
    declarationIdentity: declarationIdentity,
    generation: updatedGeneration!,
  );
  await replaceRag2ChunkSearchIndex(
    store.database,
    target: updatedTarget,
    chunks: updated.chunks,
  );
  final indexedChunkIds = await rag2ChunkSearchChunkIds(
    store.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  var applyRollbackPreserved = false;
  try {
    await replaceRag2ChunkSearchIndex(
      store.database,
      target: rag2Fts5IndexTarget(
        projectId: fixture.projectId,
        declarationIdentity: declarationIdentity,
        generation: baselineGeneration,
      ),
      chunks: baseline.chunks,
      beforeCommit: () => throw StateError('injected_index_failure'),
    );
  } on StateError catch (error) {
    applyRollbackPreserved =
        error.message == 'injected_index_failure' &&
        _sameStringSet(
          indexedChunkIds,
          await rag2ChunkSearchChunkIds(
            store.database,
            projectIdentity: projectIdentity,
            declarationIdentity: declarationIdentity,
          ),
        ) &&
        await rag2ChunkSearchEnvelopeMatches(
          store.database,
          target: updatedTarget,
          chunkCount: updated.chunks.length,
        );
  }
  final indexedChunkCount = indexedChunkIds.length;
  final chunkSearchSql = await rag2SqliteMasterSql(
    store.database,
    rag2ChunkSearchTable,
  );
  final conversationSearchSqlAfter = await rag2SqliteMasterSql(
    store.database,
    'conversation_search',
  );
  final writesThroughAppDatabase = await rag2ChunkSearchVisibleToAppDatabase(
    store.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  final indexedTermsPretokenized = await rag2ChunkSearchTermsMatchPolicy(
    store.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
    chunks: updated.chunks,
  );
  final matchedChunkCount = await rag2ChunkSearchMatchedCount(
    store.database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
    chunks: updated.chunks,
  );
  final fts5Created =
      chunkSearchSql.toLowerCase().contains('fts5') &&
      chunkSearchSql.contains(rag2ChunkSearchTable) &&
      chunkSearchSql.contains('project_identity') &&
      chunkSearchSql.contains('declaration_identity') &&
      chunkSearchSql.contains('generation') &&
      chunkSearchSql.contains('snapshot_hash');
  final sqliteTokenizerPreserved =
      _usesUnicode61(chunkSearchSql) &&
      _usesUnicode61(conversationSearchSqlAfter) &&
      conversationSearchSqlAfter == conversationSearchSqlBefore;
  final allChunksMatchable =
      matchedChunkCount == updated.chunks.length && updated.chunks.isNotEmpty;
  final conversationSearch = await store.database
      .customSelect('SELECT id, title, body FROM conversation_search')
      .get();
  final schemaVersion = await store.database
      .customSelect('PRAGMA user_version')
      .getSingle();
  final embeddings = await store.database
      .select(store.database.embeddings)
      .get();
  final conversations = await store.database
      .select(store.database.conversations)
      .get();
  final usage = await store.database
      .select(store.database.modelUsageDaily)
      .get();
  await store.close();

  final reopened = Rag2DriftDaoGenerationStore.open(
    databasePath: indexPath,
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
  final replacementIndexedLastGeneration =
      baselineIndexedIds.length == baseline.chunks.length &&
      indexedChunkIds.length == updated.chunks.length &&
      !_sameStringSet(baselineIndexedIds, indexedChunkIds) &&
      _sameStringSet(indexedChunkIds, expectedUpdatedIds);

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
  await createRag2ChunkSearchTable(firstProject.database);
  await firstProject.apply(
    declarationIdentity: declarationIdentity,
    snapshot: firstSnapshot,
  );
  final firstGeneration = await firstProject.read(declarationIdentity);
  await replaceRag2ChunkSearchIndex(
    firstProject.database,
    target: rag2Fts5IndexTarget(
      projectId: 'persistence-project-a',
      declarationIdentity: declarationIdentity,
      generation: firstGeneration!,
    ),
    chunks: firstSnapshot.chunks,
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
  final secondGeneration = await secondProject.read(declarationIdentity);
  await replaceRag2ChunkSearchIndex(
    secondProject.database,
    target: rag2Fts5IndexTarget(
      projectId: 'persistence-project-b',
      declarationIdentity: declarationIdentity,
      generation: secondGeneration!,
    ),
    chunks: secondSnapshot.chunks,
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
  await createRag2ChunkSearchTable(mismatchStore.database);
  await mismatchStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
  );
  final mismatchGeneration = await mismatchStore.read(declarationIdentity);
  await replaceRag2ChunkSearchIndex(
    mismatchStore.database,
    target: rag2Fts5IndexTarget(
      projectId: fixture.projectId,
      declarationIdentity: declarationIdentity,
      generation: mismatchGeneration!,
    ),
    chunks: updated.chunks,
  );
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
      generation: mismatchGeneration,
    ),
    chunkCount: updated.chunks.length,
  );
  await mismatchStore.close();

  final report = Rag2Fts5AdditiveIndexReport(
    fixtureId: fixture.fixtureId,
    declarationIdentity: declarationIdentity,
    reopenedGeneration: reopenedGeneration?.generation ?? 0,
    reopenedSnapshotHash: reopenedGeneration?.snapshot.snapshotHash ?? '',
    indexedChunkCount: indexedChunkCount,
    matchedChunkCount: matchedChunkCount,
    fts5Created: fts5Created,
    writesThroughAppDatabase: writesThroughAppDatabase,
    sqliteTokenizerPreserved: sqliteTokenizerPreserved,
    lexicalPolicy: rag2Fts5LexicalPolicyId,
    indexedTermsPretokenized: indexedTermsPretokenized,
    replacementIndexedLastGeneration: replacementIndexedLastGeneration,
    allChunksMatchable: allChunksMatchable,
    applyRollbackPreserved: applyRollbackPreserved,
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
    '${outputDirectory.path}/rag2_fts5_additive_index.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_fts5_additive_index.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Rag2Fts5IndexTarget rag2Fts5IndexTarget({
  required String projectId,
  required String declarationIdentity,
  required Rag2StoredGeneration generation,
}) {
  return Rag2Fts5IndexTarget(
    projectIdentity: rag2ExplicitSourceRootsProjectIdentity(projectId),
    declarationIdentity: declarationIdentity,
    generation: generation.generation,
    snapshotHash: generation.snapshot.snapshotHash,
  );
}

Future<void> createRag2ChunkSearchTable(AppDatabase database) {
  return database.ensureRag2ChunkSearchTable();
}

Future<void> replaceRag2ChunkSearchIndex(
  AppDatabase database, {
  required Rag2Fts5IndexTarget target,
  required List<Rag2KnowledgeChunk> chunks,
  void Function()? beforeCommit,
}) {
  return database.writeRag2ChunkSearchIndex(
    projectIdentity: target.projectIdentity,
    declarationIdentity: target.declarationIdentity,
    generation: target.generation,
    snapshotHash: target.snapshotHash,
    beforeCommit: beforeCommit,
    rows: [
      for (final chunk in chunks)
        Rag2ChunkSearchRow(
          chunkId: chunk.chunkId,
          objectId: chunk.objectId,
          content: tokenizeRag2Lexical(
            chunk.content,
            Rag2LexicalPolicy.trigram,
          ).join(' '),
        ),
    ],
  );
}

Future<Set<String>> rag2ChunkSearchChunkIds(
  AppDatabase database, {
  required String projectIdentity,
  required String declarationIdentity,
}) async {
  final rows = await database
      .customSelect(
        'SELECT chunk_id FROM $rag2ChunkSearchTable '
        'WHERE project_identity = ? AND declaration_identity = ?',
        variables: [
          Variable<String>(projectIdentity),
          Variable<String>(declarationIdentity),
        ],
      )
      .get();
  return {for (final row in rows) row.read<String>('chunk_id')};
}

Future<String> rag2SqliteMasterSql(AppDatabase database, String name) async {
  final rows = await database
      .customSelect(
        'SELECT sql FROM sqlite_master WHERE name = ?',
        variables: [Variable<String>(name)],
      )
      .get();
  if (rows.isEmpty) {
    return '';
  }
  return rows.single.readNullable<String>('sql') ?? '';
}

Future<bool> rag2ChunkSearchVisibleToAppDatabase(
  AppDatabase database, {
  required String projectIdentity,
  required String declarationIdentity,
}) async {
  final sql = await rag2SqliteMasterSql(database, rag2ChunkSearchTable);
  final ids = await rag2ChunkSearchChunkIds(
    database,
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
  );
  return sql.toLowerCase().contains('fts5') && ids.isNotEmpty;
}

Future<bool> rag2ChunkSearchEnvelopeMatches(
  AppDatabase database, {
  required Rag2Fts5IndexTarget target,
  required int chunkCount,
}) async {
  if (chunkCount < 1) {
    return false;
  }
  final rows = await database
      .customSelect(
        'SELECT generation, snapshot_hash, COUNT(*) AS row_count '
        'FROM $rag2ChunkSearchTable '
        'WHERE project_identity = ? AND declaration_identity = ? '
        'GROUP BY generation, snapshot_hash',
        variables: [
          Variable<String>(target.projectIdentity),
          Variable<String>(target.declarationIdentity),
        ],
      )
      .get();
  if (rows.length != 1) {
    return false;
  }
  final row = rows.single;
  return row.read<int>('generation') == target.generation &&
      row.read<String>('snapshot_hash') == target.snapshotHash &&
      row.read<int>('row_count') == chunkCount;
}

Future<bool> rag2ChunkSearchTermsMatchPolicy(
  AppDatabase database, {
  required String projectIdentity,
  required String declarationIdentity,
  required List<Rag2KnowledgeChunk> chunks,
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
  if (rows.length != chunks.length) {
    return false;
  }
  final stored = {
    for (final row in rows)
      row.read<String>('chunk_id'): row.read<String>('content'),
  };
  for (final chunk in chunks) {
    final expected = tokenizeRag2Lexical(
      chunk.content,
      Rag2LexicalPolicy.trigram,
    ).join(' ');
    if (stored[chunk.chunkId] != expected) {
      return false;
    }
  }
  return true;
}

Future<int> rag2ChunkSearchMatchedCount(
  AppDatabase database, {
  required String projectIdentity,
  required String declarationIdentity,
  required List<Rag2KnowledgeChunk> chunks,
}) async {
  var matched = 0;
  for (final chunk in chunks) {
    final terms = tokenizeRag2Lexical(chunk.content, Rag2LexicalPolicy.trigram);
    if (terms.isEmpty) {
      return 0;
    }
    final query = terms
        .map((term) => '"${term.replaceAll('"', '""')}"')
        .join(' AND ');
    final rows = await database
        .customSelect(
          'SELECT chunk_id FROM $rag2ChunkSearchTable '
          'WHERE $rag2ChunkSearchTable MATCH ? '
          'AND project_identity = ? AND declaration_identity = ? '
          'AND chunk_id = ?',
          variables: [
            Variable<String>(query),
            Variable<String>(projectIdentity),
            Variable<String>(declarationIdentity),
            Variable<String>(chunk.chunkId),
          ],
        )
        .get();
    if (rows.isNotEmpty) {
      matched += 1;
    }
  }
  return matched;
}

bool _usesUnicode61(String sql) {
  return sql.toLowerCase().contains('unicode61');
}

bool _sameStringSet(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}

final class Rag2Fts5IndexTarget {
  const Rag2Fts5IndexTarget({
    required this.projectIdentity,
    required this.declarationIdentity,
    required this.generation,
    required this.snapshotHash,
  });

  final String projectIdentity;
  final String declarationIdentity;
  final int generation;
  final String snapshotHash;
}

final class Rag2Fts5AdditiveIndexOptions {
  const Rag2Fts5AdditiveIndexOptions({
    required this.fixturePath,
    required this.outDir,
    required this.storeRoot,
  });

  final String fixturePath;
  final String outDir;
  final String storeRoot;

  static Rag2Fts5AdditiveIndexOptions? parse(List<String> args) {
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
    return Rag2Fts5AdditiveIndexOptions(
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

final class Rag2Fts5AdditiveIndexReport {
  const Rag2Fts5AdditiveIndexReport({
    required this.fixtureId,
    required this.declarationIdentity,
    required this.reopenedGeneration,
    required this.reopenedSnapshotHash,
    required this.indexedChunkCount,
    required this.matchedChunkCount,
    required this.fts5Created,
    required this.writesThroughAppDatabase,
    required this.sqliteTokenizerPreserved,
    required this.lexicalPolicy,
    required this.indexedTermsPretokenized,
    required this.replacementIndexedLastGeneration,
    required this.allChunksMatchable,
    required this.applyRollbackPreserved,
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
  final bool fts5Created;
  final bool writesThroughAppDatabase;
  final bool sqliteTokenizerPreserved;
  final String lexicalPolicy;
  final bool indexedTermsPretokenized;
  final bool replacementIndexedLastGeneration;
  final bool allChunksMatchable;
  final bool applyRollbackPreserved;
  final bool envelopeMatchesGeneration;
  final bool envelopeMismatchRejected;
  final bool declarationIsolation;
  final bool indexSurvivesReopen;
  final bool generationPreserved;
  final bool embeddingsPreserved;
  final bool conversationSearchPreserved;
  final bool appDatabaseSchemaUnchanged;

  bool get contractPassed =>
      fts5Created &&
      writesThroughAppDatabase &&
      sqliteTokenizerPreserved &&
      lexicalPolicy == rag2Fts5LexicalPolicyId &&
      indexedTermsPretokenized &&
      replacementIndexedLastGeneration &&
      allChunksMatchable &&
      applyRollbackPreserved &&
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
    'schemaName': rag2Fts5AdditiveIndexReportSchema,
    'schemaVersion': 1,
    'contract': rag2Fts5AdditiveIndexContract,
    'evaluationMode': 'fts5_additive_index_replay',
    'contractDecision': contractPassed ? 'go' : 'no_go',
    'fts5Decision': contractPassed ? 'go' : 'no_go',
    'lexicalPolicy': lexicalPolicy,
    'sqliteTokenizer': rag2Fts5SqliteTokenizer,
    'retrievalDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'appDatabaseSchemaVersion': 5,
    'fixtureId': fixtureId,
    'declarationIdentity': declarationIdentity,
    'reopenedGeneration': reopenedGeneration,
    'reopenedSnapshotHash': reopenedSnapshotHash,
    'indexedChunkCount': indexedChunkCount,
    'matchedChunkCount': matchedChunkCount,
    'fts5Created': fts5Created,
    'writesThroughAppDatabase': writesThroughAppDatabase,
    'sqliteTokenizerPreserved': sqliteTokenizerPreserved,
    'indexedTermsPretokenized': indexedTermsPretokenized,
    'replacementIndexedLastGeneration': replacementIndexedLastGeneration,
    'allChunksMatchable': allChunksMatchable,
    'applyRollbackPreserved': applyRollbackPreserved,
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
      '# RAG2 FTS5 Additive Index\n\n'
      '- Contract: `$rag2Fts5AdditiveIndexContract`\n'
      '- Contract decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- FTS5 decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Lexical policy: `$lexicalPolicy`\n'
      '- SQLite tokenizer: `$rag2Fts5SqliteTokenizer`\n'
      '- Retrieval decision: `not_evaluated`\n'
      '- Production decision: `no_go`\n'
      '- AppDatabase schema version: `5`\n'
      '- Fixture: `$fixtureId`\n'
      '- Declaration identity: `$declarationIdentity`\n'
      '- Reopened generation / hash: `$reopenedGeneration` / `$reopenedSnapshotHash`\n'
      '- Indexed / matched chunk count: `$indexedChunkCount` / `$matchedChunkCount`\n'
      '- FTS5 created: `$fts5Created`\n'
      '- Writes through AppDatabase: `$writesThroughAppDatabase`\n'
      '- SQLite tokenizer preserved: `$sqliteTokenizerPreserved`\n'
      '- Indexed terms pretokenized: `$indexedTermsPretokenized`\n'
      '- Replacement indexed last generation: `$replacementIndexedLastGeneration`\n'
      '- All chunks matchable: `$allChunksMatchable`\n'
      '- Apply rollback preserved: `$applyRollbackPreserved`\n'
      '- Envelope matches generation: `$envelopeMatchesGeneration`\n'
      '- Envelope mismatch rejected: `$envelopeMismatchRejected`\n'
      '- Declaration isolation: `$declarationIsolation`\n'
      '- Index survives reopen: `$indexSurvivesReopen`\n'
      '- Generation preserved: `$generationPreserved`\n'
      '- Embeddings preserved: `$embeddingsPreserved`\n'
      '- Conversation search preserved: `$conversationSearchPreserved`\n'
      '- AppDatabase schema unchanged: `$appDatabaseSchemaUnchanged`\n';
}
