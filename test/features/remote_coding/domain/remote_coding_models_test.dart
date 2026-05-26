import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
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
    );

    final parsed = RemoteCodingPairingPayload.fromQrData(payload.toQrData());

    expect(parsed.ticketId, payload.ticketId);
    expect(parsed.secret, payload.secret);
    expect(parsed.host, payload.host);
    expect(parsed.port, payload.port);
    expect(parsed.expiresAt, payload.expiresAt);
    expect(parsed.serverName, payload.serverName);
  });

  test('pairing QR parser rejects unrelated data', () {
    expect(
      () => RemoteCodingPairingPayload.fromQrData('{"kind":"settings"}'),
      throwsA(isA<FormatException>()),
    );
  });
}
