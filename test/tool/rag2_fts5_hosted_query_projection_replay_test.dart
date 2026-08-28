import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_drift_additive_schema_replay.dart';
import '../../tool/rag2_drift_dao_generation_store.dart';
import '../../tool/rag2_explicit_source_roots_replay.dart';
import '../../tool/rag2_fts5_additive_index_replay.dart';
import '../../tool/rag2_fts5_hosted_query_projection_replay.dart';
import '../../tool/rag2_knowledge_object_replay.dart';
import '../../tool/rag2_lexical_policy_bakeoff.dart';
import '../../tool/rag2_storage_replay.dart';

const _fixturePath = 'tool/fixtures/rag2_storage_replay/fixture.json';
const _identity =
    'declaration_40a72c56dc081f3170457e4c60666499964ea83a487c0dc414cc7d59a441be14';
const _projectId = 'rag2-storage-replay-project';
const _neighborProjectId = 'rag2-fts5-query-projection-neighbor';

void main() {
  test('projects MATCH ids onto generation provenance in order', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-query-projection-hit-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    final queryText = snapshots.updated.chunks.first.content;
    final matchIds = await store.querySearchIndex(
      declarationIdentity: _identity,
      queryText: queryText,
    );
    final hits = await store.projectSearchIndex(
      declarationIdentity: _identity,
      queryText: queryText,
    );
    final chunks = {
      for (final chunk in snapshots.updated.chunks) chunk.chunkId: chunk,
    };
    expect(hits, isNotEmpty);
    expect([for (final hit in hits) hit.chunkId], matchIds);
    final generation = await store.read(_identity);
    expect(generation, isNotNull);
    for (final hit in hits) {
      final chunk = chunks[hit.chunkId];
      expect(chunk, isNotNull);
      expect(hit.objectId, chunk!.objectId);
      expect(hit.locator, chunk.locator);
      expect(hit.contentHash, chunk.contentHash);
      expect(hit.repoRelativePath, chunk.provenance.repoRelativePath);
      expect(hit.revision, chunk.provenance.revision);
      expect(hit.lineStart, chunk.provenance.lineStart);
      expect(hit.lineEnd, chunk.provenance.lineEnd);
      expect(hit.sourceTrust, chunk.provenance.sourceTrust);
      expect(hit.generation, generation!.generation);
      expect(hit.snapshotHash, generation.snapshot.snapshotHash);
    }
    expect(
      await store.projectSearchIndex(
        declarationIdentity: _identity,
        queryText: '   ',
      ),
      isEmpty,
    );
  });

  test('projected hits omit content and keep repo-relative paths', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-query-projection-safety-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    final hits = await store.projectSearchIndex(
      declarationIdentity: _identity,
      queryText: snapshots.updated.chunks.first.content,
    );
    expect(hits, isNotEmpty);
    for (final hit in hits) {
      expect(hit.toJson().containsKey('content'), isFalse);
      expect(
        () => validateRag2RepoRelativePath(hit.repoRelativePath),
        returnsNormally,
      );
    }
  });

  test('unknown FTS chunk id fails closed', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-query-projection-unknown-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    final queryText = snapshots.updated.chunks.first.content;
    expect(
      await store.projectSearchIndex(
        declarationIdentity: _identity,
        queryText: queryText,
      ),
      isNotEmpty,
    );
    final generation = await store.read(_identity);
    await store.database.customStatement(
      'INSERT INTO $rag2ChunkSearchTable('
      'project_identity, declaration_identity, generation, snapshot_hash, '
      'chunk_id, object_id, content) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        rag2ExplicitSourceRootsProjectIdentity(_projectId),
        _identity,
        generation!.generation,
        generation.snapshot.snapshotHash,
        rag2Fts5UnknownProjectionChunkId,
        'ko_unknown_projection_sentinel',
        tokenizeRag2Lexical(queryText, Rag2LexicalPolicy.trigram).join(' '),
      ],
    );
    expect(
      await store.querySearchIndex(
        declarationIdentity: _identity,
        queryText: queryText,
      ),
      contains(rag2Fts5UnknownProjectionChunkId),
    );
    expect(
      await store.projectSearchIndex(
        declarationIdentity: _identity,
        queryText: queryText,
      ),
      isEmpty,
    );
  });

  test('mismatched FTS object_id fails closed', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-query-projection-object-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    final queryText = snapshots.updated.chunks.first.content;
    final matchIds = await store.querySearchIndex(
      declarationIdentity: _identity,
      queryText: queryText,
    );
    expect(matchIds, isNotEmpty);
    expect(
      await store.projectSearchIndex(
        declarationIdentity: _identity,
        queryText: queryText,
      ),
      isNotEmpty,
    );
    await store.database.customStatement(
      'UPDATE $rag2ChunkSearchTable SET object_id = ? '
      'WHERE project_identity = ? AND declaration_identity = ? AND chunk_id = ?',
      [
        rag2Fts5MismatchedProjectionObjectId,
        rag2ExplicitSourceRootsProjectIdentity(_projectId),
        _identity,
        matchIds.first,
      ],
    );
    expect(
      await store.querySearchIndex(
        declarationIdentity: _identity,
        queryText: queryText,
      ),
      contains(matchIds.first),
    );
    expect(
      await store.projectSearchIndex(
        declarationIdentity: _identity,
        queryText: queryText,
      ),
      isEmpty,
    );
  });

  test('mismatched FTS content fails closed', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-query-projection-content-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    final queryText = snapshots.updated.chunks.first.content;
    final matchIds = await store.querySearchIndex(
      declarationIdentity: _identity,
      queryText: queryText,
    );
    expect(matchIds, isNotEmpty);
    await store.database.customStatement(
      'UPDATE $rag2ChunkSearchTable SET content = ? '
      'WHERE project_identity = ? AND declaration_identity = ? AND chunk_id = ?',
      [
        '${tokenizeRag2Lexical(queryText, Rag2LexicalPolicy.trigram).join(' ')} extra',
        rag2ExplicitSourceRootsProjectIdentity(_projectId),
        _identity,
        matchIds.first,
      ],
    );
    expect(
      await store.querySearchIndex(
        declarationIdentity: _identity,
        queryText: queryText,
      ),
      contains(matchIds.first),
    );
    expect(
      await store.projectSearchIndex(
        declarationIdentity: _identity,
        queryText: queryText,
      ),
      isEmpty,
    );
  });

  test('projection isolates host and neighbor project slots', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-query-projection-neighbor-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final path = '${output.path}/caverno.sqlite';
    final store = await _openIndexedStore(path, snapshots);
    await store.close();
    final neighborSnapshot = await _neighborSnapshot();
    final neighborWriter = Rag2DriftDaoGenerationStore.open(
      databasePath: path,
      projectId: _neighborProjectId,
    );
    await neighborWriter.apply(
      declarationIdentity: _identity,
      snapshot: neighborSnapshot,
      indexSearch: true,
    );
    await neighborWriter.close();
    final host = Rag2DriftDaoGenerationStore.open(
      databasePath: path,
      projectId: _projectId,
    );
    addTearDown(host.close);
    final neighbor = Rag2DriftDaoGenerationStore.open(
      databasePath: path,
      projectId: _neighborProjectId,
    );
    addTearDown(neighbor.close);
    final queryText = snapshots.updated.chunks.first.content;
    final hostHits = await host.projectSearchIndex(
      declarationIdentity: _identity,
      queryText: queryText,
    );
    final neighborHits = await neighbor.projectSearchIndex(
      declarationIdentity: _identity,
      queryText: queryText,
    );
    final hostIds = {
      for (final chunk in snapshots.updated.chunks) chunk.chunkId,
    };
    final neighborIds = {
      for (final chunk in neighborSnapshot.chunks) chunk.chunkId,
    };
    expect(hostHits, isNotEmpty);
    expect(neighborHits, isNotEmpty);
    expect(
      hostIds.containsAll([for (final hit in hostHits) hit.chunkId]),
      isTrue,
    );
    expect(
      neighborIds.containsAll([for (final hit in neighborHits) hit.chunkId]),
      isTrue,
    );
    expect(
      {for (final hit in hostHits) hit.chunkId}.intersection(neighborIds),
      isEmpty,
    );
    expect(
      {for (final hit in neighborHits) hit.chunkId}.intersection(hostIds),
      isEmpty,
    );
    expect(hostHits.every((hit) => hit.projectId == _projectId), isTrue);
    expect(
      neighborHits.every((hit) => hit.projectId == _neighborProjectId),
      isTrue,
    );
  });

  test('projection without an index leaves RAG2 FTS5 absent', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-query-projection-unindexed-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    await prepareRag2DriftHost(databasePath: '${output.path}/caverno.sqlite');
    final store = Rag2DriftDaoGenerationStore.open(
      databasePath: '${output.path}/caverno.sqlite',
      projectId: _projectId,
    );
    addTearDown(store.close);
    await store.apply(
      declarationIdentity: _identity,
      snapshot: snapshots.updated,
    );
    expect(
      await rag2SqliteMasterSql(store.database, rag2ChunkSearchTable),
      isEmpty,
    );
    expect(
      await store.projectSearchIndex(
        declarationIdentity: _identity,
        queryText: snapshots.updated.chunks.first.content,
      ),
      isEmpty,
    );
    expect(
      await rag2SqliteMasterSql(store.database, rag2ChunkSearchTable),
      isEmpty,
    );
  });

  test(
    'replays twice against the same output directory',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'rag2-fts5-query-projection-twice-',
      );
      addTearDown(() => output.deleteSync(recursive: true));
      final options = Rag2Fts5HostedQueryProjectionOptions(
        fixturePath: _fixturePath,
        outDir: output.path,
        storeRoot: '${output.path}/store',
      );
      final first = await runRag2Fts5HostedQueryProjectionReplay(options);
      final second = await runRag2Fts5HostedQueryProjectionReplay(options);
      expect(first.contractPassed, isTrue);
      expect(second.toJson(), first.toJson());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('writes aggregate-only reports', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-query-projection-report-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final report = await runRag2Fts5HostedQueryProjectionReplay(
      Rag2Fts5HostedQueryProjectionOptions(
        fixturePath: _fixturePath,
        outDir: output.path,
        storeRoot: '${output.path}/store',
      ),
    );
    final jsonReport = File(
      '${output.path}/rag2_fts5_hosted_query_projection.json',
    ).readAsStringSync();
    final markdownReport = File(
      '${output.path}/rag2_fts5_hosted_query_projection.md',
    ).readAsStringSync();

    expect(report.contractPassed, isTrue);
    expect(report.toJson()['queryProjectsIndexedSlot'], isTrue);
    expect(report.toJson()['queryRejectsUnknownChunkId'], isTrue);
    expect(report.toJson()['queryRejectsMismatchedFtsRow'], isTrue);
    expect(report.toJson()['queryIsolatesNeighbor'], isTrue);
    expect(report.toJson()['fts5Decision'], 'go');
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
      rag2Fts5UnknownProjectionChunkId,
      rag2Fts5MismatchedProjectionObjectId,
    ]) {
      expect(jsonReport, isNot(contains(forbidden)));
      expect(markdownReport, isNot(contains(forbidden)));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'treats missing projection, isolation, or unknown-id reject as no-go',
    () {
      Rag2Fts5HostedQueryProjectionReport report({
        bool queryProjectsIndexedSlot = true,
        bool queryRejectsUnknownChunkId = true,
        bool queryRejectsMismatchedFtsRow = true,
        bool queryIsolatesNeighbor = true,
        bool queryWithoutIndexLeavesFts5Absent = true,
        int hostQueryHitCount = 1,
        int neighborQueryHitCount = 1,
      }) {
        return Rag2Fts5HostedQueryProjectionReport(
          fixtureId: 'fixture',
          declarationIdentity: _identity,
          hostQueryHitCount: hostQueryHitCount,
          neighborQueryHitCount: neighborQueryHitCount,
          queryProjectsIndexedSlot: queryProjectsIndexedSlot,
          queryRejectsUnknownChunkId: queryRejectsUnknownChunkId,
          queryRejectsMismatchedFtsRow: queryRejectsMismatchedFtsRow,
          queryIsolatesNeighbor: queryIsolatesNeighbor,
          queryWithoutIndexLeavesFts5Absent: queryWithoutIndexLeavesFts5Absent,
          sqliteTokenizerPreserved: true,
          embeddingsPreserved: true,
          conversationSearchPreserved: true,
          appDatabaseSchemaUnchanged: true,
        );
      }

      expect(report().contractPassed, isTrue);
      expect(report(queryProjectsIndexedSlot: false).contractPassed, isFalse);
      expect(report(queryRejectsUnknownChunkId: false).contractPassed, isFalse);
      expect(
        report(queryRejectsMismatchedFtsRow: false).contractPassed,
        isFalse,
      );
      expect(report(queryIsolatesNeighbor: false).contractPassed, isFalse);
      expect(
        report(queryWithoutIndexLeavesFts5Absent: false).contractPassed,
        isFalse,
      );
      expect(report(hostQueryHitCount: 0).contractPassed, isFalse);
      expect(report(neighborQueryHitCount: 0).contractPassed, isFalse);
    },
  );
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
  await store.apply(
    declarationIdentity: _identity,
    snapshot: snapshots.baseline,
    indexSearch: true,
  );
  await store.apply(
    declarationIdentity: _identity,
    snapshot: snapshots.updated,
    indexSearch: true,
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

Future<Rag2KnowledgeSnapshot> _neighborSnapshot() async {
  final fixtureFile = File(_fixturePath);
  final fixture = await Rag2StorageReplayFixture.load(fixtureFile);
  return prepareRag2StorageSnapshot(
    fixtureFile: fixtureFile,
    fixture: fixture,
    spec: fixture.snapshots.last,
    projectId: _neighborProjectId,
  );
}
