import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/datasources/rag2_drift_generation_dao.dart';
import 'package:caverno/features/chat/data/datasources/rag2_drift_schema.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

import 'rag2_drift_additive_schema_replay.dart';
import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_knowledge_object_replay.dart';
import 'rag2_lexical_policy_bakeoff.dart';
import 'rag2_persistence_reopen_replay.dart';
import 'rag2_storage_replay.dart';

const rag2DriftDaoGenerationStoreContract =
    'rag2-drift-dao-generation-store-contract-v1';

Future<void> main(List<String> args) async {
  if (args.contains('--crash-uncommitted')) {
    exitCode = await runRag2DriftDaoCrashUncommittedChild(args);
    return;
  }
  if (args.contains('--apply-once')) {
    exitCode = await runRag2DriftDaoApplyOnceChild(args);
    return;
  }
  stderr.writeln(
    'Usage: dart run tool/rag2_drift_dao_generation_store.dart '
    '--crash-uncommitted --fixture PATH --db PATH --ready-file PATH\n'
    '       dart run tool/rag2_drift_dao_generation_store.dart '
    '--apply-once --fixture PATH --db PATH --snapshot-index N',
  );
  exitCode = 64;
}

AppDatabase openRag2DriftDaoDatabase(String databasePath) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  File(databasePath).parent.createSync(recursive: true);
  final sqlite = sqlite3.open(databasePath);
  sqlite.execute('PRAGMA busy_timeout = 30000');
  sqlite.execute('PRAGMA synchronous = FULL');
  sqlite.select('PRAGMA journal_mode = DELETE');
  return AppDatabase(
    NativeDatabase.opened(sqlite, closeUnderlyingOnClose: true),
  );
}

final class Rag2DriftDaoGenerationStore {
  Rag2DriftDaoGenerationStore({
    required AppDatabase database,
    required this.projectId,
  }) : database = database,
       _dao = Rag2DriftGenerationDao(database);

  factory Rag2DriftDaoGenerationStore.open({
    required String databasePath,
    required String projectId,
  }) {
    return Rag2DriftDaoGenerationStore(
      database: openRag2DriftDaoDatabase(databasePath),
      projectId: projectId,
    );
  }

  final AppDatabase database;
  final String projectId;
  final Rag2DriftGenerationDao _dao;

  String get projectIdentity =>
      rag2ExplicitSourceRootsProjectIdentity(projectId);

  Future<Rag2StoredGeneration?> read(String declarationIdentity) async {
    await _ensureHostedSchema();
    return _readLocked(declarationIdentity);
  }

  Future<Rag2StorageApplyResult> apply({
    required String declarationIdentity,
    required Rag2KnowledgeSnapshot snapshot,
    Rag2BeforeGenerationCommit? beforeCommit,
    void Function()? beforeTxnCommit,
    bool commit = true,
    bool indexSearch = false,
  }) async {
    ensureRag2SnapshotMatchesProject(projectId: projectId, snapshot: snapshot);
    await _dao.beginImmediate();
    var settled = false;
    try {
      await _ensureHostedSchema();
      final memory = Rag2InMemoryGenerationStore();
      final previous = await _readLocked(declarationIdentity);
      if (previous != null) {
        memory.restore(
          declarationIdentity: declarationIdentity,
          generation: previous,
        );
      }
      Rag2StoredGeneration? pendingWrite;
      final result = memory.apply(
        declarationIdentity: declarationIdentity,
        snapshot: snapshot,
        beforeCommit: (pending) {
          pendingWrite = pending;
          beforeCommit?.call(pending);
        },
      );
      var mutated = false;
      if (result.decision == 'applied') {
        final pending = pendingWrite;
        if (pending == null) {
          throw StateError('applied generation missing pending write');
        }
        await _dao.upsertGeneration(
          Rag2GenerationsCompanion.insert(
            projectIdentity: projectIdentity,
            declarationIdentity: declarationIdentity,
            schemaName: rag2DriftStoreSchema,
            schemaVersion: rag2DriftStoreSchemaVersion,
            contract: rag2DriftAdditiveSchemaContract,
            projectId: projectId,
            generation: pending.generation,
            snapshotHash: pending.snapshot.snapshotHash,
            payload: encodeRag2PersistedGeneration(
              projectId: projectId,
              declarationIdentity: declarationIdentity,
              generation: pending,
            ),
          ),
        );
        mutated = true;
        if (indexSearch) {
          await _writeSearchIndex(
            declarationIdentity: declarationIdentity,
            generation: pending,
            previous: previous,
            delta: result.delta,
          );
        }
      } else if (result.decision == 'no_op' &&
          indexSearch &&
          previous != null) {
        await _writeSearchIndex(
          declarationIdentity: declarationIdentity,
          generation: previous,
          previous: previous,
          delta: result.delta,
        );
        mutated = true;
      }
      if (!commit) {
        return result;
      }
      beforeTxnCommit?.call();
      if (mutated) {
        await _dao.commit();
      } else {
        await _dao.rollback();
      }
      settled = true;
      return result;
    } on Object {
      if (!settled) {
        try {
          await _dao.rollback();
        } on Object {
          // The connection may already have rolled back.
        }
      }
      rethrow;
    }
  }

