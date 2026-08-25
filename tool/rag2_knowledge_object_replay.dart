import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const rag2KnowledgeObjectContract = 'rag2-knowledge-object-contract-v2';
const rag2KnowledgeObjectReplaySchema =
    'caverno_rag2_knowledge_object_replay_report';
const rag2KnowledgeObjectReplaySchemaVersion = 2;
const rag2KnowledgeObjectReplayFixtureSchema =
    'caverno_rag2_knowledge_object_replay_fixture';

Future<void> main(List<String> args) async {
  final options = Rag2KnowledgeReplayOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_knowledge_object_replay.dart '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2KnowledgeObjectReplay(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 Knowledge Object replay failed: $error');
    exitCode = 65;
  }
}

Future<Rag2KnowledgeReplayReport> runRag2KnowledgeObjectReplay(
  Rag2KnowledgeReplayOptions options,
) async {
  final fixtureFile = File(options.fixturePath);
  final fixture = await Rag2KnowledgeReplayFixture.load(fixtureFile);
  final baseline = await buildRag2KnowledgeSnapshot(
    fixture: fixture,
    fixtureFile: fixtureFile,
    spec: fixture.baseline,
  );
  final repeatedBaseline = await buildRag2KnowledgeSnapshot(
    fixture: fixture,
    fixtureFile: fixtureFile,
    spec: fixture.baseline,
  );
  final updated = await buildRag2KnowledgeSnapshot(
    fixture: fixture,
    fixtureFile: fixtureFile,
    spec: fixture.updated,
  );
  final delta = Rag2KnowledgeReplayDelta.compare(baseline, updated);
  final deterministicReplay =
      jsonEncode(baseline.toJson()) == jsonEncode(repeatedBaseline.toJson());
  final expectedPassed = fixture.expected.matches(
    baseline: baseline,
    updated: updated,
    delta: delta,
  );
  final report = Rag2KnowledgeReplayReport(
    fixtureId: fixture.fixtureId,
    deterministicReplay: deterministicReplay,
    expectedPassed: expectedPassed,
    baseline: baseline,
    updated: updated,
    delta: delta,
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_knowledge_object_replay.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_knowledge_object_replay.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<Rag2KnowledgeSnapshot> buildRag2KnowledgeSnapshot({
  required Rag2KnowledgeReplayFixture fixture,
  required File fixtureFile,
  required Rag2KnowledgeSnapshotSpec spec,
}) async {
  validateRag2RepoRelativePath(spec.root);
  final objects = <Rag2KnowledgeObject>[];
  for (final source in spec.sources) {
    validateRag2RepoRelativePath(source.path);
    final file = File('${fixtureFile.parent.path}/${spec.root}/${source.path}');
    final normalizedText = _normalizeText(await file.readAsString());
    final contentHash = _sha256(normalizedText);
    final objectId = _stableId('ko', [fixture.projectId, source.path]);
    final chunks = _chunkSource(
      objectId: objectId,
      projectId: fixture.projectId,
      source: source,
      objectContentHash: contentHash,
      normalizedText: normalizedText,
    );
    objects.add(
      Rag2KnowledgeObject(
        objectId: objectId,
        projectId: fixture.projectId,
        repoRelativePath: source.path,
        sourceKind: source.sourceKind,
        sourceTrust: source.sourceTrust,
        revision: source.revision,
        contentHash: contentHash,
        chunkIds: [for (final chunk in chunks) chunk.chunkId],
        chunks: chunks,
      ),
    );
  }
  objects.sort(
    (left, right) => left.repoRelativePath.compareTo(right.repoRelativePath),
  );
  final snapshotHash = _sha256(
    jsonEncode([for (final object in objects) object.toJson()]),
  );
  return Rag2KnowledgeSnapshot(
    snapshotId: spec.id,
    snapshotHash: snapshotHash,
    objects: objects,
  );
}

List<Rag2KnowledgeChunk> _chunkSource({
  required String objectId,
  required String projectId,
  required Rag2KnowledgeSourceSpec source,
  required String objectContentHash,
  required String normalizedText,
}) {
  final lines = normalizedText.split('\n');
  final blocks = <({int start, int end, String content})>[];
  var index = 0;
  while (index < lines.length) {
    while (index < lines.length && lines[index].trim().isEmpty) {
      index++;
    }
    if (index >= lines.length) break;
    final start = index;
    while (index < lines.length && lines[index].trim().isNotEmpty) {
      index++;
    }
    final end = index - 1;
    blocks.add((
      start: start + 1,
      end: end + 1,
      content: lines.sublist(start, index).join('\n'),
    ));
  }
  final chunks = <Rag2KnowledgeChunk>[];
  final locators = <String>{};
  final markdownHeadings = <String>[];
  for (final block in blocks) {
    final locator = source.sourceKind == 'markdown'
        ? _markdownLocator(block.content, markdownHeadings)
        : _dartLocator(block.content);
    if (!locators.add(locator)) {
      throw StateError(
        'Knowledge chunk locator is ambiguous in ${source.path}: $locator',
      );
    }
    final chunkContentHash = _sha256(block.content);
    chunks.add(
      Rag2KnowledgeChunk(
        chunkId: rag2KnowledgeChunkId(
          objectId: objectId,
          locator: locator,
          contentHash: chunkContentHash,
        ),
        objectId: objectId,
        locator: locator,
        contentHash: chunkContentHash,
        content: block.content,
        passageRole: 'unknown',
        provenance: Rag2KnowledgeProvenance(
          projectId: projectId,
          repoRelativePath: source.path,
          revision: source.revision,
          objectContentHash: objectContentHash,
          lineStart: block.start,
          lineEnd: block.end,
          sourceTrust: source.sourceTrust,
        ),
      ),
    );
  }
  return chunks;
}

String _markdownLocator(String content, List<String> headings) {
  final firstLine = content.split('\n').first;
  final match = RegExp(r'^(#{1,6})\s+(.+?)\s*$').firstMatch(firstLine);
  if (match != null) {
    final level = match.group(1)!.length;
    while (headings.length >= level) {
      headings.removeLast();
    }
    while (headings.length < level - 1) {
      headings.add('_');
    }
    headings.add(_normalizeLocatorPart(match.group(2)!));
    return 'markdown:${headings.join('/')}';
  }
  final scope = headings.isEmpty ? 'root' : headings.join('/');
  return 'markdown:$scope:body';
}

String _dartLocator(String content) {
  final firstLine = content.split('\n').first.trim();
  for (final pattern in [
    RegExp(
      r'^(?:const|final|var)\s+(?:[A-Za-z_]\w*(?:<[^>]+>)?[?]?\s+)?([A-Za-z_]\w*)\s*=',
    ),
    RegExp(r'^(?:class|enum|mixin|extension|typedef)\s+([A-Za-z_]\w*)'),
    RegExp(r'^(?:[A-Za-z_]\w*(?:<[^>]+>)?[?]?\s+)+([A-Za-z_]\w*)\s*\('),
  ]) {
    final match = pattern.firstMatch(firstLine);
    if (match != null) return 'dart:${match.group(1)}';
  }
  throw FormatException('Dart block has no stable symbol locator: $firstLine');
}

String _normalizeLocatorPart(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

String rag2KnowledgeChunkId({
  required String objectId,
  required String locator,
  required String contentHash,
}) => _stableId('kc', [objectId, locator, contentHash]);

void validateRag2RepoRelativePath(String value) {
  final segments = value.split('/');
  if (value.isEmpty ||
      value.startsWith('/') ||
      value.contains('\\') ||
      segments.any(
        (segment) => segment.isEmpty || segment == '.' || segment == '..',
      )) {
    throw FormatException(
      'Knowledge source path must be repository-relative: $value',
    );
  }
}

String _normalizeText(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

String _stableId(String prefix, List<String> parts) =>
    '${prefix}_${_sha256([rag2KnowledgeObjectContract, ...parts].join('\u0000'))}';

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();

final class Rag2KnowledgeObject {
  const Rag2KnowledgeObject({
    required this.objectId,
    required this.projectId,
    required this.repoRelativePath,
    required this.sourceKind,
    required this.sourceTrust,
    required this.revision,
    required this.contentHash,
    required this.chunkIds,
    required this.chunks,
  });
  final String objectId;
  final String projectId;
  final String repoRelativePath;
  final String sourceKind;
  final String sourceTrust;
  final String revision;
  final String contentHash;
  final List<String> chunkIds;
  final List<Rag2KnowledgeChunk> chunks;

  Map<String, Object?> toJson() => {
    'objectId': objectId,
    'projectId': projectId,
    'repoRelativePath': repoRelativePath,
    'sourceKind': sourceKind,
    'sourceTrust': sourceTrust,
    'revision': revision,
    'contentHash': contentHash,
    'chunkIds': chunkIds,
    'chunks': [for (final chunk in chunks) chunk.toJson()],
  };
}

final class Rag2KnowledgeChunk {
  const Rag2KnowledgeChunk({
    required this.chunkId,
    required this.objectId,
    required this.locator,
    required this.contentHash,
    required this.content,
    required this.passageRole,
    required this.provenance,
  });
  final String chunkId;
  final String objectId;
  final String locator;
  final String contentHash;
  final String content;
  final String passageRole;
  final Rag2KnowledgeProvenance provenance;

  Map<String, Object?> toJson() => {
    'chunkId': chunkId,
    'objectId': objectId,
    'locator': locator,
    'contentHash': contentHash,
    'passageRole': passageRole,
    'provenance': provenance.toJson(),
  };
}

final class Rag2KnowledgeProvenance {
  const Rag2KnowledgeProvenance({
    required this.projectId,
    required this.repoRelativePath,
    required this.revision,
    required this.objectContentHash,
    required this.lineStart,
    required this.lineEnd,
    required this.sourceTrust,
  });
  final String projectId;
  final String repoRelativePath;
  final String revision;
  final String objectContentHash;
  final int lineStart;
  final int lineEnd;
  final String sourceTrust;

  Map<String, Object?> toJson() => {
    'projectId': projectId,
    'repoRelativePath': repoRelativePath,
    'revision': revision,
    'objectContentHash': objectContentHash,
    'lineStart': lineStart,
    'lineEnd': lineEnd,
    'sourceTrust': sourceTrust,
  };
}

final class Rag2KnowledgeSnapshot {
  const Rag2KnowledgeSnapshot({
    required this.snapshotId,
    required this.snapshotHash,
    required this.objects,
  });
  final String snapshotId;
  final String snapshotHash;
  final List<Rag2KnowledgeObject> objects;
  List<Rag2KnowledgeChunk> get chunks =>
      objects.expand((object) => object.chunks).toList();

  Map<String, Object?> toJson() => {
    'snapshotId': snapshotId,
    'snapshotHash': snapshotHash,
    'objectCount': objects.length,
    'chunkCount': chunks.length,
    'objects': [for (final object in objects) object.toJson()],
  };
}

final class Rag2KnowledgeReplayDelta {
  const Rag2KnowledgeReplayDelta({
    required this.retainedChunkIds,
    required this.unchangedChunkIds,
    required this.metadataUpdatedChunkIds,
    required this.removedChunkIds,
    required this.addedChunkIds,
    required this.movedRetainedChunkIds,
    required this.changedObjectIds,
    required this.unchangedObjectIds,
    required this.removedObjectIds,
    required this.addedObjectIds,
  });
  final List<String> retainedChunkIds;
  final List<String> unchangedChunkIds;
  final List<String> metadataUpdatedChunkIds;
  final List<String> removedChunkIds;
  final List<String> addedChunkIds;
  final List<String> movedRetainedChunkIds;
  final List<String> changedObjectIds;
  final List<String> unchangedObjectIds;
  final List<String> removedObjectIds;
  final List<String> addedObjectIds;

  factory Rag2KnowledgeReplayDelta.compare(
    Rag2KnowledgeSnapshot baseline,
    Rag2KnowledgeSnapshot updated,
  ) {
    final beforeChunks = {
      for (final item in baseline.chunks) item.chunkId: item,
    };
    final afterChunks = {for (final item in updated.chunks) item.chunkId: item};
    final retained = beforeChunks.keys.toSet().intersection(
      afterChunks.keys.toSet(),
    );
    final beforeObjects = {
      for (final item in baseline.objects) item.objectId: item,
    };
    final afterObjects = {
      for (final item in updated.objects) item.objectId: item,
    };
    final commonObjects = beforeObjects.keys.toSet().intersection(
      afterObjects.keys.toSet(),
    );
    final unchangedChunks = retained
        .where(
          (id) =>
              jsonEncode(beforeChunks[id]!.toJson()) ==
              jsonEncode(afterChunks[id]!.toJson()),
        )
        .toSet();
    return Rag2KnowledgeReplayDelta(
      retainedChunkIds: retained.toList()..sort(),
      unchangedChunkIds: unchangedChunks.toList()..sort(),
      metadataUpdatedChunkIds: retained.difference(unchangedChunks).toList()
        ..sort(),
      removedChunkIds:
          beforeChunks.keys
              .toSet()
              .difference(afterChunks.keys.toSet())
              .toList()
            ..sort(),
      addedChunkIds:
          afterChunks.keys
              .toSet()
              .difference(beforeChunks.keys.toSet())
              .toList()
            ..sort(),
      movedRetainedChunkIds:
          retained
              .where(
                (id) =>
                    beforeChunks[id]!.provenance.lineStart !=
                        afterChunks[id]!.provenance.lineStart ||
                    beforeChunks[id]!.provenance.lineEnd !=
                        afterChunks[id]!.provenance.lineEnd,
              )
              .toList()
            ..sort(),
      changedObjectIds:
          commonObjects
              .where(
                (id) =>
                    beforeObjects[id]!.contentHash !=
                    afterObjects[id]!.contentHash,
              )
              .toList()
            ..sort(),
      unchangedObjectIds:
          commonObjects
              .where(
                (id) =>
                    beforeObjects[id]!.contentHash ==
                    afterObjects[id]!.contentHash,
              )
              .toList()
            ..sort(),
      removedObjectIds:
          beforeObjects.keys
              .toSet()
              .difference(afterObjects.keys.toSet())
              .toList()
            ..sort(),
      addedObjectIds:
          afterObjects.keys
              .toSet()
              .difference(beforeObjects.keys.toSet())
              .toList()
            ..sort(),
    );
  }

  Map<String, Object?> toJson() => {
    'retainedChunkIds': retainedChunkIds,
    'unchangedChunkIds': unchangedChunkIds,
    'metadataUpdatedChunkIds': metadataUpdatedChunkIds,
    'removedChunkIds': removedChunkIds,
    'addedChunkIds': addedChunkIds,
    'movedRetainedChunkIds': movedRetainedChunkIds,
    'changedObjectIds': changedObjectIds,
    'unchangedObjectIds': unchangedObjectIds,
    'removedObjectIds': removedObjectIds,
    'addedObjectIds': addedObjectIds,
  };
}

final class Rag2KnowledgeReplayReport {
  const Rag2KnowledgeReplayReport({
    required this.fixtureId,
    required this.deterministicReplay,
    required this.expectedPassed,
    required this.baseline,
    required this.updated,
    required this.delta,
  });
  final String fixtureId;
  final bool deterministicReplay;
  final bool expectedPassed;
  final Rag2KnowledgeSnapshot baseline;
  final Rag2KnowledgeSnapshot updated;
  final Rag2KnowledgeReplayDelta delta;
  bool get contractPassed => deterministicReplay && expectedPassed;

  Map<String, Object?> toJson() => {
    'schemaName': rag2KnowledgeObjectReplaySchema,
    'schemaVersion': rag2KnowledgeObjectReplaySchemaVersion,
    'contract': rag2KnowledgeObjectContract,
    'fixtureId': fixtureId,
    'contractDecision': contractPassed ? 'go' : 'no_go',
    'productionDecision': 'no_go',
    'storageDecision': 'not_evaluated',
    'runtimePassageRole': 'unknown',
    'deterministicReplay': deterministicReplay,
    'expectedInvalidation': expectedPassed,
    'baseline': baseline.toJson(),
    'updated': updated.toJson(),
    'delta': delta.toJson(),
  };

  String toMarkdown() =>
      '# RAG2 Knowledge Object Replay\n\n'
      '- Contract: `$rag2KnowledgeObjectContract`\n'
      '- Contract decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Production decision: `no_go`\n'
      '- Storage decision: `not_evaluated`\n'
      '- Runtime passage role: `unknown`\n'
      '- Deterministic replay: `$deterministicReplay`\n'
      '- Baseline: `${baseline.objects.length}` objects / `${baseline.chunks.length}` chunks\n'
      '- Updated: `${updated.objects.length}` objects / `${updated.chunks.length}` chunks\n'
      '- Retained / removed / added chunks: `${delta.retainedChunkIds.length}` / `${delta.removedChunkIds.length}` / `${delta.addedChunkIds.length}`\n'
      '- Retained unchanged / metadata-updated chunks: `${delta.unchangedChunkIds.length}` / `${delta.metadataUpdatedChunkIds.length}`\n'
      '- Retained chunks with moved line spans: `${delta.movedRetainedChunkIds.length}`\n'
      '- Common objects with changed / unchanged content: `${delta.changedObjectIds.length}` / `${delta.unchangedObjectIds.length}`\n'
      '- Removed / added objects: `${delta.removedObjectIds.length}` / `${delta.addedObjectIds.length}`\n';
}

final class Rag2KnowledgeReplayFixture {
  const Rag2KnowledgeReplayFixture({
    required this.fixtureId,
    required this.projectId,
    required this.snapshots,
    required this.expected,
  });
  final String fixtureId;
  final String projectId;
  final List<Rag2KnowledgeSnapshotSpec> snapshots;
  final Rag2KnowledgeReplayExpected expected;
  Rag2KnowledgeSnapshotSpec get baseline => snapshots[0];
  Rag2KnowledgeSnapshotSpec get updated => snapshots[1];

  static Future<Rag2KnowledgeReplayFixture> load(File file) async {
    final json = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    if (json['schemaName'] != rag2KnowledgeObjectReplayFixtureSchema ||
        json['schemaVersion'] != 2) {
      throw const FormatException(
        'Unsupported Knowledge Object replay fixture.',
      );
    }
    final snapshots = (json['snapshots'] as List)
        .map(
          (item) => Rag2KnowledgeSnapshotSpec.fromJson(
            (item as Map).cast<String, Object?>(),
          ),
        )
        .toList();
    if (snapshots.length != 2 ||
        snapshots.map((item) => item.id).toSet().length != 2) {
      throw const FormatException(
        'Replay fixture requires two unique snapshots.',
      );
    }
    if ((json['projectId'] as String).isEmpty ||
        snapshots.any(
          (snapshot) =>
              snapshot.sources.isEmpty ||
              snapshot.sources.map((source) => source.path).toSet().length !=
                  snapshot.sources.length,
        )) {
      throw const FormatException(
        'Project ID and unique snapshot source paths are required.',
      );
    }
    return Rag2KnowledgeReplayFixture(
      fixtureId: json['fixtureId'] as String,
      projectId: json['projectId'] as String,
      snapshots: snapshots,
      expected: Rag2KnowledgeReplayExpected.fromJson(
        (json['expected'] as Map).cast<String, Object?>(),
      ),
    );
  }
}

final class Rag2KnowledgeSnapshotSpec {
  const Rag2KnowledgeSnapshotSpec({
    required this.id,
    required this.root,
    required this.sources,
  });
  final String id;
  final String root;
  final List<Rag2KnowledgeSourceSpec> sources;

  factory Rag2KnowledgeSnapshotSpec.fromJson(Map<String, Object?> json) =>
      Rag2KnowledgeSnapshotSpec(
        id: json['id'] as String,
        root: json['root'] as String,
        sources: (json['sources'] as List)
            .map(
              (item) => Rag2KnowledgeSourceSpec.fromJson(
                (item as Map).cast<String, Object?>(),
              ),
            )
            .toList(),
      );
}

final class Rag2KnowledgeSourceSpec {
  const Rag2KnowledgeSourceSpec({
    required this.path,
    required this.revision,
    required this.sourceKind,
    required this.sourceTrust,
  });
  final String path;
  final String revision;
  final String sourceKind;
  final String sourceTrust;

  factory Rag2KnowledgeSourceSpec.fromJson(Map<String, Object?> json) {
    final sourceKind = json['sourceKind'] as String;
    final sourceTrust = json['sourceTrust'] as String;
    if (!{'code', 'markdown'}.contains(sourceKind) ||
        !{
          'workspace_tracked',
          'workspace_untracked',
          'external_reviewed',
        }.contains(sourceTrust) ||
        (json['revision'] as String).isEmpty) {
      throw const FormatException('Unsupported source kind or trust.');
    }
    return Rag2KnowledgeSourceSpec(
      path: json['path'] as String,
      revision: json['revision'] as String,
      sourceKind: sourceKind,
      sourceTrust: sourceTrust,
    );
  }
}

final class Rag2KnowledgeReplayExpected {
  const Rag2KnowledgeReplayExpected({
    required this.baselineSnapshotHash,
    required this.updatedSnapshotHash,
    required this.baselineObjectCount,
    required this.updatedObjectCount,
    required this.baselineChunkCount,
    required this.updatedChunkCount,
    required this.retainedChunkCount,
    required this.unchangedChunkCount,
    required this.metadataUpdatedChunkCount,
    required this.removedChunkCount,
    required this.addedChunkCount,
    required this.movedRetainedChunkCount,
    required this.changedObjectCount,
    required this.unchangedObjectCount,
    required this.removedObjectCount,
    required this.addedObjectCount,
    required this.retainedChunkIds,
    required this.unchangedChunkIds,
    required this.metadataUpdatedChunkIds,
    required this.removedChunkIds,
    required this.addedChunkIds,
    required this.movedRetainedChunkIds,
    required this.changedObjectIds,
    required this.unchangedObjectIds,
    required this.removedObjectIds,
    required this.addedObjectIds,
  });
  final String baselineSnapshotHash;
  final String updatedSnapshotHash;
  final int baselineObjectCount;
  final int updatedObjectCount;
  final int baselineChunkCount;
  final int updatedChunkCount;
  final int retainedChunkCount;
  final int unchangedChunkCount;
  final int metadataUpdatedChunkCount;
  final int removedChunkCount;
  final int addedChunkCount;
  final int movedRetainedChunkCount;
  final int changedObjectCount;
  final int unchangedObjectCount;
  final int removedObjectCount;
  final int addedObjectCount;
  final List<String> retainedChunkIds;
  final List<String> unchangedChunkIds;
  final List<String> metadataUpdatedChunkIds;
  final List<String> removedChunkIds;
  final List<String> addedChunkIds;
  final List<String> movedRetainedChunkIds;
  final List<String> changedObjectIds;
  final List<String> unchangedObjectIds;
  final List<String> removedObjectIds;
  final List<String> addedObjectIds;

  factory Rag2KnowledgeReplayExpected.fromJson(Map<String, Object?> json) =>
      Rag2KnowledgeReplayExpected(
        baselineSnapshotHash: json['baselineSnapshotHash'] as String,
        updatedSnapshotHash: json['updatedSnapshotHash'] as String,
        baselineObjectCount: json['baselineObjectCount'] as int,
        updatedObjectCount: json['updatedObjectCount'] as int,
        baselineChunkCount: json['baselineChunkCount'] as int,
        updatedChunkCount: json['updatedChunkCount'] as int,
        retainedChunkCount: json['retainedChunkCount'] as int,
        unchangedChunkCount: json['unchangedChunkCount'] as int,
        metadataUpdatedChunkCount: json['metadataUpdatedChunkCount'] as int,
        removedChunkCount: json['removedChunkCount'] as int,
        addedChunkCount: json['addedChunkCount'] as int,
        movedRetainedChunkCount: json['movedRetainedChunkCount'] as int,
        changedObjectCount: json['changedObjectCount'] as int,
        unchangedObjectCount: json['unchangedObjectCount'] as int,
        removedObjectCount: json['removedObjectCount'] as int,
        addedObjectCount: json['addedObjectCount'] as int,
        retainedChunkIds: _stringList(json, 'retainedChunkIds'),
        unchangedChunkIds: _stringList(json, 'unchangedChunkIds'),
        metadataUpdatedChunkIds: _stringList(json, 'metadataUpdatedChunkIds'),
        removedChunkIds: _stringList(json, 'removedChunkIds'),
        addedChunkIds: _stringList(json, 'addedChunkIds'),
        movedRetainedChunkIds: _stringList(json, 'movedRetainedChunkIds'),
        changedObjectIds: _stringList(json, 'changedObjectIds'),
        unchangedObjectIds: _stringList(json, 'unchangedObjectIds'),
        removedObjectIds: _stringList(json, 'removedObjectIds'),
        addedObjectIds: _stringList(json, 'addedObjectIds'),
      );

  bool matches({
    required Rag2KnowledgeSnapshot baseline,
    required Rag2KnowledgeSnapshot updated,
    required Rag2KnowledgeReplayDelta delta,
  }) =>
      baseline.snapshotHash == baselineSnapshotHash &&
      updated.snapshotHash == updatedSnapshotHash &&
      baseline.objects.length == baselineObjectCount &&
      updated.objects.length == updatedObjectCount &&
      baseline.chunks.length == baselineChunkCount &&
      updated.chunks.length == updatedChunkCount &&
      delta.retainedChunkIds.length == retainedChunkCount &&
      delta.unchangedChunkIds.length == unchangedChunkCount &&
      delta.metadataUpdatedChunkIds.length == metadataUpdatedChunkCount &&
      delta.removedChunkIds.length == removedChunkCount &&
      delta.addedChunkIds.length == addedChunkCount &&
      delta.movedRetainedChunkIds.length == movedRetainedChunkCount &&
      delta.changedObjectIds.length == changedObjectCount &&
      delta.unchangedObjectIds.length == unchangedObjectCount &&
      delta.removedObjectIds.length == removedObjectCount &&
      delta.addedObjectIds.length == addedObjectCount &&
      _sameStrings(delta.retainedChunkIds, retainedChunkIds) &&
      _sameStrings(delta.unchangedChunkIds, unchangedChunkIds) &&
      _sameStrings(delta.metadataUpdatedChunkIds, metadataUpdatedChunkIds) &&
      _sameStrings(delta.removedChunkIds, removedChunkIds) &&
      _sameStrings(delta.addedChunkIds, addedChunkIds) &&
      _sameStrings(delta.movedRetainedChunkIds, movedRetainedChunkIds) &&
      _sameStrings(delta.changedObjectIds, changedObjectIds) &&
      _sameStrings(delta.unchangedObjectIds, unchangedObjectIds) &&
      _sameStrings(delta.removedObjectIds, removedObjectIds) &&
      _sameStrings(delta.addedObjectIds, addedObjectIds);
}

List<String> _stringList(Map<String, Object?> json, String key) =>
    (json[key] as List).cast<String>();

bool _sameStrings(List<String> left, List<String> right) =>
    left.length == right.length &&
    left.asMap().entries.every((entry) => entry.value == right[entry.key]);

final class Rag2KnowledgeReplayOptions {
  const Rag2KnowledgeReplayOptions({
    required this.fixturePath,
    required this.outDir,
  });
  final String fixturePath;
  final String outDir;

  static Rag2KnowledgeReplayOptions? parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (index + 1 >= args.length ||
          !{'--fixture', '--out-dir'}.contains(args[index])) {
        return null;
      }
      values[args[index]] = args[index + 1];
    }
    final fixturePath = values['--fixture'];
    final outDir = values['--out-dir'];
    return fixturePath == null || outDir == null
        ? null
        : Rag2KnowledgeReplayOptions(fixturePath: fixturePath, outDir: outDir);
  }
}
