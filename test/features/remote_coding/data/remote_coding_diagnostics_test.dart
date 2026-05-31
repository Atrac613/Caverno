import 'dart:convert';

import 'package:caverno/features/remote_coding/data/remote_coding_diagnostics.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_support_packet.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server diagnostics include support state without token material', () {
    final device = RemoteCodingPairedDevice(
      id: 'device-1',
      name: 'Phone',
      tokenHash: 'secret-token-hash',
      createdAt: DateTime(2026, 5, 26, 12),
      lastSeenAt: DateTime(2026, 5, 26, 12, 30),
    );
    final snapshot = RemoteCodingDiagnostics.serverSnapshot(
      RemoteCodingServerSettings(
        enabled: true,
        port: 8767,
        pairedDevices: [device],
      ),
      isRunning: true,
      activeHost: '192.168.1.10',
      activeUrl: 'ws://192.168.1.10:8767/ws',
      activeConnectionCount: 1,
      pairingPayload: null,
      error: null,
      generatedAt: DateTime(2026, 5, 26, 13),
    );
    final encoded = jsonEncode(snapshot);

    expect(snapshot['schemaName'], 'remote_coding_host_diagnostics');
    expect(snapshot['protocolVersion'], 1);
    expect(snapshot['activeConnectionCount'], 1);
    expect(snapshot['pairedDeviceCount'], 1);
    expect(snapshot['activeUrlAvailable'], isTrue);
    expect(snapshot['privacy'], {
      'rawDeviceTokensIncluded': false,
      'tokenHashesIncluded': false,
    });
    expect(
      (snapshot['pairedDevices'] as List<dynamic>).single,
      isNot(containsPair('tokenHash', anything)),
    );
    expect(encoded, isNot(contains('secret-token-hash')));
  });

  test('mobile diagnostics include reconnect state without token material', () {
    final host = RemoteCodingHost(
      id: 'device-1',
      name: 'Desktop',
      host: '192.168.1.10',
      port: 8767,
      createdAt: DateTime(2026, 5, 26, 12),
      updatedAt: DateTime(2026, 5, 26, 12, 30),
    );
    final snapshot = RemoteCodingDiagnostics.clientSnapshot(
      status: RemoteCodingConnectionStatus.disconnected,
      host: host,
      snapshotSequence: 42,
      snapshotGeneratedAt: DateTime(2026, 5, 26, 12, 45),
      reconnectAttempt: 2,
      nextReconnectAt: DateTime(2026, 5, 26, 12, 46),
      pendingCommandCount: 1,
      isLoading: false,
      queuedCount: 0,
      hasPendingApproval: true,
      error: 'Connection closed',
      generatedAt: DateTime(2026, 5, 26, 13),
    );
    final encoded = jsonEncode(snapshot);

    expect(snapshot['schemaName'], 'remote_coding_mobile_diagnostics');
    expect(snapshot['protocolVersion'], 1);
    expect(snapshot['connectionStatus'], 'disconnected');
    expect(snapshot['autoReconnectScheduled'], isTrue);
    expect(snapshot['reconnectAttempt'], 2);
    expect(snapshot['pendingCommandCount'], 1);
    expect(snapshot['hasPendingApproval'], isTrue);
    expect(snapshot['privacy'], {
      'mobileDeviceTokenIncluded': false,
      'pairingSecretIncluded': false,
    });
    expect(encoded, isNot(contains('mobile-token')));
    expect(encoded, isNot(contains('pairing-secret')));
  });

  test('desktop support packet includes a P1 checklist patch', () {
    final diagnostics = RemoteCodingDiagnostics.serverSnapshot(
      const RemoteCodingServerSettings(enabled: true, port: 8767),
      isRunning: true,
      activeHost: '192.168.1.10',
      activeUrl: 'ws://192.168.1.10:8767/ws',
      activeConnectionCount: 1,
      pairingPayload: null,
      error: null,
      generatedAt: DateTime(2026, 5, 26, 13),
    );
    final packet = RemoteCodingSupportPacket.build(
      side: RemoteCodingSupportPacketSide.desktop,
      diagnostics: diagnostics,
      generatedAt: DateTime(2026, 5, 26, 13, 5),
    );
    final checklistPatch =
        packet['manualChecklistPatch'] as Map<String, dynamic>;
    final supportPacket =
        checklistPatch['supportPacket'] as Map<String, dynamic>;
    final encoded = jsonEncode(packet);

    expect(packet['schemaName'], 'remote_coding_p1_support_packet');
    expect(packet['side'], 'desktop');
    expect(supportPacket['desktopDiagnosticsCopied'], isTrue);
    expect(supportPacket['mobileDiagnosticsCopied'], isFalse);
    expect(supportPacket['diagnosticsContainNoTokenMaterial'], isTrue);
    expect(supportPacket['supportPacketIdentifiesEndpointAndProtocol'], isTrue);
    expect(encoded, isNot(contains('secret-token-hash')));
  });

  test('mobile support packet includes a P1 checklist patch', () {
    final diagnostics = RemoteCodingDiagnostics.clientSnapshot(
      status: RemoteCodingConnectionStatus.connected,
      host: RemoteCodingHost(
        id: 'device-1',
        name: 'Desktop',
        host: '192.168.1.10',
        port: 8767,
        createdAt: DateTime(2026, 5, 26, 12),
        updatedAt: DateTime(2026, 5, 26, 12, 30),
      ),
      snapshotSequence: 42,
      snapshotGeneratedAt: DateTime(2026, 5, 26, 12, 45),
      reconnectAttempt: 0,
      nextReconnectAt: null,
      pendingCommandCount: 0,
      isLoading: false,
      queuedCount: 0,
      hasPendingApproval: false,
      error: null,
      generatedAt: DateTime(2026, 5, 26, 13),
    );
    final packet = RemoteCodingSupportPacket.build(
      side: RemoteCodingSupportPacketSide.mobile,
      diagnostics: diagnostics,
      generatedAt: DateTime(2026, 5, 26, 13, 5),
    );
    final checklistPatch =
        packet['manualChecklistPatch'] as Map<String, dynamic>;
    final supportPacket =
        checklistPatch['supportPacket'] as Map<String, dynamic>;

    expect(packet['schemaName'], 'remote_coding_p1_support_packet');
    expect(packet['side'], 'mobile');
    expect(supportPacket['mobileDiagnosticsCopied'], isTrue);
    expect(supportPacket['desktopDiagnosticsCopied'], isFalse);
    expect(supportPacket['diagnosticsContainNoTokenMaterial'], isTrue);
    expect(supportPacket['supportPacketIdentifiesEndpointAndProtocol'], isTrue);
  });
}
