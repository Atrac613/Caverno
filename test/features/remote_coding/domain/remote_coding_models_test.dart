import 'package:caverno/features/chat/domain/services/pending_approval_summary.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_grant_kinds.dart';
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

  group('desktop-origin grant', () {
    RemoteCodingPairedDevice device({Set<String> kinds = const <String>{}}) =>
        RemoteCodingPairedDevice(
          id: 'device-1',
          name: 'Phone',
          tokenHash: 'hash',
          createdAt: DateTime.utc(2026, 9, 6),
          lastSeenAt: DateTime.utc(2026, 9, 6),
          desktopOriginKinds: kinds,
        );

    test('is empty by default, which is what pairing alone gives', () {
      expect(device().desktopOriginKinds, isEmpty);
      expect(device().toJson().containsKey('desktopOriginKinds'), isFalse);
    });

    test('round-trips through settings', () {
      final granted = device(
        kinds: {
          RemoteCodingGrantKinds.question,
          PendingApprovalKinds.localCommand,
        },
      );

      final parsed = RemoteCodingPairedDevice.fromJson(granted.toJson());

      expect(parsed.desktopOriginKinds, {
        RemoteCodingGrantKinds.question,
        PendingApprovalKinds.localCommand,
      });
    });

    test('drops a kind this build does not recognise', () {
      // A grant must not outlive the kind it names, and a string that was
      // never a kind must not become one by being carried forward.
      final parsed = RemoteCodingPairedDevice.fromJson({
        ...device().toJson(),
        'desktopOriginKinds': [
          PendingApprovalKinds.gitCommand,
          'retiredKind',
          42,
        ],
      });

      expect(parsed.desktopOriginKinds, {PendingApprovalKinds.gitCommand});
    });

    test('survives dropping the notification relay', () {
      // withoutNotificationRelay builds a fresh device rather than copying
      // one, so a field added to the class is silently lost there unless it is
      // repeated. Losing this one would revoke an authority grant as a side
      // effect of a notification setting.
      final granted = device(kinds: {PendingApprovalKinds.file});

      expect(granted.withoutNotificationRelay().desktopOriginKinds, {
        PendingApprovalKinds.file,
      });
    });
  });
}
