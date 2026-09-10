import 'dart:io';

import 'package:caverno/core/security/sensitive_file_permissions.dart';
import 'package:caverno/core/utils/app_log_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('caverno_app_log_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  List<File> logFiles(Directory directory) =>
      directory.listSync().whereType<File>().toList();

  test('writes one timestamped line per message', () {
    final sink = AppLogFile.forDirectory(tempDir)
      ..write('[ChatNotifier] Waiting for pending tool executions: 2')
      ..write('[Workflow] Task proposal ready');

    expect(sink, isNotNull);
    final logs = logFiles(tempDir);
    expect(logs, hasLength(1), reason: 'one file per day');
    expect(logs.single.path, endsWith('.log'));

    final lines = logs.single.readAsLinesSync();
    expect(lines, hasLength(2));
    expect(
      lines.first,
      matches(
        RegExp(
          r'^\d{2}:\d{2}:\d{2}\.\d{3} \[ChatNotifier\] '
          r'Waiting for pending tool executions: 2$',
        ),
      ),
    );
    expect(lines.last, endsWith('[Workflow] Task proposal ready'));
  });

  test('each line is on disk immediately', () {
    final sink = AppLogFile.forDirectory(tempDir);
    sink.write('first');
    expect(
      logFiles(tempDir).single.readAsStringSync(),
      contains('first'),
      reason:
          'a hung isolate never flushes later, so the line must already be '
          'durable when write returns',
    );
  });

  test('redacts credentials before writing to disk', () {
    const apiKey = 'sk-1234567890abcdefghijklmnop';
    const bearerToken = 'secret-bearer-token-123456';
    const privateKey = '''-----BEGIN PRIVATE KEY-----
private-key-material
-----END PRIVATE KEY-----''';

    AppLogFile.forDirectory(
      tempDir,
    ).write('Authorization: Bearer $bearerToken\n$apiKey\n$privateKey');

    final content = logFiles(tempDir).single.readAsStringSync();
    expect(content, isNot(contains(bearerToken)));
    expect(content, isNot(contains(apiKey)));
    expect(content, isNot(contains('private-key-material')));
    expect(content, contains('Authorization: [redacted]'));
    expect(content, contains('sk-[redacted]'));
    expect(content, contains('[redacted-private-key]'));
  });

  test('a missing directory is created on demand', () {
    final nested = Directory('${tempDir.path}/deeper/still');
    AppLogFile.forDirectory(nested).write('created on demand');

    expect(nested.existsSync(), isTrue);
    expect(logFiles(nested), hasLength(1));
  });

  test('hardens the log directory and existing and new log files', () async {
    if (!SensitiveFilePermissions.isSupported) return;

    final existing = File('${tempDir.path}/2999-01-01.log')
      ..writeAsStringSync('existing\n');
    expect((await Process.run('chmod', ['755', tempDir.path])).exitCode, 0);
    expect((await Process.run('chmod', ['644', existing.path])).exitCode, 0);

    AppLogFile.forDirectory(tempDir).write('fresh');

    expect(FileStat.statSync(tempDir.path).mode & 0x1ff, 0x1c0);
    for (final file in logFiles(tempDir)) {
      expect(FileStat.statSync(file.path).mode & 0x1ff, 0x180);
    }
  });

  test('an unusable destination never throws', () {
    final blocked = '${tempDir.path}/blocked';
    File(blocked).writeAsStringSync('not a directory');
    final sink = AppLogFile.forDirectory(Directory(blocked));

    expect(
      () => sink
        ..write('ignored')
        ..write('still ignored'),
      returnsNormally,
      reason: 'logging must never become a second failure',
    );
  });

  test('files older than the retention window are pruned', () {
    final stale = File('${tempDir.path}/2000-01-01.log')
      ..writeAsStringSync('old\n');
    final fresh = File(
      '${tempDir.path}/'
      '${DateTime.now().toIso8601String().substring(0, 10)}.log',
    );

    AppLogFile.forDirectory(tempDir).write('fresh');

    expect(stale.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
    expect(logFiles(tempDir), hasLength(1));
  });

  test('a non-log file in the directory is left alone', () {
    final unrelated = File('${tempDir.path}/notes.txt')
      ..writeAsStringSync('keep me');

    AppLogFile.forDirectory(tempDir).write('fresh');

    expect(unrelated.existsSync(), isTrue);
  });

  test('a disabled sink writes nothing and re-enabling resumes', () {
    final sink = AppLogFile.forDirectory(tempDir)
      ..setFileLoggingEnabled(false)
      ..write('suppressed');

    expect(logFiles(tempDir), isEmpty);

    sink
      ..setFileLoggingEnabled(true)
      ..write('resumed');

    expect(logFiles(tempDir), hasLength(1));
    expect(
      logFiles(tempDir).single.readAsStringSync(),
      contains('resumed'),
    );
  });

  test('a bound directory is where the sink writes', () {
    // The reason this exists: the sink's own fallback is $HOME/.caverno/app_logs,
    // a desktop path. On iOS and Android HOME is the sandbox root, the first
    // write threw, and the sink latched disabled -- so a device produced no log
    // at all, which is exactly where one is needed.
    final sink = AppLogFile.instance..bindDirectory(tempDir);
    addTearDown(() => sink.bindDirectory(Directory.systemTemp));

    sink.write('[ApprovalNotification] action caverno_approve');

    final files = logFiles(tempDir);
    expect(files, hasLength(1));
    expect(
      files.single.readAsStringSync(),
      contains('[ApprovalNotification] action caverno_approve'),
    );
  });

  test('rebinding moves the next line rather than the cached file', () {
    final second = Directory.systemTemp.createTempSync('caverno_app_log_2_');
    addTearDown(() {
      if (second.existsSync()) second.deleteSync(recursive: true);
    });
    final sink = AppLogFile.instance..bindDirectory(tempDir);
    addTearDown(() => sink.bindDirectory(Directory.systemTemp));

    sink.write('first');
    sink.bindDirectory(second);
    sink.write('second');

    expect(logFiles(tempDir).single.readAsStringSync(), contains('first'));
    expect(logFiles(second).single.readAsStringSync(), contains('second'));
  });
}