  Future<void> hangAfterUncommittedApply({
    required String declarationIdentity,
    required Rag2KnowledgeSnapshot snapshot,
    required File readyFile,
    bool indexSearch = false,
  }) async {
    final result = await apply(
      declarationIdentity: declarationIdentity,
      snapshot: snapshot,
      commit: false,
      indexSearch: indexSearch,
    );
    if (result.decision != 'applied') {
      throw StateError(
        'crash child expected an uncommitted apply, got ${result.decision}',
      );
    }
    readyFile.writeAsBytesSync(utf8.encode('ready\n'), flush: true);
    while (true) {
      await Future<void>.delayed(const Duration(days: 1));
    }
  }

  Future<void> close() => database.close();

  Future<void> _ensureHostedSchema() async {
    try {
      await _dao.ensureHostedSchema();
    } on Rag2DriftSchemaException catch (error) {
      throw Rag2PersistenceException(error.reason);
    }
  }

  Future<void> _writeSearchIndex({
    required String declarationIdentity,
    required Rag2StoredGeneration generation,
    Rag2StoredGeneration? previous,
    Rag2KnowledgeReplayDelta? delta,
  }) async {
    await database.ensureRag2ChunkSearchTable();
    final existing = await _indexedSearchRows(declarationIdentity);
    if (previous != null &&
        delta != null &&
        _canPatchSearchIndex(
          existing: existing,
          previous: previous,
          delta: delta,
        )) {
      final chunks = {
        for (final chunk in generation.snapshot.chunks) chunk.chunkId: chunk,
      };
      await database.patchRag2ChunkSearchIndex(
        projectIdentity: projectIdentity,
        declarationIdentity: declarationIdentity,
        generation: generation.generation,
        snapshotHash: generation.snapshot.snapshotHash,
        inTransaction: true,
        unchangedChunkIds: delta.unchangedChunkIds,
        metadataUpdatedRows: [
          for (final chunkId in delta.metadataUpdatedChunkIds)
            _searchRow(chunks[chunkId]!),
        ],
        removedChunkIds: delta.removedChunkIds,
        addedRows: [
          for (final chunkId in delta.addedChunkIds)
            _searchRow(chunks[chunkId]!),
        ],
      );
      return;
    }
    await database.writeRag2ChunkSearchIndex(
      projectIdentity: projectIdentity,
      declarationIdentity: declarationIdentity,
      generation: generation.generation,
      snapshotHash: generation.snapshot.snapshotHash,
      inTransaction: true,
      rows: [for (final chunk in generation.snapshot.chunks) _searchRow(chunk)],
    );
  }

