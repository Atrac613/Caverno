import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_drift_additive_schema_replay.dart';
import '../../tool/rag2_drift_dao_generation_store.dart';
import '../../tool/rag2_explicit_source_roots_replay.dart';
import '../../tool/rag2_fts5_additive_index_replay.dart';
import '../../tool/rag2_knowledge_object_replay.dart';
import '../../tool/rag2_storage_replay.dart';

const _fixturePath = 'tool/fixtures/rag2_storage_replay/fixture.json';
const _identity =
    'declaration_40a72c56dc081f3170457e4c60666499964ea83a487c0dc414cc7d59a441be14';
const _updatedHash =
    '3d2ef68de7071779c06e45381a761edea6494f4a9207c47463503a759914d610';
const _projectId = 'rag2-storage-replay-project';

void main() {
  final projectIdentity = rag2ExplicitSourceRootsProjectIdentity(_projectId);

  test(
    'creates a unicode61 RAG2 FTS5 table beside conversation_search',
    () async {
      final output = Directory.systemTemp.createTempSync('rag2-fts5-create-');
      addTearDown(() => output.deleteSync(recursive: true));
      final snapshots = await _snapshots();
      final store = await _openWithUpdatedGeneration(
        '${output.path}/caverno.sqlite',
        snapshots,
      );
      addTearDown(store.close);
      await createRag2ChunkSearchTable(store.database);

      final chunkSql = await rag2SqliteMasterSql(
        store.database,
        rag2ChunkSearchTable,
      );
      final searchSql = await rag2SqliteMasterSql(
        store.database,
        'conversation_search',
      );
      expect(chunkSql.toLowerCase(), contains('fts5'));
      expect(chunkSql.toLowerCase(), contains('unicode61'));
      expect(chunkSql, contains('project_identity'));
      expect(chunkSql, contains('declaration_identity'));
      expect(chunkSql, contains('snapshot_hash'));
      expect(searchSql.toLowerCase(), contains('unicode61'));
    },
  );

  test(
    'replacement keeps only the last committed generation chunk ids',
    () async {
      final output = Directory.systemTemp.createTempSync('rag2-fts5-replace-');
      addTearDown(() => output.deleteSync(recursive: true));
      final snapshots = await _snapshots();
      final store = await _openIndexedStore(
        '${output.path}/caverno.sqlite',
        snapshots,
      );
      addTearDown(store.close);
      final updatedIds = await rag2ChunkSearchChunkIds(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
      );

      expect(updatedIds, hasLength(snapshots.updated.chunks.length));
      expect(updatedIds, {
        for (final chunk in snapshots.updated.chunks) chunk.chunkId,
      });
      expect(
        await rag2ChunkSearchMatchedCount(
          store.database,
          projectIdentity: projectIdentity,
          declarationIdentity: _identity,
          chunks: snapshots.updated.chunks,
        ),
        snapshots.updated.chunks.length,
      );
      expect(
        await rag2ChunkSearchTermsMatchPolicy(
          store.database,
          projectIdentity: projectIdentity,
          declarationIdentity: _identity,
          chunks: snapshots.updated.chunks,
        ),
        isTrue,
      );
    },
  );

  test(
    'rolls back an injected index failure to the previous generation',
    () async {
      final output = Directory.systemTemp.createTempSync('rag2-fts5-rollback-');
      addTearDown(() => output.deleteSync(recursive: true));
      final snapshots = await _snapshots();
      final store = await _openIndexedStore(
        '${output.path}/caverno.sqlite',
        snapshots,
      );
      addTearDown(store.close);
      final before = await rag2ChunkSearchChunkIds(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
      );
      final generation = await store.read(_identity);
      await expectLater(
        replaceRag2ChunkSearchIndex(
          store.database,
          target: rag2Fts5IndexTarget(
            projectId: _projectId,
            declarationIdentity: _identity,
            generation: generation!,
          ),
          chunks: snapshots.baseline.chunks,
          beforeCommit: () => throw StateError('injected_index_failure'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'injected_index_failure',
          ),
        ),
      );
      expect(
        await rag2ChunkSearchChunkIds(
          store.database,
          projectIdentity: projectIdentity,
          declarationIdentity: _identity,
        ),
        before,
      );
      expect(
        await rag2ChunkSearchEnvelopeMatches(
          store.database,
          target: rag2Fts5IndexTarget(
            projectId: _projectId,
            declarationIdentity: _identity,
            generation: generation,
          ),
          chunkCount: snapshots.updated.chunks.length,
        ),
        isTrue,
      );
    },
  );

  test('isolates two projects in one FTS5 file', () async {
    final output = Directory.systemTemp.createTempSync('rag2-fts5-isolate-');
    addTearDown(() => output.deleteSync(recursive: true));
    final fixtureFile = File(_fixturePath);
    final fixture = await Rag2StorageReplayFixture.load(fixtureFile);
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
    final path = '${output.path}/caverno.sqlite';
    await prepareRag2DriftHost(databasePath: path);
    final first = Rag2DriftDaoGenerationStore.open(
      databasePath: path,
      projectId: 'persistence-project-a',
    );
    await createRag2ChunkSearchTable(first.database);
    await first.apply(declarationIdentity: _identity, snapshot: firstSnapshot);
    await replaceRag2ChunkSearchIndex(
      first.database,
      target: rag2Fts5IndexTarget(
        projectId: 'persistence-project-a',
        declarationIdentity: _identity,
        generation: (await first.read(_identity))!,
      ),
      chunks: firstSnapshot.chunks,
    );
    await first.close();
    final second = Rag2DriftDaoGenerationStore.open(
      databasePath: path,
      projectId: 'persistence-project-b',
    );
    addTearDown(second.close);
    await second.apply(
      declarationIdentity: _identity,
      snapshot: secondSnapshot,
    );
    await replaceRag2ChunkSearchIndex(
      second.database,
      target: rag2Fts5IndexTarget(
        projectId: 'persistence-project-b',
        declarationIdentity: _identity,
        generation: (await second.read(_identity))!,
      ),
      chunks: secondSnapshot.chunks,
    );

    expect(
      await rag2ChunkSearchChunkIds(
        second.database,
        projectIdentity: rag2ExplicitSourceRootsProjectIdentity(
          'persistence-project-a',
        ),
        declarationIdentity: _identity,
      ),
      {for (final chunk in firstSnapshot.chunks) chunk.chunkId},
    );
    expect(
      await rag2ChunkSearchChunkIds(
        second.database,
        projectIdentity: rag2ExplicitSourceRootsProjectIdentity(
          'persistence-project-b',
        ),
        declarationIdentity: _identity,
      ),
      {for (final chunk in secondSnapshot.chunks) chunk.chunkId},
    );
  });

  test(
    'fails closed when the index envelope disagrees with generation',
    () async {
      final output = Directory.systemTemp.createTempSync('rag2-fts5-mismatch-');
      addTearDown(() => output.deleteSync(recursive: true));
      final snapshots = await _snapshots();
      final store = await _openIndexedStore(
        '${output.path}/caverno.sqlite',
        snapshots,
      );
      addTearDown(store.close);
      final generation = await store.read(_identity);
      await store.database.customStatement(
        'UPDATE $rag2ChunkSearchTable SET snapshot_hash = ? '
        'WHERE project_identity = ? AND declaration_identity = ?',
        ['stale-hash', projectIdentity, _identity],
      );
      expect(
        await rag2ChunkSearchEnvelopeMatches(
          store.database,
          target: rag2Fts5IndexTarget(
            projectId: _projectId,
            declarationIdentity: _identity,
            generation: generation!,
          ),
          chunkCount: snapshots.updated.chunks.length,
        ),
        isFalse,
      );
    },
  );

  test('requires every chunk to MATCH', () async {
    final output = Directory.systemTemp.createTempSync('rag2-fts5-match-all-');
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    expect(
      await rag2ChunkSearchMatchedCount(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
        chunks: snapshots.updated.chunks,
      ),
      snapshots.updated.chunks.length,
    );
    await store.database.customStatement(
      'UPDATE $rag2ChunkSearchTable SET content = ? '
      'WHERE chunk_id = ?',
      ['', snapshots.updated.chunks.first.chunkId],
    );
    expect(
      await rag2ChunkSearchMatchedCount(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
        chunks: snapshots.updated.chunks,
      ),
      lessThan(snapshots.updated.chunks.length),
    );
  });

  test('preserves conversation-search contents and embeddings', () async {
    final output = Directory.systemTemp.createTempSync('rag2-fts5-host-');
    addTearDown(() => output.deleteSync(recursive: true));
    final report = await runRag2Fts5AdditiveIndexReplay(
      Rag2Fts5AdditiveIndexOptions(
        fixturePath: _fixturePath,
        outDir: output.path,
        storeRoot: '${output.path}/store',
      ),
    );

    expect(report.conversationSearchPreserved, isTrue);
    expect(report.embeddingsPreserved, isTrue);
    expect(report.appDatabaseSchemaUnchanged, isTrue);
    expect(report.writesThroughAppDatabase, isTrue);
  });

  test(
    'reopens generation 2 and the FTS5 index through the Drift DAO',
    () async {
      final output = Directory.systemTemp.createTempSync('rag2-fts5-reopen-');
      addTearDown(() => output.deleteSync(recursive: true));
      final snapshots = await _snapshots();
      final path = '${output.path}/caverno.sqlite';
      final writer = await _openIndexedStore(path, snapshots);
      await writer.close();

      final store = Rag2DriftDaoGenerationStore.open(
        databasePath: path,
        projectId: _projectId,
      );
      addTearDown(store.close);
      final generation = await store.read(_identity);
      expect(generation?.generation, 2);
      expect(generation?.snapshot.snapshotHash, _updatedHash);
      expect(
        generation?.snapshot.chunks.map((chunk) => chunk.content).join('\n'),
        contains('fixture-secret-alpha'),
      );
      expect(
        await rag2ChunkSearchChunkIds(
          store.database,
          projectIdentity: projectIdentity,
          declarationIdentity: _identity,
        ),
        {for (final chunk in snapshots.updated.chunks) chunk.chunkId},
      );
      expect(
        await rag2ChunkSearchEnvelopeMatches(
          store.database,
          target: rag2Fts5IndexTarget(
            projectId: _projectId,
            declarationIdentity: _identity,
            generation: generation!,
          ),
          chunkCount: snapshots.updated.chunks.length,
        ),
        isTrue,
      );
    },
  );

  test('replays twice against the same output directory', () async {
    final output = Directory.systemTemp.createTempSync('rag2-fts5-rerun-');
    addTearDown(() => output.deleteSync(recursive: true));
    final options = Rag2Fts5AdditiveIndexOptions(
      fixturePath: _fixturePath,
      outDir: output.path,
      storeRoot: '${output.path}/store',
    );
    final first = await runRag2Fts5AdditiveIndexReplay(options);
    final second = await runRag2Fts5AdditiveIndexReplay(options);
    expect(first.contractPassed, isTrue);
    expect(second.contractPassed, isTrue);
    expect(second.toJson(), first.toJson());
  });

  test('writes aggregate-only reports', () async {
    final output = Directory.systemTemp.createTempSync('rag2-fts5-report-');
    addTearDown(() => output.deleteSync(recursive: true));
    final report = await runRag2Fts5AdditiveIndexReplay(
      Rag2Fts5AdditiveIndexOptions(
        fixturePath: _fixturePath,
        outDir: output.path,
        storeRoot: '${output.path}/store',
      ),
    );
    final jsonReport = File(
      '${output.path}/rag2_fts5_additive_index.json',
    ).readAsStringSync();
    final markdownReport = File(
      '${output.path}/rag2_fts5_additive_index.md',
    ).readAsStringSync();

    expect(report.contractPassed, isTrue);
    expect(report.toJson()['fts5Decision'], 'go');
    expect(report.toJson()['applyRollbackPreserved'], isTrue);
    expect(report.toJson()['envelopeMatchesGeneration'], isTrue);
    expect(report.toJson()['envelopeMismatchRejected'], isTrue);
    expect(report.toJson()['declarationIsolation'], isTrue);
    expect(report.toJson()['allChunksMatchable'], isTrue);
    expect(report.toJson()['matchedChunkCount'], report.indexedChunkCount);
    expect(report.toJson()['retrievalDecision'], 'not_evaluated');
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(jsonDecode(jsonReport), report.toJson());
    expect(markdownReport, report.toMarkdown());
    for (final forbidden in [
      Directory.current.path,
      '/Users/',
      'docs/guide.md',
      'fixture-secret-alpha',
      'sourceRoots',
      'll5-sentinel',
      'stale-hash',
    ]) {
      expect(jsonReport, isNot(contains(forbidden)));
      expect(markdownReport, isNot(contains(forbidden)));
    }
  });

  test('treats missing rollback, envelope, or full MATCH as no-go', () {
    Rag2Fts5AdditiveIndexReport report({
      bool applyRollbackPreserved = true,
      bool envelopeMatchesGeneration = true,
      bool declarationIsolation = true,
      bool allChunksMatchable = true,
      int matchedChunkCount = 5,
    }) {
      return Rag2Fts5AdditiveIndexReport(
        fixtureId: 'fixture',
        declarationIdentity: _identity,
        reopenedGeneration: 2,
        reopenedSnapshotHash: _updatedHash,
        indexedChunkCount: 5,
        matchedChunkCount: matchedChunkCount,
        fts5Created: true,
        writesThroughAppDatabase: true,
        sqliteTokenizerPreserved: true,
        lexicalPolicy: rag2Fts5LexicalPolicyId,
        indexedTermsPretokenized: true,
        replacementIndexedLastGeneration: true,
        allChunksMatchable: allChunksMatchable,
        applyRollbackPreserved: applyRollbackPreserved,
        envelopeMatchesGeneration: envelopeMatchesGeneration,
        envelopeMismatchRejected: true,
        declarationIsolation: declarationIsolation,
        indexSurvivesReopen: true,
        generationPreserved: true,
        embeddingsPreserved: true,
        conversationSearchPreserved: true,
        appDatabaseSchemaUnchanged: true,
      );
    }

    expect(report().contractPassed, isTrue);
    expect(report(applyRollbackPreserved: false).contractPassed, isFalse);
    expect(report(envelopeMatchesGeneration: false).contractPassed, isFalse);
    expect(report(declarationIsolation: false).contractPassed, isFalse);
    expect(report(allChunksMatchable: false).contractPassed, isFalse);
    expect(report(matchedChunkCount: 1).contractPassed, isFalse);
  });
}

