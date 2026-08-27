import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_drift_additive_schema_replay.dart';
import '../../tool/rag2_drift_dao_generation_store.dart';
import '../../tool/rag2_explicit_source_roots_replay.dart';
import '../../tool/rag2_fts5_additive_index_replay.dart';
import '../../tool/rag2_fts5_hosted_query_replay.dart';
import '../../tool/rag2_knowledge_object_replay.dart';
import '../../tool/rag2_storage_replay.dart';

const _fixturePath = 'tool/fixtures/rag2_storage_replay/fixture.json';
const _identity =
    'declaration_40a72c56dc081f3170457e4c60666499964ea83a487c0dc414cc7d59a441be14';
const _projectId = 'rag2-storage-replay-project';
const _neighborProjectId = 'rag2-fts5-hosted-query-neighbor';

void main() {
  test('query hits the indexed slot from tokenized chunk text', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-hosted-query-hit-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    final hits = await store.querySearchIndex(
      declarationIdentity: _identity,
      queryText: snapshots.updated.chunks.first.content,
    );
    expect(hits, isNotEmpty);
    expect(
      {
        for (final chunk in snapshots.updated.chunks) chunk.chunkId,
      }.containsAll(hits),
      isTrue,
    );
    expect(hits, [...hits]..sort());
    expect(
      await store.querySearchIndex(
        declarationIdentity: _identity,
        queryText: '   ',
      ),
      isEmpty,
    );
  });

  test('query isolates host and neighbor project slots', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-hosted-query-neighbor-',
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
    final hostHits = await host.querySearchIndex(
      declarationIdentity: _identity,
      queryText: queryText,
    );
    final neighborHits = await neighbor.querySearchIndex(
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
    expect(hostIds.containsAll(hostHits), isTrue);
    expect(neighborIds.containsAll(neighborHits), isTrue);
    expect(hostHits.toSet().intersection(neighborIds), isEmpty);
    expect(neighborHits.toSet().intersection(hostIds), isEmpty);
  });

  test('query rejects a mismatched generation envelope', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-hosted-query-envelope-',
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
      await store.querySearchIndex(
        declarationIdentity: _identity,
        queryText: queryText,
      ),
      isNotEmpty,
    );
    await store.database.customStatement(
      'UPDATE $rag2ChunkSearchTable SET snapshot_hash = ? '
      'WHERE project_identity = ? AND declaration_identity = ?',
      [
        'stale-hash',
        rag2ExplicitSourceRootsProjectIdentity(_projectId),
        _identity,
      ],
    );
    expect(
      await store.querySearchIndex(
        declarationIdentity: _identity,
        queryText: queryText,
      ),
      isEmpty,
    );
  });

  test('query with a non-positive limit returns no chunk ids', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-hosted-query-limit-',
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
      await store.querySearchIndex(
        declarationIdentity: _identity,
        queryText: queryText,
      ),
      isNotEmpty,
    );
    expect(
      await store.querySearchIndex(
        declarationIdentity: _identity,
        queryText: queryText,
        limit: 0,
      ),
      isEmpty,
    );
  });

  test('query is hidden after clear and restored after rebuild', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-hosted-query-rebuild-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    final queryText = snapshots.updated.chunks.first.content;
    await store.clearSearchIndex(declarationIdentity: _identity);
    expect(
      await store.querySearchIndex(
        declarationIdentity: _identity,
        queryText: queryText,
      ),
      isEmpty,
    );
    await store.rebuildSearchIndex(declarationIdentity: _identity);
    expect(
      await store.querySearchIndex(
        declarationIdentity: _identity,
        queryText: queryText,
      ),
      isNotEmpty,
    );
  });

  test('query without an index leaves RAG2 FTS5 absent', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-hosted-query-unindexed-',
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
      await store.querySearchIndex(
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

  test('query after drop returns no chunk ids', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-hosted-query-drop-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    await store.drop(declarationIdentity: _identity);
    expect(
      await store.querySearchIndex(
        declarationIdentity: _identity,
        queryText: snapshots.updated.chunks.first.content,
      ),
      isEmpty,
    );
  });

  test(
    'replays twice against the same output directory',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'rag2-fts5-hosted-query-twice-',
      );
      addTearDown(() => output.deleteSync(recursive: true));
      final options = Rag2Fts5HostedQueryOptions(
        fixturePath: _fixturePath,
        outDir: output.path,
        storeRoot: '${output.path}/store',
      );
      final first = await runRag2Fts5HostedQueryReplay(options);
      final second = await runRag2Fts5HostedQueryReplay(options);
      expect(first.contractPassed, isTrue);
      expect(second.toJson(), first.toJson());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('writes aggregate-only reports', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-hosted-query-report-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final report = await runRag2Fts5HostedQueryReplay(
      Rag2Fts5HostedQueryOptions(
        fixturePath: _fixturePath,
        outDir: output.path,
        storeRoot: '${output.path}/store',
      ),
    );
    final jsonReport = File(
      '${output.path}/rag2_fts5_hosted_query.json',
    ).readAsStringSync();
    final markdownReport = File(
      '${output.path}/rag2_fts5_hosted_query.md',
    ).readAsStringSync();

    expect(report.contractPassed, isTrue);
    expect(report.toJson()['queryHitsIndexedSlot'], isTrue);
    expect(report.toJson()['queryIsolatesNeighbor'], isTrue);
    expect(report.toJson()['queryRejectsMismatchedEnvelope'], isTrue);
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
      'stale-hash',
    ]) {
      expect(jsonReport, isNot(contains(forbidden)));
      expect(markdownReport, isNot(contains(forbidden)));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'treats missing hit, isolation, envelope, or rebuild restore as no-go',
    () {
      Rag2Fts5HostedQueryReport report({
        bool queryHitsIndexedSlot = true,
        bool queryHiddenUntilRebuild = true,
        bool queryIsolatesNeighbor = true,
        bool queryRejectsMismatchedEnvelope = true,
        bool queryWithoutIndexLeavesFts5Absent = true,
        bool queryAfterDropIsEmpty = true,
        int hostQueryHitCount = 1,
        int neighborQueryHitCount = 1,
      }) {
        return Rag2Fts5HostedQueryReport(
          fixtureId: 'fixture',
          declarationIdentity: _identity,
          hostQueryHitCount: hostQueryHitCount,
          neighborQueryHitCount: neighborQueryHitCount,
          queryHitsIndexedSlot: queryHitsIndexedSlot,
          queryHiddenUntilRebuild: queryHiddenUntilRebuild,
          queryIsolatesNeighbor: queryIsolatesNeighbor,
          queryRejectsMismatchedEnvelope: queryRejectsMismatchedEnvelope,
          queryWithoutIndexLeavesFts5Absent: queryWithoutIndexLeavesFts5Absent,
          queryAfterDropIsEmpty: queryAfterDropIsEmpty,
          sqliteTokenizerPreserved: true,
          embeddingsPreserved: true,
          conversationSearchPreserved: true,
          appDatabaseSchemaUnchanged: true,
        );
      }

      expect(report().contractPassed, isTrue);
      expect(report(queryHitsIndexedSlot: false).contractPassed, isFalse);
      expect(report(queryHiddenUntilRebuild: false).contractPassed, isFalse);
      expect(report(queryIsolatesNeighbor: false).contractPassed, isFalse);
      expect(
        report(queryRejectsMismatchedEnvelope: false).contractPassed,
        isFalse,
      );
      expect(
        report(queryWithoutIndexLeavesFts5Absent: false).contractPassed,
        isFalse,
      );
      expect(report(queryAfterDropIsEmpty: false).contractPassed, isFalse);
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
