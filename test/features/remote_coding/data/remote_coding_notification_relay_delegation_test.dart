import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_delegation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const delegationId = 'delegation_123';
  const deliveryHandle = 'delivery_handle_1';
  const targetDeviceId = 'device_123';
  const challengeId = 'challenge_123';
  final challengeSecret = List.filled(43, 's').join();
  final now = DateTime.utc(2026, 8, 10, 16);
  var credentialCreations = 0;
  late RemoteCodingRelayDelegationStateMachine stateMachine;

  setUp(() {
    credentialCreations = 0;
    stateMachine = RemoteCodingRelayDelegationStateMachine(
      credentialFactory: (_) {
        credentialCreations += 1;
        return RemoteCodingRelayDelegatedCredential(
          keyId: 'delivery-key-123',
          secret: 'desktop-delivery-secret',
          expiresAt: now.add(const Duration(days: 30)),
        );
      },
    );
  });

  RemoteCodingRelayDelegationFailure? create({DateTime? expiresAt}) {
    return stateMachine.create(
      delegationId: delegationId,
      deliveryHandle: deliveryHandle,
      targetDeviceId: targetDeviceId,
      challengeId: challengeId,
      challengeDigest: RemoteCodingRelayDelegationStateMachine.challengeDigest(
        challengeSecret,
      ),
      expiresAt: expiresAt ?? now.add(const Duration(minutes: 5)),
      now: now,
    );
  }

  RemoteCodingRelayDelegationRedemptionResult redeem({
    String? secret,
    String? deviceId,
    String idempotencyKey = 'idempotency_123',
    DateTime? requestedAt,
  }) {
    return stateMachine.redeem(
      delegationId: delegationId,
      challengeId: challengeId,
      challengeSecret: secret ?? challengeSecret,
      targetDeviceId: deviceId ?? targetDeviceId,
      idempotencyKey: idempotencyKey,
      now: requestedAt ?? now,
    );
  }

  test('redeems once and replays the same idempotent response', () {
    expect(create(), isNull);
    final pending = stateMachine.read(delegationId)!;
    expect(pending.state, RemoteCodingRelayDelegationState.pending);
    expect(pending.challengeDigest, isNot(challengeSecret));
    expect(pending.redemptionResponse, isNull);

    final first = redeem();
    final retried = redeem();

    expect(first.isAccepted, isTrue);
    expect(retried.isAccepted, isTrue);
    expect(retried.response?.toJson(), first.response?.toJson());
    expect(first.response?.deliverySecret, 'desktop-delivery-secret');
    expect(credentialCreations, 1);
    expect(
      stateMachine.read(delegationId)?.state,
      RemoteCodingRelayDelegationState.redeemed,
    );
  });

  test('rejects a second redemption with another idempotency key', () {
    expect(create(), isNull);
    expect(redeem().isAccepted, isTrue);

    final replay = redeem(idempotencyKey: 'idempotency_456');

    expect(replay.failure, RemoteCodingRelayDelegationFailure.alreadyRedeemed);
    expect(credentialCreations, 1);
  });

  test('challenge and target device mismatches do not consume the grant', () {
    expect(create(), isNull);

    expect(
      redeem(secret: List.filled(43, 'x').join()).failure,
      RemoteCodingRelayDelegationFailure.challengeMismatch,
    );
    expect(
      redeem(deviceId: 'device_456').failure,
      RemoteCodingRelayDelegationFailure.targetDeviceMismatch,
    );
    expect(redeem().isAccepted, isTrue);
    expect(credentialCreations, 1);
  });

  test('expires an unredeemed or unactivated delegation', () {
    expect(create(), isNull);

    final lateRedemption = redeem(
      requestedAt: now.add(const Duration(minutes: 6)),
    );

    expect(lateRedemption.failure, RemoteCodingRelayDelegationFailure.expired);
    expect(
      stateMachine.read(delegationId)?.state,
      RemoteCodingRelayDelegationState.expired,
    );
    expect(credentialCreations, 0);
  });

  test('activates only the redeemed credential and revokes idempotently', () {
    expect(create(), isNull);
    expect(redeem().isAccepted, isTrue);

    expect(
      stateMachine.activate(
        delegationId: delegationId,
        deliveryKeyId: 'delivery-key-456',
        now: now,
      ),
      RemoteCodingRelayDelegationFailure.deliveryCredentialMismatch,
    );
    expect(
      stateMachine.activate(
        delegationId: delegationId,
        deliveryKeyId: 'delivery-key-123',
        now: now,
      ),
      isNull,
    );
    expect(
      stateMachine.activate(
        delegationId: delegationId,
        deliveryKeyId: 'delivery-key-123',
        now: now,
      ),
      isNull,
    );
    expect(
      stateMachine.read(delegationId)?.state,
      RemoteCodingRelayDelegationState.active,
    );
    expect(stateMachine.revoke(delegationId), isNull);
    expect(stateMachine.revoke(delegationId), isNull);
    expect(
      stateMachine.read(delegationId)?.state,
      RemoteCodingRelayDelegationState.revoked,
    );
  });

  test('rejects duplicate delegation IDs and already-expired creation', () {
    expect(create(), isNull);
    expect(create(), RemoteCodingRelayDelegationFailure.duplicateDelegation);

    final expiredMachine = RemoteCodingRelayDelegationStateMachine(
      credentialFactory: (_) => throw StateError('must not create'),
    );
    expect(
      expiredMachine.create(
        delegationId: 'delegation_456',
        deliveryHandle: deliveryHandle,
        targetDeviceId: targetDeviceId,
        challengeId: challengeId,
        challengeDigest:
            RemoteCodingRelayDelegationStateMachine.challengeDigest(
              challengeSecret,
            ),
        expiresAt: now,
        now: now,
      ),
      RemoteCodingRelayDelegationFailure.expired,
    );
  });

  group('delegation expiry acceptance', () {
    final scannedAt = DateTime.utc(2026, 8, 10, 16);

    test('accepts an expiry the relay stamps after the QR was generated', () {
      // The desktop generates the challenge first and the phone scans it
      // later, so the relay always stamps a delegation that outlives the
      // challenge printed in the QR. That must not be rejected.
      expect(
        isRemoteCodingRelayDelegationExpiryAcceptable(
          delegationExpiresAt: scannedAt.add(const Duration(minutes: 5)),
          now: scannedAt,
        ),
        isTrue,
      );
    });

    test('rejects an expiry that already passed', () {
      expect(
        isRemoteCodingRelayDelegationExpiryAcceptable(
          delegationExpiresAt: scannedAt,
          now: scannedAt,
        ),
        isFalse,
      );
    });

    test('rejects a delegation that would outlive the bounded window', () {
      expect(
        isRemoteCodingRelayDelegationExpiryAcceptable(
          delegationExpiresAt: scannedAt.add(const Duration(minutes: 11)),
          now: scannedAt,
        ),
        isFalse,
      );
    });

    test('tolerates the clock skew the signed contract already allows', () {
      expect(
        isRemoteCodingRelayDelegationExpiryAcceptable(
          delegationExpiresAt: scannedAt.add(const Duration(minutes: 9)),
          now: scannedAt,
        ),
        isTrue,
      );
    });
  });
}
