import '../domain/remote_coding_models.dart';

class RemoteCodingMultiDeviceEvidence {
  const RemoteCodingMultiDeviceEvidence._();

  static Map<String, dynamic> build({
    required RemoteCodingServerSettings settings,
    required int activeConnectionCount,
    required bool revokingOneDeviceKeepsOtherDeviceUsable,
    required bool approvalsReachOnlyRemoteOriginTurns,
    DateTime? generatedAt,
  }) {
    final now = generatedAt ?? DateTime.now();
    final pairedDeviceCount = settings.pairedDevices.length;
    final twoDevicesReady = pairedDeviceCount >= 2;
    final activeSessionCountReady = activeConnectionCount >= 2;

    return {
      'schemaName': 'remote_coding_p1_multi_device_evidence',
      'schemaVersion': 1,
      'generatedAt': now.toIso8601String(),
      'review': {
        'pairedDeviceCount': pairedDeviceCount,
        'activeConnectionCount': activeConnectionCount,
        'twoDevicesReady': twoDevicesReady,
        'activeSessionCountReady': activeSessionCountReady,
        'independentRevocationConfirmed':
            revokingOneDeviceKeepsOtherDeviceUsable,
        'remoteApprovalBoundaryConfirmed': approvalsReachOnlyRemoteOriginTurns,
        'pairedDevices': settings.pairedDevices
            .map(_pairedDeviceSnapshot)
            .toList(growable: false),
      },
      'manualChecklistPatch': {
        'schemaName': 'remote_coding_p1_manual_checklist_patch',
        'schemaVersion': 1,
        'multiDevice': {
          'twoDevicesCanPair': twoDevicesReady,
          'activeSessionCountUpdates': activeSessionCountReady,
          'revokingOneDeviceKeepsOtherDeviceUsable':
              revokingOneDeviceKeepsOtherDeviceUsable,
          'approvalsReachOnlyRemoteOriginTurns':
              approvalsReachOnlyRemoteOriginTurns,
        },
      },
    };
  }

  static Map<String, dynamic> _pairedDeviceSnapshot(
    RemoteCodingPairedDevice device,
  ) {
    return {
      'id': device.id,
      'name': device.name,
      'createdAt': device.createdAt.toIso8601String(),
      'lastSeenAt': device.lastSeenAt.toIso8601String(),
    };
  }
}