  Future<List<_IndexedSearchRow>> _indexedSearchRows(
    String declarationIdentity,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT generation, snapshot_hash, chunk_id, object_id, content '
          'FROM ${AppDatabase.rag2ChunkSearchTable} '
          'WHERE project_identity = ? AND declaration_identity = ?',
          variables: [
            Variable<String>(projectIdentity),
            Variable<String>(declarationIdentity),
          ],
        )
        .get();
    return [
      for (final row in rows)
        _IndexedSearchRow(
          generation: row.read<int>('generation'),
          snapshotHash: row.read<String>('snapshot_hash'),
          chunkId: row.read<String>('chunk_id'),
          objectId: row.read<String>('object_id'),
          content: row.read<String>('content'),
        ),
    ];
  }

  bool _canPatchSearchIndex({
    required List<_IndexedSearchRow> existing,
    required Rag2StoredGeneration previous,
    required Rag2KnowledgeReplayDelta delta,
  }) {
    final expected = {
      for (final chunk in previous.snapshot.chunks)
        chunk.chunkId: _searchRow(chunk),
    };
    if (existing.isEmpty || existing.length != expected.length) {
      return false;
    }
    final seen = <String>{};
    for (final row in existing) {
      final want = expected[row.chunkId];
      if (want == null ||
          row.generation != previous.generation ||
          row.snapshotHash != previous.snapshot.snapshotHash ||
          row.objectId != want.objectId ||
          row.content != want.content) {
        return false;
      }
      seen.add(row.chunkId);
    }
    return seen.length == expected.length &&
        seen.containsAll(delta.removedChunkIds) &&
        seen.containsAll(delta.unchangedChunkIds) &&
        seen.containsAll(delta.metadataUpdatedChunkIds);
  }

  Rag2ChunkSearchRow _searchRow(Rag2KnowledgeChunk chunk) {
    return Rag2ChunkSearchRow(
      chunkId: chunk.chunkId,
      objectId: chunk.objectId,
      content: tokenizeRag2Lexical(
        chunk.content,
        Rag2LexicalPolicy.trigram,
      ).join(' '),
    );
  }

  Future<Rag2StoredGeneration?> _readLocked(String declarationIdentity) {
    return _dao
        .readGeneration(
          projectIdentity: projectIdentity,
          declarationIdentity: declarationIdentity,
        )
        .then((row) {
          if (row == null) {
            return null;
          }
          return generationFromRag2GenerationRow(
            row: row,
            projectId: projectId,
            declarationIdentity: declarationIdentity,
          );
        });
  }
}

final class _IndexedSearchRow {
  const _IndexedSearchRow({
    required this.generation,
    required this.snapshotHash,
    required this.chunkId,
    required this.objectId,
    required this.content,
  });

  final int generation;
  final String snapshotHash;
  final String chunkId;
  final String objectId;
  final String content;
}

Future<int> runRag2DriftDaoCrashUncommittedChild(List<String> args) async {
  final indexSearch = args.contains('--index-search');
  final options = Rag2DriftCrashChildOptions.parse(
    args.where((arg) => arg != '--index-search').toList(),
  );
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_drift_dao_generation_store.dart '
      '--crash-uncommitted --fixture PATH --db PATH --ready-file PATH '
      '[--index-search]',
    );
    return 64;
  }
  try {
    final fixtureFile = File(options.fixturePath);
    final fixture = await Rag2StorageReplayFixture.load(fixtureFile);
    final declarationIdentity = rag2ExplicitSourceRootsDeclarationIdentity(
      fixture.sourceRoots,
    );
    final updated = await prepareRag2StorageSnapshot(
      fixtureFile: fixtureFile,
      fixture: fixture,
      spec: fixture.snapshots.last,
    );
    final store = Rag2DriftDaoGenerationStore.open(
      databasePath: options.databasePath,
      projectId: fixture.projectId,
    );
    await store.hangAfterUncommittedApply(
      declarationIdentity: declarationIdentity,
      snapshot: updated,
      readyFile: File(options.readyFilePath),
      indexSearch: indexSearch,
    );
    return 0;
  } on Object catch (error) {
    stderr.writeln('RAG2 Drift DAO crash child failed: $error');
    return 65;
  }
}

Future<int> runRag2DriftDaoApplyOnceChild(List<String> args) async {
  final options = Rag2DriftApplyOnceOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_drift_dao_generation_store.dart '
      '--apply-once --fixture PATH --db PATH --snapshot-index N',
    );
    return 64;
  }
  try {
    final fixtureFile = File(options.fixturePath);
    final fixture = await Rag2StorageReplayFixture.load(fixtureFile);
    if (options.snapshotIndex < 0 ||
        options.snapshotIndex >= fixture.snapshots.length) {
      stderr.writeln('snapshot-index out of range');
      return 64;
    }
    final declarationIdentity = rag2ExplicitSourceRootsDeclarationIdentity(
      fixture.sourceRoots,
    );
    final snapshot = await prepareRag2StorageSnapshot(
      fixtureFile: fixtureFile,
      fixture: fixture,
      spec: fixture.snapshots[options.snapshotIndex],
    );
    final store = Rag2DriftDaoGenerationStore.open(
      databasePath: options.databasePath,
      projectId: fixture.projectId,
    );
    try {
      await store.apply(
        declarationIdentity: declarationIdentity,
        snapshot: snapshot,
      );
    } finally {
      await store.close();
    }
    return 0;
  } on Object catch (error) {
    stderr.writeln('RAG2 Drift DAO apply-once child failed: $error');
    return 65;
  }
}

