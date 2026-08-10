import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_client.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_contract.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_provisioning.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_repository.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_secure_store.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 8, 10, 16);
  late _MemorySecureStore secureStore;
  late RemoteCodingRepository repository;
  late _FakeRelayClient relayClient;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    secureStore = _MemorySecureStore();
    repository = RemoteCodingRepository(prefs, secureStore: secureStore);
    relayClient = _FakeRelayClient(now: now);
    await repository.saveServerSettings(
      RemoteCodingServerSettings(
        enabled: true,
        pairedDevices: [
          RemoteCodingPairedDevice(
            id: 'device_123',
            name: 'Phone',
            tokenHash: 'token-hash',
            createdAt: now,
            lastSeenAt: now,
          ),
        ],
      ),
    );
  });

  test(
    'mobile authorizes a device-bound delegation with management scope',
    () async {
      await repository.saveMobileRelayRegistration(
        RemoteCodingRelayRegistrationResponse(
          deliveryHandle: 'delivery_handle_1',
          managementKeyId: 'management-key-1',
          managementSecret: 'management-secret',
          expiresAt: now.add(const Duration(days: 30)),
        ),
      );
      final coordinator = RemoteCodingMobileRelayDelegationCoordinator(
        repository: repository,
        relayClient: relayClient,
        clock: () => now,
      );

      final result = await coordinator.createDelegation(
        challengeId: 'challenge_123',
        challengeDigest: List.filled(64, 'a').join(),
        targetDeviceId: 'device_123',
      );

      expect(result.delegationId, 'delegation_123');
      expect(relayClient.createdWithManagementKeyId, 'management-key-1');
      expect(relayClient.createdWithManagementSecret, 'management-secret');
      expect(relayClient.creationRequest?.targetDeviceId, 'device_123');
    },
  );

  test('desktop persists the credential before relay activation', () async {
    final coordinator = RemoteCodingDesktopRelayProvisioningCoordinator(
      repository: repository,
      relayClient: relayClient,
      clock: () => now,
    );
    relayClient.onActivate = () async {
      final stored = repository.loadServerSettings().pairedDevices.single;
      expect(
        stored.relayCredentialState,
        RemoteCodingRelayCredentialState.pendingActivation,
      );
      expect(
        await repository.loadDesktopRelayDeliverySecret('device_123'),
        'desktop-delivery-secret',
      );
    };

    final active = await coordinator.redeemAndActivate(
      deviceId: 'device_123',
      delegationId: 'delegation_123',
      challengeId: 'challenge_123',
      challengeSecret: List.filled(43, 's').join(),
      idempotencyKey: 'idempotency_123',
    );

    expect(
      active.relayCredentialState,
      RemoteCodingRelayCredentialState.active,
    );
    expect(active.hasUsableNotificationRelayAt(now), isTrue);
    expect(relayClient.redemptionCount, 1);
    expect(relayClient.activationCount, 1);
  });

  test('activation failure retains retryable credential state', () async {
    final coordinator = RemoteCodingDesktopRelayProvisioningCoordinator(
      repository: repository,
      relayClient: relayClient,
      clock: () => now,
    );
    relayClient.activationFailuresRemaining = 1;

    await expectLater(
      coordinator.redeemAndActivate(
        deviceId: 'device_123',
        delegationId: 'delegation_123',
        challengeId: 'challenge_123',
        challengeSecret: List.filled(43, 's').join(),
        idempotencyKey: 'idempotency_123',
      ),
      throwsStateError,
    );
    expect(
      repository.loadServerSettings().pairedDevices.single.relayCredentialState,
      RemoteCodingRelayCredentialState.pendingActivation,
    );
    expect(
      await repository.loadDesktopRelayDeliverySecret('device_123'),
      'desktop-delivery-secret',
    );

    final active = await coordinator.retryPendingActivation(
      deviceId: 'device_123',
      delegationId: 'delegation_123',
    );

    expect(
      active.relayCredentialState,
      RemoteCodingRelayCredentialState.active,
    );
    expect(relayClient.redemptionCount, 1);
    expect(relayClient.activationCount, 2);
  });

  test(
    'revocation failure retains secret until an idempotent retry succeeds',
    () async {
      final coordinator = RemoteCodingDesktopRelayProvisioningCoordinator(
        repository: repository,
        relayClient: relayClient,
        clock: () => now,
      );
      await repository.installPendingDesktopRelayCredential(
        deviceId: 'device_123',
        credential: relayClient.credential,
      );
      await repository.markDesktopRelayCredentialActive(
        deviceId: 'device_123',
        deliveryKeyId: relayClient.credential.deliveryKeyId,
      );
      relayClient.revocationFailuresRemaining = 1;

      await expectLater(
        coordinator.revokeCredential('device_123'),
        throwsStateError,
      );
      expect(
        repository
            .loadServerSettings()
            .pairedDevices
            .single
            .relayCredentialState,
        RemoteCodingRelayCredentialState.pendingRevocation,
      );
      expect(
        await repository.loadDesktopRelayDeliverySecret('device_123'),
        'desktop-delivery-secret',
      );

      final cleared = await coordinator.retryPendingRevocation('device_123');

      expect(cleared.hasNotificationRelay, isFalse);
      expect(
        await repository.loadDesktopRelayDeliverySecret('device_123'),
        isNull,
      );
      expect(relayClient.revocationCount, 2);
    },
  );

  test('mobile delegation fails closed when registration is expired', () async {
    await repository.saveMobileRelayRegistration(
      RemoteCodingRelayRegistrationResponse(
        deliveryHandle: 'delivery_handle_1',
        managementKeyId: 'management-key-1',
        managementSecret: 'management-secret',
        expiresAt: now,
      ),
    );
    final coordinator = RemoteCodingMobileRelayDelegationCoordinator(
      repository: repository,
      relayClient: relayClient,
      clock: () => now,
    );

    await expectLater(
      coordinator.createDelegation(
        challengeId: 'challenge_123',
        challengeDigest: List.filled(64, 'a').join(),
        targetDeviceId: 'device_123',
      ),
      throwsStateError,
    );
    expect(relayClient.creationCount, 0);
  });
}

