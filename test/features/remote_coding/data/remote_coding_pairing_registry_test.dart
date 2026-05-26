import 'package:caverno/features/remote_coding/data/remote_coding_pairing_registry.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RemoteCodingPairingPayload payload({
    String ticketId = 'ticket-1',
    String secret = 'secret-1',
    DateTime? expiresAt,
  }) {
    return RemoteCodingPairingPayload(
      ticketId: ticketId,
      secret: secret,
      host: '192.168.1.10',
      port: 8767,
      expiresAt: expiresAt ?? DateTime(2026, 5, 26, 12, 5),
      serverName: 'desktop',
    );
  }

  test('pairing tickets are single use after successful consume', () {
    final registry = RemoteCodingPairingRegistry();
    registry.add(payload());

    final first = registry.consume(
      ticketId: 'ticket-1',
      secret: 'secret-1',
      now: DateTime(2026, 5, 26, 12),
    );
    final second = registry.consume(
      ticketId: 'ticket-1',
      secret: 'secret-1',
      now: DateTime(2026, 5, 26, 12),
    );

    expect(first.status, RemoteCodingPairingConsumeStatus.accepted);
    expect(second.status, RemoteCodingPairingConsumeStatus.missing);
  });

  test('expired pairing tickets are rejected and removed', () {
    final registry = RemoteCodingPairingRegistry();
    registry.add(payload(expiresAt: DateTime(2026, 5, 26, 12)));

    final result = registry.consume(
      ticketId: 'ticket-1',
      secret: 'secret-1',
      now: DateTime(2026, 5, 26, 12),
    );

    expect(result.status, RemoteCodingPairingConsumeStatus.expired);
    expect(registry.contains('ticket-1'), isFalse);
  });

  test('purgeExpired removes only expired tickets', () {
    final registry = RemoteCodingPairingRegistry();
    registry
      ..add(payload(ticketId: 'expired', expiresAt: DateTime(2026, 5, 26, 12)))
      ..add(payload(ticketId: 'active'));

    registry.purgeExpired(now: DateTime(2026, 5, 26, 12));

    expect(registry.contains('expired'), isFalse);
    expect(registry.contains('active'), isTrue);
  });

  test('remove invalidates a pairing ticket before it is used', () {
    final registry = RemoteCodingPairingRegistry();
    registry.add(payload());

    registry.remove('ticket-1');
    final result = registry.consume(
      ticketId: 'ticket-1',
      secret: 'secret-1',
      now: DateTime(2026, 5, 26, 12),
    );

    expect(result.status, RemoteCodingPairingConsumeStatus.missing);
  });
}
