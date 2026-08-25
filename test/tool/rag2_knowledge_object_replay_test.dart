import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_knowledge_object_replay.dart';

void main() {
  const fixturePath = 'tool/fixtures/rag2_knowledge_object_replay/fixture.json';

  test('pins deterministic Knowledge Object and Chunk identities', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-ko-');
    addTearDown(() => directory.deleteSync(recursive: true));

    final report = await runRag2KnowledgeObjectReplay(
      Rag2KnowledgeReplayOptions(
        fixturePath: fixturePath,
        outDir: directory.path,
      ),
    );

    expect(report.contractPassed, isTrue);
    expect(report.toJson()['schemaVersion'], 2);
    expect(report.toJson()['contract'], 'rag2-knowledge-object-contract-v2');
    expect(report.toJson()['contractDecision'], 'go');
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(report.toJson()['storageDecision'], 'not_evaluated');
    expect(report.toJson()['runtimePassageRole'], 'unknown');
    expect(
      report.baseline.snapshotHash,
      'd2805345bf2b59571a814cd2064731cf762147311d6eda888af87dd134215236',
    );
    expect(
      report.updated.snapshotHash,
      'fec1d48d6294268da79aac72c397217170183496f0fb8f9e1ff26ff037a8c9a0',
    );
    expect(
      report.baseline.chunks.every((chunk) => chunk.passageRole == 'unknown'),
      isTrue,
    );
    expect(
      report.baseline.chunks.every(
        (chunk) =>
            chunk.provenance.lineStart >= 1 &&
            chunk.provenance.lineEnd >= chunk.provenance.lineStart &&
            chunk.provenance.sourceTrust == 'workspace_tracked',
      ),
      isTrue,
    );
    expect(report.baseline.objects, hasLength(3));
    expect(report.updated.objects, hasLength(3));
    expect(report.baseline.chunks, hasLength(6));
    expect(report.updated.chunks, hasLength(7));
    expect(
      report.baseline.chunks.every((chunk) => chunk.locator.isNotEmpty),
      isTrue,
    );
    expect(
      jsonEncode(report.toJson()),
      isNot(contains(Directory.current.path)),
    );
  });

  test('accounts for chunk metadata and object lifecycle changes', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-ko-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2KnowledgeObjectReplay(
      Rag2KnowledgeReplayOptions(
        fixturePath: fixturePath,
        outDir: directory.path,
      ),
    );

    expect(report.delta.retainedChunkIds, hasLength(4));
    expect(report.delta.unchangedChunkIds, hasLength(2));
    expect(report.delta.metadataUpdatedChunkIds, hasLength(2));
    expect(report.delta.removedChunkIds, hasLength(2));
    expect(report.delta.addedChunkIds, hasLength(3));
    expect(report.delta.changedObjectIds, hasLength(1));
    expect(report.delta.unchangedObjectIds, hasLength(1));
    expect(report.delta.removedObjectIds, hasLength(1));
    expect(report.delta.addedObjectIds, hasLength(1));
    expect(report.delta.movedRetainedChunkIds, [
      'kc_5ceaabc6e46e6281fcdabf22977566155b6cbe9e14833086a8a8ec85d90d365f',
    ]);
    final movedId = report.delta.movedRetainedChunkIds.single;
    final before = report.baseline.chunks.singleWhere(
      (chunk) => chunk.chunkId == movedId,
    );
    final after = report.updated.chunks.singleWhere(
      (chunk) => chunk.chunkId == movedId,
    );
    expect((before.provenance.lineStart, before.provenance.lineEnd), (6, 7));
    expect((after.provenance.lineStart, after.provenance.lineEnd), (8, 9));
  });

  test('writes deterministic JSON and Markdown reports', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-ko-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2KnowledgeObjectReplay(
      Rag2KnowledgeReplayOptions(
        fixturePath: fixturePath,
        outDir: directory.path,
      ),
    );

    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_knowledge_object_replay.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File(
        '${directory.path}/rag2_knowledge_object_replay.md',
      ).readAsStringSync(),
      report.toMarkdown(),
    );
    final jsonReport = File(
      '${directory.path}/rag2_knowledge_object_replay.json',
    ).readAsStringSync();
    final markdownReport = File(
      '${directory.path}/rag2_knowledge_object_replay.md',
    ).readAsStringSync();
    for (final sensitiveText in [
      '/Users/example/private.txt',
      'fixture-secret',
    ]) {
      expect(jsonReport, isNot(contains(sensitiveText)));
      expect(markdownReport, isNot(contains(sensitiveText)));
    }
    expect(
      report.baseline.chunks.any(
        (chunk) => chunk.content.contains('fixture-secret'),
      ),
      isTrue,
    );
  });

  test('keeps a surviving identical block ID after sibling removal', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-ko-identical-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final baselineSource = File('${directory.path}/baseline/docs/repeated.md');
    final updatedSource = File('${directory.path}/updated/docs/repeated.md');
    baselineSource.createSync(recursive: true);
    updatedSource.createSync(recursive: true);
    baselineSource.writeAsStringSync(
      '# First\n\nSame body.\n\n# Second\n\nSame body.\n',
    );
    updatedSource.writeAsStringSync('# Second\n\nSame body.\n');
    final loadedFixture = await Rag2KnowledgeReplayFixture.load(
      File(fixturePath),
    );
    const baselineSpec = Rag2KnowledgeSnapshotSpec(
      id: 'baseline-identical',
      root: 'baseline',
      sources: [
        Rag2KnowledgeSourceSpec(
          path: 'docs/repeated.md',
          revision: 'repeated-r1',
          sourceKind: 'markdown',
          sourceTrust: 'workspace_tracked',
        ),
      ],
    );
    const updatedSpec = Rag2KnowledgeSnapshotSpec(
      id: 'updated-identical',
      root: 'updated',
      sources: [
        Rag2KnowledgeSourceSpec(
          path: 'docs/repeated.md',
          revision: 'repeated-r2',
          sourceKind: 'markdown',
          sourceTrust: 'workspace_tracked',
        ),
      ],
    );
    final fixture = Rag2KnowledgeReplayFixture(
      fixtureId: 'identical-blocks',
      projectId: 'identical-project',
      snapshots: const [baselineSpec, updatedSpec],
      expected: loadedFixture.expected,
    );
    final fixtureFile = File('${directory.path}/fixture.json');
    final baseline = await buildRag2KnowledgeSnapshot(
      fixture: fixture,
      fixtureFile: fixtureFile,
      spec: baselineSpec,
    );
    final updated = await buildRag2KnowledgeSnapshot(
      fixture: fixture,
      fixtureFile: fixtureFile,
      spec: updatedSpec,
    );
    final identicalBaselineChunks = baseline.chunks
        .where((chunk) => chunk.content == 'Same body.')
        .toList();
    final survivorBefore = identicalBaselineChunks.singleWhere(
      (chunk) => chunk.locator == 'markdown:second:body',
    );
    final survivorAfter = updated.chunks.singleWhere(
      (chunk) => chunk.locator == 'markdown:second:body',
    );

    expect(identicalBaselineChunks, hasLength(2));
    expect(
      identicalBaselineChunks.map((chunk) => chunk.chunkId).toSet(),
      hasLength(2),
    );
    expect(survivorAfter.chunkId, survivorBefore.chunkId);
  });

  test('fails closed when a source has ambiguous semantic locators', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-ko-ambiguous-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final source = File('${directory.path}/baseline/docs/duplicate.md');
    source.createSync(recursive: true);
    source.writeAsStringSync(
      '# Repeated\nFirst block.\n\n# Repeated\nSecond block.\n',
    );
    final loadedFixture = await Rag2KnowledgeReplayFixture.load(
      File(fixturePath),
    );
    final snapshot = Rag2KnowledgeSnapshotSpec(
      id: 'ambiguous',
      root: 'baseline',
      sources: const [
        Rag2KnowledgeSourceSpec(
          path: 'docs/duplicate.md',
          revision: 'duplicate-r1',
          sourceKind: 'markdown',
          sourceTrust: 'workspace_tracked',
        ),
      ],
    );
    final fixture = Rag2KnowledgeReplayFixture(
      fixtureId: 'ambiguous-locator',
      projectId: 'ambiguous-project',
      snapshots: [snapshot, snapshot],
      expected: loadedFixture.expected,
    );

    await expectLater(
      buildRag2KnowledgeSnapshot(
        fixture: fixture,
        fixtureFile: File('${directory.path}/fixture.json'),
        spec: snapshot,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Knowledge chunk locator is ambiguous'),
        ),
      ),
    );
  });

  test('fails closed for repository path escape attempts', () {
    for (final path in ['/tmp/file.md', '../file.md', 'docs/../file.md']) {
      expect(
        () => validateRag2RepoRelativePath(path),
        throwsA(isA<FormatException>()),
      );
    }
    expect(() => validateRag2RepoRelativePath('docs/file.md'), returnsNormally);
  });

  test('pinned identity mismatch cannot pass by counts alone', () async {
    final fixtureJson =
        (jsonDecode(File(fixturePath).readAsStringSync()) as Map)
            .cast<String, Object?>();
    final expectedJson = (fixtureJson['expected'] as Map)
        .cast<String, Object?>();
    final expected = Rag2KnowledgeReplayExpected.fromJson(expectedJson);
    final directory = Directory.systemTemp.createTempSync('rag2-ko-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2KnowledgeObjectReplay(
      Rag2KnowledgeReplayOptions(
        fixturePath: fixturePath,
        outDir: directory.path,
      ),
    );
    final tampered = Map<String, Object?>.from(expectedJson);
    tampered['retainedChunkIds'] = [
      'kc_wrong',
      ...expected.retainedChunkIds.skip(1),
    ];

    expect(
      Rag2KnowledgeReplayExpected.fromJson(tampered).matches(
        baseline: report.baseline,
        updated: report.updated,
        delta: report.delta,
      ),
      isFalse,
    );
  });
}
