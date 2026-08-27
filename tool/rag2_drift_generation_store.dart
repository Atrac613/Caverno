import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/rag2_drift_schema.dart';
import 'package:sqlite3/sqlite3.dart';

import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_knowledge_object_replay.dart';
import 'rag2_persistence_reopen_replay.dart';
import 'rag2_storage_replay.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--crash-uncommitted')) {
    exitCode = await runRag2DriftCrashUncommittedChild(args);
    return;
  }
  if (args.contains('--apply-once')) {
    exitCode = await runRag2DriftApplyOnceChild(args);
    return;
  }
  stderr.writeln(
    'Usage: dart run tool/rag2_drift_generation_store.dart '
    '--crash-uncommitted --fixture PATH --db PATH --ready-file PATH\n'
    '       dart run tool/rag2_drift_generation_store.dart '
    '--apply-once --fixture PATH --db PATH --snapshot-index N',
  );
  exitCode = 64;
}

final class Rag2DriftGenerationStore {
  Rag2DriftGenerationStore({
    required this.databasePath,
    required this.projectId,
  });

  final String databasePath;
  final String projectId;
  Database? _database;

  String get projectIdentity =>
      rag2ExplicitSourceRootsProjectIdentity(projectId);

  Future<Rag2StoredGeneration?> read(String declarationIdentity) async {
    final database = _open();
    _ensureHostedSchema(database);
    return _readLocked(database, declarationIdentity);
  }

  Future<Rag2StorageApplyResult> apply({
    required String declarationIdentity,
    required Rag2KnowledgeSnapshot snapshot,
    Rag2BeforeGenerationCommit? beforeCommit,
    bool commit = true,
  }) async {
    ensureRag2SnapshotMatchesProject(projectId: projectId, snapshot: snapshot);
    final database = _open();
    database.execute('BEGIN IMMEDIATE');
    try {
      _ensureHostedSchema(database);
      final memory = Rag2InMemoryGenerationStore();
      final previous = _readLocked(database, declarationIdentity);
      if (previous != null) {
        memory.restore(
          declarationIdentity: declarationIdentity,
          generation: previous,
        );
      }
      final result = memory.apply(
        declarationIdentity: declarationIdentity,
        snapshot: snapshot,
        beforeCommit: (pending) {
          _upsert(database, declarationIdentity, pending);
          beforeCommit?.call(pending);
        },
      );
      if (!commit) {
        return result;
      }
      if (result.decision == 'applied') {
        database.execute('COMMIT');
      } else {
        database.execute('ROLLBACK');
      }
      return result;
    } on Object {
      try {
        database.execute('ROLLBACK');
      } on Object {
        // The connection may already have rolled back.
      }
      rethrow;
    }
  }