Future<Rag2DriftDaoGenerationStore> _openIndexedStore(
  String path,
  ({Rag2KnowledgeSnapshot baseline, Rag2KnowledgeSnapshot updated}) snapshots,
) async {
  await prepareRag2DriftHost(databasePath: path);
  final store = Rag2DriftDaoGenerationStore.open(
    databasePath: path,
    projectId: _projectId,
  );
  await createRag2ChunkSearchTable(store.database);
  await store.apply(
    declarationIdentity: _identity,
    snapshot: snapshots.baseline,
  );
  await replaceRag2ChunkSearchIndex(
    store.database,
    target: rag2Fts5IndexTarget(
      projectId: _projectId,
      declarationIdentity: _identity,
      generation: (await store.read(_identity))!,
    ),
    chunks: snapshots.baseline.chunks,
  );
  await store.apply(
    declarationIdentity: _identity,
    snapshot: snapshots.updated,
  );
  await replaceRag2ChunkSearchIndex(
    store.database,
    target: rag2Fts5IndexTarget(
      projectId: _projectId,
      declarationIdentity: _identity,
      generation: (await store.read(_identity))!,
    ),
    chunks: snapshots.updated.chunks,
  );
  return store;
}

Future<Rag2DriftDaoGenerationStore> _openWithUpdatedGeneration(
  String path,
  ({Rag2KnowledgeSnapshot baseline, Rag2KnowledgeSnapshot updated}) snapshots,
) async {
  await prepareRag2DriftHost(databasePath: path);
  final store = Rag2DriftDaoGenerationStore.open(
    databasePath: path,
    projectId: _projectId,
  );
  await store.apply(
    declarationIdentity: _identity,
    snapshot: snapshots.baseline,
  );
  await store.apply(
    declarationIdentity: _identity,
    snapshot: snapshots.updated,
  );
  return store;
}

Future<({Rag2KnowledgeSnapshot baseline, Rag2KnowledgeSnapshot updated})>
_snapshots() async {
  final fixtureFile = File(_fixturePath);
  final fixture = await Rag2StorageReplayFixture.load(fixtureFile);
  return (
    baseline: await prepareRag2StorageSnapshot(
      fixtureFile: fixtureFile,
      fixture: fixture,
      spec: fixture.snapshots.first,
    ),
    updated: await prepareRag2StorageSnapshot(
      fixtureFile: fixtureFile,
      fixture: fixture,
      spec: fixture.snapshots.last,
    ),
  );
}
