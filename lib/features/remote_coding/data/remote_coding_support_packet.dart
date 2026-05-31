import 'remote_coding_protocol.dart';

class RemoteCodingSupportPacket {
  const RemoteCodingSupportPacket._();

  static Map<String, dynamic> build({
    required RemoteCodingSupportPacketSide side,
    required Map<String, dynamic> diagnostics,
    DateTime? generatedAt,
  }) {
    final now = generatedAt ?? DateTime.now();
    final endpoint = _endpointSummary(diagnostics);
    final redacted = _diagnosticsAreRedacted(diagnostics);
    final identifiesEndpointAndProtocol =
        diagnostics['protocolVersion'] == remoteCodingProtocolVersion &&
        endpoint.isNotEmpty;

    return {
      'schemaName': 'remote_coding_p1_support_packet',
      'schemaVersion': 1,
      'generatedAt': now.toIso8601String(),
      'side': side.name,
      'review': {
        'diagnosticsSchemaName': diagnostics['schemaName'],
        'protocolVersion': diagnostics['protocolVersion'],
        'endpoint': endpoint,
        'connectionStatus': diagnostics['connectionStatus'],
        'isRunning': diagnostics['isRunning'],
        'activeConnectionCount': diagnostics['activeConnectionCount'],
        'pairedDeviceCount': diagnostics['pairedDeviceCount'],
        'snapshotSequence': diagnostics['snapshotSequence'],
        'snapshotGeneratedAt': diagnostics['snapshotGeneratedAt'],
        'redactionReady': redacted,
        'endpointAndProtocolReady': identifiesEndpointAndProtocol,
      },
      'manualChecklistPatch': {
        'schemaName': 'remote_coding_p1_manual_checklist_patch',
        'schemaVersion': 1,
        'supportPacket': {
          'mobileDiagnosticsCopied':
              side == RemoteCodingSupportPacketSide.mobile,
          'desktopDiagnosticsCopied':
              side == RemoteCodingSupportPacketSide.desktop,
          'diagnosticsContainNoTokenMaterial': redacted,
          'supportPacketIdentifiesEndpointAndProtocol':
              identifiesEndpointAndProtocol,
        },
      },
      'diagnostics': diagnostics,
    };
  }

  static Map<String, dynamic> _endpointSummary(
    Map<String, dynamic> diagnostics,
  ) {
    final host =
        (diagnostics['hostAddress'] as String?) ??
        (diagnostics['activeHost'] as String?);
    final port = diagnostics['hostPort'] ?? diagnostics['port'];
    if (host is String && host.trim().isNotEmpty && port is num) {
      return {'host': host, 'port': port.toInt(), 'websocketPath': '/ws'};
    }
    if (port is num) {
      return {
        'port': port.toInt(),
        'websocketPath': '/ws',
        'activeHostAvailable': false,
      };
    }
    return const <String, dynamic>{};
  }

  static bool _diagnosticsAreRedacted(Map<String, dynamic> diagnostics) {
    final privacy = diagnostics['privacy'];
    if (privacy is! Map<String, dynamic>) {
      return false;
    }
    const sensitiveFlags = [
      'rawDeviceTokensIncluded',
      'tokenHashesIncluded',
      'mobileDeviceTokenIncluded',
      'pairingSecretIncluded',
    ];
    return sensitiveFlags.every((flag) => privacy[flag] != true);
  }
}

enum RemoteCodingSupportPacketSide { desktop, mobile }