final class _FakeRelayClient implements RemoteCodingNotificationRelayClient {
  _FakeRelayClient({required this.now});

  final DateTime now;
  int creationCount = 0;
  int redemptionCount = 0;
  int activationCount = 0;
  int revocationCount = 0;
  int activationFailuresRemaining = 0;
  int revocationFailuresRemaining = 0;
  String? createdWithManagementKeyId;
  String? createdWithManagementSecret;
  RemoteCodingRelayDelegationCreationRequest? creationRequest;
  Future<void> Function()? onActivate;

  RemoteCodingRelayDelegationRedemptionResponse get credential =>
      RemoteCodingRelayDelegationRedemptionResponse(
        delegationId: 'delegation_123',
        deliveryHandle: 'delivery_handle_1',
        deliveryKeyId: 'delivery-key-123',
        deliverySecret: 'desktop-delivery-secret',
        expiresAt: now.add(const Duration(days: 30)),
      );

  @override
  Future<RemoteCodingRelayDelegationCreationResponse> createDelegation({
    required String deliveryHandle,
    required String managementKeyId,
    required String managementSecret,
    required RemoteCodingRelayDelegationCreationRequest request,
  }) async {
    creationCount += 1;
    createdWithManagementKeyId = managementKeyId;
    createdWithManagementSecret = managementSecret;
    creationRequest = request;
    return RemoteCodingRelayDelegationCreationResponse(
      delegationId: 'delegation_123',
      challengeId: request.challengeId,
      targetDeviceId: request.targetDeviceId,
      expiresAt: now.add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<RemoteCodingRelayDelegationRedemptionResponse> redeemDelegation({
    required String delegationId,
    required RemoteCodingRelayDelegationRedemptionRequest request,
  }) async {
    redemptionCount += 1;
    return credential;
  }

  @override
  Future<void> activateDelegation({
    required String deliveryHandle,
    required String delegationId,
    required String deliveryKeyId,
    required String deliverySecret,
    required RemoteCodingRelayDelegationActivationRequest request,
  }) async {
    activationCount += 1;
    await onActivate?.call();
    if (activationFailuresRemaining > 0) {
      activationFailuresRemaining -= 1;
      throw StateError('activation failed');
    }
  }

  @override
  Future<void> revokeDeliveryCredential({
    required String deliveryHandle,
    required String deliveryKeyId,
    required String deliverySecret,
    required RemoteCodingRelayDeliveryCredentialRevocationRequest request,
  }) async {
    revocationCount += 1;
    if (revocationFailuresRemaining > 0) {
      revocationFailuresRemaining -= 1;
      throw StateError('revocation failed');
    }
  }

  @override
  Future<void> deliver({
    required String deliveryHandle,
    required String deliveryKeyId,
    required String deliverySecret,
    required RemoteCodingRelayDeliveryRequest request,
  }) => throw UnimplementedError();

  @override
  Future<RemoteCodingRelayRegistrationResponse> register({
    required RemoteCodingRelayRegistrationRequest request,
    required String appCheckToken,
  }) => throw UnimplementedError();

  @override
  Future<void> revokeRegistration({
    required String deliveryHandle,
    required String managementKeyId,
    required String managementSecret,
  }) => throw UnimplementedError();

  @override
  Future<void> rotateFcmToken({
    required String deliveryHandle,
    required String managementKeyId,
    required String managementSecret,
    required RemoteCodingRelayTokenRotationRequest request,
  }) => throw UnimplementedError();
}

final class _MemorySecureStore implements RemoteCodingSecureStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}
