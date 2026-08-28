import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_drift_additive_schema_replay.dart';
import '../../tool/rag2_drift_dao_generation_store.dart';
import '../../tool/rag2_explicit_source_roots_replay.dart';
import '../../tool/rag2_fts5_additive_index_replay.dart';
import '../../tool/rag2_fts5_incremental_index_replay.dart';
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
    'empty slot full-replaces, then generation 2 preserves unchanged rowids',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'rag2-fts5-incremental-rowid-',
      );
      addTearDown(() => output.deleteSync(recursive: true));
      final snapshots = await _snapshots();
      final delta = Rag2KnowledgeReplayDelta.compare(
        snapshots.baseline,
        snapshots.updated,
      );
      final path = '${output.path}/caverno.sqlite';
      await prepareRag2DriftHost(databasePath: path);
      final store = Rag2DriftDaoGenerationStore.open(
        databasePath: path,
        projectId: _projectId,
      );
      addTearDown(store.close);
      final first = await store.apply(
        declarationIdentity: _identity,
        snapshot: snapshots.baseline,
        indexSearch: true,
      );
      expect(first.decision, 'applied');
      expect(
        await rag2ChunkSearchChunkIds(
          store.database,
          projectIdentity: projectIdentity,
          declarationIdentity: _identity,
        ),
        {for (final chunk in snapshots.baseline.chunks) chunk.chunkId},
      );
      final before = await rag2ChunkSearchRowids(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
      );
      final contentsBefore = await rag2ChunkSearchContents(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
      );
      final second = await store.apply(
        declarationIdentity: _identity,
        snapshot: snapshots.updated,
        indexSearch: true,
      );
      expect(second.decision, 'applied');
      expect(second.delta.unchangedChunkIds, delta.unchangedChunkIds);
      final after = await rag2ChunkSearchRowids(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
      );
      final contentsAfter = await rag2ChunkSearchContents(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
      );
      for (final chunkId in delta.unchangedChunkIds) {
        expect(after[chunkId], before[chunkId]);
        expect(contentsAfter[chunkId], contentsBefore[chunkId]);
      }
      for (final chunkId in delta.removedChunkIds) {
        expect(after.containsKey(chunkId), isFalse);
      }
      for (final chunkId in delta.addedChunkIds) {
        expect(after.containsKey(chunkId), isTrue);
      }
    },
  );

  test(
    'full-replaces when unchanged FTS5 content disagrees with previous generation',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'rag2-fts5-incremental-corrupt-content-',
      );
      addTearDown(() => output.deleteSync(recursive: true));
      final snapshots = await _snapshots();
      final delta = Rag2KnowledgeReplayDelta.compare(
        snapshots.baseline,
        snapshots.updated,
      );
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
        indexSearch: true,
      );
      await store.database.customStatement(
        'UPDATE $rag2ChunkSearchTable SET content = ? '
        'WHERE project_identity = ? AND declaration_identity = ? AND chunk_id = ?',
        [
          'corrupt-index-token',
          projectIdentity,
          _identity,
          delta.unchangedChunkIds.first,
        ],
      );
      final result = await store.apply(
        declarationIdentity: _identity,
        snapshot: snapshots.updated,
        indexSearch: true,
      );
      expect(result.decision, 'applied');
      expect(
        await rag2ChunkSearchTermsMatchPolicy(
          store.database,
          projectIdentity: projectIdentity,
          declarationIdentity: _identity,
          chunks: snapshots.updated.chunks,
        ),
        isTrue,
      );
      expect(
        await rag2ChunkSearchContents(
          store.database,
          projectIdentity: projectIdentity,
          declarationIdentity: _identity,
        ),
        isNot(containsValue('corrupt-index-token')),
      );
    },
  );

  test(
    'full-replaces when FTS5 envelope disagrees with previous generation',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'rag2-fts5-incremental-corrupt-envelope-',
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
        indexSearch: true,
      );
      await store.database.customStatement(
        'UPDATE $rag2ChunkSearchTable SET snapshot_hash = ? '
        'WHERE project_identity = ? AND declaration_identity = ?',
        ['stale-hash', projectIdentity, _identity],
      );
      final result = await store.apply(
        declarationIdentity: _identity,
        snapshot: snapshots.updated,
        indexSearch: true,
      );
      expect(result.decision, 'applied');
      final generation = await store.read(_identity);
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

  test('incremental apply reopens generation 2 and its FTS5 slot', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-incremental-reopen-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final path = '${output.path}/caverno.sqlite';
    final writer = await _openPatchedStore(path, snapshots);
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
  });

  test('rolls back a failed incremental patch', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-incremental-rollback-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = await _openPatchedStore(
      '${output.path}/caverno.sqlite',
      snapshots,
    );
    addTearDown(store.close);
    final before = await rag2ChunkSearchRowids(
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
      await rag2ChunkSearchRowids(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
      ),
      before,
    );
  });

  test(
    'recovers generation 1 rowids after a killed incremental apply',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'rag2-fts5-incremental-crash-',
      );
      addTearDown(() => output.deleteSync(recursive: true));
      final snapshots = await _snapshots();
      final path = '${output.path}/caverno.sqlite';
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
      final before = await rag2ChunkSearchRowids(
        store.database,
        projectIdentity: projectIdentity,
        declarationIdentity: _identity,
      );
      await store.close();
      final recovered = await recoverAfterKilledUncommittedDriftDaoWrite(
        fixturePath: _fixturePath,
        databasePath: path,
        projectId: _projectId,
        declarationIdentity: _identity,
        indexSearch: true,
      );
      expect(recovered?.generation, 1);
      final opened = Rag2DriftDaoGenerationStore.open(
        databasePath: path,
        projectId: _projectId,
      );
      addTearDown(opened.close);
      expect(
        await rag2ChunkSearchRowids(
          opened.database,
          projectIdentity: projectIdentity,
          declarationIdentity: _identity,
        ),
        before,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'preserves conversation-search contents and embeddings',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'rag2-fts5-incremental-host-',
      );
      addTearDown(() => output.deleteSync(recursive: true));
      final report = await runRag2Fts5IncrementalIndexReplay(
        Rag2Fts5IncrementalIndexOptions(
          fixturePath: _fixturePath,
          outDir: output.path,
          storeRoot: '${output.path}/store',
        ),
      );
      expect(report.conversationSearchPreserved, isTrue);
      expect(report.embeddingsPreserved, isTrue);
      expect(report.appDatabaseSchemaUnchanged, isTrue);
      expect(report.sqliteTokenizerPreserved, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'replays twice against the same output directory',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'rag2-fts5-incremental-twice-',
      );
      addTearDown(() => output.deleteSync(recursive: true));
      final options = Rag2Fts5IncrementalIndexOptions(
        fixturePath: _fixturePath,
        outDir: output.path,
        storeRoot: '${output.path}/store',
      );
      final first = await runRag2Fts5IncrementalIndexReplay(options);
      final second = await runRag2Fts5IncrementalIndexReplay(options);
      expect(first.contractPassed, isTrue);
      expect(second.toJson(), first.toJson());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('writes aggregate-only reports', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-fts5-incremental-report-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final report = await runRag2Fts5IncrementalIndexReplay(
      Rag2Fts5IncrementalIndexOptions(
        fixturePath: _fixturePath,
        outDir: output.path,
        storeRoot: '${output.path}/store',
      ),
    );
    final jsonReport = File(
      '${output.path}/rag2_fts5_incremental_index.json',
    ).readAsStringSync();
    final markdownReport = File(
      '${output.path}/rag2_fts5_incremental_index.md',
    ).readAsStringSync();

    expect(report.contractPassed, isTrue);
    expect(report.toJson()['unchangedRowidsPreserved'], isTrue);
    expect(report.toJson()['emptySlotFullReplace'], isTrue);
    expect(report.toJson()['mismatchedSlotFullReplace'], isTrue);
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
      'corrupt-index-token',
    ]) {
      expect(jsonReport, isNot(contains(forbidden)));
      expect(markdownReport, isNot(contains(forbidden)));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('treats missing skip, rollback, or crash recovery as no-go', () {
    Rag2Fts5IncrementalIndexReport report({
      bool emptySlotFullReplace = true,
      bool unchangedRowidsPreserved = true,
      bool unchangedContentPreserved = true,
      bool removedChunksAbsent = true,
      bool addedChunksPresent = true,
      bool mismatchedSlotFullReplace = true,
      bool applyRollbackPreserved = true,
      bool crashRecoveredIndex = true,
      bool allChunksMatchable = true,
    }) {
      return Rag2Fts5IncrementalIndexReport(
        fixtureId: 'fixture',
        declarationIdentity: _identity,
        reopenedGeneration: 2,
        reopenedSnapshotHash: _updatedHash,
        indexedChunkCount: 5,
        matchedChunkCount: 5,
        unchangedChunkCount: 2,
        metadataUpdatedChunkCount: 2,
        removedChunkCount: 1,
        addedChunkCount: 1,
        emptySlotFullReplace: emptySlotFullReplace,
        unchangedRowidsPreserved: unchangedRowidsPreserved,
        unchangedContentPreserved: unchangedContentPreserved,
        removedChunksAbsent: removedChunksAbsent,
        addedChunksPresent: addedChunksPresent,
        mismatchedSlotFullReplace: mismatchedSlotFullReplace,
        deltaCountsMatchFixture: true,
        sqliteTokenizerPreserved: true,
        indexedTermsPretokenized: true,
        applyIndexesLastGeneration: true,
        allChunksMatchable: allChunksMatchable,
        applyRollbackPreserved: applyRollbackPreserved,
        crashRecoveredIndex: crashRecoveredIndex,
        envelopeMatchesGeneration: true,
        indexSurvivesReopen: true,
        generationPreserved: true,
        embeddingsPreserved: true,
        conversationSearchPreserved: true,
        appDatabaseSchemaUnchanged: true,
      );
    }

    expect(report().contractPassed, isTrue);
    expect(report(emptySlotFullReplace: false).contractPassed, isFalse);
    expect(report(unchangedRowidsPreserved: false).contractPassed, isFalse);
    expect(report(unchangedContentPreserved: false).contractPassed, isFalse);
    expect(report(removedChunksAbsent: false).contractPassed, isFalse);
    expect(report(addedChunksPresent: false).contractPassed, isFalse);
    expect(report(mismatchedSlotFullReplace: false).contractPassed, isFalse);
    expect(report(applyRollbackPreserved: false).contractPassed, isFalse);
    expect(report(crashRecoveredIndex: false).contractPassed, isFalse);
    expect(report(allChunksMatchable: false).contractPassed, isFalse);
  });
}

Future<Rag2DriftDaoGenerationStore> _openPatchedStore(
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
