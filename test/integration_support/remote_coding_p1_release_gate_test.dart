import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/remote_coding_p1_release_gate.dart';

void main() {
  test('blocks release when user-operated P1 evidence is missing', () {
    final result = buildRemoteCodingP1ReleaseGate(
      repoRoot: Directory.current,
      generatedAt: DateTime(2026, 5, 26, 12),
    );

    expect(result.status, 'blocked');
    expect(result.staticGates.where((gate) => !gate.isReady), isEmpty);
    expect(result.blockedGateIds, contains('resilience_soak'));
    expect(result.blockedGateIds, contains('support_packet_review'));
    expect(result.blockedGateIds, contains('multi_device_household'));
    expect(result.toMarkdown(), contains('Remote Coding P1 Release Gate'));
  });

  test('passes when static checks and complete manual checklist are ready', () {
    final root = Directory.systemTemp.createTempSync(
      'remote_coding_p1_gate_test_',
    );
    addTearDown(() {
      root.deleteSync(recursive: true);
    });
    final checklist = remoteCodingP1ManualChecklistTemplate(
      generatedAt: DateTime(2026, 5, 26, 12),
    );
    final readyChecklist = _markAllBooleansReady(checklist);
    final checklistFile = File('${root.path}/manual_checklist.json')
      ..writeAsStringSync(const JsonEncoder().convert(readyChecklist));

    final result = buildRemoteCodingP1ReleaseGate(
      repoRoot: Directory.current,
      manualChecklistFile: checklistFile,
      generatedAt: DateTime(2026, 5, 26, 12),
    );

    expect(result.status, 'ready_for_remote_coding_p1_release');
    expect(result.blockedGateIds, isEmpty);
    expect(result.toJson()['schemaName'], 'remote_coding_p1_release_gate');
  });

  test('manual checklist template covers every P1 evidence section', () {
    final template = remoteCodingP1ManualChecklistTemplate(
      generatedAt: DateTime(2026, 5, 26, 12),
    );

    expect(template['resilienceSoak'], isA<Map<String, Object?>>());
    expect(template['supportPacket'], isA<Map<String, Object?>>());
    expect(template['multiDevice'], isA<Map<String, Object?>>());
  });

  test('support packets can satisfy the support packet checklist section', () {
    final root = Directory.systemTemp.createTempSync(
      'remote_coding_p1_support_packet_gate_test_',
    );
    addTearDown(() {
      root.deleteSync(recursive: true);
    });
    final checklist = remoteCodingP1ManualChecklistTemplate(
      generatedAt: DateTime(2026, 5, 26, 12),
    );
    final readyChecklist = _markAllBooleansReady(checklist);
    if (readyChecklist case final Map<String, Object?> readyMap) {
      readyMap['supportPacket'] = {
        'mobileDiagnosticsCopied': false,
        'desktopDiagnosticsCopied': false,
        'diagnosticsContainNoTokenMaterial': false,
        'supportPacketIdentifiesEndpointAndProtocol': false,
      };
    }
    final checklistFile = File('${root.path}/manual_checklist.json')
      ..writeAsStringSync(const JsonEncoder().convert(readyChecklist));
    final mobilePacket = File('${root.path}/mobile_support_packet.json')
      ..writeAsStringSync(
        const JsonEncoder().convert(
          _supportPacket(side: 'mobile', mobile: true, desktop: false),
        ),
      );
    final desktopPacket = File('${root.path}/desktop_support_packet.json')
      ..writeAsStringSync(
        const JsonEncoder().convert(
          _supportPacket(side: 'desktop', mobile: false, desktop: true),
        ),
      );

    final result = buildRemoteCodingP1ReleaseGate(
      repoRoot: Directory.current,
      manualChecklistFile: checklistFile,
      supportPacketFiles: [mobilePacket, desktopPacket],
      generatedAt: DateTime(2026, 5, 26, 12),
    );

    expect(result.status, 'ready_for_remote_coding_p1_release');
    expect(result.blockedGateIds, isNot(contains('support_packet_review')));
  });

  test('multi-device evidence can satisfy the household checklist section', () {
    final root = Directory.systemTemp.createTempSync(
      'remote_coding_p1_multi_device_gate_test_',
    );
    addTearDown(() {
      root.deleteSync(recursive: true);
    });
    final checklist = remoteCodingP1ManualChecklistTemplate(
      generatedAt: DateTime(2026, 5, 26, 12),
    );
    final readyChecklist = _markAllBooleansReady(checklist);
    if (readyChecklist case final Map<String, Object?> readyMap) {
      readyMap['multiDevice'] = {
        'twoDevicesCanPair': false,
        'activeSessionCountUpdates': false,
        'revokingOneDeviceKeepsOtherDeviceUsable': false,
        'approvalsReachOnlyRemoteOriginTurns': false,
      };
    }
    final checklistFile = File('${root.path}/manual_checklist.json')
      ..writeAsStringSync(const JsonEncoder().convert(readyChecklist));
    final evidenceFile = File('${root.path}/multi_device_evidence.json')
      ..writeAsStringSync(const JsonEncoder().convert(_multiDeviceEvidence()));

    final result = buildRemoteCodingP1ReleaseGate(
      repoRoot: Directory.current,
      manualChecklistFile: checklistFile,
      multiDeviceEvidenceFiles: [evidenceFile],
      generatedAt: DateTime(2026, 5, 26, 12),
    );

    expect(result.status, 'ready_for_remote_coding_p1_release');
    expect(result.blockedGateIds, isNot(contains('multi_device_household')));
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

Map<String, Object?> _supportPacket({
  required String side,
  required bool mobile,
  required bool desktop,
}) {
  return {
    'schemaName': 'remote_coding_p1_support_packet',
    'schemaVersion': 1,
    'side': side,
    'manualChecklistPatch': {
      'schemaName': 'remote_coding_p1_manual_checklist_patch',
      'schemaVersion': 1,
      'supportPacket': {
        'mobileDiagnosticsCopied': mobile,
        'desktopDiagnosticsCopied': desktop,
        'diagnosticsContainNoTokenMaterial': true,
        'supportPacketIdentifiesEndpointAndProtocol': true,
      },
    },
  };
}

Map<String, Object?> _multiDeviceEvidence() {
  return {
    'schemaName': 'remote_coding_p1_multi_device_evidence',
    'schemaVersion': 1,
    'manualChecklistPatch': {
      'schemaName': 'remote_coding_p1_manual_checklist_patch',
      'schemaVersion': 1,
      'multiDevice': {
        'twoDevicesCanPair': true,
        'activeSessionCountUpdates': true,
        'revokingOneDeviceKeepsOtherDeviceUsable': true,
        'approvalsReachOnlyRemoteOriginTurns': true,
      },
    },
  };
}
