import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_transport_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pairing QR payload round-trips and preserves expiry', () {
    final payload = RemoteCodingPairingPayload(
      ticketId: 'ticket-1',
      secret: 'pair-secret',
      host: '192.168.1.10',
      port: 8767,
      expiresAt: DateTime.utc(2026, 5, 26, 12),
      serverName: 'Caverno Desktop',
      certificatePin: 'test-certificate-pin',
    );

    final parsed = RemoteCodingPairingPayload.fromQrData(payload.toQrData());

    expect(parsed.ticketId, payload.ticketId);
    expect(parsed.secret, payload.secret);
    expect(parsed.host, payload.host);
    expect(parsed.port, payload.port);
    expect(parsed.expiresAt, payload.expiresAt);
    expect(parsed.serverName, payload.serverName);
    expect(parsed.certificatePin, payload.certificatePin);
    expect(parsed.websocketUrl, startsWith('wss://'));
  });

  test('pairing QR parser rejects plaintext payloads', () {
    expect(
      () => RemoteCodingPairingPayload.fromQrData(
        '{"kind":"caverno_remote_coding_v1","ticketId":"t","secret":"s",'
        '"host":"192.168.1.10","port":8767,'
        '"expiresAt":"2026-05-26T12:00:00.000Z","serverName":"Desktop"}',
      ),
      throwsA(isA<RemoteCodingPlaintextDowngradeException>()),
    );
  });

  test('pairing QR parser rejects unrelated data', () {
    expect(
      () => RemoteCodingPairingPayload.fromQrData('{"kind":"settings"}'),
      throwsA(isA<FormatException>()),
    );
  });
}
