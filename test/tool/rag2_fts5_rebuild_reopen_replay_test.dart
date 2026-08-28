import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_drift_additive_schema_replay.dart';
import '../../tool/rag2_drift_dao_generation_store.dart';
import '../../tool/rag2_explicit_source_roots_replay.dart';
import '../../tool/rag2_fts5_additive_index_replay.dart';
import '../../tool/rag2_fts5_rebuild_reopen_replay.dart';
import '../../tool/rag2_fts5_visibility_drop_replay.dart';
import '../../tool/rag2_knowledge_object_replay.dart';
import '../../tool/rag2_storage_replay.dart';

const _fixturePath = 'tool/fixtures/rag2_storage_replay/fixture.json';
const _identity =
    'declaration_40a72c56dc081f3170457e4c60666499964ea83a487c0dc414cc7d59a441be14';
const _updatedHash =
    '3d2ef68de7071779c06e45381a761edea6494f4a9207c47463503a759914d610';
const _projectId = 'rag2-storage-replay-project';
const _neighborProjectId = 'rag2-fts5-rebuild-neighbor';
const _staleHash = 'stale-hash';

void main() {
  final projectIdentity = rag2ExplicitSourceRootsProjectIdentity(_projectId);

  test('rebuilds a cleared slot from generation 2 payload', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-rebuild-clear-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    await store.clearSearchIndex(declarationIdentity: _identity);
    await store.rebuildSearchIndex(declarationIdentity: _identity);
    final generation = await store.read(_identity);
    expect(generation?.generation, 2);
    expect(generation?.snapshot.snapshotHash, _updatedHash);
    expect(
      await rag2Fts5SlotMatchesGeneration(
        store.database,
        projectId: _projectId,
        declarationIdentity: _identity,
        generation: generation!,
      ),
      isTrue,
    );
  });

  test('rebuilds a mismatched slot without bumping generation', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-rebuild-mismatch-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    await store.database.customStatement(
      'UPDATE $rag2ChunkSearchTable SET snapshot_hash = ? '
      'WHERE project_identity = ? AND declaration_identity = ?',
      [_staleHash, projectIdentity, _identity],
    );
    await store.rebuildSearchIndex(declarationIdentity: _identity);
    final generation = await store.read(_identity);
    expect(generation?.generation, 2);
    expect(generation?.snapshot.snapshotHash, _updatedHash);
    expect(
      await rag2Fts5SlotMatchesGeneration(
        store.database,
        projectId: _projectId,
        declarationIdentity: _identity,
        generation: generation!,
      ),
      isTrue,
    );
  });

  test('rebuild is deterministic and reopens generation 2', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-rebuild-reopen-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final path = '${output.path}/caverno.sqlite';
    final writer = await _openIndexedStore(path, snapshots);
    await writer.clearSearchIndex(declarationIdentity: _identity);
    await writer.rebuildSearchIndex(declarationIdentity: _identity);
    await writer.rebuildSearchIndex(declarationIdentity: _identity);
    await writer.close();
    final store = Rag2DriftDaoGenerationStore.open(
      databasePath: path,
      projectId: _projectId,
    );
    addTearDown(store.close);
    final generation = await store.read(_identity);
    expect(generation?.generation, 2);
    expect(
      await rag2Fts5SlotMatchesGeneration(
        store.database,
        projectId: _projectId,
        declarationIdentity: _identity,
        generation: generation!,
      ),
      isTrue,
    );
  });

  test('rebuild preserves a neighbor project index', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-rebuild-neighbor-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final path = '${output.path}/caverno.sqlite';
    final store = await _openIndexedStore(path, snapshots);
    await store.close();
    final neighborSnapshot = await _neighborSnapshot();
    final neighbor = Rag2DriftDaoGenerationStore.open(
      databasePath: path,
      projectId: _neighborProjectId,
    );
    await neighbor.apply(
      declarationIdentity: _identity,
      snapshot: neighborSnapshot,
      indexSearch: true,
    );
    await neighbor.close();
    final rebuildTarget = Rag2DriftDaoGenerationStore.open(
      databasePath: path,
      projectId: _projectId,
    );
    addTearDown(rebuildTarget.close);
    await rebuildTarget.clearSearchIndex(declarationIdentity: _identity);
    await rebuildTarget.rebuildSearchIndex(declarationIdentity: _identity);
    final neighborReader = Rag2DriftDaoGenerationStore.open(
      databasePath: path,
      projectId: _neighborProjectId,
    );
    addTearDown(neighborReader.close);
    final neighborGeneration = await neighborReader.read(_identity);
    expect(neighborGeneration?.generation, 1);
    expect(
      await rag2Fts5SlotMatchesGeneration(
        rebuildTarget.database,
        projectId: _neighborProjectId,
        declarationIdentity: _identity,
        generation: neighborGeneration!,
      ),
      isTrue,
    );
  });

  test('rolls back a failed rebuild', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-rebuild-rollback-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    await store.database.customStatement(
      'UPDATE $rag2ChunkSearchTable SET snapshot_hash = ? '
      'WHERE project_identity = ? AND declaration_identity = ?',
      [_staleHash, projectIdentity, _identity],
    );
    await expectLater(
      store.rebuildSearchIndex(
        declarationIdentity: _identity,
        beforeTxnCommit: () => throw StateError('injected_rebuild_failure'),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'injected_rebuild_failure',
        ),
      ),
    );
    final generation = await store.read(_identity);
    expect(generation?.generation, 2);
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
  });

  test('recovers generation 2 after a killed uncommitted rebuild', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-rebuild-crash-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final path = '${output.path}/caverno.sqlite';
    final store = await _openIndexedStore(path, snapshots);
    await store.clearSearchIndex(declarationIdentity: _identity);
    await store.close();
    final recovered = await recoverAfterKilledUncommittedDriftDaoWrite(
      fixturePath: _fixturePath,
      databasePath: path,
      projectId: _projectId,
      declarationIdentity: _identity,
      rebuildUncommitted: true,
    );
    expect(recovered?.generation, 2);
    expect(recovered?.snapshot.snapshotHash, _updatedHash);
    final opened = Rag2DriftDaoGenerationStore.open(
      databasePath: path,
      projectId: _projectId,
    );
    addTearDown(opened.close);
    expect(
      await rag2ChunkSearchChunkIds(
        opened.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
      ),
      isEmpty,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('rebuild without a generation does not create FTS rows', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-rebuild-missing-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    await store.drop(declarationIdentity: _identity);
    await store.rebuildSearchIndex(declarationIdentity: _identity);
    expect(await store.read(_identity), isNull);
    expect(
      await rag2ChunkSearchChunkIds(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
      ),
      isEmpty,
    );
  });

  test(
    'rebuild of an unindexed generation creates FTS from the payload',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'rag2-fts5-rebuild-unindexed-',
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
      await store.rebuildSearchIndex(declarationIdentity: _identity);
      final generation = await store.read(_identity);
      expect(generation?.generation, 2);
      expect(
        await rag2Fts5SlotMatchesGeneration(
          store.database,
          projectId: _projectId,
          declarationIdentity: _identity,
          generation: generation!,
        ),
        isTrue,
      );
    },
  );

  test('refuses rebuildUncommitted with indexSearch or dropUncommitted', () async {
    await expectLater(
      recoverAfterKilledUncommittedDriftDaoWrite(
        fixturePath: _fixturePath,
        databasePath: 'unused.sqlite',
        projectId: _projectId,
        declarationIdentity: _identity,
        indexSearch: true,
        rebuildUncommitted: true,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          'rebuildUncommitted cannot be combined with indexSearch or dropUncommitted',
        ),
      ),
    );
    await expectLater(
      recoverAfterKilledUncommittedDriftDaoWrite(
        fixturePath: _fixturePath,
        databasePath: 'unused.sqlite',
        projectId: _projectId,
        declarationIdentity: _identity,
        dropUncommitted: true,
        rebuildUncommitted: true,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          'rebuildUncommitted cannot be combined with indexSearch or dropUncommitted',
        ),
      ),
    );
  });

  test('replays twice against the same output directory', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-rebuild-twice-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final options = Rag2Fts5RebuildReopenOptions(
      fixturePath: _fixturePath,
      outDir: output.path,
      storeRoot: '${output.path}/store',
    );
    final first = await runRag2Fts5RebuildReopenReplay(options);
    final second = await runRag2Fts5RebuildReopenReplay(options);
    expect(first.contractPassed, isTrue);
    expect(second.toJson(), first.toJson());
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('writes aggregate-only reports', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-rebuild-report-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final report = await runRag2Fts5RebuildReopenReplay(
      Rag2Fts5RebuildReopenOptions(
        fixturePath: _fixturePath,
        outDir: output.path,
        storeRoot: '${output.path}/store',
      ),
    );
    final jsonReport = File(
      '${output.path}/rag2_fts5_rebuild_reopen.json',
    ).readAsStringSync();
    final markdownReport = File(
      '${output.path}/rag2_fts5_rebuild_reopen.md',
    ).readAsStringSync();

    expect(report.contractPassed, isTrue);
    expect(report.toJson()['rebuiltClearedSlot'], isTrue);
    expect(report.toJson()['rebuildReopened'], isTrue);
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

  test('treats missing rebuild, reopen, or crash recovery as no-go', () {
    Rag2Fts5RebuildReopenReport report({
      bool rebuiltClearedSlot = true,
      bool rebuiltMismatchedSlot = true,
      bool rebuildDeterministic = true,
      bool rebuildReopened = true,
      bool rebuildRollbackPreserved = true,
      bool crashRecoveredAfterRebuild = true,
      bool neighborIndexPreserved = true,
      bool rebuildWithoutGenerationNoOp = true,
      bool rebuildUnindexedCreatesIndex = true,
    }) {
      return Rag2Fts5RebuildReopenReport(
        fixtureId: 'fixture',
        declarationIdentity: _identity,
        reopenedGeneration: 2,
        rebuiltClearedSlot: rebuiltClearedSlot,
        rebuiltMismatchedSlot: rebuiltMismatchedSlot,
        rebuildDeterministic: rebuildDeterministic,
        rebuildReopened: rebuildReopened,
        rebuildRollbackPreserved: rebuildRollbackPreserved,
        crashRecoveredAfterRebuild: crashRecoveredAfterRebuild,
        neighborIndexPreserved: neighborIndexPreserved,
        rebuildWithoutGenerationNoOp: rebuildWithoutGenerationNoOp,
        rebuildUnindexedCreatesIndex: rebuildUnindexedCreatesIndex,
        sqliteTokenizerPreserved: true,
        embeddingsPreserved: true,
        conversationSearchPreserved: true,
        appDatabaseSchemaUnchanged: true,
      );
    }

    expect(report().contractPassed, isTrue);
    expect(report(rebuiltClearedSlot: false).contractPassed, isFalse);
    expect(report(rebuiltMismatchedSlot: false).contractPassed, isFalse);
    expect(report(rebuildDeterministic: false).contractPassed, isFalse);
    expect(report(rebuildReopened: false).contractPassed, isFalse);
    expect(report(rebuildRollbackPreserved: false).contractPassed, isFalse);
    expect(report(crashRecoveredAfterRebuild: false).contractPassed, isFalse);
    expect(report(neighborIndexPreserved: false).contractPassed, isFalse);
    expect(report(rebuildWithoutGenerationNoOp: false).contractPassed, isFalse);
    expect(report(rebuildUnindexedCreatesIndex: false).contractPassed, isFalse);
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
