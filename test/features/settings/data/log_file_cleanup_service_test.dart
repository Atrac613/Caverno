import 'dart:io';

import 'package:caverno/core/services/tool_approval_audit_log.dart';
import 'package:caverno/core/utils/app_log_file.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/settings/data/log_file_cleanup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late LogFileCleanupService service;

  setUp(() {
    root = Directory.systemTemp.createTempSync('log_cleanup_');
    service = LogFileCleanupService(
      sessionLogStore: LlmSessionLogStore(
        rootDirectoryProvider: () async =>
            Directory('${root.path}/session_logs'),
      ),
      approvalAuditLog: ToolApprovalAuditLog(
        rootDirectoryProvider: () async => root,
      ),
      appLogFile: AppLogFile.forDirectory(Directory('${root.path}/app_logs')),
      enabled: true,
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  File seed(String relativePath, String contents) {
    final file = File('${root.path}/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    return file;
  }

  test('reports usage per target and ignores foreign files', () async {
    seed('session_logs/chat/a.jsonl', '{"a":1}\n');
    seed('session_logs/coding/b.jsonl.1', '{"b":2}\n');
    seed('session_logs/chat/notes.txt', 'ignored');
    seed('approval_audit/2026-09-09.jsonl', '{"c":3}\n');
    seed('app_logs/2026-09-09.log', 'line\n');

    final sessions = await service.usage(LogFileTarget.llmSessionLogs);
    expect(sessions.fileCount, 2, reason: 'rotated siblings count, .txt does not');
    expect(sessions.totalBytes, greaterThan(0));
    expect((await service.usage(LogFileTarget.approvalAudit)).fileCount, 1);
    expect((await service.usage(LogFileTarget.appLogFile)).fileCount, 1);
  });

  test('reports an empty target that was never written', () async {
    for (final target in LogFileTarget.values) {
      expect((await service.usage(target)).isEmpty, isTrue, reason: '$target');
    }
  });

  test('deletes only the requested target and keeps the directory', () async {
    seed('session_logs/chat/a.jsonl', '{"a":1}\n');
    seed('approval_audit/2026-09-09.jsonl', '{"c":3}\n');
    final foreign = seed('session_logs/chat/notes.txt', 'ignored');

    expect(await service.deleteAll(LogFileTarget.llmSessionLogs), 1);

    expect((await service.usage(LogFileTarget.llmSessionLogs)).isEmpty, isTrue);
    // The audit trail is a separate opt-out, so it must survive.
    expect((await service.usage(LogFileTarget.approvalAudit)).fileCount, 1);
    expect(foreign.existsSync(), isTrue);
    expect(
      Directory('${root.path}/session_logs/chat').existsSync(),
      isTrue,
      reason: 'directories keep their owner-only permissions',
    );
  });

  test('deleting nothing reports zero rather than throwing', () async {
    for (final target in LogFileTarget.values) {
      expect(await service.deleteAll(target), 0, reason: '$target');
    }
  });

  test('defaults to a no-op under flutter test', () async {
    // Guards the developer's real ~/.caverno corpus against any widget test
    // that mounts the Logging page.
    final guarded = LogFileCleanupService(
      sessionLogStore: LlmSessionLogStore(
        rootDirectoryProvider: () async =>
            Directory('${root.path}/session_logs'),
      ),
      approvalAuditLog: ToolApprovalAuditLog(
        rootDirectoryProvider: () async => root,
      ),
      appLogFile: AppLogFile.forDirectory(Directory('${root.path}/app_logs')),
    );
    seed('session_logs/chat/a.jsonl', '{"a":1}\n');

    expect((await guarded.usage(LogFileTarget.llmSessionLogs)).isEmpty, isTrue);
    expect(await guarded.deleteAll(LogFileTarget.llmSessionLogs), 0);
    expect(
      File('${root.path}/session_logs/chat/a.jsonl').existsSync(),
      isTrue,
    );
  });

  test('app log writes resume after a delete', () async {
    final sink = AppLogFile.forDirectory(Directory('${root.path}/app_logs'))
      ..setFileLoggingEnabled(true)
      ..write('before');
    final cleanup = LogFileCleanupService(
      sessionLogStore: LlmSessionLogStore(
        rootDirectoryProvider: () async =>
            Directory('${root.path}/session_logs'),
      ),
      approvalAuditLog: ToolApprovalAuditLog(
        rootDirectoryProvider: () async => root,
      ),
      appLogFile: sink,
      enabled: true,
    );

    expect(await cleanup.deleteAll(LogFileTarget.appLogFile), 1);
    expect((await cleanup.usage(LogFileTarget.appLogFile)).isEmpty, isTrue);

    // The cached day-file was dropped, so this re-creates the file through the
    // permission-hardening path instead of appending to a deleted handle.
    sink.write('after');

    final files = Directory('${root.path}/app_logs')
        .listSync()
        .whereType<File>()
        .toList();
    expect(files, hasLength(1));
    final contents = files.single.readAsStringSync();
    expect(contents, contains('after'));
    expect(contents, isNot(contains('before')));
  });
}
