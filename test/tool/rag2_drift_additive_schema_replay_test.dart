import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../tool/rag2_drift_additive_schema_replay.dart';
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
const _projectId = 'rag2-storage-replay-project';

void main() {
  test('migrates v4 AppDatabase without rewriting embedding rows', () async {
    final output = Directory.systemTemp.createTempSync('rag2-drift-migrate-');
    addTearDown(() => output.deleteSync(recursive: true));
    final path = '${output.path}/caverno.sqlite';
    final seeded = await prepareRag2DriftHost(databasePath: path);
    final host = AppDatabase(NativeDatabase(File(path)));
    addTearDown(host.close);
    final embeddings = await host.select(host.embeddings).get();
    final version = await host.customSelect('PRAGMA user_version').getSingle();

    expect(embeddings.single.sourceId, seeded.sourceId);
    expect(embeddings.single.sourceType, 'conversation');
    expect(embeddings.single.chunkIndex, 0);
    expect(embeddings.single.model, 'll5-sentinel-model');
    expect(embeddings.single.dim, 1);
    expect(embeddings.single.snippet, 'll5-sentinel-snippet');
    expect(embeddings.single.createdAtMs, 0);
    expect(embeddings.single.vector, Uint8List.fromList(const [1, 2, 3, 4]));
    expect(embeddings.single.id, seeded.id);
    expect(
      (await host.select(host.conversations).get()).single.id,
      rag2DriftHostConversationId,
    );
    expect(
      (await host.select(host.conversations).get()).single.title,
      rag2DriftHostConversationTitle,
    );
    expect(
      (await host.select(host.conversations).get()).single.payload,
      rag2DriftHostConversationPayload,
    );
    expect(
      (await host.select(host.modelUsageDaily).get()).single.totalTokens,
      rag2DriftHostUsageTokens,
    );
    expect(
      (await host
              .customSelect('SELECT id, title, body FROM conversation_search')
              .get())
          .single
          .read<String>('body'),
      rag2DriftHostSearchBody,
    );
    final schema = await inspectRag2DriftHostSchema(host);
    expect(schema.onlyConversationSearchFts5, isTrue);
    expect(schema.logicalTables, rag2DriftHostLogicalTables);
    expect(version.data['user_version'], 5);
  });

  test('reopens the last committed generation from a new connection', () async {
    final output = Directory.systemTemp.createTempSync('rag2-drift-reopen-');
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final path = '${output.path}/caverno.sqlite';
    await prepareRag2DriftHost(databasePath: path);
    final store = Rag2DriftGenerationStore(
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
    store.close();

    final host = AppDatabase(NativeDatabase(File(path)));
    addTearDown(host.close);
    final generation = await readRag2GenerationFromAppDatabase(
      database: host,
      projectId: _projectId,
      declarationIdentity: _identity,
    );
    final embeddings = await host.select(host.embeddings).get();

    expect(generation?.generation, 2);
    expect(generation?.snapshot.snapshotHash, _updatedHash);
    expect(
      generation?.snapshot.chunks.map((chunk) => chunk.content).join('\n'),
      contains('fixture-secret-alpha'),
    );
    expect(embeddings.single.sourceId, 'll5-sentinel');
    expect(
      _identity,
      rag2ExplicitSourceRootsDeclarationIdentity(const ['lib', 'docs']),
    );
  });

  test(
    'recovers generation 1 after a killed uncommitted writer',
    () async {
      final output = Directory.systemTemp.createTempSync('rag2-drift-crash-');
      addTearDown(() => output.deleteSync(recursive: true));
      final snapshots = await _snapshots();
      final path = '${output.path}/caverno.sqlite';
      await prepareRag2DriftHost(databasePath: path);
      final store = Rag2DriftGenerationStore(
        databasePath: path,
        projectId: _projectId,
      );
      await store.apply(
        declarationIdentity: _identity,
        snapshot: snapshots.baseline,
      );
      store.close();

      final generation = await recoverAfterKilledUncommittedDriftWrite(
        fixturePath: _fixturePath,
        databasePath: path,
        projectId: _projectId,
        declarationIdentity: _identity,
      );

      expect(generation?.generation, 1);
      expect(generation?.snapshot.snapshotHash, _baselineHash);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'serializes concurrent writers onto increasing generations',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'rag2-drift-concurrent-',
      );
      addTearDown(() => output.deleteSync(recursive: true));
      final path = '${output.path}/caverno.sqlite';
      await prepareRag2DriftHost(databasePath: path);
      await Future.wait([
        applyRag2DriftSnapshotInChild(
          fixturePath: _fixturePath,
          databasePath: path,
          snapshotIndex: 0,
        ),
        applyRag2DriftSnapshotInChild(
          fixturePath: _fixturePath,
          databasePath: path,
          snapshotIndex: 1,
        ),
      ]);

      final store = Rag2DriftGenerationStore(
        databasePath: path,
        projectId: _projectId,
      );
      addTearDown(store.close);
      final generation = await store.read(_identity);
      expect(generation?.generation, 2);
      expect(
        generation?.snapshot.snapshotHash,
        isIn([_baselineHash, _updatedHash]),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'rejects a generation row whose envelope disagrees with the payload',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'rag2-drift-envelope-',
      );
      addTearDown(() => output.deleteSync(recursive: true));
      final snapshots = await _snapshots();
      final path = '${output.path}/caverno.sqlite';
      await prepareRag2DriftHost(databasePath: path);
      final store = Rag2DriftGenerationStore(
        databasePath: path,
        projectId: _projectId,
      );
      await store.apply(
        declarationIdentity: _identity,
        snapshot: snapshots.baseline,
      );
      store.close();

      final mutated = sqlite3.open(path);
      mutated.execute('UPDATE rag2_generations SET generation = 99');
      mutated.dispose();

      final reopened = Rag2DriftGenerationStore(
        databasePath: path,
        projectId: _projectId,
      );
      addTearDown(reopened.close);
      await expectLater(
        reopened.read(_identity),
        throwsA(
          isA<Rag2PersistenceException>().having(
            (error) => error.reason,
            'reason',
            'persisted_identity_mismatch',
          ),
        ),
      );
    },
  );

  test('rejects an unsupported schema without mutating rows', () async {
    final output = Directory.systemTemp.createTempSync('rag2-drift-schema-');
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final path = '${output.path}/caverno.sqlite';
    await prepareRag2DriftHost(databasePath: path);
    final store = Rag2DriftGenerationStore(
      databasePath: path,
      projectId: _projectId,
    );
    await store.apply(
      declarationIdentity: _identity,
      snapshot: snapshots.baseline,
    );
    store.close();

    final mutated = sqlite3.open(path);
    mutated.execute(
      "UPDATE rag2_store_meta SET value = '2' WHERE key = 'schema_version'",
    );
    mutated.dispose();

    final rejected = Rag2DriftGenerationStore(
      databasePath: path,
      projectId: _projectId,
    );
    addTearDown(rejected.close);
    await expectLater(
      rejected.read(_identity),
      throwsA(
        isA<Rag2PersistenceException>().having(
          (error) => error.reason,
          'reason',
          'unsupported_schema',
        ),
      ),
    );
    final host = AppDatabase(NativeDatabase(File(path)));
    addTearDown(host.close);
    expect(
      (await host.select(host.embeddings).get()).single.sourceId,
      'll5-sentinel',
    );
    final check = sqlite3.open(path);
    addTearDown(check.dispose);
    expect(
      check
          .select(
            "SELECT value FROM rag2_store_meta WHERE key = 'schema_version'",
          )
          .first['value'],
      '2',
    );
    expect(
      check
          .select('SELECT generation FROM rag2_generations')
          .first['generation'],
      1,
    );
  });

  test('rejects a schema mutation on an already-open store', () async {
    final output = Directory.systemTemp.createTempSync(
      'rag2-drift-open-schema-',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final path = '${output.path}/caverno.sqlite';
    await prepareRag2DriftHost(databasePath: path);
    final store = Rag2DriftGenerationStore(
      databasePath: path,
      projectId: _projectId,
    );
    addTearDown(store.close);
    await store.apply(
      declarationIdentity: _identity,
      snapshot: snapshots.baseline,
    );

    final mutated = sqlite3.open(path);
    mutated.execute(
      "UPDATE rag2_store_meta SET value = '2' WHERE key = 'schema_version'",
    );
    mutated.dispose();

    await expectLater(
      store.read(_identity),
      throwsA(
        isA<Rag2PersistenceException>().having(
          (error) => error.reason,
          'reason',
          'unsupported_schema',
        ),
      ),
    );
    await expectLater(
      store.apply(declarationIdentity: _identity, snapshot: snapshots.updated),
      throwsA(
        isA<Rag2PersistenceException>().having(
          (error) => error.reason,
          'reason',
          'unsupported_schema',
        ),
      ),
    );
    final check = sqlite3.open(path);
    addTearDown(check.dispose);
    expect(
      check
          .select(
            "SELECT value FROM rag2_store_meta WHERE key = 'schema_version'",
          )
          .first['value'],
      '2',
    );
    expect(
      check
          .select('SELECT generation FROM rag2_generations')
          .first['generation'],
      1,
    );
  });

  test('isolates two projects in one AppDatabase file', () async {
    final output = Directory.systemTemp.createTempSync('rag2-drift-isolate-');
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
    final first = Rag2DriftGenerationStore(
      databasePath: path,
      projectId: 'persistence-project-a',
    );
    await first.apply(declarationIdentity: _identity, snapshot: firstSnapshot);
    first.close();
    final second = Rag2DriftGenerationStore(
      databasePath: path,
      projectId: 'persistence-project-b',
    );
    await second.apply(
      declarationIdentity: _identity,
      snapshot: secondSnapshot,
    );
    second.close();

    final firstRead = Rag2DriftGenerationStore(
      databasePath: path,
      projectId: 'persistence-project-a',
    );
    final secondRead = Rag2DriftGenerationStore(
      databasePath: path,
      projectId: 'persistence-project-b',
    );
    addTearDown(firstRead.close);
    addTearDown(secondRead.close);

    expect(
      (await firstRead.read(_identity))?.snapshot.snapshotHash,
      firstSnapshot.snapshotHash,
    );
    expect(
      (await secondRead.read(_identity))?.snapshot.snapshotHash,
      secondSnapshot.snapshotHash,
    );
    expect(firstSnapshot.snapshotHash, isNot(secondSnapshot.snapshotHash));
  });

  test('rejects a snapshot that belongs to another project', () async {
    final output = Directory.systemTemp.createTempSync('rag2-drift-foreign-');
    addTearDown(() => output.deleteSync(recursive: true));
    final snapshots = await _snapshots();
    final path = '${output.path}/caverno.sqlite';
    await prepareRag2DriftHost(databasePath: path);
    final store = Rag2DriftGenerationStore(
      databasePath: path,
      projectId: 'persistence-project-a',
    );
    addTearDown(store.close);

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
  });

  test(
    'replays twice against the same output directory',
    () async {
      final output = Directory.systemTemp.createTempSync('rag2-drift-rerun-');
      addTearDown(() => output.deleteSync(recursive: true));
      final options = Rag2DriftAdditiveSchemaOptions(
        fixturePath: _fixturePath,
        outDir: output.path,
        storeRoot: '${output.path}/store',
      );
      final first = await runRag2DriftAdditiveSchemaReplay(options);
      final second = await runRag2DriftAdditiveSchemaReplay(options);
      expect(first.contractPassed, isTrue);
      expect(second.contractPassed, isTrue);
      expect(second.toJson(), first.toJson());
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('writes aggregate-only reports', () async {
    final output = Directory.systemTemp.createTempSync('rag2-drift-report-');
    addTearDown(() => output.deleteSync(recursive: true));
    final report = await runRag2DriftAdditiveSchemaReplay(
      Rag2DriftAdditiveSchemaOptions(
        fixturePath: _fixturePath,
        outDir: output.path,
        storeRoot: '${output.path}/store',
      ),
    );
    final jsonReport = File(
      '${output.path}/rag2_drift_additive_schema.json',
    ).readAsStringSync();
    final markdownReport = File(
      '${output.path}/rag2_drift_additive_schema.md',
    ).readAsStringSync();

    expect(report.contractPassed, isTrue);
    expect(report.toJson()['driftAdditiveDecision'], 'go');
    expect(report.toJson()['fts5Decision'], 'not_selected');
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(report.toJson()['appDatabaseSchemaVersion'], 5);
    expect(jsonDecode(jsonReport), report.toJson());
    expect(markdownReport, report.toMarkdown());
    for (final forbidden in [
      Directory.current.path,
      '/Users/',
      'docs/guide.md',
      'fixture-secret-alpha',
      'sourceRoots',
      'll5-sentinel',
    ]) {
      expect(jsonReport, isNot(contains(forbidden)));
      expect(markdownReport, isNot(contains(forbidden)));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
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
