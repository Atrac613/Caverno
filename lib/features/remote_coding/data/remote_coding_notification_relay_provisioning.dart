import 'remote_coding_notification_relay_client.dart';
import 'remote_coding_notification_relay_contract.dart';
import 'remote_coding_repository.dart';
import '../domain/remote_coding_models.dart';

final class RemoteCodingMobileRelayDelegationCoordinator {
  const RemoteCodingMobileRelayDelegationCoordinator({
    required this.repository,
    required this.relayClient,
    required this.clock,
  });

  final RemoteCodingRepository repository;
  final RemoteCodingNotificationRelayClient relayClient;
  final RemoteCodingRelayClock clock;

  Future<RemoteCodingRelayDelegationCreationResponse> createDelegation({
    required String challengeId,
    required String challengeDigest,
    required String targetDeviceId,
  }) async {
    final registration = await repository.loadMobileRelayRegistration();
    final now = clock().toUtc();
    if (registration == null || !registration.expiresAt.isAfter(now)) {
      throw StateError('Mobile relay registration is unavailable or expired.');
    }
    final delegation = await relayClient.createDelegation(
      deliveryHandle: registration.deliveryHandle,
      managementKeyId: registration.managementKeyId,
      managementSecret: registration.managementSecret,
      request: RemoteCodingRelayDelegationCreationRequest(
        challengeId: challengeId,
        challengeDigest: challengeDigest,
        targetDeviceId: targetDeviceId,
        requestedAt: now,
      ),
    );
    if (delegation.challengeId != challengeId ||
        delegation.targetDeviceId != targetDeviceId) {
      throw StateError('Relay returned a mismatched delegation binding.');
    }
    return delegation;
  }
}

final class RemoteCodingDesktopRelayProvisioningCoordinator {
  const RemoteCodingDesktopRelayProvisioningCoordinator({
    required this.repository,
    required this.relayClient,
    required this.clock,
  });

  final RemoteCodingRepository repository;
  final RemoteCodingNotificationRelayClient relayClient;
  final RemoteCodingRelayClock clock;

  Future<RemoteCodingPairedDevice> redeemAndActivate({
    required String deviceId,
    required String delegationId,
    required String challengeId,
    required String challengeSecret,
    required String idempotencyKey,
  }) async {
    _requirePairedDevice(deviceId);
    final now = clock().toUtc();
    final credential = await relayClient.redeemDelegation(
      delegationId: delegationId,
      request: RemoteCodingRelayDelegationRedemptionRequest(
        challengeId: challengeId,
        challengeSecret: challengeSecret,
        targetDeviceId: deviceId,
        idempotencyKey: idempotencyKey,
        requestedAt: now,
      ),
    );
    if (credential.delegationId != delegationId) {
      throw StateError('Relay returned a mismatched delegation credential.');
    }
    await repository.installPendingDesktopRelayCredential(
      deviceId: deviceId,
      credential: credential,
    );
    return _activateInstalled(
      deviceId: deviceId,
      delegationId: delegationId,
      now: now,
    );
  }

  Future<RemoteCodingPairedDevice> retryPendingActivation({
    required String deviceId,
    required String delegationId,
  }) {
    final device = _requirePairedDevice(deviceId);
    if (device.relayCredentialState !=
        RemoteCodingRelayCredentialState.pendingActivation) {
      throw StateError('Desktop relay credential is not pending activation.');
    }
    return _activateInstalled(
      deviceId: deviceId,
      delegationId: delegationId,
      now: clock().toUtc(),
    );
  }

  Future<RemoteCodingPairedDevice> revokeCredential(String deviceId) async {
    final device = _requirePairedDevice(deviceId);
    if (!device.hasNotificationRelay) {
      return device;
    }
    final secret = await repository.loadDesktopRelayDeliverySecret(deviceId);
    if (secret == null || secret.trim().isEmpty) {
      throw StateError('Desktop relay delivery secret is unavailable.');
    }
    await repository.markDesktopRelayCredentialPendingRevocation(deviceId);
    return _revokePending(deviceId: deviceId, secret: secret);
  }

  Future<RemoteCodingPairedDevice> retryPendingRevocation(
    String deviceId,
  ) async {
    final device = _requirePairedDevice(deviceId);
    if (device.relayCredentialState !=
        RemoteCodingRelayCredentialState.pendingRevocation) {
      throw StateError('Desktop relay credential is not pending revocation.');
    }
    final secret = await repository.loadDesktopRelayDeliverySecret(deviceId);
    if (secret == null || secret.trim().isEmpty) {
      throw StateError('Desktop relay delivery secret is unavailable.');
    }
    return _revokePending(deviceId: deviceId, secret: secret);
  }

  Future<RemoteCodingPairedDevice> _activateInstalled({
    required String deviceId,
    required String delegationId,
    required DateTime now,
  }) async {
    final device = _requirePairedDevice(deviceId);
    final deliveryHandle = device.relayDeliveryHandle;
    final deliveryKeyId = device.relayDeliveryKeyId;
    final secret = await repository.loadDesktopRelayDeliverySecret(deviceId);
    if (!device.hasNotificationRelay ||
        deliveryHandle == null ||
        deliveryKeyId == null ||
        secret == null ||
        secret.trim().isEmpty) {
      throw StateError('Pending desktop relay credential is incomplete.');
    }
    await relayClient.activateDelegation(
      deliveryHandle: deliveryHandle,
      delegationId: delegationId,
      deliveryKeyId: deliveryKeyId,
      deliverySecret: secret,
      request: RemoteCodingRelayDelegationActivationRequest(
        deliveryKeyId: deliveryKeyId,
        activatedAt: now,
      ),
    );
    return repository.markDesktopRelayCredentialActive(
      deviceId: deviceId,
      deliveryKeyId: deliveryKeyId,
    );
  }

  Future<RemoteCodingPairedDevice> _revokePending({
    required String deviceId,
    required String secret,
  }) async {
    final device = _requirePairedDevice(deviceId);
    final deliveryHandle = device.relayDeliveryHandle;
    final deliveryKeyId = device.relayDeliveryKeyId;
    if (deliveryHandle == null || deliveryKeyId == null) {
      throw StateError('Pending desktop relay revocation is incomplete.');
    }
    await relayClient.revokeDeliveryCredential(
      deliveryHandle: deliveryHandle,
      deliveryKeyId: deliveryKeyId,
      deliverySecret: secret,
      request: RemoteCodingRelayDeliveryCredentialRevocationRequest(
        requestedAt: clock().toUtc(),
      ),
    );
    return repository.clearDesktopRelayCredential(deviceId);
  }

  RemoteCodingPairedDevice _requirePairedDevice(String deviceId) {
    return repository.loadServerSettings().pairedDevices.firstWhere(
      (device) => device.id == deviceId,
      orElse: () => throw StateError('Remote coding device was not found.'),
    );
  }
}
