import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:crypto/crypto.dart';

import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_knowledge_object_replay.dart';
import 'rag2_provenance_attestation_replay.dart';
import 'rag2_source_discovery_replay.dart';
import 'rag2_source_scope_measurement.dart' show rag2SourceRoleForPath;

const rag2StorageReplayContract = 'rag2-storage-replay-contract-v1';
const rag2StorageReplayFixtureSchema = 'caverno_rag2_storage_replay_fixture';
const rag2StorageReplayReportSchema = 'caverno_rag2_storage_replay_report';

Future<void> main(List<String> args) async {
  final options = Rag2StorageReplayOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_storage_replay.dart '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2StorageReplay(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 storage replay failed: $error');
    exitCode = 65;
  }
}

Future<Rag2StorageReplayReport> runRag2StorageReplay(
  Rag2StorageReplayOptions options,
) async {
  final fixtureFile = File(options.fixturePath);
  final fixture = await Rag2StorageReplayFixture.load(fixtureFile);
  final store = Rag2InMemoryGenerationStore();
  final declarationIdentity = rag2StorageDeclarationIdentity(
    projectId: fixture.projectId,
    sourceRoots: fixture.sourceRoots,
  );
  final baseline = await prepareRag2StorageSnapshot(
    fixtureFile: fixtureFile,
    fixture: fixture,
    spec: fixture.snapshots[0],
  );
  final updated = await prepareRag2StorageSnapshot(
    fixtureFile: fixtureFile,
    fixture: fixture,
    spec: fixture.snapshots[1],
  );

  final initial = store.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  final identical = store.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  final replacement = store.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
  );
  final beforeFailure = store.read(declarationIdentity)!;
  final injectedFailure = store.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
    beforeCommit: (_) => throw StateError('injected_apply_failure'),
  );
  final applyRollbackPreserved =
      store.read(declarationIdentity)!.generation == beforeFailure.generation &&
      store.read(declarationIdentity)!.snapshot.snapshotHash ==
          beforeFailure.snapshot.snapshotHash;

  var preparationRejected = false;
  try {
    final rejectedEvidence = Map<String, Rag2GitEvidence>.from(
      fixture.snapshots[1].gitEvidenceByPath,
    )..remove(fixture.snapshots[1].gitEvidenceByPath.keys.first);
    await prepareRag2StorageSnapshot(
      fixtureFile: fixtureFile,
      fixture: fixture,
      spec: fixture.snapshots[1],
      gitEvidenceByPath: rejectedEvidence,
    );
  } on Rag2StoragePreparationException {
    preparationRejected = true;
  }
  final preparationRollbackPreserved =
      store.read(declarationIdentity)!.generation == beforeFailure.generation &&
      store.read(declarationIdentity)!.snapshot.snapshotHash ==
          beforeFailure.snapshot.snapshotHash;

  final deterministicBaseline = await prepareRag2StorageSnapshot(
    fixtureFile: fixtureFile,
    fixture: fixture,
    spec: fixture.snapshots[0],
  );
  final deterministicUpdated = await prepareRag2StorageSnapshot(
    fixtureFile: fixtureFile,
    fixture: fixture,
    spec: fixture.snapshots[1],
  );
  final deterministicReplay =
      jsonEncode(baseline.toJson()) ==
          jsonEncode(deterministicBaseline.toJson()) &&
      jsonEncode(updated.toJson()) == jsonEncode(deterministicUpdated.toJson());
  final expectedPassed = fixture.expected.matches(
    baseline: baseline,
    updated: updated,
    initial: initial,
    replacement: replacement,
  );
  final report = Rag2StorageReplayReport(
    fixtureId: fixture.fixtureId,
    declarationIdentity: declarationIdentity,
    deterministicReplay: deterministicReplay,
    expectedPassed: expectedPassed,
    initial: initial,
    identical: identical,
    replacement: replacement,
    injectedFailure: injectedFailure,
    applyRollbackPreserved: applyRollbackPreserved,
    preparationRejected: preparationRejected,
    preparationRollbackPreserved: preparationRollbackPreserved,
  );

  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File('${outputDirectory.path}/rag2_storage_replay.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_storage_replay.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<Rag2KnowledgeSnapshot> prepareRag2StorageSnapshot({
  required File fixtureFile,
  required Rag2StorageReplayFixture fixture,
  required Rag2StorageSnapshotSpec spec,
  Map<String, Rag2GitEvidence>? gitEvidenceByPath,
  Rag2SourceDiscoveryPolicy policy = rag2ExplicitSourceRootsPolicy,
}) async {
  final rootPath = '${fixtureFile.parent.path}/${spec.root}';
  final project = CodingProject(
    id: fixture.projectId,
    name: 'RAG2 storage replay fixture',
    rootPath: rootPath,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
  final canonicalRoot = await Directory(rootPath).resolveSymbolicLinks();
  final roots = await validateRag2ExplicitSourceRoots(
    canonicalProjectRoot: canonicalRoot,
    sourceRoots: fixture.sourceRoots,
  );
  if (roots.blocker != null) {
    throw Rag2StoragePreparationException(roots.blocker!);
  }
  final inventory = await inventoryRag2SourceCandidates(
    project: project,
    maxFileBytes: policy.maxFileBytes,
  );
  final selected = inventory.candidates
      .where(
        (candidate) =>
            rag2PathIsWithinExplicitRoots(
              candidate.path,
              roots.normalizedRoots,
            ) &&
            rag2SourceRoleForPath(candidate.path) != 'instruction_bearing',
      )
      .toList();
  final selectedInventory = Rag2SourceCandidateInventory(
    candidates: List.unmodifiable(selected),
    exclusions: const [],
    corpusBytes: selected.fold(0, (sum, candidate) => sum + candidate.bytes),
  );
  final violations = rag2SourceInventoryViolations(
    inventory: selectedInventory,
    policy: policy,
  );
  if (selected.isEmpty || violations.isNotEmpty) {
    throw Rag2StoragePreparationException(
      violations.isEmpty ? 'eligible_sources_unavailable' : violations.first,
    );
  }
  final evidence = gitEvidenceByPath ?? spec.gitEvidenceByPath;
  final discovery = await discoverRag2SourcesFromInventory(
    project: project,
    policy: policy,
    inventory: selectedInventory,
    gitEvidenceProvider: (path) async =>
        evidence[path] ??
        const Rag2GitEvidence(
          available: false,
          lsFilesExitCode: 127,
          statusPorcelain: '',
        ),
  );
  if (discovery.violations.isNotEmpty ||
      discovery.exclusions.isNotEmpty ||
      discovery.candidates.length != selected.length) {
    throw const Rag2StoragePreparationException(
      'source_attestation_incomplete',
    );
  }

  final objects = <Rag2KnowledgeObject>[];
  for (final source in discovery.candidates) {
    objects.add(
      rag2KnowledgeObjectFromDiscoveredSource(
        projectId: fixture.projectId,
        source: source,
      ),
    );
  }
  objects.sort(
    (left, right) => left.repoRelativePath.compareTo(right.repoRelativePath),
  );
  return Rag2KnowledgeSnapshot(
    snapshotId: spec.id,
    snapshotHash: rag2KnowledgeSnapshotHash(objects),
    objects: List.unmodifiable(objects),
  );
}

Rag2KnowledgeObject rag2KnowledgeObjectFromDiscoveredSource({
  required String projectId,
  required Rag2DiscoveredSource source,
}) {
  final attestation = source.attestation;
  if (!attestation.hasBoundText || source.chunks.isEmpty) {
    throw const Rag2StoragePreparationException('attested_text_unavailable');
  }
  final path = attestation.repoRelativePath;
  final objectId = rag2KnowledgeObjectId(
    projectId: projectId,
    repoRelativePath: path,
  );
  final lines = attestation.attestedText!.split('\n');
  final chunks = <Rag2KnowledgeChunk>[
    for (final candidate in source.chunks)
      Rag2KnowledgeChunk(
        chunkId: rag2KnowledgeChunkId(
          objectId: objectId,
          locator: candidate.locator,
          contentHash: candidate.contentHash,
        ),
        objectId: objectId,
        locator: candidate.locator,
        contentHash: candidate.contentHash,
        content: lines
            .sublist(candidate.lineStart - 1, candidate.lineEnd)
            .join('\n'),
        passageRole: 'unknown',
        provenance: Rag2KnowledgeProvenance(
          projectId: projectId,
          repoRelativePath: path,
          revision: attestation.revision!,
          objectContentHash: attestation.contentHash!,
          lineStart: candidate.lineStart,
          lineEnd: candidate.lineEnd,
          sourceTrust: attestation.sourceTrust!,
        ),
      ),
  ];
  return Rag2KnowledgeObject(
    objectId: objectId,
    projectId: projectId,
    repoRelativePath: path,
    sourceKind: source.sourceKind,
    sourceTrust: attestation.sourceTrust!,
    revision: attestation.revision!,
    contentHash: attestation.contentHash!,
    chunkIds: [for (final chunk in chunks) chunk.chunkId],
    chunks: chunks,
  );
}

String rag2StorageDeclarationIdentity({
  required String projectId,
  required List<String> sourceRoots,
}) {
  final roots = List<String>.from(sourceRoots)..sort();
  return 'declaration_${sha256.convert(utf8.encode([rag2StorageReplayContract, projectId, ...roots].join('\u0000')))}';
}

typedef Rag2BeforeGenerationCommit =
    void Function(Rag2StoredGeneration pending);

final class Rag2InMemoryGenerationStore {
  final Map<String, Rag2StoredGeneration> _generations = {};

  Rag2StoredGeneration? read(String declarationIdentity) =>
      _generations[declarationIdentity];

  Rag2StorageApplyResult apply({
    required String declarationIdentity,
    required Rag2KnowledgeSnapshot snapshot,
    Rag2BeforeGenerationCommit? beforeCommit,
  }) {
    _validateSnapshot(snapshot);
    final previous = _generations[declarationIdentity];
    if (previous?.snapshot.snapshotHash == snapshot.snapshotHash) {
      return Rag2StorageApplyResult(
        decision: 'no_op',
        generation: previous!.generation,
        snapshotHash: previous.snapshot.snapshotHash,
        delta: Rag2KnowledgeReplayDelta.compare(
          previous.snapshot,
          previous.snapshot,
        ),
      );
    }
    final empty = const Rag2KnowledgeSnapshot(
      snapshotId: 'empty',
      snapshotHash: '',
      objects: [],
    );
    final delta = Rag2KnowledgeReplayDelta.compare(
      previous?.snapshot ?? empty,
      snapshot,
    );
    final pending = Rag2StoredGeneration(
      generation: (previous?.generation ?? 0) + 1,
      snapshot: snapshot,
    );
    try {
      beforeCommit?.call(pending);
      _generations[declarationIdentity] = pending;
      return Rag2StorageApplyResult(
        decision: 'applied',
        generation: pending.generation,
        snapshotHash: snapshot.snapshotHash,
        delta: delta,
      );
    } on Object {
      return Rag2StorageApplyResult(
        decision: 'rolled_back',
        generation: previous?.generation ?? 0,
        snapshotHash: previous?.snapshot.snapshotHash ?? '',
        delta: delta,
      );
    }
  }

  void _validateSnapshot(Rag2KnowledgeSnapshot snapshot) {
    if (snapshot.objects.isEmpty ||
        rag2KnowledgeSnapshotHash(snapshot.objects) != snapshot.snapshotHash) {
      throw const Rag2StoragePreparationException('snapshot_invalid');
    }
    final projectIds = snapshot.objects
        .map((object) => object.projectId)
        .toSet();
    final objectIds = snapshot.objects.map((object) => object.objectId).toSet();
    final chunks = snapshot.chunks;
    if (projectIds.length != 1 ||
        objectIds.length != snapshot.objects.length ||
        chunks.map((chunk) => chunk.chunkId).toSet().length != chunks.length ||
        chunks.any((chunk) => !objectIds.contains(chunk.objectId))) {
      throw const Rag2StoragePreparationException('snapshot_invalid');
    }
  }
}

final class Rag2StoredGeneration {
  const Rag2StoredGeneration({
    required this.generation,
    required this.snapshot,
  });

  final int generation;
  final Rag2KnowledgeSnapshot snapshot;
}

final class Rag2StorageApplyResult {
  const Rag2StorageApplyResult({
    required this.decision,
    required this.generation,
    required this.snapshotHash,
    required this.delta,
  });

  final String decision;
  final int generation;
  final String snapshotHash;
  final Rag2KnowledgeReplayDelta delta;

  Map<String, Object?> toAggregateJson() => {
    'decision': decision,
    'generation': generation,
    'snapshotHash': snapshotHash,
    'retainedChunkCount': delta.retainedChunkIds.length,
    'unchangedChunkCount': delta.unchangedChunkIds.length,
    'metadataUpdatedChunkCount': delta.metadataUpdatedChunkIds.length,
    'removedChunkCount': delta.removedChunkIds.length,
    'addedChunkCount': delta.addedChunkIds.length,
    'changedObjectCount': delta.changedObjectIds.length,
    'unchangedObjectCount': delta.unchangedObjectIds.length,
    'removedObjectCount': delta.removedObjectIds.length,
    'addedObjectCount': delta.addedObjectIds.length,
  };
}

final class Rag2StorageReplayReport {
  const Rag2StorageReplayReport({
    required this.fixtureId,
    required this.declarationIdentity,
    required this.deterministicReplay,
    required this.expectedPassed,
    required this.initial,
    required this.identical,
    required this.replacement,
    required this.injectedFailure,
    required this.applyRollbackPreserved,
    required this.preparationRejected,
    required this.preparationRollbackPreserved,
  });

  final String fixtureId;
  final String declarationIdentity;
  final bool deterministicReplay;
  final bool expectedPassed;
  final Rag2StorageApplyResult initial;
  final Rag2StorageApplyResult identical;
  final Rag2StorageApplyResult replacement;
  final Rag2StorageApplyResult injectedFailure;
  final bool applyRollbackPreserved;
  final bool preparationRejected;
  final bool preparationRollbackPreserved;

  bool get contractPassed =>
      deterministicReplay &&
      expectedPassed &&
      initial.decision == 'applied' &&
      identical.decision == 'no_op' &&
      replacement.decision == 'applied' &&
      injectedFailure.decision == 'rolled_back' &&
      applyRollbackPreserved &&
      preparationRejected &&
      preparationRollbackPreserved;

  Map<String, Object?> toJson() => {
    'schemaName': rag2StorageReplayReportSchema,
    'schemaVersion': 1,
    'contract': rag2StorageReplayContract,
    'evaluationMode': 'backend_neutral_offline_replay',
    'contractDecision': contractPassed ? 'go' : 'no_go',
    'storageDecision': contractPassed ? 'go' : 'no_go',
    'retrievalDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'fixtureId': fixtureId,
    'declarationIdentity': declarationIdentity,
    'deterministicReplay': deterministicReplay,
    'expectedPassed': expectedPassed,
    'applyRollbackPreserved': applyRollbackPreserved,
    'preparationRejected': preparationRejected,
    'preparationRollbackPreserved': preparationRollbackPreserved,
    'initial': initial.toAggregateJson(),
    'identical': identical.toAggregateJson(),
    'replacement': replacement.toAggregateJson(),
    'injectedFailure': injectedFailure.toAggregateJson(),
  };

  String toMarkdown() =>
      '# RAG2 Storage Replay\n\n'
      '- Contract: `$rag2StorageReplayContract`\n'
      '- Contract decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Storage decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Retrieval decision: `not_evaluated`\n'
      '- Production decision: `no_go`\n'
      '- Deterministic replay: `$deterministicReplay`\n'
      '- Initial / identical / replacement generations: `${initial.generation}` / `${identical.generation}` / `${replacement.generation}`\n'
      '- Replacement retained / removed / added chunks: `${replacement.delta.retainedChunkIds.length}` / `${replacement.delta.removedChunkIds.length}` / `${replacement.delta.addedChunkIds.length}`\n'
      '- Replacement metadata updates: `${replacement.delta.metadataUpdatedChunkIds.length}`\n'
      '- Apply rollback preserved: `$applyRollbackPreserved`\n'
      '- Preparation rollback preserved: `$preparationRollbackPreserved`\n';
}

final class Rag2StorageReplayFixture {
  const Rag2StorageReplayFixture({
    required this.fixtureId,
    required this.projectId,
    required this.sourceRoots,
    required this.snapshots,
    required this.expected,
  });

  final String fixtureId;
  final String projectId;
  final List<String> sourceRoots;
  final List<Rag2StorageSnapshotSpec> snapshots;
  final Rag2StorageReplayExpected expected;

  static Future<Rag2StorageReplayFixture> load(File file) async {
    final json = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    if (json['schemaName'] != rag2StorageReplayFixtureSchema ||
        json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported storage replay fixture.');
    }
    final snapshots = (json['snapshots'] as List)
        .map(
          (item) => Rag2StorageSnapshotSpec.fromJson(
            (item as Map).cast<String, Object?>(),
          ),
        )
        .toList();
    if (snapshots.length != 2) {
      throw const FormatException('Storage replay requires two snapshots.');
    }
    return Rag2StorageReplayFixture(
      fixtureId: json['fixtureId'] as String,
      projectId: json['projectId'] as String,
      sourceRoots: (json['sourceRoots'] as List).cast<String>(),
      snapshots: snapshots,
      expected: Rag2StorageReplayExpected.fromJson(
        (json['expected'] as Map).cast<String, Object?>(),
      ),
    );
  }
}

final class Rag2StorageSnapshotSpec {
  const Rag2StorageSnapshotSpec({
    required this.id,
    required this.root,
    required this.gitEvidenceByPath,
  });

  final String id;
  final String root;
  final Map<String, Rag2GitEvidence> gitEvidenceByPath;

  factory Rag2StorageSnapshotSpec.fromJson(Map<String, Object?> json) =>
      Rag2StorageSnapshotSpec(
        id: json['id'] as String,
        root: json['root'] as String,
        gitEvidenceByPath: (json['gitEvidenceByPath'] as Map).map(
          (key, value) => MapEntry(
            key as String,
            Rag2GitEvidence.fromJson((value as Map).cast<String, Object?>()),
          ),
        ),
      );
}

final class Rag2StorageReplayExpected {
  const Rag2StorageReplayExpected({
    required this.baselineSnapshotHash,
    required this.updatedSnapshotHash,
    required this.initialObjectCount,
    required this.initialChunkCount,
    required this.retainedChunkCount,
    required this.metadataUpdatedChunkCount,
    required this.removedChunkCount,
    required this.addedChunkCount,
    required this.removedObjectCount,
    required this.addedObjectCount,
  });

  final String baselineSnapshotHash;
  final String updatedSnapshotHash;
  final int initialObjectCount;
  final int initialChunkCount;
  final int retainedChunkCount;
  final int metadataUpdatedChunkCount;
  final int removedChunkCount;
  final int addedChunkCount;
  final int removedObjectCount;
  final int addedObjectCount;

  factory Rag2StorageReplayExpected.fromJson(Map<String, Object?> json) =>
      Rag2StorageReplayExpected(
        baselineSnapshotHash: json['baselineSnapshotHash'] as String,
        updatedSnapshotHash: json['updatedSnapshotHash'] as String,
        initialObjectCount: json['initialObjectCount'] as int,
        initialChunkCount: json['initialChunkCount'] as int,
        retainedChunkCount: json['retainedChunkCount'] as int,
        metadataUpdatedChunkCount: json['metadataUpdatedChunkCount'] as int,
        removedChunkCount: json['removedChunkCount'] as int,
        addedChunkCount: json['addedChunkCount'] as int,
        removedObjectCount: json['removedObjectCount'] as int,
        addedObjectCount: json['addedObjectCount'] as int,
      );

  bool matches({
    required Rag2KnowledgeSnapshot baseline,
    required Rag2KnowledgeSnapshot updated,
    required Rag2StorageApplyResult initial,
    required Rag2StorageApplyResult replacement,
  }) =>
      baseline.snapshotHash == baselineSnapshotHash &&
      updated.snapshotHash == updatedSnapshotHash &&
      baseline.objects.length == initialObjectCount &&
      baseline.chunks.length == initialChunkCount &&
      replacement.delta.retainedChunkIds.length == retainedChunkCount &&
      replacement.delta.metadataUpdatedChunkIds.length ==
          metadataUpdatedChunkCount &&
      replacement.delta.removedChunkIds.length == removedChunkCount &&
      replacement.delta.addedChunkIds.length == addedChunkCount &&
      replacement.delta.removedObjectIds.length == removedObjectCount &&
      replacement.delta.addedObjectIds.length == addedObjectCount &&
      initial.generation == 1 &&
      replacement.generation == 2;
}

final class Rag2StoragePreparationException implements Exception {
  const Rag2StoragePreparationException(this.reason);
  final String reason;
}

final class Rag2StorageReplayOptions {
  const Rag2StorageReplayOptions({
    required this.fixturePath,
    required this.outDir,
  });

  final String fixturePath;
  final String outDir;

  static Rag2StorageReplayOptions? parse(List<String> args) {
    String? fixturePath;
    String? outDir;
    for (var index = 0; index < args.length; index++) {
      if (index + 1 >= args.length) return null;
      switch (args[index]) {
        case '--fixture':
          fixturePath = args[++index];
        case '--out-dir':
          outDir = args[++index];
        default:
          return null;
      }
    }
    return fixturePath == null || outDir == null
        ? null
        : Rag2StorageReplayOptions(fixturePath: fixturePath, outDir: outDir);
  }
}
