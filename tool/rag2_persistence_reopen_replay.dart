import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_knowledge_object_replay.dart';
import 'rag2_storage_replay.dart';

const rag2PersistenceReopenContract = 'rag2-persistence-reopen-contract-v1';
const rag2PersistenceStoreSchema = 'caverno_rag2_persisted_generation';
const rag2PersistenceStoreSchemaVersion = 1;
const rag2PersistenceReplayReportSchema =
    'caverno_rag2_persistence_reopen_report';

Future<void> main(List<String> args) async {
  final options = Rag2PersistenceReopenOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_persistence_reopen_replay.dart '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2PersistenceReopenReplay(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 persistence reopen replay failed: $error');
    exitCode = 65;
  }
}

Future<Rag2PersistenceReopenReport> runRag2PersistenceReopenReplay(
  Rag2PersistenceReopenOptions options,
) async {
  final fixtureFile = File(options.fixturePath);
  final fixture = await Rag2StorageReplayFixture.load(fixtureFile);
  final declarationIdentity = rag2ExplicitSourceRootsDeclarationIdentity(
    fixture.sourceRoots,
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

  final reopenRoot = _freshDirectory('${options.storeRoot}/reopen');
  final reopenStore = Rag2DurableGenerationStore(
    storeRoot: reopenRoot.path,
    projectId: fixture.projectId,
  );
  await reopenStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  await reopenStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
  );
  final reopened = Rag2DurableGenerationStore(
    storeRoot: reopenRoot.path,
    projectId: fixture.projectId,
  );
  final reopenedGeneration = await reopened.read(declarationIdentity);
  final reopenedNoOp = await reopened.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
  );
  final attestedTextPreserved =
      reopenedGeneration != null &&
      reopenedGeneration.generation == 2 &&
      reopenedGeneration.snapshot.snapshotHash == updated.snapshotHash &&
      reopenedGeneration.snapshot.chunks.any(
        (chunk) => chunk.content.contains('fixture-secret-alpha'),
      ) &&
      reopenedNoOp.decision == 'no_op';

  final crashRoot = _freshDirectory('${options.storeRoot}/crash');
  final crashStore = Rag2DurableGenerationStore(
    storeRoot: crashRoot.path,
    projectId: fixture.projectId,
  );
  await crashStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  final crashAttempt = await crashStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
    simulateCrashBeforeRename: true,
  );
  final recovered = Rag2DurableGenerationStore(
    storeRoot: crashRoot.path,
    projectId: fixture.projectId,
  );
  final recoveredGeneration = await recovered.read(declarationIdentity);
  final bakRoot = _freshDirectory('${options.storeRoot}/backup');
  final bakStore = Rag2DurableGenerationStore(
    storeRoot: bakRoot.path,
    projectId: fixture.projectId,
  );
  await bakStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  await bakStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
    simulateCrashAfterQuiescingCurrent: true,
  );
  final bakRecovered = await Rag2DurableGenerationStore(
    storeRoot: bakRoot.path,
    projectId: fixture.projectId,
  ).read(declarationIdentity);
  final crashRecovered =
      crashAttempt.decision == 'rolled_back' &&
      recoveredGeneration?.generation == 1 &&
      recoveredGeneration?.snapshot.snapshotHash == baseline.snapshotHash &&
      bakRecovered?.generation == 1 &&
      bakRecovered?.snapshot.snapshotHash == baseline.snapshotHash;

  final schemaRoot = _freshDirectory('${options.storeRoot}/schema');
  final schemaStore = Rag2DurableGenerationStore(
    storeRoot: schemaRoot.path,
    projectId: fixture.projectId,
  );
  await schemaStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  final current = schemaStore.currentFile(declarationIdentity);
  final originalBytes = current.readAsStringSync();
  current.writeAsStringSync(
    originalBytes.replaceFirst('"schemaVersion": 1', '"schemaVersion": 2'),
  );
  var unsupportedSchemaRejected = false;
  try {
    await Rag2DurableGenerationStore(
      storeRoot: schemaRoot.path,
      projectId: fixture.projectId,
    ).read(declarationIdentity);
  } on Rag2PersistenceException catch (error) {
    unsupportedSchemaRejected =
        error.reason == 'unsupported_schema' &&
        current.readAsStringSync() ==
            originalBytes.replaceFirst(
              '"schemaVersion": 1',
              '"schemaVersion": 2',
            );
  }

  final isolateRoot = _freshDirectory('${options.storeRoot}/isolate');
  final firstProject = Rag2DurableGenerationStore(
    storeRoot: isolateRoot.path,
    projectId: 'persistence-project-a',
  );
  final secondProject = Rag2DurableGenerationStore(
    storeRoot: isolateRoot.path,
    projectId: 'persistence-project-b',
  );
  final firstSnapshot = await prepareRag2StorageSnapshot(
    fixtureFile: fixtureFile,
    fixture: fixture,
    spec: fixture.snapshots[1],
    projectId: 'persistence-project-a',
  );
  final secondSnapshot = await prepareRag2StorageSnapshot(
    fixtureFile: fixtureFile,
    fixture: fixture,
    spec: fixture.snapshots[0],
    projectId: 'persistence-project-b',
  );
  await firstProject.apply(
    declarationIdentity: declarationIdentity,
    snapshot: firstSnapshot,
  );
  await secondProject.apply(
    declarationIdentity: declarationIdentity,
    snapshot: secondSnapshot,
  );
  final isolatedFirst = await Rag2DurableGenerationStore(
    storeRoot: isolateRoot.path,
    projectId: 'persistence-project-a',
  ).read(declarationIdentity);
  final isolatedSecond = await Rag2DurableGenerationStore(
    storeRoot: isolateRoot.path,
    projectId: 'persistence-project-b',
  ).read(declarationIdentity);
  final declarationIsolation =
      isolatedFirst?.generation == 1 &&
      isolatedFirst?.snapshot.snapshotHash == firstSnapshot.snapshotHash &&
      isolatedSecond?.generation == 1 &&
      isolatedSecond?.snapshot.snapshotHash == secondSnapshot.snapshotHash &&
      firstProject.slotDirectory(declarationIdentity).path !=
          secondProject.slotDirectory(declarationIdentity).path;
  var foreignSnapshotRejected = false;
  try {
    await Rag2DurableGenerationStore(
      storeRoot: _freshDirectory('${options.storeRoot}/foreign').path,
      projectId: 'persistence-project-a',
    ).apply(declarationIdentity: declarationIdentity, snapshot: baseline);
  } on Rag2PersistenceException catch (error) {
    foreignSnapshotRejected = error.reason == 'persisted_identity_mismatch';
  }

  final report = Rag2PersistenceReopenReport(
    fixtureId: fixture.fixtureId,
    declarationIdentity: declarationIdentity,
    reopenedGeneration: reopenedGeneration?.generation ?? 0,
    reopenedSnapshotHash: reopenedGeneration?.snapshot.snapshotHash ?? '',
    recoveredGeneration: recoveredGeneration?.generation ?? 0,
    recoveredSnapshotHash: recoveredGeneration?.snapshot.snapshotHash ?? '',
    attestedTextPreserved: attestedTextPreserved,
    crashRecovered: crashRecovered,
    unsupportedSchemaRejected: unsupportedSchemaRejected,
    declarationIsolation: declarationIsolation,
    foreignSnapshotRejected: foreignSnapshotRejected,
  );
  final outputDirectory = Directory(options.outDir)
    ..createSync(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_persistence_reopen.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_persistence_reopen.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

final class Rag2PersistenceReopenOptions {
  const Rag2PersistenceReopenOptions({
    required this.fixturePath,
    required this.outDir,
    required this.storeRoot,
  });

  final String fixturePath;
  final String outDir;
  final String storeRoot;

  static Rag2PersistenceReopenOptions? parse(List<String> args) {
    String? fixturePath;
    String? outDir;
    String? storeRoot;
    for (var index = 0; index < args.length; index++) {
      if (index + 1 >= args.length) {
        return null;
      }
      switch (args[index]) {
        case '--fixture':
          fixturePath = args[++index];
        case '--out-dir':
          outDir = args[++index];
        case '--store-dir':
          storeRoot = args[++index];
        default:
          return null;
      }
    }
    if (fixturePath == null || outDir == null) {
      return null;
    }
    return Rag2PersistenceReopenOptions(
      fixturePath: fixturePath,
      outDir: outDir,
      storeRoot: storeRoot ?? '$outDir/store',
    );
  }
}

final class Rag2DurableGenerationStore {
  Rag2DurableGenerationStore({
    required this.storeRoot,
    required this.projectId,
  });

  final String storeRoot;
  final String projectId;

  String get projectIdentity =>
      rag2ExplicitSourceRootsProjectIdentity(projectId);

  Directory slotDirectory(String declarationIdentity) =>
      Directory('$storeRoot/$projectIdentity/$declarationIdentity');

  File currentFile(String declarationIdentity) =>
      File('${slotDirectory(declarationIdentity).path}/current.json');

  File partialFile(String declarationIdentity) =>
      File('${slotDirectory(declarationIdentity).path}/current.json.partial');

  File backupFile(String declarationIdentity) =>
      File('${slotDirectory(declarationIdentity).path}/current.json.bak');

  Future<Rag2StoredGeneration?> read(String declarationIdentity) async {
    _recoverSlot(declarationIdentity);
    final current = currentFile(declarationIdentity);
    if (!current.existsSync()) {
      return null;
    }
    return decodeRag2PersistedGeneration(
      bytes: current.readAsStringSync(),
      expectedProjectId: projectId,
      expectedDeclarationIdentity: declarationIdentity,
    );
  }

  Future<Rag2StorageApplyResult> apply({
    required String declarationIdentity,
    required Rag2KnowledgeSnapshot snapshot,
    Rag2BeforeGenerationCommit? beforeCommit,
    bool simulateCrashBeforeRename = false,
    bool simulateCrashAfterQuiescingCurrent = false,
  }) async {
    if (simulateCrashBeforeRename && simulateCrashAfterQuiescingCurrent) {
      throw ArgumentError(
        'Use only one crash simulation: before rename or after quiescing current.',
      );
    }
    ensureRag2SnapshotMatchesProject(projectId: projectId, snapshot: snapshot);
    final memory = Rag2InMemoryGenerationStore();
    final previous = await read(declarationIdentity);
    if (previous != null) {
      memory.restore(
        declarationIdentity: declarationIdentity,
        generation: previous,
      );
    }
    final simulatingCrash =
        simulateCrashBeforeRename || simulateCrashAfterQuiescingCurrent;
    final partial = partialFile(declarationIdentity);
    final result = memory.apply(
      declarationIdentity: declarationIdentity,
      snapshot: snapshot,
      beforeCommit: (pending) {
        slotDirectory(declarationIdentity).createSync(recursive: true);
        partial.writeAsStringSync(
          encodeRag2PersistedGeneration(
            projectId: projectId,
            declarationIdentity: declarationIdentity,
            generation: pending,
          ),
        );
        if (simulateCrashAfterQuiescingCurrent) {
          _quiesceCurrentToBackup(declarationIdentity);
        }
        if (simulatingCrash) {
          throw StateError('simulated_crash_before_commit');
        }
        beforeCommit?.call(pending);
      },
    );
    if (result.decision == 'applied') {
      _replaceCurrent(declarationIdentity);
    } else if (!simulatingCrash && partial.existsSync()) {
      partial.deleteSync();
    }
    return result;
  }

  void _recoverSlot(String declarationIdentity) {
    final current = currentFile(declarationIdentity);
    final partial = partialFile(declarationIdentity);
    final backup = backupFile(declarationIdentity);
    if (partial.existsSync()) {
      partial.deleteSync();
    }
    if (!current.existsSync() && backup.existsSync()) {
      backup.renameSync(current.path);
    } else if (current.existsSync() && backup.existsSync()) {
      backup.deleteSync();
    }
  }

  void _quiesceCurrentToBackup(String declarationIdentity) {
    final current = currentFile(declarationIdentity);
    final backup = backupFile(declarationIdentity);
    if (!current.existsSync()) {
      return;
    }
    if (backup.existsSync()) {
      backup.deleteSync();
    }
    current.renameSync(backup.path);
  }

  void _replaceCurrent(String declarationIdentity) {
    final partial = partialFile(declarationIdentity);
    final current = currentFile(declarationIdentity);
    final backup = backupFile(declarationIdentity);
    _quiesceCurrentToBackup(declarationIdentity);
    partial.renameSync(current.path);
    if (backup.existsSync()) {
      backup.deleteSync();
    }
  }
}

String encodeRag2PersistedGeneration({
  required String projectId,
  required String declarationIdentity,
  required Rag2StoredGeneration generation,
}) {
  final record = {
    'schemaName': rag2PersistenceStoreSchema,
    'schemaVersion': rag2PersistenceStoreSchemaVersion,
    'contract': rag2PersistenceReopenContract,
    'projectId': projectId,
    'projectIdentity': rag2ExplicitSourceRootsProjectIdentity(projectId),
    'declarationIdentity': declarationIdentity,
    'generation': generation.generation,
    'snapshotId': generation.snapshot.snapshotId,
    'snapshotHash': generation.snapshot.snapshotHash,
    'objects': [
      for (final object in generation.snapshot.objects)
        _persistedObjectJson(object),
    ],
  };
  return '${const JsonEncoder.withIndent('  ').convert(record)}\n';
}

Rag2StoredGeneration decodeRag2PersistedGeneration({
  required String bytes,
  required String expectedProjectId,
  required String expectedDeclarationIdentity,
}) {
  final json = jsonDecode(bytes);
  if (json is! Map) {
    throw const Rag2PersistenceException('persisted_record_invalid');
  }
  final record = json.cast<String, Object?>();
  if (record['schemaName'] != rag2PersistenceStoreSchema ||
      record['schemaVersion'] != rag2PersistenceStoreSchemaVersion) {
    throw const Rag2PersistenceException('unsupported_schema');
  }
  if (record['contract'] != rag2PersistenceReopenContract ||
      record['projectId'] != expectedProjectId ||
      record['projectIdentity'] !=
          rag2ExplicitSourceRootsProjectIdentity(expectedProjectId) ||
      record['declarationIdentity'] != expectedDeclarationIdentity) {
    throw const Rag2PersistenceException('persisted_identity_mismatch');
  }
  final generation = record['generation'];
  if (generation is! int || generation < 1) {
    throw const Rag2PersistenceException('generation_invalid');
  }
  final objectsJson = record['objects'];
  if (objectsJson is! List || objectsJson.isEmpty) {
    throw const Rag2PersistenceException('persisted_record_invalid');
  }
  final objects = [
    for (final item in objectsJson)
      _objectFromPersistedJson((item as Map).cast<String, Object?>()),
  ];
  final snapshot = Rag2KnowledgeSnapshot(
    snapshotId: record['snapshotId'] as String,
    snapshotHash: record['snapshotHash'] as String,
    objects: List.unmodifiable(objects),
  );
  if (rag2KnowledgeSnapshotHash(objects) != snapshot.snapshotHash) {
    throw const Rag2PersistenceException('persisted_hash_mismatch');
  }
  ensureRag2SnapshotMatchesProject(
    projectId: expectedProjectId,
    snapshot: snapshot,
  );
  return Rag2StoredGeneration(generation: generation, snapshot: snapshot);
}

Map<String, Object?> _persistedObjectJson(Rag2KnowledgeObject object) {
  final json = object.toJson();
  json['chunks'] = [
    for (final chunk in object.chunks)
      {...chunk.toJson(), 'content': chunk.content},
  ];
  return json;
}

Rag2KnowledgeObject _objectFromPersistedJson(Map<String, Object?> json) {
  final chunksJson = json['chunks'];
  if (chunksJson is! List || chunksJson.isEmpty) {
    throw const Rag2PersistenceException('chunk_text_missing');
  }
  final chunks = [
    for (final item in chunksJson)
      _chunkFromPersistedJson((item as Map).cast<String, Object?>()),
  ];
  final object = Rag2KnowledgeObject(
    objectId: json['objectId'] as String,
    projectId: json['projectId'] as String,
    repoRelativePath: json['repoRelativePath'] as String,
    sourceKind: json['sourceKind'] as String,
    sourceTrust: json['sourceTrust'] as String,
    revision: json['revision'] as String,
    contentHash: json['contentHash'] as String,
    chunkIds: (json['chunkIds'] as List).cast<String>(),
    chunks: chunks,
  );
  if (object.chunkIds.join('\u0000') !=
      chunks.map((chunk) => chunk.chunkId).join('\u0000')) {
    throw const Rag2PersistenceException('persisted_record_invalid');
  }
  return object;
}

Rag2KnowledgeChunk _chunkFromPersistedJson(Map<String, Object?> json) {
  final content = json['content'];
  if (content is! String) {
    throw const Rag2PersistenceException('chunk_text_missing');
  }
  final contentHash = json['contentHash'] as String;
  if (sha256.convert(utf8.encode(content)).toString() != contentHash) {
    throw const Rag2PersistenceException('persisted_hash_mismatch');
  }
  final provenanceJson = json['provenance'];
  if (provenanceJson is! Map) {
    throw const Rag2PersistenceException('persisted_record_invalid');
  }
  final provenance = provenanceJson.cast<String, Object?>();
  return Rag2KnowledgeChunk(
    chunkId: json['chunkId'] as String,
    objectId: json['objectId'] as String,
    locator: json['locator'] as String,
    contentHash: contentHash,
    content: content,
    passageRole: json['passageRole'] as String,
    provenance: Rag2KnowledgeProvenance(
      projectId: provenance['projectId'] as String,
      repoRelativePath: provenance['repoRelativePath'] as String,
      revision: provenance['revision'] as String,
      objectContentHash: provenance['objectContentHash'] as String,
      lineStart: provenance['lineStart'] as int,
      lineEnd: provenance['lineEnd'] as int,
      sourceTrust: provenance['sourceTrust'] as String,
    ),
  );
}

void ensureRag2SnapshotMatchesProject({
  required String projectId,
  required Rag2KnowledgeSnapshot snapshot,
}) {
  for (final object in snapshot.objects) {
    final expectedObjectId = rag2KnowledgeObjectId(
      projectId: projectId,
      repoRelativePath: object.repoRelativePath,
    );
    if (object.projectId != projectId || object.objectId != expectedObjectId) {
      throw const Rag2PersistenceException('persisted_identity_mismatch');
    }
    for (final chunk in object.chunks) {
      final expectedChunkId = rag2KnowledgeChunkId(
        objectId: object.objectId,
        locator: chunk.locator,
        contentHash: chunk.contentHash,
      );
      if (chunk.objectId != object.objectId ||
          chunk.chunkId != expectedChunkId ||
          chunk.provenance.projectId != projectId ||
          chunk.provenance.repoRelativePath != object.repoRelativePath) {
        throw const Rag2PersistenceException('persisted_identity_mismatch');
      }
    }
  }
}

Directory _freshDirectory(String path) {
  final directory = Directory(path);
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
  directory.createSync(recursive: true);
  return directory;
}

final class Rag2PersistenceException implements Exception {
  const Rag2PersistenceException(this.reason);
  final String reason;

  @override
  String toString() => 'RAG2 persistence failed: $reason';
}

final class Rag2PersistenceReopenReport {
  const Rag2PersistenceReopenReport({
    required this.fixtureId,
    required this.declarationIdentity,
    required this.reopenedGeneration,
    required this.reopenedSnapshotHash,
    required this.recoveredGeneration,
    required this.recoveredSnapshotHash,
    required this.attestedTextPreserved,
    required this.crashRecovered,
    required this.unsupportedSchemaRejected,
    required this.declarationIsolation,
    required this.foreignSnapshotRejected,
  });

  final String fixtureId;
  final String declarationIdentity;
  final int reopenedGeneration;
  final String reopenedSnapshotHash;
  final int recoveredGeneration;
  final String recoveredSnapshotHash;
  final bool attestedTextPreserved;
  final bool crashRecovered;
  final bool unsupportedSchemaRejected;
  final bool declarationIsolation;
  final bool foreignSnapshotRejected;

  bool get contractPassed =>
      attestedTextPreserved &&
      crashRecovered &&
      unsupportedSchemaRejected &&
      declarationIsolation &&
      foreignSnapshotRejected &&
      reopenedGeneration == 2 &&
      recoveredGeneration == 1;

  Map<String, Object?> toJson() => {
    'schemaName': rag2PersistenceReplayReportSchema,
    'schemaVersion': 1,
    'contract': rag2PersistenceReopenContract,
    'evaluationMode': 'backend_neutral_durable_replay',
    'contractDecision': contractPassed ? 'go' : 'no_go',
    'persistenceDecision': contractPassed ? 'go' : 'no_go',
    'backendDecision': 'not_selected',
    'storageDecision': 'go',
    'retrievalDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'fixtureId': fixtureId,
    'declarationIdentity': declarationIdentity,
    'reopenedGeneration': reopenedGeneration,
    'reopenedSnapshotHash': reopenedSnapshotHash,
    'recoveredGeneration': recoveredGeneration,
    'recoveredSnapshotHash': recoveredSnapshotHash,
    'attestedTextPreserved': attestedTextPreserved,
    'crashRecovered': crashRecovered,
    'unsupportedSchemaRejected': unsupportedSchemaRejected,
    'declarationIsolation': declarationIsolation,
    'foreignSnapshotRejected': foreignSnapshotRejected,
  };

  String toMarkdown() =>
      '# RAG2 Persistence Reopen\n\n'
      '- Contract: `$rag2PersistenceReopenContract`\n'
      '- Contract decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Persistence decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Backend decision: `not_selected`\n'
      '- Storage decision: `go`\n'
      '- Retrieval decision: `not_evaluated`\n'
      '- Production decision: `no_go`\n'
      '- Fixture: `$fixtureId`\n'
      '- Declaration identity: `$declarationIdentity`\n'
      '- Reopened generation / hash: `$reopenedGeneration` / `$reopenedSnapshotHash`\n'
      '- Recovered generation / hash: `$recoveredGeneration` / `$recoveredSnapshotHash`\n'
      '- Attested text preserved: `$attestedTextPreserved`\n'
      '- Crash recovered: `$crashRecovered`\n'
      '- Unsupported schema rejected: `$unsupportedSchemaRejected`\n'
      '- Declaration isolation: `$declarationIsolation`\n'
      '- Foreign snapshot rejected: `$foreignSnapshotRejected`\n';
}
