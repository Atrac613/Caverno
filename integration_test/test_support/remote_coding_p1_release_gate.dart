import 'dart:convert';
import 'dart:io';

class RemoteCodingP1Gate {
  const RemoteCodingP1Gate({
    required this.id,
    required this.label,
    required this.status,
    required this.evidence,
    this.nextAction,
    this.userOperated = false,
  });

  final String id;
  final String label;
  final String status;
  final List<String> evidence;
  final String? nextAction;
  final bool userOperated;

  bool get isReady => status == 'ready';

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'status': status,
    'evidence': evidence,
    'userOperated': userOperated,
    if (nextAction != null && nextAction!.isNotEmpty) 'nextAction': nextAction,
  };
}

class RemoteCodingP1ReleaseGateResult {
  const RemoteCodingP1ReleaseGateResult({
    required this.generatedAt,
    required this.status,
    required this.staticGates,
    required this.manualGates,
    required this.blockedGateIds,
    required this.nextAction,
  });

  final DateTime generatedAt;
  final String status;
  final List<RemoteCodingP1Gate> staticGates;
  final List<RemoteCodingP1Gate> manualGates;
  final List<String> blockedGateIds;
  final String nextAction;

  Map<String, Object?> toJson() => {
    'schemaName': 'remote_coding_p1_release_gate',
    'schemaVersion': 1,
    'generatedAt': generatedAt.toIso8601String(),
    'status': status,
    'blockedGateIds': blockedGateIds,
    'nextAction': nextAction,
    'operationBoundary':
        'Static checks cover resilience and diagnostics. LAN soak, backgrounding, and support packet review remain user-operated.',
    'staticGates': staticGates.map((gate) => gate.toJson()).toList(),
    'manualGates': manualGates.map((gate) => gate.toJson()).toList(),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Remote Coding P1 Release Gate')
      ..writeln()
      ..writeln('- Status: `$status`')
      ..writeln('- Generated at: `${generatedAt.toIso8601String()}`')
      ..writeln('- Next action: $nextAction')
      ..writeln()
      ..writeln('## Static Gates');
    for (final gate in staticGates) {
      buffer
        ..writeln()
        ..writeln('- `${gate.id}`: `${gate.status}`')
        ..writeln('  - ${gate.label}');
      for (final evidence in gate.evidence) {
        buffer.writeln('  - Evidence: $evidence');
      }
      if (gate.nextAction != null) {
        buffer.writeln('  - Next action: ${gate.nextAction}');
      }
    }
    buffer
      ..writeln()
      ..writeln('## Manual Gates');
    for (final gate in manualGates) {
      buffer
        ..writeln()
        ..writeln('- `${gate.id}`: `${gate.status}`')
        ..writeln('  - ${gate.label}');
      for (final evidence in gate.evidence) {
        buffer.writeln('  - Evidence: $evidence');
      }
      if (gate.nextAction != null) {
        buffer.writeln('  - Next action: ${gate.nextAction}');
      }
    }
    return buffer.toString();
  }
}

RemoteCodingP1ReleaseGateResult buildRemoteCodingP1ReleaseGate({
  required Directory repoRoot,
  File? manualChecklistFile,
  DateTime? generatedAt,
}) {
  final checklist = _readChecklist(manualChecklistFile);
  final staticGates = _buildStaticGates(repoRoot);
  final manualGates = _buildManualGates(checklist);
  final blockedGateIds = [
    for (final gate in [...staticGates, ...manualGates])
      if (!gate.isReady) gate.id,
  ];
  final status = blockedGateIds.isEmpty
      ? 'ready_for_remote_coding_p1_release'
      : 'blocked';
  return RemoteCodingP1ReleaseGateResult(
    generatedAt: generatedAt ?? DateTime.now(),
    status: status,
    staticGates: staticGates,
    manualGates: manualGates,
    blockedGateIds: blockedGateIds,
    nextAction: blockedGateIds.isEmpty
        ? 'Remote Coding P1 release evidence is complete.'
        : 'Resolve blocked Remote Coding P1 gates before product release.',
  );
}

