import 'package:uuid/uuid.dart';

import 'remote_coding_notification_relay_client.dart';
import 'remote_coding_notification_relay_contract.dart';
import 'remote_coding_repository.dart';

final class RemoteCodingMobileRelayRegistrationCoordinator {
  RemoteCodingMobileRelayRegistrationCoordinator({
    required this.repository,
    required this.relayClient,
    required this.clock,
    String Function()? installationIdFactory,
  }) : installationIdFactory = installationIdFactory ?? const Uuid().v4;

  final RemoteCodingRepository repository;
  final RemoteCodingNotificationRelayClient relayClient;
  final RemoteCodingRelayClock clock;
  final String Function() installationIdFactory;

  Future<RemoteCodingRelayRegistrationResponse> ensureRegistered({
    required RemoteCodingRelayPlatform platform,
    required String fcmRegistrationToken,
    required String appCheckToken,
  }) async {
    final normalizedFcmToken = fcmRegistrationToken.trim();
    final normalizedAppCheckToken = appCheckToken.trim();
    if (normalizedFcmToken.isEmpty || normalizedAppCheckToken.isEmpty) {
      throw const FormatException(
        'FCM and Firebase App Check tokens are required.',
      );
    }
    final now = clock().toUtc();
    final existing = await repository.loadMobileRelayRegistration();
    if (existing != null && existing.expiresAt.toUtc().isAfter(now)) {
      await relayClient.rotateFcmToken(
        deliveryHandle: existing.deliveryHandle,
        managementKeyId: existing.managementKeyId,
        managementSecret: existing.managementSecret,
        request: RemoteCodingRelayTokenRotationRequest(
          fcmRegistrationToken: normalizedFcmToken,
        ),
      );
      return existing;
    }
    if (existing != null) {
      await repository.clearMobileRelayRegistration();
    }
    final installationId = await repository
        .loadOrCreateMobileRelayInstallationId(installationIdFactory);
    final registration = await relayClient.register(
      request: RemoteCodingRelayRegistrationRequest(
        installationId: installationId,
        platform: platform,
        fcmRegistrationToken: normalizedFcmToken,
        requestedAt: now,
      ),
      appCheckToken: normalizedAppCheckToken,
    );
    if (!registration.expiresAt.toUtc().isAfter(now)) {
      throw StateError('Relay returned an expired mobile registration.');
    }
    try {
      await repository.saveMobileRelayRegistration(registration);
    } catch (_) {
      await _revokeUnpersistedRegistration(registration);
      rethrow;
    }
    return registration;
  }

  Future<void> rotateToken(String fcmRegistrationToken) async {
    final normalizedFcmToken = fcmRegistrationToken.trim();
    if (normalizedFcmToken.isEmpty) {
      throw const FormatException('FCM registration token is required.');
    }
    final registration = await repository.loadMobileRelayRegistration();
    if (registration == null ||
        !registration.expiresAt.toUtc().isAfter(clock().toUtc())) {
      throw StateError('Mobile relay registration is unavailable or expired.');
    }
    await relayClient.rotateFcmToken(
      deliveryHandle: registration.deliveryHandle,
      managementKeyId: registration.managementKeyId,
      managementSecret: registration.managementSecret,
      request: RemoteCodingRelayTokenRotationRequest(
        fcmRegistrationToken: normalizedFcmToken,
      ),
    );
  }

  Future<void> revokeRegistration() async {
    final registration = await repository.loadMobileRelayRegistration();
    if (registration == null) {
      return;
    }
    if (registration.expiresAt.toUtc().isAfter(clock().toUtc())) {
      await relayClient.revokeRegistration(
        deliveryHandle: registration.deliveryHandle,
        managementKeyId: registration.managementKeyId,
        managementSecret: registration.managementSecret,
      );
    }
    await repository.clearMobileRelayRegistration();
  }

  Future<void> _revokeUnpersistedRegistration(
    RemoteCodingRelayRegistrationResponse registration,
  ) async {
    try {
      await relayClient.revokeRegistration(
        deliveryHandle: registration.deliveryHandle,
        managementKeyId: registration.managementKeyId,
        managementSecret: registration.managementSecret,
      );
    } catch (_) {
      // The local persistence error remains authoritative for the caller.
    }
  }
}
