import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_client.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_contract.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_mobile_registration.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_repository.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_secure_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 8, 10, 16);
  late RemoteCodingRepository repository;
  late _FakeRelayClient relayClient;
  late RemoteCodingMobileRelayRegistrationCoordinator coordinator;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = RemoteCodingRepository(
      await SharedPreferences.getInstance(),
      secureStore: _MemorySecureStore(),
    );
    relayClient = _FakeRelayClient(now);
    coordinator = RemoteCodingMobileRelayRegistrationCoordinator(
      repository: repository,
      relayClient: relayClient,
      clock: () => now,
      installationIdFactory: () => 'installation_123',
    );
  });

  test(
    'new mobile registration uses App Check and persists management scope',
    () async {
      final registration = await coordinator.ensureRegistered(
        platform: RemoteCodingRelayPlatform.ios,
        fcmRegistrationToken: 'fcm-token-1',
        appCheckToken: 'app-check-token',
      );

      expect(relayClient.registrationCount, 1);
      expect(
        relayClient.registrationRequest?.installationId,
        'installation_123',
      );
      expect(
        relayClient.registrationRequest?.platform,
        RemoteCodingRelayPlatform.ios,
      );
      expect(relayClient.registrationAppCheckToken, 'app-check-token');
      expect(
        (await repository.loadMobileRelayRegistration())?.toJson(),
        registration.toJson(),
      );
    },
  );

  test(
    'existing registration rotates the token without creating an orphan',
    () async {
      await repository.saveMobileRelayRegistration(relayClient.registration);

      final registration = await coordinator.ensureRegistered(
        platform: RemoteCodingRelayPlatform.android,
        fcmRegistrationToken: 'fcm-token-refreshed',
        appCheckToken: 'app-check-token',
      );

      expect(
        registration.deliveryHandle,
        relayClient.registration.deliveryHandle,
      );
      expect(relayClient.registrationCount, 0);
      expect(relayClient.rotationCount, 1);
      expect(relayClient.rotatedFcmToken, 'fcm-token-refreshed');
    },
  );

  test('revocation failure keeps the local management credential', () async {
    await repository.saveMobileRelayRegistration(relayClient.registration);
    relayClient.revocationFailuresRemaining = 1;

    await expectLater(coordinator.revokeRegistration(), throwsStateError);

    expect(await repository.loadMobileRelayRegistration(), isNotNull);
    await coordinator.revokeRegistration();
    expect(await repository.loadMobileRelayRegistration(), isNull);
  });

  test(
    'expired registration is replaced with the stable installation ID',
    () async {
      await repository.saveMobileRelayRegistration(
        RemoteCodingRelayRegistrationResponse(
          deliveryHandle: 'expired_handle',
          managementKeyId: 'expired_key',
          managementSecret: 'expired_secret',
          expiresAt: now,
        ),
      );

      await coordinator.ensureRegistered(
        platform: RemoteCodingRelayPlatform.ios,
        fcmRegistrationToken: 'fcm-token-new',
        appCheckToken: 'app-check-token',
      );

      expect(relayClient.registrationCount, 1);
      expect(relayClient.rotationCount, 0);
      expect(
        relayClient.registrationRequest?.installationId,
        'installation_123',
      );
    },
  );
}

final class _FakeRelayClient implements RemoteCodingNotificationRelayClient {
  _FakeRelayClient(this.now);

  final DateTime now;
  int registrationCount = 0;
  int rotationCount = 0;
  int revocationCount = 0;
  int revocationFailuresRemaining = 0;
  RemoteCodingRelayRegistrationRequest? registrationRequest;
  String? registrationAppCheckToken;
  String? rotatedFcmToken;

  late final registration = RemoteCodingRelayRegistrationResponse(
    deliveryHandle: 'delivery_handle_1',
    managementKeyId: 'management_key_1',
    managementSecret: 'management_secret_1',
    expiresAt: now.add(const Duration(days: 30)),
  );

  @override
  Future<RemoteCodingRelayRegistrationResponse> register({
    required RemoteCodingRelayRegistrationRequest request,
    required String appCheckToken,
  }) async {
    registrationCount += 1;
    registrationRequest = request;
    registrationAppCheckToken = appCheckToken;
    return registration;
  }

  @override
  Future<void> rotateFcmToken({
    required String deliveryHandle,
    required String managementKeyId,
    required String managementSecret,
    required RemoteCodingRelayTokenRotationRequest request,
  }) async {
    rotationCount += 1;
    rotatedFcmToken = request.fcmRegistrationToken;
  }

  @override
  Future<void> revokeRegistration({
    required String deliveryHandle,
    required String managementKeyId,
    required String managementSecret,
  }) async {
    revocationCount += 1;
    if (revocationFailuresRemaining > 0) {
      revocationFailuresRemaining -= 1;
      throw StateError('relay unavailable');
    }
  }

  @override
  Future<RemoteCodingRelayDelegationCreationResponse> createDelegation({
    required String deliveryHandle,
    required String managementKeyId,
    required String managementSecret,
    required RemoteCodingRelayDelegationCreationRequest request,
  }) => throw UnimplementedError();

  @override
  Future<RemoteCodingRelayDelegationRedemptionResponse> redeemDelegation({
    required String delegationId,
    required RemoteCodingRelayDelegationRedemptionRequest request,
  }) => throw UnimplementedError();

  @override
  Future<void> activateDelegation({
    required String deliveryHandle,
    required String delegationId,
    required String deliveryKeyId,
    required String deliverySecret,
    required RemoteCodingRelayDelegationActivationRequest request,
  }) => throw UnimplementedError();

  @override
  Future<void> revokeDeliveryCredential({
    required String deliveryHandle,
    required String deliveryKeyId,
    required String deliverySecret,
    required RemoteCodingRelayDeliveryCredentialRevocationRequest request,
  }) => throw UnimplementedError();

  @override
  Future<void> deliver({
    required String deliveryHandle,
    required String deliveryKeyId,
    required String deliverySecret,
    required RemoteCodingRelayDeliveryRequest request,
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
