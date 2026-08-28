import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_explicit_source_roots_replay.dart';
import '../../tool/rag2_knowledge_object_replay.dart';
import '../../tool/rag2_persistence_reopen_replay.dart';
import '../../tool/rag2_storage_replay.dart';

const _fixturePath = 'tool/fixtures/rag2_storage_replay/fixture.json';
const _identity =
    'declaration_40a72c56dc081f3170457e4c60666499964ea83a487c0dc414cc7d59a441be14';
const _baselineHash =
    '31d8769e4f33bab976367e724440209bc5d3da2c3772559522f7ea655f48c95b';
const _updatedHash =
    '3d2ef68de7071779c06e45381a761edea6494f4a9207c47463503a759914d610';

void main() {
  test('reopens the last committed generation from a new store', () async {
    final output = Directory.systemTemp.createTempSync('rag2-persist-reopen-');
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = Rag2DurableGenerationStore(
      storeRoot: output.path,
      projectId: 'rag2-storage-replay-project',
    );

    await store.apply(
      declarationIdentity: _identity,
      snapshot: snapshots.baseline,
    );
    await store.apply(
      declarationIdentity: _identity,
      snapshot: snapshots.updated,
    );

    final reopened = await Rag2DurableGenerationStore(
      storeRoot: output.path,
      projectId: 'rag2-storage-replay-project',
    ).read(_identity);

    expect(reopened?.generation, 2);
    expect(reopened?.snapshot.snapshotHash, _updatedHash);
    expect(
      reopened?.snapshot.chunks.map((chunk) => chunk.content).join('\n'),
      contains('fixture-secret-alpha'),
    );
    expect(
      _identity,
      rag2ExplicitSourceRootsDeclarationIdentity(const ['lib', 'docs']),
    );
  });

  test('discards a crash partial and preserves the prior generation', () async {
    final output = Directory.systemTemp.createTempSync('rag2-persist-crash-');
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = Rag2DurableGenerationStore(
      storeRoot: output.path,
      projectId: 'rag2-storage-replay-project',
    );
    await store.apply(
      declarationIdentity: _identity,
      snapshot: snapshots.baseline,
    );
    final crashed = await store.apply(
      declarationIdentity: _identity,
      snapshot: snapshots.updated,
      simulateCrashBeforeRename: true,
    );

    expect(crashed.decision, 'rolled_back');
    expect(store.partialFile(_identity).existsSync(), isTrue);

    final recovered = await Rag2DurableGenerationStore(
      storeRoot: output.path,
      projectId: 'rag2-storage-replay-project',
    ).read(_identity);

    expect(recovered?.generation, 1);
    expect(recovered?.snapshot.snapshotHash, _baselineHash);
    expect(store.partialFile(_identity).existsSync(), isFalse);
  });

  test('rejects an unsupported schema without mutating current', () async {
    final output = Directory.systemTemp.createTempSync('rag2-persist-schema-');
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = Rag2DurableGenerationStore(
      storeRoot: output.path,
      projectId: 'rag2-storage-replay-project',
    );
    await store.apply(
      declarationIdentity: _identity,
      snapshot: snapshots.baseline,
    );
    final current = store.currentFile(_identity);
    final mutated = current.readAsStringSync().replaceFirst(
      '"schemaVersion": 1',
      '"schemaVersion": 2',
    );
    current.writeAsStringSync(mutated);

    await expectLater(
      Rag2DurableGenerationStore(
        storeRoot: output.path,
        projectId: 'rag2-storage-replay-project',
      ).read(_identity),
      throwsA(
        isA<Rag2PersistenceException>().having(
          (error) => error.reason,
          'reason',
          'unsupported_schema',
        ),
      ),
    );
    expect(current.readAsStringSync(), mutated);
  });

  test('isolates two projects that share source roots', () async {
    final output = Directory.systemTemp.createTempSync('rag2-persist-isolate-');
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
    final first = Rag2DurableGenerationStore(
      storeRoot: output.path,
      projectId: 'persistence-project-a',
    );
    final second = Rag2DurableGenerationStore(
      storeRoot: output.path,
      projectId: 'persistence-project-b',
    );

    await first.apply(declarationIdentity: _identity, snapshot: firstSnapshot);
    await second.apply(
      declarationIdentity: _identity,
      snapshot: secondSnapshot,
    );

    expect(
      first.slotDirectory(_identity).path,
      isNot(second.slotDirectory(_identity).path),
    );
    expect(
      (await first.read(_identity))?.snapshot.snapshotHash,
      firstSnapshot.snapshotHash,
    );
    expect(
      (await second.read(_identity))?.snapshot.snapshotHash,
      secondSnapshot.snapshotHash,
    );
    expect(firstSnapshot.snapshotHash, isNot(secondSnapshot.snapshotHash));
    expect(firstSnapshot.snapshotHash, isNot(_updatedHash));
  });

  test('rejects a snapshot that belongs to another project', () async {
    final output = Directory.systemTemp.createTempSync('rag2-persist-foreign-');
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = Rag2DurableGenerationStore(
      storeRoot: output.path,
      projectId: 'persistence-project-a',
    );

    await expectLater(
      store.apply(declarationIdentity: _identity, snapshot: snapshots.baseline),
      throwsA(
        isA<Rag2PersistenceException>().having(
          (error) => error.reason,
          'reason',
          'persisted_identity_mismatch',
        ),
      ),
    );
    expect(store.currentFile(_identity).existsSync(), isFalse);
  });

  test('restores backup when current is missing after a crash', () async {
    final output = Directory.systemTemp.createTempSync('rag2-persist-bak-');
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final store = Rag2DurableGenerationStore(
      storeRoot: output.path,
      projectId: 'rag2-storage-replay-project',
    );
    await store.apply(
      declarationIdentity: _identity,
      snapshot: snapshots.baseline,
    );
    final crashed = await store.apply(
      declarationIdentity: _identity,
      snapshot: snapshots.updated,
      simulateCrashAfterQuiescingCurrent: true,
    );

    expect(crashed.decision, 'rolled_back');
    expect(store.currentFile(_identity).existsSync(), isFalse);
    expect(store.backupFile(_identity).existsSync(), isTrue);
    expect(store.partialFile(_identity).existsSync(), isTrue);

    final recovered = await Rag2DurableGenerationStore(
      storeRoot: output.path,
      projectId: 'rag2-storage-replay-project',
    ).read(_identity);

    expect(recovered?.generation, 1);
    expect(recovered?.snapshot.snapshotHash, _baselineHash);
    expect(store.currentFile(_identity).existsSync(), isTrue);
    expect(store.backupFile(_identity).existsSync(), isFalse);
    expect(store.partialFile(_identity).existsSync(), isFalse);
  });

  test('replays twice against the same output directory', () async {
    final output = Directory.systemTemp.createTempSync('rag2-persist-rerun-');
    addTearDown(() => output.deleteSync(recursive: true));
    final options = Rag2PersistenceReopenOptions(
      fixturePath: _fixturePath,
      outDir: output.path,
      storeRoot: '${output.path}/store',
    );

    final first = await runRag2PersistenceReopenReplay(options);
    final second = await runRag2PersistenceReopenReplay(options);

    expect(first.contractPassed, isTrue);
    expect(second.contractPassed, isTrue);
    expect(second.toJson(), first.toJson());
  });

  test('writes aggregate-only reports', () async {
    final output = Directory.systemTemp.createTempSync('rag2-persist-report-');
    addTearDown(() => output.deleteSync(recursive: true));
    final report = await runRag2PersistenceReopenReplay(
      Rag2PersistenceReopenOptions(
        fixturePath: _fixturePath,
        outDir: output.path,
        storeRoot: '${output.path}/store',
      ),
    );
    final jsonReport = File(
      '${output.path}/rag2_persistence_reopen.json',
    ).readAsStringSync();
    final markdownReport = File(
      '${output.path}/rag2_persistence_reopen.md',
    ).readAsStringSync();

    expect(report.contractPassed, isTrue);
    expect(report.toJson()['persistenceDecision'], 'go');
    expect(report.toJson()['declarationIsolation'], isTrue);
    expect(report.toJson()['foreignSnapshotRejected'], isTrue);
    expect(report.toJson()['backendDecision'], 'not_selected');
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(jsonDecode(jsonReport), report.toJson());
    expect(markdownReport, report.toMarkdown());
    for (final forbidden in [
      Directory.current.path,
      '/Users/',
      'docs/guide.md',
      'fixture-secret-alpha',
      'sourceRoots',
    ]) {
      expect(jsonReport, isNot(contains(forbidden)));
      expect(markdownReport, isNot(contains(forbidden)));
    }
  });
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
