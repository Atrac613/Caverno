import 'package:caverno/features/remote_coding/data/remote_coding_notification_payload.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_client.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_contract.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_repository.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_secure_store.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_terminal_notification_delivery.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 8, 10, 16);
  late RemoteCodingRepository repository;
  late _FakeRelayClient relayClient;
  late List<Duration> retryDelays;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = RemoteCodingRepository(
      await SharedPreferences.getInstance(),
      secureStore: _MemorySecureStore(),
    );
    relayClient = _FakeRelayClient();
    retryDelays = <Duration>[];
  });

  test(
    'active devices receive concurrent best-effort delivery with retries',
    () async {
      final devices = <RemoteCodingPairedDevice>[
        _device('device_1', now),
        _device('device_2', now),
        _device(
          'device_revoking',
          now,
          state: RemoteCodingRelayCredentialState.pendingRevocation,
        ),
        _device('device_expired', now, expiresAt: now),
      ];
      await repository.saveDesktopRelayDeliverySecret(
        deviceId: 'device_1',
        deliverySecret: 'secret_1',
      );
      await repository.saveDesktopRelayDeliverySecret(
        deviceId: 'device_2',
        deliverySecret: 'secret_2',
      );
      relayClient.transientFailuresByHandle['handle_device_1'] = 2;
      final service = RemoteCodingTerminalNotificationDeliveryService(
        repository: repository,
        relayClient: relayClient,
        clock: () => now,
        retryDelay: (delay) async => retryDelays.add(delay),
      );

      final report = await service.deliver(
        notification: _notification(now),
        devices: devices,
      );

      expect(report.configuredDeviceCount, 4);
      expect(report.attemptedDeviceCount, 2);
      expect(report.deliveredDeviceCount, 2);
      expect(report.failedDeviceCount, 0);
      expect(relayClient.attemptsByHandle['handle_device_1'], 3);
      expect(relayClient.attemptsByHandle['handle_device_2'], 1);
      expect(retryDelays, const [
        Duration(milliseconds: 250),
        Duration(seconds: 1),
      ]);
      expect(
        relayClient.notifications.every(
          (notification) => notification.eventId == 'event_123456',
        ),
        isTrue,
      );
    },
  );

  test(
    'non-retryable rejection and missing secret are isolated per device',
    () async {
      final devices = <RemoteCodingPairedDevice>[
        _device('device_rejected', now),
        _device('device_missing_secret', now),
      ];
      await repository.saveDesktopRelayDeliverySecret(
        deviceId: 'device_rejected',
        deliverySecret: 'secret_rejected',
      );
      relayClient.statusByHandle['handle_device_rejected'] = 401;
      final service = RemoteCodingTerminalNotificationDeliveryService(
        repository: repository,
        relayClient: relayClient,
        clock: () => now,
        retryDelay: (delay) async => retryDelays.add(delay),
      );

      final report = await service.deliver(
        notification: _notification(now),
        devices: devices,
      );

      expect(report.attemptedDeviceCount, 2);
      expect(report.deliveredDeviceCount, 0);
      expect(report.failedDeviceCount, 2);
      expect(relayClient.attemptsByHandle['handle_device_rejected'], 1);
      expect(retryDelays, isEmpty);
    },
  );

  test('relay replay response is accepted as idempotent delivery', () async {
    final device = _device('device_replay', now);
    await repository.saveDesktopRelayDeliverySecret(
      deviceId: device.id,
      deliverySecret: 'secret_replay',
    );
    relayClient.statusByHandle['handle_device_replay'] = 409;
    final service = RemoteCodingTerminalNotificationDeliveryService(
      repository: repository,
      relayClient: relayClient,
      clock: () => now,
      retryDelay: (_) async {},
    );

    final report = await service.deliver(
      notification: _notification(now),
      devices: [device],
    );

    expect(report.deliveredDeviceCount, 1);
    expect(report.failedDeviceCount, 0);
  });
}

RemoteCodingPairedDevice _device(
  String id,
  DateTime now, {
  RemoteCodingRelayCredentialState state =
      RemoteCodingRelayCredentialState.active,
  DateTime? expiresAt,
}) {
  return RemoteCodingPairedDevice(
    id: id,
    name: id,
    tokenHash: 'token_hash_$id',
    createdAt: now,
    lastSeenAt: now,
    relayDeliveryHandle: 'handle_$id',
    relayDeliveryKeyId: 'key_$id',
    relayDelegationId: 'delegation_$id',
    relayCredentialExpiresAt: expiresAt ?? now.add(const Duration(days: 30)),
    relayCredentialState: state,
  );
}

RemoteCodingNotificationPayload _notification(DateTime now) {
  return RemoteCodingNotificationPayload(
    eventId: 'event_123456',
    turnId: 'turn_1234567',
    conversationId: 'conversation_123',
    outcome: RemoteCodingNotificationOutcome.completed,
    title: 'Remote coding completed',
    body: 'Your remote coding task completed.',
    completedAt: now,
  );
}

final class _FakeRelayClient implements RemoteCodingNotificationRelayClient {
  final Map<String, int> transientFailuresByHandle = <String, int>{};
  final Map<String, int> statusByHandle = <String, int>{};
  final Map<String, int> attemptsByHandle = <String, int>{};
  final List<RemoteCodingNotificationPayload> notifications =
      <RemoteCodingNotificationPayload>[];

  @override
  Future<void> deliver({
    required String deliveryHandle,
    required String deliveryKeyId,
    required String deliverySecret,
    required RemoteCodingRelayDeliveryRequest request,
  }) async {
    attemptsByHandle.update(
      deliveryHandle,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    final transientFailures = transientFailuresByHandle[deliveryHandle] ?? 0;
    if (transientFailures > 0) {
      transientFailuresByHandle[deliveryHandle] = transientFailures - 1;
      throw const RemoteCodingRelayClientException(
        operation: 'notification delivery',
        failure: RemoteCodingRelayClientFailure.transport,
      );
    }
    final status = statusByHandle[deliveryHandle];
    if (status != null) {
      throw RemoteCodingRelayClientException(
        operation: 'notification delivery',
        failure: RemoteCodingRelayClientFailure.rejected,
        statusCode: status,
      );
    }
    notifications.add(request.notification);
  }

  @override
  Future<RemoteCodingRelayRegistrationResponse> register({
    required RemoteCodingRelayRegistrationRequest request,
    required String appCheckToken,
  }) => throw UnimplementedError();

  @override
  Future<void> rotateFcmToken({
    required String deliveryHandle,
    required String managementKeyId,
    required String managementSecret,
    required RemoteCodingRelayTokenRotationRequest request,
  }) => throw UnimplementedError();

  @override
  Future<void> revokeRegistration({
    required String deliveryHandle,
    required String managementKeyId,
    required String managementSecret,
  }) => throw UnimplementedError();

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
