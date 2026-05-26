import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/remote_coding_p0_release_gate.dart';

void main() {
  test('blocks release when user-operated P0 evidence is missing', () {
    final result = buildRemoteCodingP0ReleaseGate(
      repoRoot: Directory.current,
      generatedAt: DateTime(2026, 5, 26, 12),
    );

    expect(result.status, 'blocked');
    expect(result.staticGates.where((gate) => !gate.isReady), isEmpty);
    expect(result.blockedGateIds, contains('real_device_matrix'));
    expect(result.blockedGateIds, contains('failure_ux_matrix'));
    expect(result.blockedGateIds, contains('release_signing_permissions'));
    expect(result.blockedGateIds, contains('data_protection_migration'));
    expect(result.toMarkdown(), contains('Remote Coding P0 Release Gate'));
  });

  test('passes when static checks and complete manual checklist are ready', () {
    final root = Directory.systemTemp.createTempSync(
      'remote_coding_p0_gate_test_',
    );
    addTearDown(() {
      root.deleteSync(recursive: true);
    });
    final checklist = remoteCodingP0ManualChecklistTemplate(
      generatedAt: DateTime(2026, 5, 26, 12),
    );
    final readyChecklist = _markAllBooleansReady(checklist);
    final checklistFile = File('${root.path}/manual_checklist.json')
      ..writeAsStringSync(const JsonEncoder().convert(readyChecklist));

    final result = buildRemoteCodingP0ReleaseGate(
      repoRoot: Directory.current,
      manualChecklistFile: checklistFile,
      generatedAt: DateTime(2026, 5, 26, 12),
    );

    expect(result.status, 'ready_for_remote_coding_p0_release');
    expect(result.blockedGateIds, isEmpty);
    expect(result.toJson()['schemaName'], 'remote_coding_p0_release_gate');
  });

  test('manual checklist template covers every P0 evidence section', () {
    final template = remoteCodingP0ManualChecklistTemplate(
      generatedAt: DateTime(2026, 5, 26, 12),
    );

    expect(template['realDeviceMatrix'], isA<Map<String, Object?>>());
    expect(template['failureUxMatrix'], isA<Map<String, Object?>>());
    expect(template['releaseSigning'], isA<Map<String, Object?>>());
    expect(template['dataProtection'], isA<Map<String, Object?>>());
  });
}

Object? _markAllBooleansReady(Object? value) {
  if (value is bool) {
    return true;
  }
  if (value is Map<String, Object?>) {
    return value.map(
      (key, child) => MapEntry(key, _markAllBooleansReady(child)),
    );
  }
  return value;
}
