import 'dart:convert';
import 'dart:io';

class RemoteCodingP0Gate {
  const RemoteCodingP0Gate({
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

class RemoteCodingP0ReleaseGateResult {
  const RemoteCodingP0ReleaseGateResult({
    required this.generatedAt,
    required this.status,
    required this.staticGates,
    required this.manualGates,
    required this.blockedGateIds,
    required this.nextAction,
  });

  final DateTime generatedAt;
  final String status;
  final List<RemoteCodingP0Gate> staticGates;
  final List<RemoteCodingP0Gate> manualGates;
  final List<String> blockedGateIds;
  final String nextAction;

  Map<String, Object?> toJson() => {
    'schemaName': 'remote_coding_p0_release_gate',
    'schemaVersion': 1,
    'generatedAt': generatedAt.toIso8601String(),
    'status': status,
    'blockedGateIds': blockedGateIds,
    'nextAction': nextAction,
    'operationBoundary':
        'Static checks are automated; device, signing, and migration evidence remains user-operated.',
    'staticGates': staticGates.map((gate) => gate.toJson()).toList(),
    'manualGates': manualGates.map((gate) => gate.toJson()).toList(),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Remote Coding P0 Release Gate')
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

RemoteCodingP0ReleaseGateResult buildRemoteCodingP0ReleaseGate({
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
      ? 'ready_for_remote_coding_p0_release'
      : 'blocked';
  return RemoteCodingP0ReleaseGateResult(
    generatedAt: generatedAt ?? DateTime.now(),
    status: status,
    staticGates: staticGates,
    manualGates: manualGates,
    blockedGateIds: blockedGateIds,
    nextAction: blockedGateIds.isEmpty
        ? 'Remote Coding P0 release evidence is complete.'
        : 'Resolve blocked Remote Coding P0 gates before product release.',
  );
}

Map<String, Object?> remoteCodingP0ManualChecklistTemplate({
  DateTime? generatedAt,
}) {
  final now = generatedAt ?? DateTime.now();
  return {
    'schemaName': 'remote_coding_p0_manual_checklist',
    'schemaVersion': 1,
    'generatedAt': now.toIso8601String(),
    'realDeviceMatrix': {
      'macosHostIosPairing': false,
      'macosHostIosReconnect': false,
      'macosHostIosStreaming': false,
      'macosHostIosStop': false,
      'macosHostIosApproval': false,
      'macosHostIosRevocation': false,
      'macosHostAndroidPairing': false,
      'macosHostAndroidReconnect': false,
      'macosHostAndroidStreaming': false,
      'macosHostAndroidStop': false,
      'macosHostAndroidApproval': false,
      'macosHostAndroidRevocation': false,
    },
    'failureUxMatrix': {
      'hostNotRunning': false,
      'wifiMismatch': false,
      'desktopIpChanged': false,
      'expiredQr': false,
      'revokedOrRejectedToken': false,
    },
    'releaseSigning': {
      'macosNotarizationReady': false,
      'iosSigningReady': false,
      'androidSigningReady': false,
      'permissionsAndLocalNetworkReviewed': false,
    },
    'dataProtection': {
      'mobileTokenSecureStorageVerified': false,
      'desktopTokenHashOnlyVerified': false,
      'settingsConversationMigrationVerified': false,
      'existingUserStartupCompatibilityVerified': false,
    },
  };
}

List<RemoteCodingP0Gate> _buildStaticGates(Directory repoRoot) {
  final protocol = _read(
    repoRoot,
    'lib/features/remote_coding/data/remote_coding_protocol.dart',
  );
  final androidManifest = _read(
    repoRoot,
    'android/app/src/main/AndroidManifest.xml',
  );
  final iosInfo = _read(repoRoot, 'ios/Runner/Info.plist');
  final macosReleaseEntitlements = _read(
    repoRoot,
    'macos/Runner/Release.entitlements',
  );
  final chatNotifierTest = _read(
    repoRoot,
    'test/features/chat/presentation/providers/chat_notifier_test.dart',
  );
  final mobileWidgetTest = _read(
    repoRoot,
    'test/features/chat/presentation/pages/chat_page_remote_coding_test.dart',
  );
  final repository = _read(
    repoRoot,
    'lib/features/remote_coding/data/remote_coding_repository.dart',
  );
  final diagnosticsTest = _read(
    repoRoot,
    'test/features/remote_coding/data/remote_coding_diagnostics_test.dart',
  );

  return [
    _staticGate(
      id: 'protocol_blocks_mobile_project_management',
      label: 'Mobile protocol has no project add/remove commands.',
      ready:
          protocol.contains('allowedClientCommands') &&
          !protocol.contains("'addProject'") &&
          !protocol.contains("'removeProject'") &&
          !protocol.contains("'deleteProject'"),
      evidence: const [
        'Remote protocol allowlist excludes mobile project management commands.',
      ],
      nextAction:
          'Keep project registration and removal desktop-only for Remote Coding v1.',
    ),
    _staticGate(
      id: 'mobile_coding_tab_remote_only',
      label: 'Mobile Coding tab is Remote Coding only.',
      ready:
          mobileWidgetTest.contains('coding tab is remote-only') &&
          mobileWidgetTest.contains('find.byType(RemoteCodingPage)') &&
          mobileWidgetTest.contains('Icons.create_new_folder_outlined'),
      evidence: const [
        'Widget coverage proves mobile uses RemoteCodingPage and hides local add-project controls.',
      ],
      nextAction: 'Restore the mobile remote-only widget gate.',
    ),
    _staticGate(
      id: 'remote_origin_safety_tests',
      label:
          'Remote-origin mutations, git writes, and non-read-only commands are approval gated.',
      ready:
          chatNotifierTest.contains('remote file mutations require approval') &&
          chatNotifierTest.contains(
            'remote non-read-only local commands require approval',
          ) &&
          chatNotifierTest.contains('remote git writes require approval') &&
          chatNotifierTest.contains(
            'remote saved deny rules block local commands before mobile approval',
          ),
      evidence: const [
        'Chat notifier tests cover remote write approvals, read-only command passthrough, git approvals, and saved deny rules.',
      ],
      nextAction:
          'Add or restore remote-origin safety tests before release sign-off.',
    ),
    _staticGate(
      id: 'android_cleartext_not_global',
      label: 'Android does not globally permit cleartext traffic.',
      ready: !androidManifest.contains('android:usesCleartextTraffic="true"'),
      evidence: const [
        'Android manifest avoids app-wide cleartext opt-in while Remote Coding remains LAN-only.',
      ],
      nextAction: 'Remove any app-wide Android cleartext opt-in.',
    ),
    _staticGate(
      id: 'apple_local_network_permissions',
      label:
          'Apple platforms declare local networking and macOS server entitlement.',
      ready:
          iosInfo.contains('NSAllowsLocalNetworking') &&
          iosInfo.contains('NSLocalNetworkUsageDescription') &&
          macosReleaseEntitlements.contains(
            'com.apple.security.network.server',
          ) &&
          macosReleaseEntitlements.contains(
            'com.apple.security.network.client',
          ),
      evidence: const [
        'iOS Info.plist allows local networking and macOS release entitlements allow LAN host/client sockets.',
      ],
      nextAction:
          'Restore local-network usage strings and macOS network entitlements.',
    ),
    _staticGate(
      id: 'token_storage_and_redaction',
      label:
          'Mobile tokens use secure storage and desktop diagnostics are redacted.',
      ready:
          repository.contains('FlutterSecureStorage') &&
          repository.contains('_secureStorage.write') &&
          diagnosticsTest.contains('rawDeviceTokensIncluded') &&
          diagnosticsTest.contains('tokenHashesIncluded') &&
          diagnosticsTest.contains('secret-token-hash'),
      evidence: const [
        'Repository stores mobile token material in secure storage and diagnostics tests prove hashes/raw tokens are excluded.',
      ],
      nextAction:
          'Restore secure mobile token storage and redacted diagnostics coverage.',
    ),
  ];
}

List<RemoteCodingP0Gate> _buildManualGates(Map<String, dynamic>? checklist) {
  return [
    _manualGate(
      id: 'real_device_matrix',
      label:
          'macOS host with iOS and Android covers pairing, reconnect, streaming, stop, approval, and revocation.',
      checklist: checklist,
      requiredPaths: const [
        'realDeviceMatrix.macosHostIosPairing',
        'realDeviceMatrix.macosHostIosReconnect',
        'realDeviceMatrix.macosHostIosStreaming',
        'realDeviceMatrix.macosHostIosStop',
        'realDeviceMatrix.macosHostIosApproval',
        'realDeviceMatrix.macosHostIosRevocation',
        'realDeviceMatrix.macosHostAndroidPairing',
        'realDeviceMatrix.macosHostAndroidReconnect',
        'realDeviceMatrix.macosHostAndroidStreaming',
        'realDeviceMatrix.macosHostAndroidStop',
        'realDeviceMatrix.macosHostAndroidApproval',
        'realDeviceMatrix.macosHostAndroidRevocation',
      ],
      nextAction:
          'Run the Remote Coding real-device matrix on iOS and Android against the macOS host.',
    ),
    _manualGate(
      id: 'failure_ux_matrix',
      label:
          'Mobile failure UX covers host stopped, Wi-Fi mismatch, IP change, expired QR, and token rejection/revocation.',
      checklist: checklist,
      requiredPaths: const [
        'failureUxMatrix.hostNotRunning',
        'failureUxMatrix.wifiMismatch',
        'failureUxMatrix.desktopIpChanged',
        'failureUxMatrix.expiredQr',
        'failureUxMatrix.revokedOrRejectedToken',
      ],
      nextAction:
          'Exercise each connection failure and capture the displayed recovery guidance.',
    ),
    _manualGate(
      id: 'release_signing_permissions',
      label:
          'macOS notarization, iOS signing, Android signing, and permissions/local-network metadata are reviewed.',
      checklist: checklist,
      requiredPaths: const [
        'releaseSigning.macosNotarizationReady',
        'releaseSigning.iosSigningReady',
        'releaseSigning.androidSigningReady',
        'releaseSigning.permissionsAndLocalNetworkReviewed',
      ],
      nextAction:
          'Complete release signing and permission review evidence for all target platforms.',
    ),
    _manualGate(
      id: 'data_protection_migration',
      label:
          'Secure token storage, desktop token hashing, migrations, and existing-user startup compatibility are verified.',
      checklist: checklist,
      requiredPaths: const [
        'dataProtection.mobileTokenSecureStorageVerified',
        'dataProtection.desktopTokenHashOnlyVerified',
        'dataProtection.settingsConversationMigrationVerified',
        'dataProtection.existingUserStartupCompatibilityVerified',
      ],
      nextAction:
          'Verify stored Remote Coding data with upgraded existing-user settings and conversations.',
    ),
  ];
}

RemoteCodingP0Gate _staticGate({
  required String id,
  required String label,
  required bool ready,
  required List<String> evidence,
  required String nextAction,
}) {
  return RemoteCodingP0Gate(
    id: id,
    label: label,
    status: ready ? 'ready' : 'blocked',
    evidence: evidence,
    nextAction: ready ? null : nextAction,
  );
}

RemoteCodingP0Gate _manualGate({
  required String id,
  required String label,
  required Map<String, dynamic>? checklist,
  required List<String> requiredPaths,
  required String nextAction,
}) {
  if (checklist == null) {
    return RemoteCodingP0Gate(
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
  return RemoteCodingP0Gate(
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
      'Remote Coding P0 checklist must be a JSON object.',
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