  Future<void> hangAfterUncommittedApply({
    required String declarationIdentity,
    required Rag2KnowledgeSnapshot snapshot,
    required File readyFile,
  }) async {
    final result = await apply(
      declarationIdentity: declarationIdentity,
      snapshot: snapshot,
      commit: false,
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

  void close() {
    _database?.dispose();
    _database = null;
  }

  Database _open() {
    final existing = _database;
    if (existing != null) {
      return existing;
    }
    final database = sqlite3.open(databasePath);
    try {
      database.execute('PRAGMA busy_timeout = 30000');
      database.execute('PRAGMA synchronous = FULL');
      database.select('PRAGMA journal_mode = DELETE');
    } on Object {
      database.dispose();
      rethrow;
    }
    _database = database;
    return database;
  }

  Rag2StoredGeneration? _readLocked(
    Database database,
    String declarationIdentity,
  ) {
    final rows = database.select(
      'SELECT project_identity, declaration_identity, schema_name, '
      'schema_version, contract, project_id, generation, snapshot_hash, '
      'payload FROM rag2_generations '
      'WHERE project_identity = ? AND declaration_identity = ?',
      [projectIdentity, declarationIdentity],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _generationFromRow(
      row: rows.first,
      declarationIdentity: declarationIdentity,
    );
  }

  Rag2StoredGeneration _generationFromRow({
    required Row row,
    required String declarationIdentity,
  }) {
    if (row['schema_name'] != rag2DriftStoreSchema ||
        _sqliteInt(row['schema_version']) != rag2DriftStoreSchemaVersion ||
        row['contract'] != rag2DriftAdditiveSchemaContract) {
      throw const Rag2PersistenceException('unsupported_schema');
    }
    if (row['project_id'] != projectId ||
        row['project_identity'] != projectIdentity ||
        row['declaration_identity'] != declarationIdentity) {
      throw const Rag2PersistenceException('persisted_identity_mismatch');
    }
    final decoded = decodeRag2PersistedGeneration(
      bytes: row['payload'] as String,
      expectedProjectId: projectId,
      expectedDeclarationIdentity: declarationIdentity,
    );
    if (_sqliteInt(row['generation']) != decoded.generation) {
      throw const Rag2PersistenceException('persisted_identity_mismatch');
    }
    if (row['snapshot_hash'] != decoded.snapshot.snapshotHash) {
      throw const Rag2PersistenceException('persisted_hash_mismatch');
    }
    return decoded;
  }

  void _upsert(
    Database database,
    String declarationIdentity,
    Rag2StoredGeneration pending,
  ) {
    database.execute(
      'INSERT INTO rag2_generations ('
      'project_identity, declaration_identity, schema_name, schema_version, '
      'contract, project_id, generation, snapshot_hash, payload'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(project_identity, declaration_identity) DO UPDATE SET '
      'schema_name = excluded.schema_name, '
      'schema_version = excluded.schema_version, '
      'contract = excluded.contract, '
      'project_id = excluded.project_id, '
      'generation = excluded.generation, '
      'snapshot_hash = excluded.snapshot_hash, '
      'payload = excluded.payload',
      [
        projectIdentity,
        declarationIdentity,
        rag2DriftStoreSchema,
        rag2DriftStoreSchemaVersion,
        rag2DriftAdditiveSchemaContract,
        projectId,
        pending.generation,
        pending.snapshot.snapshotHash,
        encodeRag2PersistedGeneration(
          projectId: projectId,
          declarationIdentity: declarationIdentity,
          generation: pending,
        ),
      ],
    );
  }

  void _ensureHostedSchema(Database database) {
    final tables = database
        .select("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((row) => row['name'] as String)
        .toSet();
    if (!tables.contains('rag2_store_meta') ||
        !tables.contains('rag2_generations') ||
        !tables.contains('embeddings')) {
      throw const Rag2PersistenceException('unsupported_schema');
    }
    final metadata = {
      for (final row in database.select(
        'SELECT key, value FROM rag2_store_meta',
      ))
        row['key'] as String: row['value'] as String,
    };
    if (metadata['schema_name'] != rag2DriftStoreSchema ||
        metadata['schema_version'] != '$rag2DriftStoreSchemaVersion' ||
        metadata['contract'] != rag2DriftAdditiveSchemaContract) {
      throw const Rag2PersistenceException('unsupported_schema');
    }
  }
}

int _sqliteInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is BigInt) {
    return value.toInt();
  }
  throw const Rag2PersistenceException('persisted_record_invalid');
}

Future<int> runRag2DriftCrashUncommittedChild(List<String> args) async {
  final options = Rag2DriftCrashChildOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_drift_generation_store.dart '
      '--crash-uncommitted --fixture PATH --db PATH --ready-file PATH',
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
    final store = Rag2DriftGenerationStore(
      databasePath: options.databasePath,
      projectId: fixture.projectId,
    );
    await store.hangAfterUncommittedApply(
      declarationIdentity: declarationIdentity,
      snapshot: updated,
      readyFile: File(options.readyFilePath),
    );
    return 0;
  } on Object catch (error) {
    stderr.writeln('RAG2 Drift crash child failed: $error');
    return 65;
  }
}

Future<int> runRag2DriftApplyOnceChild(List<String> args) async {
  final options = Rag2DriftApplyOnceOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_drift_generation_store.dart '
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
    final store = Rag2DriftGenerationStore(
      databasePath: options.databasePath,
      projectId: fixture.projectId,
    );
    try {
      await store.apply(
        declarationIdentity: declarationIdentity,
        snapshot: snapshot,
      );
    } finally {
      store.close();
    }
    return 0;
  } on Object catch (error) {
    stderr.writeln('RAG2 Drift apply-once child failed: $error');
    return 65;
  }
}

