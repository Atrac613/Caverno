import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_knowledge_object_replay.dart';
import 'rag2_persistence_reopen_replay.dart';
import 'rag2_storage_replay.dart';

const rag2SqliteDurabilityContract = 'rag2-sqlite-durability-contract-v1';
const rag2SqliteStoreSchema = 'caverno_rag2_sqlite_generation_store';
const rag2SqliteStoreSchemaVersion = 1;
const rag2SqliteDurabilityReportSchema =
    'caverno_rag2_sqlite_durability_report';

Future<void> main(List<String> args) async {
  if (args.contains('--crash-uncommitted')) {
    exitCode = await runRag2SqliteCrashUncommittedChild(args);
    return;
  }
  if (args.contains('--apply-once')) {
    exitCode = await runRag2SqliteApplyOnceChild(args);
    return;
  }
  final options = Rag2SqliteDurabilityOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_sqlite_durability_replay.dart '
      '--fixture PATH --out-dir PATH\n'
      '       dart run tool/rag2_sqlite_durability_replay.dart '
      '--crash-uncommitted --fixture PATH --db PATH --ready-file PATH\n'
      '       dart run tool/rag2_sqlite_durability_replay.dart '
      '--apply-once --fixture PATH --db PATH --snapshot-index N',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2SqliteDurabilityReplay(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 SQLite durability replay failed: $error');
    exitCode = 65;
  }
}

