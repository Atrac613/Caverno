import 'remote_coding_notification_relay_contract.dart';
import 'remote_coding_security.dart';

/// Longest delegation lifetime the relay is allowed to issue.
const remoteCodingRelayDelegationMaximumLifetime = Duration(minutes: 5);

/// Clock skew already tolerated between a device and the relay by the signed
/// request contract.
const remoteCodingRelayDelegationMaximumClockSkew = Duration(minutes: 5);

/// Whether a relay-issued delegation expiry is acceptable to the mobile client.
///
/// The delegation must still be valid and must stay short-lived. It is
/// deliberately not compared against the QR challenge expiry: the relay stamps
/// the delegation from its own clock when the phone redeems the code, which is
/// necessarily later than the moment the desktop generated the challenge, so
/// that comparison rejected every real scan. The challenge window itself is
/// still enforced by the desktop, which refuses an expired challenge when it
/// consumes one.
bool isRemoteCodingRelayDelegationExpiryAcceptable({
  required DateTime delegationExpiresAt,
  required DateTime now,
  Duration maximumLifetime = remoteCodingRelayDelegationMaximumLifetime,
  Duration maximumClockSkew = remoteCodingRelayDelegationMaximumClockSkew,
}) {
  final expiry = delegationExpiresAt.toUtc();
  final reference = now.toUtc();
  if (!expiry.isAfter(reference)) {
    return false;
  }
  return !expiry.isAfter(reference.add(maximumLifetime + maximumClockSkew));
}

enum RemoteCodingRelayDelegationState {
  pending,
  redeemed,
  active,
  expired,
  revoked,
}

enum RemoteCodingRelayDelegationFailure {
  duplicateDelegation,
  notFound,
  expired,
  challengeMismatch,
  targetDeviceMismatch,
  alreadyRedeemed,
  invalidState,
  deliveryCredentialMismatch,
}

final class RemoteCodingRelayDelegatedCredential {
  const RemoteCodingRelayDelegatedCredential({
    required this.keyId,
    required this.secret,
    required this.expiresAt,
  });

  final String keyId;
  final String secret;
  final DateTime expiresAt;
}

typedef RemoteCodingRelayDeliveryCredentialFactory =
    RemoteCodingRelayDelegatedCredential Function(
      RemoteCodingRelayDelegationRecord delegation,
    );

final class RemoteCodingRelayDelegationRecord {
  const RemoteCodingRelayDelegationRecord({
    required this.delegationId,
    required this.deliveryHandle,
    required this.targetDeviceId,
    required this.challengeId,
    required this.challengeDigest,
    required this.expiresAt,
    required this.state,
    this.redemptionIdempotencyKey,
    this.redemptionResponse,
  });

  final String delegationId;
  final String deliveryHandle;
  final String targetDeviceId;
  final String challengeId;
  final String challengeDigest;
  final DateTime expiresAt;
  final RemoteCodingRelayDelegationState state;
  final String? redemptionIdempotencyKey;
  final RemoteCodingRelayDelegationRedemptionResponse? redemptionResponse;

  RemoteCodingRelayDelegationRecord copyWith({
    RemoteCodingRelayDelegationState? state,
    String? redemptionIdempotencyKey,
    RemoteCodingRelayDelegationRedemptionResponse? redemptionResponse,
  }) {
    return RemoteCodingRelayDelegationRecord(
      delegationId: delegationId,
      deliveryHandle: deliveryHandle,
      targetDeviceId: targetDeviceId,
      challengeId: challengeId,
      challengeDigest: challengeDigest,
      expiresAt: expiresAt,
      state: state ?? this.state,
      redemptionIdempotencyKey:
          redemptionIdempotencyKey ?? this.redemptionIdempotencyKey,
      redemptionResponse: redemptionResponse ?? this.redemptionResponse,
    );
  }
}

final class RemoteCodingRelayDelegationRedemptionResult {
  const RemoteCodingRelayDelegationRedemptionResult._({
    this.response,
    this.failure,
  });

  const RemoteCodingRelayDelegationRedemptionResult.accepted(
    RemoteCodingRelayDelegationRedemptionResponse response,
  ) : this._(response: response);

