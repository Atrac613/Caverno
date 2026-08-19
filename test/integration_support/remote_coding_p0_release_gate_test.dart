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
    expect(result.transportContainment.isReady, isTrue);
    expect(
      result.toJson()['transportContainment'],
      containsPair('plaintextNonLoopbackListenerCanStart', false),
    );
    expect(result.toJson()['schemaVersion'], 2);
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
    expect(result.toJson()['schemaVersion'], 2);
    expect(result.transportContainment.isReady, isTrue);
  });

  test('blocks transportContainment when the server binds anyIPv4 directly', () {
    final root = Directory.systemTemp.createTempSync(
      'remote_coding_p0_transport_gate_',
    );
    addTearDown(() {
      root.deleteSync(recursive: true);
    });
    File(
        '${root.path}/lib/features/remote_coding/presentation/remote_coding_server_notifier.dart',
      )
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        'final server = await HttpServer.bind(InternetAddress.anyIPv4, port);',
      );

    final result = buildRemoteCodingP0ReleaseGate(
      repoRoot: root,
      generatedAt: DateTime(2026, 5, 26, 12),
    );

    expect(result.blockedGateIds, contains('transport_containment'));
    expect(result.transportContainment.isReady, isFalse);
    expect(
      result.toJson()['transportContainment'],
      containsPair('plaintextNonLoopbackListenerCanStart', true),
    );
  });

  test(
    'product isolate smoke proves a plaintext LAN listener cannot start',
    () async {
      final result = await _runPlaintextLanSmoke(product: true);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains('plaintext_non_loopback_listener_can_start=false'),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'non-product smoke is not containment evidence',
    () async {
      final result = await _runPlaintextLanSmoke(product: false);

      expect(result.exitCode, 2, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stderr,
        contains('non-product isolate as containment evidence'),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

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

Future<ProcessResult> _runPlaintextLanSmoke({required bool product}) {
  final fvmDart = File('.fvm/flutter_sdk/bin/dart');
  final executable = fvmDart.existsSync() ? fvmDart.path : 'dart';
  return Process.run(executable, [
    'run',
    if (product) '--define=dart.vm.product=true',
    'tool/remote_coding_plaintext_lan_smoke.dart',
  ]);
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