Future<Rag2SqliteDurabilityReport> runRag2SqliteDurabilityReplay(
  Rag2SqliteDurabilityOptions options,
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

  final reopenDir = _freshDirectory('${options.storeRoot}/reopen');
  final reopenPath = '${reopenDir.path}/store.sqlite';
  final reopenStore = Rag2SqliteGenerationStore(
    databasePath: reopenPath,
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
  reopenStore.close();
  final reopened = Rag2SqliteGenerationStore(
    databasePath: reopenPath,
    projectId: fixture.projectId,
  );
  final reopenedGeneration = await reopened.read(declarationIdentity);
  final reopenedNoOp = await reopened.apply(
    declarationIdentity: declarationIdentity,
    snapshot: updated,
  );
  final hasFts5 = reopened.hasFts5Tables;
  reopened.close();
  final attestedTextPreserved =
      reopenedGeneration != null &&
      reopenedGeneration.generation == 2 &&
      reopenedGeneration.snapshot.snapshotHash == updated.snapshotHash &&
      reopenedGeneration.snapshot.chunks.any(
        (chunk) => chunk.content.contains('fixture-secret-alpha'),
      ) &&
      reopenedNoOp.decision == 'no_op' &&
      !hasFts5;

  final crashDir = _freshDirectory('${options.storeRoot}/crash');
  final crashPath = '${crashDir.path}/store.sqlite';
  final crashStore = Rag2SqliteGenerationStore(
    databasePath: crashPath,
    projectId: fixture.projectId,
  );
  await crashStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  crashStore.close();
  final recoveredGeneration = await recoverAfterKilledUncommittedWrite(
    fixturePath: options.fixturePath,
    databasePath: crashPath,
    projectId: fixture.projectId,
    declarationIdentity: declarationIdentity,
  );
  final crashRecovered =
      recoveredGeneration?.generation == 1 &&
      recoveredGeneration?.snapshot.snapshotHash == baseline.snapshotHash;

  final schemaDir = _freshDirectory('${options.storeRoot}/schema');
  final schemaPath = '${schemaDir.path}/store.sqlite';
  final schemaStore = Rag2SqliteGenerationStore(
    databasePath: schemaPath,
    projectId: fixture.projectId,
  );
  await schemaStore.apply(
    declarationIdentity: declarationIdentity,
    snapshot: baseline,
  );
  schemaStore.close();
  final mutated = sqlite3.open(schemaPath);
  mutated.execute(
    "UPDATE rag2_store_meta SET value = '2' WHERE key = 'schema_version'",
  );
  final mutatedVersion = mutated
      .select("SELECT value FROM rag2_store_meta WHERE key = 'schema_version'")
      .first['value'];
  mutated.close();
  var unsupportedSchemaRejected = false;
  try {
    await Rag2SqliteGenerationStore(
      databasePath: schemaPath,
      projectId: fixture.projectId,
    ).read(declarationIdentity);
  } on Rag2PersistenceException catch (error) {
    final check = sqlite3.open(schemaPath);
    unsupportedSchemaRejected =
        error.reason == 'unsupported_schema' &&
        check
                .select(
                  "SELECT value FROM rag2_store_meta WHERE key = 'schema_version'",
                )
                .first['value'] ==
            mutatedVersion;
    check.close();
  }

  final isolateDir = _freshDirectory('${options.storeRoot}/isolate');
  final isolatePath = '${isolateDir.path}/store.sqlite';
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
  final firstProject = Rag2SqliteGenerationStore(
    databasePath: isolatePath,
    projectId: 'persistence-project-a',
  );
  final secondProject = Rag2SqliteGenerationStore(
    databasePath: isolatePath,
    projectId: 'persistence-project-b',
  );
  await firstProject.apply(
    declarationIdentity: declarationIdentity,
    snapshot: firstSnapshot,
  );
  firstProject.close();
  await secondProject.apply(
    declarationIdentity: declarationIdentity,
    snapshot: secondSnapshot,
  );
  secondProject.close();
  final isolatedFirst = Rag2SqliteGenerationStore(
    databasePath: isolatePath,
    projectId: 'persistence-project-a',
  );
  final isolatedSecond = Rag2SqliteGenerationStore(
    databasePath: isolatePath,
    projectId: 'persistence-project-b',
  );
  final firstRead = await isolatedFirst.read(declarationIdentity);
  final secondRead = await isolatedSecond.read(declarationIdentity);
  isolatedFirst.close();
  isolatedSecond.close();
  final declarationIsolation =
      firstRead?.generation == 1 &&
      firstRead?.snapshot.snapshotHash == firstSnapshot.snapshotHash &&
      secondRead?.generation == 1 &&
      secondRead?.snapshot.snapshotHash == secondSnapshot.snapshotHash;

  var foreignSnapshotRejected = false;
  final foreignStore = Rag2SqliteGenerationStore(
    databasePath:
        '${_freshDirectory('${options.storeRoot}/foreign').path}/store.sqlite',
    projectId: 'persistence-project-a',
  );
  try {
    await foreignStore.apply(
      declarationIdentity: declarationIdentity,
      snapshot: baseline,
    );
  } on Rag2PersistenceException catch (error) {
    foreignSnapshotRejected = error.reason == 'persisted_identity_mismatch';
  } finally {
    foreignStore.close();
  }

  final report = Rag2SqliteDurabilityReport(
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
    '${outputDirectory.path}/rag2_sqlite_durability.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_sqlite_durability.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

final class Rag2SqliteDurabilityOptions {
  const Rag2SqliteDurabilityOptions({
    required this.fixturePath,
    required this.outDir,
    required this.storeRoot,
  });

  final String fixturePath;
  final String outDir;
  final String storeRoot;

  static Rag2SqliteDurabilityOptions? parse(List<String> args) {
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
    return Rag2SqliteDurabilityOptions(
      fixturePath: fixturePath,
      outDir: outDir,
      storeRoot: storeRoot ?? '$outDir/store',
    );
  }
}

final class Rag2SqliteGenerationStore {
  Rag2SqliteGenerationStore({
    required this.databasePath,
    required this.projectId,
  });

  final String databasePath;
  final String projectId;
  Database? _database;

  String get projectIdentity =>
      rag2ExplicitSourceRootsProjectIdentity(projectId);

  bool get hasFts5Tables {
    final rows = _open().select(
      "SELECT sql FROM sqlite_master WHERE type IN ('table', 'view')",
    );
    return rows.any((row) {
      final sql = row['sql'];
      return sql is String && sql.toLowerCase().contains('fts5');
    });
  }

  Future<Rag2StoredGeneration?> read(String declarationIdentity) async {
    return _readLocked(_open(), declarationIdentity);
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
    _database?.close();
    _database = null;
  }

  Database _open() {
    final existing = _database;
    if (existing != null) {
      return existing;
    }
    File(databasePath).parent.createSync(recursive: true);
    final database = sqlite3.open(databasePath);
    try {
      database.execute('PRAGMA busy_timeout = 30000');
      database.execute('PRAGMA synchronous = FULL');
      database.select('PRAGMA journal_mode = DELETE');
      database.execute('BEGIN IMMEDIATE');
      try {
        _ensureSchema(database);
        database.execute('COMMIT');
      } on Object {
        try {
          database.execute('ROLLBACK');
        } on Object {
          // The connection may already have rolled back.
        }
        rethrow;
      }
    } on Object {
      database.close();
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
    if (row['schema_name'] != rag2SqliteStoreSchema ||
        _sqliteInt(row['schema_version']) != rag2SqliteStoreSchemaVersion ||
        row['contract'] != rag2SqliteDurabilityContract) {
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
        rag2SqliteStoreSchema,
        rag2SqliteStoreSchemaVersion,
        rag2SqliteDurabilityContract,
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

  void _ensureSchema(Database database) {
    final tables = database
        .select("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((row) => row['name'] as String)
        .toSet();
    if (!tables.contains('rag2_store_meta')) {
      if (tables.contains('rag2_generations')) {
        throw const Rag2PersistenceException('unsupported_schema');
      }
      database.execute(
        'CREATE TABLE rag2_store_meta ('
        'key TEXT PRIMARY KEY NOT NULL, '
        'value TEXT NOT NULL)',
      );
      database.execute(
        'CREATE TABLE rag2_generations ('
        'project_identity TEXT NOT NULL, '
        'declaration_identity TEXT NOT NULL, '
        'schema_name TEXT NOT NULL, '
        'schema_version INTEGER NOT NULL, '
        'contract TEXT NOT NULL, '
        'project_id TEXT NOT NULL, '
        'generation INTEGER NOT NULL, '
        'snapshot_hash TEXT NOT NULL, '
        'payload TEXT NOT NULL, '
        'PRIMARY KEY (project_identity, declaration_identity))',
      );
      database.execute(
        'INSERT INTO rag2_store_meta(key, value) VALUES (?, ?), (?, ?), (?, ?)',
        [
          'schema_name',
          rag2SqliteStoreSchema,
          'schema_version',
          '$rag2SqliteStoreSchemaVersion',
          'contract',
          rag2SqliteDurabilityContract,
        ],
      );
      return;
    }
    final metadata = {
      for (final row in database.select(
        'SELECT key, value FROM rag2_store_meta',
      ))
        row['key'] as String: row['value'] as String,
    };
    if (metadata['schema_name'] != rag2SqliteStoreSchema ||
        metadata['schema_version'] != '$rag2SqliteStoreSchemaVersion' ||
        metadata['contract'] != rag2SqliteDurabilityContract) {
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

Future<int> runRag2SqliteCrashUncommittedChild(List<String> args) async {
  final options = Rag2SqliteCrashChildOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_sqlite_durability_replay.dart '
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
    final store = Rag2SqliteGenerationStore(
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
    stderr.writeln('RAG2 SQLite crash child failed: $error');
    return 65;
  }
}

Future<int> runRag2SqliteApplyOnceChild(List<String> args) async {
  final options = Rag2SqliteApplyOnceOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_sqlite_durability_replay.dart '
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
    final store = Rag2SqliteGenerationStore(
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
    stderr.writeln('RAG2 SQLite apply-once child failed: $error');
    return 65;
  }
}

Future<Rag2StoredGeneration?> recoverAfterKilledUncommittedWrite({
  required String fixturePath,
  required String databasePath,
  required String projectId,
  required String declarationIdentity,
}) async {
  final readyFile = File('$databasePath.crash-ready');
  if (readyFile.existsSync()) {
    readyFile.deleteSync();
  }
  final process = await _startSqliteReplayChild([
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
  final recovered = Rag2SqliteGenerationStore(
    databasePath: databasePath,
    projectId: projectId,
  );
  try {
    return recovered.read(declarationIdentity);
  } finally {
    recovered.close();
  }
}

Future<void> applyRag2SqliteSnapshotInChild({
  required String fixturePath,
  required String databasePath,
  required int snapshotIndex,
}) async {
  final process = await _startSqliteReplayChild([
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

Future<Process> _startSqliteReplayChild(List<String> arguments) {
  return Process.start(_sqliteDartExecutable(), [
    '--disable-dart-dev',
    'tool/rag2_sqlite_durability_replay.dart',
    ...arguments,
  ], workingDirectory: Directory.current.path);
}

String _sqliteDartExecutable() {
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

final class Rag2SqliteCrashChildOptions {
  const Rag2SqliteCrashChildOptions({
    required this.fixturePath,
    required this.databasePath,
    required this.readyFilePath,
  });

  final String fixturePath;
  final String databasePath;
  final String readyFilePath;

  static Rag2SqliteCrashChildOptions? parse(List<String> args) {
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
    return Rag2SqliteCrashChildOptions(
      fixturePath: fixturePath,
      databasePath: databasePath,
      readyFilePath: readyFilePath,
    );
  }
}

final class Rag2SqliteApplyOnceOptions {
  const Rag2SqliteApplyOnceOptions({
    required this.fixturePath,
    required this.databasePath,
    required this.snapshotIndex,
  });

  final String fixturePath;
  final String databasePath;
  final int snapshotIndex;

  static Rag2SqliteApplyOnceOptions? parse(List<String> args) {
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
    return Rag2SqliteApplyOnceOptions(
      fixturePath: fixturePath,
      databasePath: databasePath,
      snapshotIndex: snapshotIndex,
    );
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

final class Rag2SqliteDurabilityReport {
  const Rag2SqliteDurabilityReport({
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
    'schemaName': rag2SqliteDurabilityReportSchema,
    'schemaVersion': 1,
    'contract': rag2SqliteDurabilityContract,
    'evaluationMode': 'isolated_sqlite_durability_replay',
    'contractDecision': contractPassed ? 'go' : 'no_go',
    'sqliteDurabilityDecision': contractPassed ? 'go' : 'no_go',
    'driftDecision': 'not_selected',
    'fts5Decision': 'not_selected',
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
      '# RAG2 SQLite Durability\n\n'
      '- Contract: `$rag2SqliteDurabilityContract`\n'
      '- Contract decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- SQLite durability decision: `${contractPassed ? 'go' : 'no_go'}`\n'
      '- Drift decision: `not_selected`\n'
      '- FTS5 decision: `not_selected`\n'
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