Map<String, Object?> remoteCodingP1ManualChecklistTemplate({
  DateTime? generatedAt,
}) {
  final now = generatedAt ?? DateTime.now();
  return {
    'schemaName': 'remote_coding_p1_manual_checklist',
    'schemaVersion': 1,
    'generatedAt': now.toIso8601String(),
    'resilienceSoak': {
      'iosLanSoakThirtyMinutes': false,
      'androidLanSoakThirtyMinutes': false,
      'desktopSleepWakeReconnect': false,
      'mobileBackgroundResumeReconnect': false,
      'desktopIpChangeRecovery': false,
    },
    'supportPacket': {
      'mobileDiagnosticsCopied': false,
      'desktopDiagnosticsCopied': false,
      'diagnosticsContainNoTokenMaterial': false,
      'supportPacketIdentifiesEndpointAndProtocol': false,
    },
    'multiDevice': {
      'twoDevicesCanPair': false,
      'activeSessionCountUpdates': false,
      'revokingOneDeviceKeepsOtherDeviceUsable': false,
      'approvalsReachOnlyRemoteOriginTurns': false,
    },
  };
}

List<RemoteCodingP1Gate> _buildStaticGates(Directory repoRoot) {
  final clientNotifier = _read(
    repoRoot,
    'lib/features/remote_coding/presentation/remote_coding_client_notifier.dart',
  );
  final serverNotifier = _read(
    repoRoot,
    'lib/features/remote_coding/presentation/remote_coding_server_notifier.dart',
  );
  final diagnostics = _read(
    repoRoot,
    'lib/features/remote_coding/data/remote_coding_diagnostics.dart',
  );
  final remotePage = _read(
    repoRoot,
    'lib/features/remote_coding/presentation/remote_coding_page.dart',
  );
  final clientTest = _read(
    repoRoot,
    'test/features/remote_coding/presentation/remote_coding_client_state_test.dart',
  );
  final diagnosticsTest = _read(
    repoRoot,
    'test/features/remote_coding/data/remote_coding_diagnostics_test.dart',
  );
  final widgetTest = _read(
    repoRoot,
    'test/features/chat/presentation/pages/chat_page_remote_coding_test.dart',
  );
  final docs = _read(repoRoot, 'docs/remote_coding_p1_release_gate.md');

  return [
    _staticGate(
      id: 'mobile_auto_reconnect',
      label:
          'Mobile schedules bounded automatic reconnect after unexpected LAN drops.',
      ready:
          clientNotifier.contains('_reconnectBackoffDelays') &&
          clientNotifier.contains('_scheduleReconnect') &&
          clientNotifier.contains('nextReconnectAt') &&
          clientNotifier.contains('pingInterval') &&
          clientTest.contains(
            'unexpected disconnect schedules a bounded reconnect attempt',
          ) &&
          clientTest.contains(
            'manual disconnect clears scheduled reconnect metadata',
          ),
      evidence: const [
        'Client notifier uses finite reconnect backoff, socket ping intervals, and reconnect state tests.',
      ],
      nextAction:
          'Restore finite reconnect scheduling and tests for unexpected disconnects.',
    ),
    _staticGate(
      id: 'command_timeout_correlation',
      label: 'Mobile tracks request IDs and exposes timed-out remote commands.',
      ready:
          clientNotifier.contains('_pendingCommandTimers') &&
          clientNotifier.contains('_commandTimeout') &&
          clientNotifier.contains('_clearPendingCommandTimer(message.id)') &&
          clientNotifier.contains('pendingCommandCount'),
      evidence: const [
        'Client notifier tracks command IDs, clears them on correlated replies, and surfaces timeout state.',
      ],
      nextAction:
          'Restore request correlation and command timeout tracking in the mobile client.',
    ),
    _staticGate(
      id: 'support_diagnostics',
      label:
          'Mobile and desktop diagnostics expose support state without token material.',
      ready:
          diagnostics.contains('remote_coding_mobile_diagnostics') &&
          diagnostics.contains('protocolVersion') &&
          diagnostics.contains('mobileDeviceTokenIncluded') &&
          diagnostics.contains('pairingSecretIncluded') &&
          remotePage.contains('Copy Diagnostics') &&
          diagnosticsTest.contains(
            'mobile diagnostics include reconnect state without token material',
          ) &&
          widgetTest.contains(
            'mobile connection view copies redacted diagnostics',
          ),
      evidence: const [
        'Diagnostics include protocol and reconnect metadata, while widget and unit tests prove redacted copy support.',
      ],
      nextAction:
          'Restore mobile diagnostics copy support and redaction coverage.',
    ),
    _staticGate(
      id: 'host_snapshot_metadata',
      label:
          'Host snapshots advertise protocol and Remote Coding capabilities.',
      ready:
          serverNotifier.contains(
            "'protocolVersion': remoteCodingProtocolVersion",
          ) &&
          serverNotifier.contains("'capabilities'") &&
          serverNotifier.contains("'projectManagement': false") &&
          serverNotifier.contains("'activeConnectionCount'"),
      evidence: const [
        'Host snapshots expose protocol version, safe mobile capabilities, and active session count.',
      ],
      nextAction: 'Restore support metadata in remote host snapshots.',
    ),
    _staticGate(
      id: 'p1_docs_and_gate',
      label: 'Remote Coding P1 has a documented release gate.',
      ready:
          docs.contains('Remote Coding P1 Release Gate') &&
          docs.contains('resilienceSoak') &&
          docs.contains('supportPacket') &&
          docs.contains('multiDevice'),
      evidence: const [
        'P1 documentation names the automated gate and manual evidence sections.',
      ],
      nextAction: 'Restore Remote Coding P1 release gate documentation.',
    ),
  ];
}

