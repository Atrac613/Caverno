import 'dart:convert';

import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_pairing.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final expiresAt = DateTime.utc(2026, 8, 10, 12, 5);

  RemoteCodingNotificationRelayPairingPayload payload({
    String challengeId = 'challenge-1',
    String targetDeviceId = 'device-1',
    DateTime? expiry,
  }) {
    return RemoteCodingNotificationRelayPairingPayload(
      challengeId: challengeId,
      challengeSecret: RemoteCodingSecurity.randomToken(byteLength: 32),
      targetDeviceId: targetDeviceId,
      expiresAt: expiry ?? expiresAt,
    );
  }

  test('round trips a dedicated QR without relay origin or LAN token', () {
    final original = payload();

    final decoded = RemoteCodingNotificationRelayPairingPayload.fromQrData(
      original.toQrData(),
    );
    final wire = jsonDecode(original.toQrData()) as Map<String, dynamic>;

    expect(decoded.challengeId, original.challengeId);
    expect(decoded.challengeSecret, original.challengeSecret);
    expect(decoded.challengeDigest, hasLength(64));
    expect(decoded.targetDeviceId, original.targetDeviceId);
    expect(
      wire.keys,
      unorderedEquals(<String>{
        'kind',
        'challengeId',
        'challengeSecret',
        'targetDeviceId',
        'expiresAt',
      }),
    );
    expect(original.toQrData(), isNot(contains('relayUrl')));
    expect(original.toQrData(), isNot(contains('deviceToken')));
  });

  test('rejects unsupported fields and short secrets', () {
    final wire = jsonDecode(payload().toQrData()) as Map<String, dynamic>;

    expect(
      () => RemoteCodingNotificationRelayPairingPayload.fromQrData(
        jsonEncode(<String, dynamic>{...wire, 'relayUrl': 'https://evil.test'}),
      ),
      throwsFormatException,
    );
    expect(
      () => RemoteCodingNotificationRelayPairingPayload.fromQrData(
        jsonEncode(<String, dynamic>{...wire, 'challengeSecret': 'short'}),
      ),
      throwsFormatException,
    );
  });

  test('registry binds a challenge to one authenticated device and use', () {
    final registry = RemoteCodingNotificationRelayPairingRegistry();
    registry.add(payload());

    final wrongDevice = registry.consume(
      challengeId: 'challenge-1',
      authenticatedDeviceId: 'device-2',
      now: DateTime.utc(2026, 8, 10, 12),
    );
    final replay = registry.consume(
      challengeId: 'challenge-1',
      authenticatedDeviceId: 'device-1',
      now: DateTime.utc(2026, 8, 10, 12),
    );

    expect(
      wrongDevice.status,
      RemoteCodingRelayPairingConsumeStatus.wrongDevice,
    );
    expect(replay.status, RemoteCodingRelayPairingConsumeStatus.missing);
  });

  test('registry rejects an expired challenge and removes it', () {
    final registry = RemoteCodingNotificationRelayPairingRegistry();
    registry.add(payload(expiry: DateTime.utc(2026, 8, 10, 12)));

    final result = registry.consume(
      challengeId: 'challenge-1',
      authenticatedDeviceId: 'device-1',
      now: DateTime.utc(2026, 8, 10, 12),
    );

    expect(result.status, RemoteCodingRelayPairingConsumeStatus.expired);
    expect(registry.contains('challenge-1'), isFalse);
  });

  test('delegation-ready payload cannot carry secrets or relay origin', () {
    final message = RemoteCodingRelayDelegationReadyMessage(
      challengeId: 'challenge-1',
      delegationId: 'delegation-1',
      expiresAt: expiresAt,
    );

    final wire = message.toPayload();
    final decoded = RemoteCodingRelayDelegationReadyMessage.fromPayload(wire);

    expect(decoded.delegationId, 'delegation-1');
    expect(
      wire.keys,
      unorderedEquals(<String>{'challengeId', 'delegationId', 'expiresAt'}),
    );
    expect(jsonEncode(wire), isNot(contains('secret')));
    expect(jsonEncode(wire), isNot(contains('relayUrl')));
  });
}
