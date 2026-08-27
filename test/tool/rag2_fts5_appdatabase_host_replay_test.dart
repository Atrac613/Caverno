import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_drift_additive_schema_replay.dart';
import '../../tool/rag2_drift_dao_generation_store.dart';
import '../../tool/rag2_explicit_source_roots_replay.dart';
import '../../tool/rag2_fts5_additive_index_replay.dart';
import '../../tool/rag2_fts5_appdatabase_host_replay.dart';
import '../../tool/rag2_knowledge_object_replay.dart';
import '../../tool/rag2_storage_replay.dart';

const _fixturePath = 'tool/fixtures/rag2_storage_replay/fixture.json';
const _identity =
    'declaration_40a72c56dc081f3170457e4c60666499964ea83a487c0dc414cc7d59a441be14';
const _baselineHash =
    '31d8769e4f33bab976367e724440209bc5d3da2c3772559522f7ea655f48c95b';
const _updatedHash =
    '3d2ef68de7071779c06e45381a761edea6494f4a9207c47463503a759914d610';
const _projectId = 'rag2-storage-replay-project';

void main() {
  final projectIdentity = rag2ExplicitSourceRootsProjectIdentity(_projectId);

  test('v5 host upgrade does not create rag2_chunk_search', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-host-upgrade-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    await prepareRag2DriftHost(databasePath: '${output.path}/caverno.sqlite');
    final store = Rag2DriftDaoGenerationStore.open(
      databasePath: '${output.path}/caverno.sqlite',
      projectId: _projectId,
    );
    addTearDown(store.close);
    expect(
      await rag2SqliteMasterSql(store.database, rag2ChunkSearchTable),
      isEmpty,
    );
    await store.apply(
      declarationIdentity: _identity,
      snapshot: (await _snapshots()).baseline,
    );
    expect(
      await rag2SqliteMasterSql(store.database, rag2ChunkSearchTable),
      isEmpty,
    );
  });

  test('no-op apply with indexSearch backfills the FTS5 slot', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-host-noop-index-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final path = '${output.path}/caverno.sqlite';
    await prepareRag2DriftHost(databasePath: path);
    final store = Rag2DriftDaoGenerationStore.open(
      databasePath: path,
      projectId: _projectId,
    );
    addTearDown(store.close);
    await store.apply(
      declarationIdentity: _identity,
      snapshot: snapshots.baseline,
    );
    await store.apply(
      declarationIdentity: _identity,
      snapshot: snapshots.updated,
    );
    expect(
      await rag2SqliteMasterSql(store.database, rag2ChunkSearchTable),
      isEmpty,
    );
    final result = await store.apply(
      declarationIdentity: _identity,
      snapshot: snapshots.updated,
      indexSearch: true,
    );
    expect(result.decision, 'no_op');
    final generation = await store.read(_identity);
    expect(generation?.generation, 2);
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
  });

  test(
    'apply with indexSearch reopens generation 2 and its FTS5 slot',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'rag2-fts5-host-reopen-',
      );
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

  test('rolls back generation and index together', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-host-rollback-',
    );
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
    await expectLater(
      store.apply(
        declarationIdentity: _identity,
        snapshot: snapshots.baseline,
        indexSearch: true,
        beforeTxnCommit: () => throw StateError('injected_index_apply_failure'),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'injected_index_apply_failure',
        ),
      ),
    );
    final generation = await store.read(_identity);
    expect(generation?.generation, 2);
    expect(generation?.snapshot.snapshotHash, _updatedHash);
    expect(
      await rag2ChunkSearchChunkIds(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
      ),
      before,
    );
  });

  test(
    'recovers generation 1 index after a killed uncommitted apply',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'rag2-fts5-host-crash-',
      );
      addTearDown(() => output.deleteSync(recursive: true));
      final snapshots = await _snapshots();
      final path = '${output.path}/caverno.sqlite';
      await prepareRag2DriftHost(databasePath: path);
      final writer = Rag2DriftDaoGenerationStore.open(
        databasePath: path,
        projectId: _projectId,
      );
      await writer.apply(
        declarationIdentity: _identity,
        snapshot: snapshots.baseline,
        indexSearch: true,
      );
      await writer.close();

      final generation = await recoverAfterKilledUncommittedDriftDaoWrite(
        fixturePath: _fixturePath,
        databasePath: path,
        projectId: _projectId,
        declarationIdentity: _identity,
        indexSearch: true,
      );
      expect(generation?.generation, 1);
      expect(generation?.snapshot.snapshotHash, _baselineHash);

      final recovered = Rag2DriftDaoGenerationStore.open(
        databasePath: path,
        projectId: _projectId,
      );
      addTearDown(recovered.close);
      expect(
        await rag2ChunkSearchChunkIds(
          recovered.database,
          projectIdentity: projectIdentity,
          declarationIdentity: _identity,
        ),
        {for (final chunk in snapshots.baseline.chunks) chunk.chunkId},
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('indexes two projects through one hosted AppDatabase file', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-host-isolate-',
    );
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
    await first.apply(
      declarationIdentity: _identity,
      snapshot: firstSnapshot,
      indexSearch: true,
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
      indexSearch: true,
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
    'preserves conversation-search contents and embeddings',
    () async {
      final output = Directory.systemTemp.createTempSync('rag2-fts5-host-ll5-');
      addTearDown(() => output.deleteSync(recursive: true));
      final report = await runRag2Fts5AppDatabaseHostReplay(
        Rag2Fts5AppDatabaseHostOptions(
          fixturePath: _fixturePath,
          outDir: output.path,
          storeRoot: '${output.path}/store',
        ),
      );
      expect(report.conversationSearchPreserved, isTrue);
      expect(report.embeddingsPreserved, isTrue);
      expect(report.appDatabaseSchemaUnchanged, isTrue);
      expect(report.fts5AbsentAfterHostUpgrade, isTrue);
      expect(report.applyWithoutIndexLeavesFts5Absent, isTrue);
      expect(report.crashRecoveredIndex, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'replays twice against the same output directory',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'rag2-fts5-host-rerun-',
      );
      addTearDown(() => output.deleteSync(recursive: true));
      final options = Rag2Fts5AppDatabaseHostOptions(
        fixturePath: _fixturePath,
        outDir: output.path,
        storeRoot: '${output.path}/store',
      );
      final first = await runRag2Fts5AppDatabaseHostReplay(options);
      final second = await runRag2Fts5AppDatabaseHostReplay(options);
      expect(first.contractPassed, isTrue);
      expect(second.contractPassed, isTrue);
      expect(second.toJson(), first.toJson());
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('writes aggregate-only reports', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-host-report-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final report = await runRag2Fts5AppDatabaseHostReplay(
      Rag2Fts5AppDatabaseHostOptions(
        fixturePath: _fixturePath,
        outDir: output.path,
        storeRoot: '${output.path}/store',
      ),
    );
    final jsonReport = File(
      '${output.path}/rag2_fts5_appdatabase_host.json',
    ).readAsStringSync();
    final markdownReport = File(
      '${output.path}/rag2_fts5_appdatabase_host.md',
    ).readAsStringSync();

    expect(report.contractPassed, isTrue);
    expect(report.toJson()['noOpIndexBackfill'], isTrue);
    expect(report.toJson()['indexedTermsPretokenized'], isTrue);
    expect(report.toJson()['envelopeMismatchRejected'], isTrue);
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

  test('treats missing host, rollback, or crash recovery as no-go', () {
    Rag2Fts5AppDatabaseHostReport report({
      bool fts5AbsentAfterHostUpgrade = true,
      bool applyWithoutIndexLeavesFts5Absent = true,
      bool noOpIndexBackfill = true,
      bool indexedTermsPretokenized = true,
      bool applyRollbackPreserved = true,
      bool crashRecoveredIndex = true,
      bool envelopeMismatchRejected = true,
      bool allChunksMatchable = true,
    }) {
      return Rag2Fts5AppDatabaseHostReport(
        fixtureId: 'fixture',
        declarationIdentity: _identity,
        reopenedGeneration: 2,
        reopenedSnapshotHash: _updatedHash,
        indexedChunkCount: 5,
        matchedChunkCount: 5,
        fts5AbsentAfterHostUpgrade: fts5AbsentAfterHostUpgrade,
        applyWithoutIndexLeavesFts5Absent: applyWithoutIndexLeavesFts5Absent,
        noOpIndexBackfill: noOpIndexBackfill,
        writesThroughAppDatabase: true,
        sqliteTokenizerPreserved: true,
        indexedTermsPretokenized: indexedTermsPretokenized,
        applyIndexesLastGeneration: true,
        allChunksMatchable: allChunksMatchable,
        applyRollbackPreserved: applyRollbackPreserved,
        crashRecoveredIndex: crashRecoveredIndex,
        envelopeMatchesGeneration: true,
        envelopeMismatchRejected: envelopeMismatchRejected,
        declarationIsolation: true,
        indexSurvivesReopen: true,
        generationPreserved: true,
        embeddingsPreserved: true,
        conversationSearchPreserved: true,
        appDatabaseSchemaUnchanged: true,
      );
    }

    expect(report().contractPassed, isTrue);
    expect(report(fts5AbsentAfterHostUpgrade: false).contractPassed, isFalse);
    expect(
      report(applyWithoutIndexLeavesFts5Absent: false).contractPassed,
      isFalse,
    );
    expect(report(noOpIndexBackfill: false).contractPassed, isFalse);
    expect(report(indexedTermsPretokenized: false).contractPassed, isFalse);
    expect(report(applyRollbackPreserved: false).contractPassed, isFalse);
    expect(report(crashRecoveredIndex: false).contractPassed, isFalse);
    expect(report(envelopeMismatchRejected: false).contractPassed, isFalse);
    expect(report(allChunksMatchable: false).contractPassed, isFalse);
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