Future<Rag2StoredGeneration?> recoverAfterKilledUncommittedDriftDaoWrite({
  required String fixturePath,
  required String databasePath,
  required String projectId,
  required String declarationIdentity,
  bool indexSearch = false,
}) async {
  final readyFile = File('$databasePath.crash-ready');
  if (readyFile.existsSync()) {
    readyFile.deleteSync();
  }
  final process = await _startDriftDaoReplayChild([
    '--crash-uncommitted',
    '--fixture',
    File(fixturePath).absolute.path,
    '--db',
    File(databasePath).absolute.path,
    '--ready-file',
    readyFile.absolute.path,
    if (indexSearch) '--index-search',
  ]);
  final stderrBuffer = StringBuffer();
  process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
  process.stdout.listen((_) {});
  var exited = false;
  final exitFuture = process.exitCode.then((code) {
    exited = true;
    return code;
  });
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!readyFile.existsSync()) {
    if (exited) {
      throw StateError(
        'crash child exited before writing ready: $stderrBuffer',
      );
    }
    if (DateTime.now().isAfter(deadline)) {
      process.kill(ProcessSignal.sigkill);
      await exitFuture;
      throw StateError('crash child timed out before ready: $stderrBuffer');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  process.kill(ProcessSignal.sigkill);
  await exitFuture;
  final recovered = Rag2DriftDaoGenerationStore.open(
    databasePath: databasePath,
    projectId: projectId,
  );
  try {
    return await recovered.read(declarationIdentity);
  } finally {
    await recovered.close();
  }
}

Future<void> applyRag2DriftDaoSnapshotInChild({
  required String fixturePath,
  required String databasePath,
  required int snapshotIndex,
}) async {
  final process = await _startDriftDaoReplayChild([
    '--apply-once',
    '--fixture',
    File(fixturePath).absolute.path,
    '--db',
    File(databasePath).absolute.path,
    '--snapshot-index',
    '$snapshotIndex',
  ]);
  final stderrBuffer = StringBuffer();
  final stdoutBuffer = StringBuffer();
  process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
  process.stdout.transform(utf8.decoder).listen(stdoutBuffer.write);
  final code = await process.exitCode;
  if (code != 0) {
    throw StateError(
      'apply-once child exited $code: $stderrBuffer$stdoutBuffer',
    );
  }
}

Future<Process> _startDriftDaoReplayChild(List<String> arguments) {
  return Process.start(_driftDaoDartExecutable(), [
    '--disable-dart-dev',
    'tool/rag2_drift_dao_generation_store.dart',
    ...arguments,
  ], workingDirectory: Directory.current.path);
}

String _driftDaoDartExecutable() {
  final executableName = Platform.isWindows ? 'dart.exe' : 'dart';
  final flutterRoots = <String>[
    Directory.current.uri.resolve('.fvm/flutter_sdk/').toFilePath(),
    if ((Platform.environment['FLUTTER_ROOT'] ?? '').trim().isNotEmpty)
      Platform.environment['FLUTTER_ROOT']!.trim(),
  ];
  for (final flutterRoot in flutterRoots) {
    final candidate = File.fromUri(
      Directory(
        flutterRoot,
      ).uri.resolve('bin/cache/dart-sdk/bin/$executableName'),
    );
    if (candidate.existsSync()) {
      return candidate.path;
    }
  }
  final which = Process.runSync('which', [executableName]);
  if (which.exitCode == 0) {
    final path = (which.stdout as String).trim();
    if (path.isNotEmpty && File(path).existsSync()) {
      return path;
    }
  }
  return executableName;
}
