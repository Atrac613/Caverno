import 'remote_coding_protocol.dart';
import '../domain/remote_coding_models.dart';

class RemoteCodingDiagnostics {
  const RemoteCodingDiagnostics._();

  static Map<String, dynamic> serverSnapshot(
    RemoteCodingServerSettings settings, {
    required bool isRunning,
    required String? activeHost,
    required String? activeUrl,
    required int activeConnectionCount,
    required RemoteCodingPairingPayload? pairingPayload,
    required String? error,
    DateTime? generatedAt,
  }) {
    final now = generatedAt ?? DateTime.now();
    return {
      'schemaName': 'remote_coding_host_diagnostics',
      'schemaVersion': 1,
      'protocolVersion': remoteCodingProtocolVersion,
      'generatedAt': now.toIso8601String(),
      'enabled': settings.enabled,
      'isRunning': isRunning,
      'activeHost': activeHost,
      'activeUrlAvailable': activeUrl != null,
      'port': settings.port,
      'activeConnectionCount': activeConnectionCount,
      'pairedDeviceCount': settings.pairedDevices.length,
      'pairingCodeActive': pairingPayload != null,
      if (pairingPayload != null)
        'pairingCodeExpiresAt': pairingPayload.expiresAt.toIso8601String(),
      'pairedDevices': settings.pairedDevices
          .map(_pairedDeviceSnapshot)
          .toList(growable: false),
      'privacy': {
        'rawDeviceTokensIncluded': false,
        'tokenHashesIncluded': false,
      },
      if (error != null && error.isNotEmpty) 'error': error,
    };
  }

  static Map<String, dynamic> clientSnapshot({
    required RemoteCodingConnectionStatus status,
    required RemoteCodingHost? host,
    required int snapshotSequence,
    required DateTime? snapshotGeneratedAt,
    required int reconnectAttempt,
    required DateTime? nextReconnectAt,
    required int pendingCommandCount,
    required bool isLoading,
    required int queuedCount,
    required bool hasPendingApproval,
    required String? error,
    DateTime? generatedAt,
  }) {
    final now = generatedAt ?? DateTime.now();
    return {
      'schemaName': 'remote_coding_mobile_diagnostics',
      'schemaVersion': 1,
      'protocolVersion': remoteCodingProtocolVersion,
      'generatedAt': now.toIso8601String(),
      'connectionStatus': status.name,
      'hostConfigured': host != null,
      if (host != null) ...{
        'hostId': host.id,
        'hostName': host.name,
        'hostAddress': host.host,
        'hostPort': host.port,
      },
      'snapshotSequence': snapshotSequence,
      'snapshotGeneratedAt': snapshotGeneratedAt?.toIso8601String(),
      'reconnectAttempt': reconnectAttempt,
      'autoReconnectScheduled': nextReconnectAt != null,
      'nextReconnectAt': nextReconnectAt?.toIso8601String(),
      'pendingCommandCount': pendingCommandCount,
      'isLoading': isLoading,
      'queuedCount': queuedCount,
      'hasPendingApproval': hasPendingApproval,
      'privacy': {
        'mobileDeviceTokenIncluded': false,
        'pairingSecretIncluded': false,
      },
      if (error != null && error.isNotEmpty) 'error': error,
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
