import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_knowledge_object_replay.dart';
import '../../tool/rag2_provenance_attestation_replay.dart';
import '../../tool/rag2_source_discovery_replay.dart';
import '../../tool/rag2_storage_replay.dart';

void main() {
  const fixturePath = 'tool/fixtures/rag2_storage_replay/fixture.json';

  test('replays atomic generations, no-op, and stale replacement', () async {
    final output = Directory.systemTemp.createTempSync('rag2-storage-');
    addTearDown(() => output.deleteSync(recursive: true));

    final report = await runRag2StorageReplay(
      Rag2StorageReplayOptions(fixturePath: fixturePath, outDir: output.path),
    );

    expect(report.contractPassed, isTrue);
    expect(report.toJson()['storageDecision'], 'go');
    expect(report.toJson()['retrievalDecision'], 'not_evaluated');
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(
      report.declarationIdentity,
      'declaration_27ebda6085a09404847c3dc50567c0e11c4df91d77597ac576b4ed74d1de7a6b',
    );
    expect(report.initial.decision, 'applied');
    expect(report.initial.generation, 1);
    expect(
      report.initial.snapshotHash,
      '31d8769e4f33bab976367e724440209bc5d3da2c3772559522f7ea655f48c95b',
    );
    expect(report.identical.decision, 'no_op');
    expect(report.identical.generation, 1);
    expect(report.identical.snapshotHash, report.initial.snapshotHash);
    expect(report.replacement.decision, 'applied');
    expect(report.replacement.generation, 2);
    expect(
      report.replacement.snapshotHash,
      '3d2ef68de7071779c06e45381a761edea6494f4a9207c47463503a759914d610',
    );
    expect(report.replacement.delta.retainedChunkIds, hasLength(4));
    expect(report.replacement.delta.unchangedChunkIds, hasLength(2));
    expect(report.replacement.delta.metadataUpdatedChunkIds, [
      'kc_d561543fa32fe550eb7ebd2c78d21f78e3b63bc56bfcc98dd73115835bffbecc',
      'kc_d7ffcd909fe78aa91ac0867b2bf948b70e09250551f4f13917fadb2f0461f256',
    ]);
    expect(report.replacement.delta.removedChunkIds, [
      'kc_55a9433d487f5e68723f2dbd8234120957226cc586fcbbe43c9169f981814cf1',
    ]);
    expect(report.replacement.delta.addedChunkIds, [
      'kc_9802f439e25180cf490cff40e25b658068cb0e059a9effb41bd681a7670d10ee',
    ]);
    expect(report.replacement.delta.removedObjectIds, [
      'ko_783bdb7341695a15391af2d5652368f7ee3aa8b81901e87b13e05334a0b7393f',
    ]);
    expect(report.replacement.delta.addedObjectIds, [
      'ko_75dfb5d24a8a0dfa20cef0de005e38c5ef90a28ebde8b4f6e7b61bd23ce1afc8',
    ]);
    expect(report.deterministicReplay, isTrue);
  });

  test('excludes every source outside explicit roots', () async {
    final fixtureFile = File(fixturePath);
    final fixture = await Rag2StorageReplayFixture.load(fixtureFile);

    final snapshot = await prepareRag2StorageSnapshot(
      fixtureFile: fixtureFile,
      fixture: fixture,
      spec: fixture.snapshots.first,
    );

    expect(snapshot.objects, hasLength(3));
    expect(snapshot.objects.map((object) => object.repoRelativePath), [
      'docs/guide.md',
      'docs/legacy.md',
      'lib/config.dart',
    ]);
    expect(snapshot.chunks.map((chunk) => chunk.locator), [
      'markdown:storage-guide',
      'markdown:storage-guide/policy',
      'markdown:legacy',
      'dart:storageMode',
      'dart:ReplayPolicy',
    ]);
    expect(
      snapshot.chunks.any(
        (chunk) => chunk.content.contains('outside-root-evidence-marker'),
      ),
      isFalse,
    );
  });

  test(
    'attestation and policy failures preserve the prior generation',
    () async {
      final fixtureFile = File(fixturePath);
      final fixture = await Rag2StorageReplayFixture.load(fixtureFile);
      final baseline = await prepareRag2StorageSnapshot(
        fixtureFile: fixtureFile,
        fixture: fixture,
        spec: fixture.snapshots.first,
      );
      final store = Rag2InMemoryGenerationStore();
      final declaration = rag2StorageDeclarationIdentity(
        projectId: fixture.projectId,
        sourceRoots: fixture.sourceRoots,
      );
      store.apply(declarationIdentity: declaration, snapshot: baseline);

      final incompleteEvidence = Map<String, Rag2GitEvidence>.from(
        fixture.snapshots.last.gitEvidenceByPath,
      )..remove('docs/guide.md');
      await expectLater(
        prepareRag2StorageSnapshot(
          fixtureFile: fixtureFile,
          fixture: fixture,
          spec: fixture.snapshots.last,
          gitEvidenceByPath: incompleteEvidence,
        ),
        throwsA(
          isA<Rag2StoragePreparationException>().having(
            (error) => error.reason,
            'reason',
            'source_attestation_incomplete',
          ),
        ),
      );
      await expectLater(
        prepareRag2StorageSnapshot(
          fixtureFile: fixtureFile,
          fixture: fixture,
          spec: fixture.snapshots.last,
          policy: const Rag2SourceDiscoveryPolicy(
            maxFiles: 1,
            maxFileBytes: 1024,
            maxCorpusBytes: 4096,
          ),
        ),
        throwsA(isA<Rag2StoragePreparationException>()),
      );

      expect(store.read(declaration)?.generation, 1);
      expect(
        store.read(declaration)?.snapshot.snapshotHash,
        baseline.snapshotHash,
      );
    },
  );

  test('injected apply failure rolls back the complete replacement', () async {
    final fixtureFile = File(fixturePath);
    final fixture = await Rag2StorageReplayFixture.load(fixtureFile);
    final baseline = await prepareRag2StorageSnapshot(
      fixtureFile: fixtureFile,
      fixture: fixture,
      spec: fixture.snapshots.first,
    );
    final updated = await prepareRag2StorageSnapshot(
      fixtureFile: fixtureFile,
      fixture: fixture,
      spec: fixture.snapshots.last,
    );
    final store = Rag2InMemoryGenerationStore();
    const declaration = 'test-declaration';
    store.apply(declarationIdentity: declaration, snapshot: baseline);

    final result = store.apply(
      declarationIdentity: declaration,
      snapshot: updated,
      beforeCommit: (_) => throw StateError('stop before commit'),
    );

    expect(result.decision, 'rolled_back');
    expect(store.read(declaration)?.generation, 1);
    expect(
      store.read(declaration)?.snapshot.snapshotHash,
      baseline.snapshotHash,
    );
    expect(store.read(declaration)?.snapshot.objects, same(baseline.objects));

    expect(
      () => store.apply(
        declarationIdentity: declaration,
        snapshot: Rag2KnowledgeSnapshot(
          snapshotId: 'invalid-identical-hash',
          snapshotHash: baseline.snapshotHash,
          objects: const [],
        ),
      ),
      throwsA(
        isA<Rag2StoragePreparationException>().having(
          (error) => error.reason,
          'reason',
          'snapshot_invalid',
        ),
      ),
    );
    expect(store.read(declaration)?.generation, 1);
    expect(
      store.read(declaration)?.snapshot.snapshotHash,
      baseline.snapshotHash,
    );
  });

  test('maps stored chunks from attested text after files change', () async {
    final root = Directory.systemTemp.createTempSync('rag2-storage-bound-');
    addTearDown(() => root.deleteSync(recursive: true));
    File(
      '${root.path}/guide.md',
    ).writeAsStringSync('# Bound Marker\n\nOriginal storage body.\n');
    final result = await discoverRag2Sources(
      project: CodingProject(
        id: 'bound-storage',
        name: 'Bound storage',
        rootPath: root.path,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
      policy: const Rag2SourceDiscoveryPolicy(
        maxFiles: 4,
        maxFileBytes: 4096,
        maxCorpusBytes: 8192,
      ),
      gitEvidenceProvider: (path) async => const Rag2GitEvidence(
        available: true,
        lsFilesExitCode: 0,
        statusPorcelain: '',
        headBlobRevision: '1111111111111111111111111111111111111111',
      ),
    );
    File(
      '${root.path}/guide.md',
    ).writeAsStringSync('# Bound Marker\n\nMutated storage body.\n');

    final object = rag2KnowledgeObjectFromDiscoveredSource(
      projectId: 'bound-storage',
      source: result.candidates.single,
    );
    final storedText = object.chunks.map((chunk) => chunk.content).join('\n');

    expect(result.candidates.single.attestation.hasBoundText, isTrue);
    expect(storedText, contains('Original storage body.'));
    expect(storedText, isNot(contains('Mutated storage body.')));
  });

  test('writes deterministic aggregate-only reports', () async {
    final output = Directory.systemTemp.createTempSync('rag2-storage-privacy-');
    addTearDown(() => output.deleteSync(recursive: true));
    final report = await runRag2StorageReplay(
      Rag2StorageReplayOptions(fixturePath: fixturePath, outDir: output.path),
    );
    final jsonReport = File(
      '${output.path}/rag2_storage_replay.json',
    ).readAsStringSync();
    final markdownReport = File(
      '${output.path}/rag2_storage_replay.md',
    ).readAsStringSync();

    expect(jsonDecode(jsonReport), report.toJson());
    expect(markdownReport, report.toMarkdown());
    for (final forbidden in [
      Directory.current.path,
      '/Users/',
      '"sourceRoots"',
      'docs/guide.md',
      'lib/config.dart',
      '1111111111111111111111111111111111111111',
      'fixture-secret-alpha',
      'stale-marker-legacy',
      'current-marker-replacement',
      'outside-root-evidence-marker',
      'Apply a complete generation atomically.',
    ]) {
      expect(jsonReport, isNot(contains(forbidden)));
      expect(markdownReport, isNot(contains(forbidden)));
    }
  });
}
