import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_drift_additive_schema_replay.dart';
import '../../tool/rag2_drift_dao_generation_store.dart';
import '../../tool/rag2_explicit_source_roots_replay.dart';
import '../../tool/rag2_fts5_additive_index_replay.dart';
import '../../tool/rag2_fts5_visibility_drop_replay.dart';
import '../../tool/rag2_knowledge_object_replay.dart';
import '../../tool/rag2_storage_replay.dart';

const _fixturePath = 'tool/fixtures/rag2_storage_replay/fixture.json';
const _identity =
    'declaration_40a72c56dc081f3170457e4c60666499964ea83a487c0dc414cc7d59a441be14';
const _updatedHash =
    '3d2ef68de7071779c06e45381a761edea6494f4a9207c47463503a759914d610';
const _projectId = 'rag2-storage-replay-project';
const _neighborProjectId = 'rag2-fts5-visibility-neighbor';

void main() {
  final projectIdentity = rag2ExplicitSourceRootsProjectIdentity(_projectId);

  test('clearSearchIndex hides FTS5 and keeps generation 2', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-visibility-clear-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    await store.clearSearchIndex(declarationIdentity: _identity);
    final generation = await store.read(_identity);
    expect(generation?.generation, 2);
    expect(generation?.snapshot.snapshotHash, _updatedHash);
    expect(
      await rag2ChunkSearchChunkIds(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
      ),
      isEmpty,
    );
    expect(
      await rag2ChunkSearchMatchedCount(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
        chunks: snapshots.updated.chunks,
      ),
      0,
    );
  });

  test('drop removes generation and FTS5 visibility', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-visibility-drop-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    await store.drop(declarationIdentity: _identity);
    expect(await store.read(_identity), isNull);
    expect(
      await rag2ChunkSearchChunkIds(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
      ),
      isEmpty,
    );
    expect(
      await rag2ChunkSearchMatchedCount(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
        chunks: snapshots.updated.chunks,
      ),
      0,
    );
  });

  test('drop preserves a neighbor project index', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-visibility-neighbor-',
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
    final dropper = Rag2DriftDaoGenerationStore.open(
      databasePath: path,
      projectId: _projectId,
    );
    addTearDown(dropper.close);
    await dropper.drop(declarationIdentity: _identity);
    expect(await dropper.read(_identity), isNull);
    final neighborReader = Rag2DriftDaoGenerationStore.open(
      databasePath: path,
      projectId: _neighborProjectId,
    );
    addTearDown(neighborReader.close);
    final neighborGeneration = await neighborReader.read(_identity);
    expect(neighborGeneration?.generation, 1);
    expect(
      await rag2Fts5SlotMatchesGeneration(
        dropper.database,
        projectId: _neighborProjectId,
        declarationIdentity: _identity,
        generation: neighborGeneration!,
      ),
      isTrue,
    );
  });

  test('rolls back a failed drop', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-visibility-rollback-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openIndexedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    await expectLater(
      store.drop(
        declarationIdentity: _identity,
        beforeTxnCommit: () => throw StateError('injected_drop_failure'),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'injected_drop_failure',
        ),
      ),
    );
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

  test('recovers generation 2 after a killed uncommitted drop', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-visibility-crash-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final path = '${output.path}/caverno.sqlite';
    final store = await _openIndexedStore(path, snapshots);
    await store.close();
    final recovered = await recoverAfterKilledUncommittedDriftDaoWrite(
      fixturePath: _fixturePath,
      databasePath: path,
      projectId: _projectId,
      declarationIdentity: _identity,
      dropUncommitted: true,
    );
    expect(recovered?.generation, 2);
    expect(recovered?.snapshot.snapshotHash, _updatedHash);
    final opened = Rag2DriftDaoGenerationStore.open(
      databasePath: path,
      projectId: _projectId,
    );
    addTearDown(opened.close);
    expect(
      await rag2Fts5SlotMatchesGeneration(
        opened.database,
        projectId: _projectId,
        declarationIdentity: _identity,
        generation: recovered!,
      ),
      isTrue,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('refuses dropUncommitted with indexSearch', () async {
    await expectLater(
      recoverAfterKilledUncommittedDriftDaoWrite(
        fixturePath: _fixturePath,
        databasePath: 'unused.sqlite',
        projectId: _projectId,
        declarationIdentity: _identity,
        indexSearch: true,
        dropUncommitted: true,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          'dropUncommitted and indexSearch cannot be combined',
        ),
      ),
    );
  });

  test('drop without an index leaves RAG2 FTS5 absent', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-visibility-unindexed-',
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
    await store.drop(declarationIdentity: _identity);
    expect(await store.read(_identity), isNull);
    expect(
      await rag2SqliteMasterSql(store.database, rag2ChunkSearchTable),
      isEmpty,
    );
  });

  test('replays twice against the same output directory', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-visibility-twice-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final options = Rag2Fts5VisibilityDropOptions(
      fixturePath: _fixturePath,
      outDir: output.path,
      storeRoot: '${output.path}/store',
    );
    final first = await runRag2Fts5VisibilityDropReplay(options);
    final second = await runRag2Fts5VisibilityDropReplay(options);
    expect(first.contractPassed, isTrue);
    expect(second.toJson(), first.toJson());
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('writes aggregate-only reports', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-visibility-report-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final report = await runRag2Fts5VisibilityDropReplay(
      Rag2Fts5VisibilityDropOptions(
        fixturePath: _fixturePath,
        outDir: output.path,
        storeRoot: '${output.path}/store',
      ),
    );
    final jsonReport = File(
      '${output.path}/rag2_fts5_visibility_drop.json',
    ).readAsStringSync();
    final markdownReport = File(
      '${output.path}/rag2_fts5_visibility_drop.md',
    ).readAsStringSync();

    expect(report.contractPassed, isTrue);
    expect(report.toJson()['clearHidesIndex'], isTrue);
    expect(report.toJson()['clearThenIndexedApplyRestores'], isTrue);
    expect(report.toJson()['dropRemovesGenerationAndIndex'], isTrue);
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

  test('treats missing hide, drop, or crash recovery as no-go', () {
    Rag2Fts5VisibilityDropReport report({
      bool clearHidesIndex = true,
      bool clearThenIndexedApplyRestores = true,
      bool dropRemovesGenerationAndIndex = true,
      bool dropRollbackPreserved = true,
      bool crashRecoveredAfterDrop = true,
      bool neighborIndexPreserved = true,
      bool dropWithoutIndexLeavesFts5Absent = true,
    }) {
      return Rag2Fts5VisibilityDropReport(
        fixtureId: 'fixture',
        declarationIdentity: _identity,
        reopenedGeneration: 0,
        clearHidesIndex: clearHidesIndex,
        clearThenIndexedApplyRestores: clearThenIndexedApplyRestores,
        dropRemovesGenerationAndIndex: dropRemovesGenerationAndIndex,
        dropRollbackPreserved: dropRollbackPreserved,
        crashRecoveredAfterDrop: crashRecoveredAfterDrop,
        neighborIndexPreserved: neighborIndexPreserved,
        dropWithoutIndexLeavesFts5Absent: dropWithoutIndexLeavesFts5Absent,
        dropSurvivesReopen: true,
        sqliteTokenizerPreserved: true,
        embeddingsPreserved: true,
        conversationSearchPreserved: true,
        appDatabaseSchemaUnchanged: true,
      );
    }

    expect(report().contractPassed, isTrue);
    expect(report(clearHidesIndex: false).contractPassed, isFalse);
    expect(
      report(clearThenIndexedApplyRestores: false).contractPassed,
      isFalse,
    );
    expect(
      report(dropRemovesGenerationAndIndex: false).contractPassed,
      isFalse,
    );
    expect(report(dropRollbackPreserved: false).contractPassed, isFalse);
    expect(report(crashRecoveredAfterDrop: false).contractPassed, isFalse);
    expect(report(neighborIndexPreserved: false).contractPassed, isFalse);
    expect(
      report(dropWithoutIndexLeavesFts5Absent: false).contractPassed,
      isFalse,
    );
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
