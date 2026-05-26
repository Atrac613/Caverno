import 'dart:async';
import 'dart:io';

import 'package:caverno/features/remote_coding/data/remote_coding_connection_messages.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final host = RemoteCodingHost(
    id: 'host-1',
    name: 'Desktop',
    host: '192.168.1.10',
    port: 8767,
    createdAt: DateTime(2026, 5, 26, 12),
    updatedAt: DateTime(2026, 5, 26, 12),
  );

  test('describes connection timeout with LAN recovery guidance', () {
    final message = RemoteCodingConnectionMessages.connectionFailure(
      TimeoutException('timeout'),
      host,
    );

    expect(message, contains('Timed out connecting'));
    expect(message, contains('192.168.1.10:8767'));
    expect(message, contains('same LAN'));
  });

  test('describes socket failures with firewall guidance', () {
    final message = RemoteCodingConnectionMessages.connectionFailure(
      const SocketException('connection refused'),
      host,
    );

    expect(message, contains('Could not reach'));
    expect(message, contains('desktop firewall'));
    expect(message, contains('desktop IP has not changed'));
  });

  test('describes expired QR and rejected token recovery', () {
    expect(
      RemoteCodingConnectionMessages.expiredPairingCode(),
      contains('5 minutes'),
    );
    expect(
      RemoteCodingConnectionMessages.unauthorizedToken(),
      contains('Pair with the desktop again'),
    );
  });

  test('builds recovery steps for saved hosts and token failures', () {
    final steps = RemoteCodingConnectionMessages.recoverySteps(
      host: host,
      error: RemoteCodingConnectionMessages.unauthorizedToken(),
    );

    expect(steps, contains('Current saved endpoint: 192.168.1.10:8767.'));
    expect(
      steps,
      contains('Use Forget Host, then pair again from the desktop QR.'),
    );
  });

  test('builds recovery steps for automatic reconnects', () {
    final steps = RemoteCodingConnectionMessages.recoverySteps(
      host: host,
      error:
          'Connection closed. Reconnecting to 192.168.1.10:8767 in 2 seconds.',
    );

    expect(
      steps,
      contains('Leave this screen open; the app will retry automatically.'),
    );
  });
}