Future<Rag2StoredGeneration?> recoverAfterKilledUncommittedDriftWrite({
  required String fixturePath,
  required String databasePath,
  required String projectId,
  required String declarationIdentity,
}) async {
  final readyFile = File('$databasePath.crash-ready');
  if (readyFile.existsSync()) {
    readyFile.deleteSync();
  }
  final process = await _startDriftReplayChild([
    '--crash-uncommitted',
    '--fixture',
    File(fixturePath).absolute.path,
    '--db',
    File(databasePath).absolute.path,
    '--ready-file',
    readyFile.absolute.path,
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
  final recovered = Rag2DriftGenerationStore(
    databasePath: databasePath,
    projectId: projectId,
  );
  try {
    return recovered.read(declarationIdentity);
  } finally {
    recovered.close();
  }
}

Future<void> applyRag2DriftSnapshotInChild({
  required String fixturePath,
  required String databasePath,
  required int snapshotIndex,
}) async {
  final process = await _startDriftReplayChild([
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

Future<Process> _startDriftReplayChild(List<String> arguments) {
  return Process.start(_driftDartExecutable(), [
    '--disable-dart-dev',
    'tool/rag2_drift_generation_store.dart',
    ...arguments,
  ], workingDirectory: Directory.current.path);
}

String _driftDartExecutable() {
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

final class Rag2DriftCrashChildOptions {
  const Rag2DriftCrashChildOptions({
    required this.fixturePath,
    required this.databasePath,
    required this.readyFilePath,
  });

  final String fixturePath;
  final String databasePath;
  final String readyFilePath;

  static Rag2DriftCrashChildOptions? parse(List<String> args) {
    String? fixturePath;
    String? databasePath;
    String? readyFilePath;
    for (var index = 0; index < args.length; index++) {
      switch (args[index]) {
        case '--crash-uncommitted':
          continue;
        case '--fixture':
          if (index + 1 >= args.length) {
            return null;
          }
          fixturePath = args[++index];
        case '--db':
          if (index + 1 >= args.length) {
            return null;
          }
          databasePath = args[++index];
        case '--ready-file':
          if (index + 1 >= args.length) {
            return null;
          }
          readyFilePath = args[++index];
        default:
          return null;
      }
    }
    if (fixturePath == null || databasePath == null || readyFilePath == null) {
      return null;
    }
    return Rag2DriftCrashChildOptions(
      fixturePath: fixturePath,
      databasePath: databasePath,
      readyFilePath: readyFilePath,
    );
  }
}

final class Rag2DriftApplyOnceOptions {
  const Rag2DriftApplyOnceOptions({
    required this.fixturePath,
    required this.databasePath,
    required this.snapshotIndex,
  });

  final String fixturePath;
  final String databasePath;
  final int snapshotIndex;

  static Rag2DriftApplyOnceOptions? parse(List<String> args) {
    String? fixturePath;
    String? databasePath;
    int? snapshotIndex;
    for (var index = 0; index < args.length; index++) {
      switch (args[index]) {
        case '--apply-once':
          continue;
        case '--fixture':
          if (index + 1 >= args.length) {
            return null;
          }
          fixturePath = args[++index];
        case '--db':
          if (index + 1 >= args.length) {
            return null;
          }
          databasePath = args[++index];
        case '--snapshot-index':
          if (index + 1 >= args.length) {
            return null;
          }
          snapshotIndex = int.tryParse(args[++index]);
        default:
          return null;
      }
    }
    if (fixturePath == null || databasePath == null || snapshotIndex == null) {
      return null;
    }
    return Rag2DriftApplyOnceOptions(
      fixturePath: fixturePath,
      databasePath: databasePath,
      snapshotIndex: snapshotIndex,
    );
  }
}
