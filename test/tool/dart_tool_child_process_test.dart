import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/dart_tool_child_process.dart';

void main() {
  test('child arguments stay on dartvm so SIGKILL hits the writer', () {
    expect(
      dartToolChildArguments('tool/rag2_sqlite_durability_replay.dart', const [
        '--apply-once',
      ]),
      [
        '--disable-dart-dev',
        'tool/rag2_sqlite_durability_replay.dart',
        '--apply-once',
      ],
    );
  });

  test('resolveDartExecutable points at a real dart binary', () {
    final executable = resolveDartExecutable();
    expect(executable, isNotEmpty);
    final isBareName = executable == 'dart' || executable == 'dart.exe';
    expect(isBareName || File(executable).existsSync(), isTrue);
  });

  test('sqlite3 native library is available to crash children', () {
    final path = resolveSqlite3NativeLibraryPath();
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(
      path.contains('sqlite3'),
      isTrue,
      reason: 'expected a sqlite3 dylib, got $path',
    );
  });

  test('preload environment exposes the sqlite3 dylib to dartvm', () {
    const libraryPath = '/tmp/libsqlite3.so';
    final environment = nativeLibraryPreloadEnvironment(libraryPath);
    if (Platform.isLinux) {
      expect(environment['LD_PRELOAD'], libraryPath);
    } else if (Platform.isMacOS) {
      expect(environment['DYLD_INSERT_LIBRARIES'], libraryPath);
    } else if (Platform.isWindows) {
      expect(environment['PATH'], startsWith('/tmp'));
    }
  });

  test(
    'a dartvm child can open sqlite3 through the preloaded native library',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'dart-tool-child-sqlite3-',
      );
      addTearDown(() => output.deleteSync(recursive: true));
      final process = await startDartToolChild(
        scriptPath: 'tool/rag2_sqlite_durability_replay.dart',
        arguments: [
          '--apply-once',
          '--fixture',
          File('tool/fixtures/rag2_storage_replay/fixture.json').absolute.path,
          '--db',
          '${output.path}/store.sqlite',
          '--snapshot-index',
          '0',
        ],
      );
      final stderr = process.stderr.transform(utf8.decoder).join();
      final stdout = process.stdout.transform(utf8.decoder).join();
      final code = await process.exitCode;
      expect(
        code,
        0,
        reason: 'stderr: ${await stderr}\nstdout: ${await stdout}',
      );
      expect(File('${output.path}/store.sqlite').existsSync(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