  const RemoteCodingRelayDelegationRedemptionResult.rejected(
    RemoteCodingRelayDelegationFailure failure,
  ) : this._(failure: failure);

  final RemoteCodingRelayDelegationRedemptionResponse? response;
  final RemoteCodingRelayDelegationFailure? failure;

  bool get isAccepted => response != null && failure == null;
}

/// In-memory reference state machine for the one-time delegation contract.
///
/// A deployed relay must provide the same conditional transitions through a
/// shared durable store. This class intentionally stores only the QR challenge
/// digest, never the challenge secret itself.
final class RemoteCodingRelayDelegationStateMachine {
  RemoteCodingRelayDelegationStateMachine({
    required RemoteCodingRelayDeliveryCredentialFactory credentialFactory,
  }) : _credentialFactory = credentialFactory;

  final RemoteCodingRelayDeliveryCredentialFactory _credentialFactory;
  final Map<String, RemoteCodingRelayDelegationRecord> _delegations =
      <String, RemoteCodingRelayDelegationRecord>{};

  static String challengeDigest(String challengeSecret) {
    return RemoteCodingSecurity.hashToken(challengeSecret);
  }

  RemoteCodingRelayDelegationFailure? create({
    required String delegationId,
    required String deliveryHandle,
    required String targetDeviceId,
    required String challengeId,
    required String challengeDigest,
    required DateTime expiresAt,
    required DateTime now,
  }) {
    _requireNonEmpty(delegationId, 'delegationId');
    _requireNonEmpty(deliveryHandle, 'deliveryHandle');
    _requireNonEmpty(targetDeviceId, 'targetDeviceId');
    _requireNonEmpty(challengeId, 'challengeId');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(challengeDigest)) {
      throw const FormatException('Delegation challenge digest is invalid.');
    }
    if (_delegations.containsKey(delegationId)) {
      return RemoteCodingRelayDelegationFailure.duplicateDelegation;
    }
    if (!expiresAt.toUtc().isAfter(now.toUtc())) {
      return RemoteCodingRelayDelegationFailure.expired;
    }
    _delegations[delegationId] = RemoteCodingRelayDelegationRecord(
      delegationId: delegationId,
      deliveryHandle: deliveryHandle,
      targetDeviceId: targetDeviceId,
      challengeId: challengeId,
      challengeDigest: challengeDigest,
      expiresAt: expiresAt.toUtc(),
      state: RemoteCodingRelayDelegationState.pending,
    );
    return null;
  }

  RemoteCodingRelayDelegationRedemptionResult redeem({
    required String delegationId,
    required String challengeId,
    required String challengeSecret,
    required String targetDeviceId,
    required String idempotencyKey,
    required DateTime now,
  }) {
    final record = _resolve(delegationId, now);
    if (record == null) {
      return const RemoteCodingRelayDelegationRedemptionResult.rejected(
        RemoteCodingRelayDelegationFailure.notFound,
      );
    }
    if (record.state == RemoteCodingRelayDelegationState.expired) {
      return const RemoteCodingRelayDelegationRedemptionResult.rejected(
        RemoteCodingRelayDelegationFailure.expired,
      );
    }
    if (!RemoteCodingSecurity.constantTimeEquals(
      record.targetDeviceId,
      targetDeviceId,
    )) {
      return const RemoteCodingRelayDelegationRedemptionResult.rejected(
        RemoteCodingRelayDelegationFailure.targetDeviceMismatch,
      );
    }
    final suppliedDigest = challengeDigest(challengeSecret);
    if (!RemoteCodingSecurity.constantTimeEquals(
          record.challengeId,
          challengeId,
        ) ||
        !RemoteCodingSecurity.constantTimeEquals(
          record.challengeDigest,
          suppliedDigest,
        )) {
      return const RemoteCodingRelayDelegationRedemptionResult.rejected(
        RemoteCodingRelayDelegationFailure.challengeMismatch,
      );
    }
    if (record.state == RemoteCodingRelayDelegationState.redeemed) {
      if (RemoteCodingSecurity.constantTimeEquals(
            record.redemptionIdempotencyKey ?? '',
            idempotencyKey,
          ) &&
          record.redemptionResponse != null) {
        return RemoteCodingRelayDelegationRedemptionResult.accepted(
          record.redemptionResponse!,
        );
      }
      return const RemoteCodingRelayDelegationRedemptionResult.rejected(
        RemoteCodingRelayDelegationFailure.alreadyRedeemed,
      );
    }
    if (record.state != RemoteCodingRelayDelegationState.pending) {
      return const RemoteCodingRelayDelegationRedemptionResult.rejected(
        RemoteCodingRelayDelegationFailure.invalidState,
      );
    }
    _requireNonEmpty(idempotencyKey, 'idempotencyKey');
    final credential = _credentialFactory(record);
    _validateCredential(credential, now);
    final response = RemoteCodingRelayDelegationRedemptionResponse(
      delegationId: record.delegationId,
      deliveryHandle: record.deliveryHandle,
      deliveryKeyId: credential.keyId,
      deliverySecret: credential.secret,
      expiresAt: credential.expiresAt.toUtc(),
    );
    _delegations[delegationId] = record.copyWith(
      state: RemoteCodingRelayDelegationState.redeemed,
      redemptionIdempotencyKey: idempotencyKey,
      redemptionResponse: response,
    );
    return RemoteCodingRelayDelegationRedemptionResult.accepted(response);
  }

  RemoteCodingRelayDelegationFailure? activate({
    required String delegationId,
    required String deliveryKeyId,
    required DateTime now,
  }) {
    final record = _resolve(delegationId, now);
    if (record == null) {
      return RemoteCodingRelayDelegationFailure.notFound;
    }
    if (record.state == RemoteCodingRelayDelegationState.expired) {
      return RemoteCodingRelayDelegationFailure.expired;
    }
    final expectedKeyId = record.redemptionResponse?.deliveryKeyId;
    if (expectedKeyId == null ||
        !RemoteCodingSecurity.constantTimeEquals(
          expectedKeyId,
          deliveryKeyId,
        )) {
      return RemoteCodingRelayDelegationFailure.deliveryCredentialMismatch;
    }
    if (record.state == RemoteCodingRelayDelegationState.active) {
      return null;
    }
    if (record.state != RemoteCodingRelayDelegationState.redeemed) {
      return RemoteCodingRelayDelegationFailure.invalidState;
    }
    _delegations[delegationId] = record.copyWith(
      state: RemoteCodingRelayDelegationState.active,
    );
    return null;
  }

  RemoteCodingRelayDelegationFailure? revoke(String delegationId) {
    final record = _delegations[delegationId];
    if (record == null) {
      return RemoteCodingRelayDelegationFailure.notFound;
    }
    if (record.state == RemoteCodingRelayDelegationState.revoked) {
      return null;
    }
    _delegations[delegationId] = record.copyWith(
      state: RemoteCodingRelayDelegationState.revoked,
    );
    return null;
  }

  RemoteCodingRelayDelegationRecord? read(String delegationId) {
    return _delegations[delegationId];
  }

  RemoteCodingRelayDelegationRecord? _resolve(
    String delegationId,
    DateTime now,
  ) {
    final record = _delegations[delegationId];
    if (record == null) {
      return null;
    }
    if ((record.state == RemoteCodingRelayDelegationState.pending ||
            record.state == RemoteCodingRelayDelegationState.redeemed) &&
        !record.expiresAt.isAfter(now.toUtc())) {
      final expired = record.copyWith(
        state: RemoteCodingRelayDelegationState.expired,
      );
      _delegations[delegationId] = expired;
      return expired;
    }
    return record;
  }

  void _validateCredential(
    RemoteCodingRelayDelegatedCredential credential,
    DateTime now,
  ) {
    _requireNonEmpty(credential.keyId, 'deliveryKeyId');
    _requireNonEmpty(credential.secret, 'deliverySecret');
    if (!credential.expiresAt.toUtc().isAfter(now.toUtc())) {
      throw const FormatException('Delivery credential is already expired.');
    }
  }

  void _requireNonEmpty(String value, String field) {
    if (value.trim().isEmpty) {
      throw FormatException('Delegation field "$field" is required.');
    }
  }
}