List<RemoteCodingP1Gate> _buildManualGates(Map<String, dynamic>? checklist) {
  return [
    _manualGate(
      id: 'resilience_soak',
      label:
          'iOS and Android survive LAN soak, background/resume, sleep/wake, and desktop IP change recovery.',
      checklist: checklist,
      requiredPaths: const [
        'resilienceSoak.iosLanSoakThirtyMinutes',
        'resilienceSoak.androidLanSoakThirtyMinutes',
        'resilienceSoak.desktopSleepWakeReconnect',
        'resilienceSoak.mobileBackgroundResumeReconnect',
        'resilienceSoak.desktopIpChangeRecovery',
      ],
      nextAction:
          'Run the P1 LAN resilience soak on real iOS and Android devices.',
    ),
    _manualGate(
      id: 'support_packet_review',
      label:
          'Mobile and desktop support packets are useful and contain no token material.',
      checklist: checklist,
      requiredPaths: const [
        'supportPacket.mobileDiagnosticsCopied',
        'supportPacket.desktopDiagnosticsCopied',
        'supportPacket.diagnosticsContainNoTokenMaterial',
        'supportPacket.supportPacketIdentifiesEndpointAndProtocol',
      ],
      nextAction:
          'Capture and review copied diagnostics from both sides of a paired session.',
    ),
    _manualGate(
      id: 'multi_device_household',
      label:
          'Multiple paired devices can coexist, revoke independently, and preserve remote approval boundaries.',
      checklist: checklist,
      requiredPaths: const [
        'multiDevice.twoDevicesCanPair',
        'multiDevice.activeSessionCountUpdates',
        'multiDevice.revokingOneDeviceKeepsOtherDeviceUsable',
        'multiDevice.approvalsReachOnlyRemoteOriginTurns',
      ],
      nextAction:
          'Verify two-device pairing, active counts, independent revocation, and approval routing.',
    ),
  ];
}

RemoteCodingP1Gate _staticGate({
  required String id,
  required String label,
  required bool ready,
  required List<String> evidence,
  required String nextAction,
}) {
  return RemoteCodingP1Gate(
    id: id,
    label: label,
    status: ready ? 'ready' : 'blocked',
    evidence: evidence,
    nextAction: ready ? null : nextAction,
  );
}

RemoteCodingP1Gate _manualGate({
  required String id,
  required String label,
  required Map<String, dynamic>? checklist,
  required List<String> requiredPaths,
  required String nextAction,
}) {
  if (checklist == null) {
    return RemoteCodingP1Gate(
      id: id,
      label: label,
      status: 'blocked',
      evidence: const ['Manual checklist evidence is missing.'],
      nextAction: nextAction,
      userOperated: true,
    );
  }
  final missing = requiredPaths
      .where((path) => _boolAt(checklist, path) != true)
      .toList(growable: false);
  return RemoteCodingP1Gate(
    id: id,
    label: label,
    status: missing.isEmpty ? 'ready' : 'blocked',
    evidence: missing.isEmpty
        ? ['All required checklist fields are true.']
        : ['Missing or false checklist fields: ${missing.join(', ')}'],
    nextAction: missing.isEmpty ? null : nextAction,
    userOperated: true,
  );
}

Map<String, dynamic>? _readChecklist(File? file) {
  if (file == null || !file.existsSync()) {
    return null;
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
      'Remote Coding P1 checklist must be a JSON object.',
    );
  }
  return decoded;
}

bool? _boolAt(Map<String, dynamic> source, String dottedPath) {
  Object? current = source;
  for (final segment in dottedPath.split('.')) {
    if (current is! Map<String, dynamic>) {
      return null;
    }
    current = current[segment];
  }
  return current is bool ? current : null;
}

String _read(Directory root, String relativePath) {
  final file = File('${root.path}/$relativePath');
  return file.existsSync() ? file.readAsStringSync() : '';
}
