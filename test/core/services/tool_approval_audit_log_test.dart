import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/tool_approval_audit_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('approval_audit_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  ToolApprovalAuditLog buildLog() =>
      ToolApprovalAuditLog(rootDirectoryProvider: () async => tempDir);

  List<Map<String, dynamic>> readEntries() {
    final auditDir = Directory('${tempDir.path}/approval_audit');
    final files = auditDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.jsonl'))
        .toList();
    return files
        .expand((file) => file.readAsLinesSync())
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
  }

  test('records an allowed auto-review verdict as a JSON line', () async {
    await buildLog().record(
      tool: 'browser_click',
      actionKind: 'browser_click',
      domain: 'browser',
      mode: 'autoReview',
      outcome: 'allowed',
      decisionSource: 'auto_review',
      rationale: 'User asked to open the link.',
      riskLevel: 'low',
      arguments: const {'ref': 7, 'selector': '#next'},
      workspaceMode: 'chat',
      sessionId: 'session-1',
    );

    final entries = readEntries();
    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry['tool'], 'browser_click');
    expect(entry['outcome'], 'allowed');
    expect(entry['decisionSource'], 'auto_review');
    expect(entry['rationale'], 'User asked to open the link.');
    expect(entry['riskLevel'], 'low');
    expect(entry['mode'], 'autoReview');
    expect(entry['domain'], 'browser');
    expect(entry['sessionId'], 'session-1');
    expect((entry['arguments'] as Map)['selector'], '#next');
    expect(entry['timestamp'], isA<String>());
  });

  test('redacts secret-bearing argument values', () async {
    await buildLog().record(
      tool: 'browser_fill',
      actionKind: 'browser_fill',
      domain: 'browser',
      mode: 'fullAccess',
      outcome: 'allowed',
      decisionSource: 'full_access',
      arguments: const {
        'selector': '#password',
        'value': 'hunter2hunter2',
        'reason': 'log in',
      },
    );

    final args = readEntries().single['arguments'] as Map;
    // The selector and reason stay; the secret value is replaced with a marker.
    expect(args['selector'], '#password');
    expect(args['reason'], 'log in');
    expect(args['value'], '[redacted len=14]');
  });

  test('appends multiple decisions to the same day file', () async {
    final log = buildLog();
    await log.record(
      tool: 'ssh_execute_command',
      actionKind: 'ssh_execute_command',
      domain: 'connection',
      mode: 'autoReview',
      outcome: 'denied',
      decisionSource: 'auto_review',
      rationale: 'Destructive command.',
    );
    await log.record(
      tool: 'git_execute_command',
      actionKind: 'git_execute_command',
      domain: 'coding',
      mode: 'fullAccess',
      outcome: 'allowed',
      decisionSource: 'full_access',
    );

    final entries = readEntries();
    expect(entries, hasLength(2));
    expect(entries.map((e) => e['outcome']), containsAll(['denied', 'allowed']));
  });

  test('prunes day-files older than the retention window', () async {
    final auditDir = Directory('${tempDir.path}/approval_audit')
      ..createSync(recursive: true);
    File('${auditDir.path}/2000-01-01.jsonl').writeAsStringSync('{"old":1}\n');
    File(
      '${auditDir.path}/2999-01-01.jsonl',
    ).writeAsStringSync('{"future":1}\n');

    final log = ToolApprovalAuditLog(
      rootDirectoryProvider: () async => tempDir,
      retentionPolicy: const ToolApprovalAuditRetentionPolicy(
        maxAge: Duration(days: 30),
        maxFiles: null,
      ),
    );
    await log.record(
      tool: 'git_execute_command',
      actionKind: 'git_execute_command',
      domain: 'coding',
      mode: 'fullAccess',
      outcome: 'allowed',
    );

    final names = auditDir
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toList();
    expect(names, isNot(contains('2000-01-01.jsonl')));
    // A far-future stamp is not yet expired, so it is retained.
    expect(names, contains('2999-01-01.jsonl'));
    // Today's freshly written file is also present.
    expect(names.any((name) => name != '2999-01-01.jsonl'), isTrue);
  });

  test('keeps only the most recent day-files when over the file cap', () async {
    final auditDir = Directory('${tempDir.path}/approval_audit')
      ..createSync(recursive: true);
    for (final day in [
      '2001-01-01',
      '2001-01-02',
      '2001-01-03',
      '2001-01-04',
    ]) {
      File('${auditDir.path}/$day.jsonl').writeAsStringSync('{"d":"$day"}\n');
    }

    final log = ToolApprovalAuditLog(
      rootDirectoryProvider: () async => tempDir,
      retentionPolicy: const ToolApprovalAuditRetentionPolicy(
        maxAge: null,
        maxFiles: 3,
      ),
    );
    await log.record(
      tool: 'browser_click',
      actionKind: 'browser_click',
      domain: 'browser',
      mode: 'fullAccess',
      outcome: 'allowed',
    );

    final names = auditDir
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toList();
    // Newest three survive: today's file plus the two most recent old ones.
    expect(names, hasLength(3));
    expect(names, contains('2001-01-04.jsonl'));
    expect(names, contains('2001-01-03.jsonl'));
    expect(names, isNot(contains('2001-01-02.jsonl')));
    expect(names, isNot(contains('2001-01-01.jsonl')));
  });

  test('no-ops under flutter test when no root is injected', () async {
    // The default constructor must not write into the developer's home dir
    // during tests; this call should be a silent no-op.
    await ToolApprovalAuditLog().record(
      tool: 'browser_click',
      actionKind: 'browser_click',
      domain: 'browser',
      mode: 'fullAccess',
      outcome: 'allowed',
    );
    // No exception, and our injected temp dir remains untouched.
    expect(Directory('${tempDir.path}/approval_audit').existsSync(), isFalse);
  });
}
