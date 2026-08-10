import 'dart:async';
import 'dart:convert';

import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_mobile_notification_gateway.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_client.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_contract.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_providers.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_payload.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_receipt_store.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_repository.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_secure_store.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_mobile_notification_notifier.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_client_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 8, 10, 16);

  test(
    'permission is requested only when the user enables notifications',
    () async {
      final fixture = await _fixture(now);
      addTearDown(fixture.dispose);

      await fixture.waitForStatus(
        RemoteCodingMobileNotificationStatus.notDetermined,
      );
      expect(fixture.gateway.permissionRequestCount, 0);

      final enabled = await fixture.notifier.enable();

      expect(enabled, isTrue);
      expect(fixture.gateway.permissionRequestCount, 1);
      expect(fixture.notificationService.channelPreparationCount, 1);
      expect(fixture.relayClient.registrationCount, 1);
      expect(
        fixture.container.read(remoteCodingMobileNotificationProvider).status,
        RemoteCodingMobileNotificationStatus.enabled,
      );
      expect(fixture.repository.loadMobileRelayNotificationsEnabled(), isTrue);
    },
  );

  test(
    'WebSocket terminal events provide a deduplicated local fallback',
    () async {
      final fixture = await _fixture(now);
      addTearDown(fixture.dispose);
      await fixture.waitForStatus(
        RemoteCodingMobileNotificationStatus.notDetermined,
      );
      final notification = RemoteCodingNotificationPayload.fromFcmData(
        _terminalData(now),
      );

      fixture.clientNotifier.emitTerminalNotification(notification);
      await _waitUntil(
        () => fixture.notificationService.shownNotifications.length == 1,
      );
      fixture.clientNotifier.emitTerminalNotification(notification);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fixture.notificationService.shownNotifications, hasLength(1));
    },
  );

  test(
    'denied permission remains visible and creates no relay registration',
    () async {
      final fixture = await _fixture(
        now,
        requestedPermission: RemoteCodingNotificationPermission.denied,
      );
      addTearDown(fixture.dispose);
      await fixture.waitForStatus(
        RemoteCodingMobileNotificationStatus.notDetermined,
      );

      final enabled = await fixture.notifier.enable();

      expect(enabled, isFalse);
      final state = fixture.container.read(
        remoteCodingMobileNotificationProvider,
      );
      expect(state.status, RemoteCodingMobileNotificationStatus.denied);
      expect(state.message, contains('system settings'));
      expect(fixture.relayClient.registrationCount, 0);
    },
  );

  test('FCM token refresh rotates the persisted relay registration', () async {
    final fixture = await _fixture(now);
    addTearDown(fixture.dispose);
    await fixture.waitForStatus(
      RemoteCodingMobileNotificationStatus.notDetermined,
    );
    expect(await fixture.notifier.enable(), isTrue);

    fixture.gateway.tokenRefreshController.add('fcm-token-refreshed');
    await _waitUntil(() => fixture.relayClient.rotationCount == 1);

    expect(fixture.relayClient.rotatedFcmToken, 'fcm-token-refreshed');
    expect(
      fixture.container.read(remoteCodingMobileNotificationProvider).status,
      RemoteCodingMobileNotificationStatus.enabled,
    );
  });

  test('revocation failure retains enabled state for retry', () async {
    final fixture = await _fixture(now);
    addTearDown(fixture.dispose);
    await fixture.waitForStatus(
      RemoteCodingMobileNotificationStatus.notDetermined,
    );
    expect(await fixture.notifier.enable(), isTrue);
    fixture.relayClient.revocationFailuresRemaining = 1;

    expect(await fixture.notifier.disable(), isFalse);

    expect(fixture.repository.loadMobileRelayNotificationsEnabled(), isTrue);
    expect(await fixture.repository.loadMobileRelayRegistration(), isNotNull);
    expect(await fixture.notifier.disable(), isTrue);
    expect(fixture.repository.loadMobileRelayNotificationsEnabled(), isFalse);
    expect(fixture.gateway.tokenDisableCount, 1);
  });

  test(
    'foreground and tapped FCM data use the frozen payload contract',
    () async {
      final fixture = await _fixture(now);
      addTearDown(fixture.dispose);
      await fixture.waitForStatus(
        RemoteCodingMobileNotificationStatus.notDetermined,
      );
      expect(await fixture.notifier.enable(), isTrue);
      final data = _terminalData(now);

      fixture.gateway.foregroundController.add(data);
      await _waitUntil(
        () =>
            fixture.container
                .read(remoteCodingMobileNotificationProvider)
                .lastForegroundNotification !=
            null,
      );
      fixture.gateway.tapController.add(data);
      await _waitUntil(
        () =>
            fixture.container
                .read(remoteCodingMobileNotificationProvider)
                .pendingNotificationTap !=
            null,
      );

      final state = fixture.container.read(
        remoteCodingMobileNotificationProvider,
      );
      expect(state.lastForegroundNotification?.eventId, 'event_123456');
      fixture.gateway.foregroundController.add(data);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fixture.notificationService.shownNotifications, hasLength(1));
      expect(state.pendingNotificationTap?.conversationId, 'conversation_123');
      fixture.notifier.clearPendingNotificationTap();
      expect(
        fixture.container
            .read(remoteCodingMobileNotificationProvider)
            .pendingNotificationTap,
        isNull,
      );
    },
  );

  test(
    'local notification taps use the same frozen payload contract',
    () async {
      final fixture = await _fixture(now);
      addTearDown(fixture.dispose);
      await fixture.waitForStatus(
        RemoteCodingMobileNotificationStatus.notDetermined,
      );
      fixture.notificationService.tapController.add(
        jsonEncode(_terminalData(now)),
      );

      await _waitUntil(
        () =>
            fixture.container
                .read(remoteCodingMobileNotificationProvider)
                .pendingNotificationTap !=
            null,
      );

      expect(
        fixture.container
            .read(remoteCodingMobileNotificationProvider)
            .pendingNotificationTap
            ?.eventId,
        'event_123456',
      );
    },
  );
}

Map<String, dynamic> _terminalData(DateTime now) => <String, dynamic>{
  'kind': 'remote_coding_run_terminal',
  'schemaVersion': '1',
  'eventId': 'event_123456',
  'turnId': 'turn_1234567',
  'conversationId': 'conversation_123',
  'outcome': 'completed',
  'title': 'Remote coding completed',
  'body': 'Your remote coding task completed.',
  'completedAt': now.toIso8601String(),
};

Future<_Fixture> _fixture(
  DateTime now, {
  RemoteCodingNotificationPermission requestedPermission =
      RemoteCodingNotificationPermission.authorized,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final repository = RemoteCodingRepository(
    preferences,
    secureStore: _MemorySecureStore(),
  );
  final gateway = _FakeNotificationGateway(
    requestedPermission: requestedPermission,
  );
  final relayClient = _FakeRelayClient(now);
  final notificationService = _FakeNotificationService();
  final clientNotifier = _FakeRemoteCodingClientNotifier();
  final container = ProviderContainer(
    overrides: [
      remoteCodingRepositoryProvider.overrideWithValue(repository),
      remoteCodingMobileNotificationGatewayProvider.overrideWithValue(gateway),
      remoteCodingNotificationRelayClientProvider.overrideWithValue(
        relayClient,
      ),
      remoteCodingNotificationReceiptStoreProvider.overrideWithValue(
        RemoteCodingNotificationReceiptStore(preferences),
      ),
      notificationServiceProvider.overrideWithValue(notificationService),
      remoteCodingClientProvider.overrideWith(() => clientNotifier),
    ],
  );
  container.read(remoteCodingMobileNotificationProvider);
  return _Fixture(
    container: container,
    repository: repository,
    gateway: gateway,
    relayClient: relayClient,
    notificationService: notificationService,
    clientNotifier: clientNotifier,
  );
}

final class _Fixture {
  const _Fixture({
    required this.container,
    required this.repository,
    required this.gateway,
    required this.relayClient,
    required this.notificationService,
    required this.clientNotifier,
  });

  final ProviderContainer container;
  final RemoteCodingRepository repository;
  final _FakeNotificationGateway gateway;
  final _FakeRelayClient relayClient;
  final _FakeNotificationService notificationService;
  final _FakeRemoteCodingClientNotifier clientNotifier;

  RemoteCodingMobileNotificationNotifier get notifier =>
      container.read(remoteCodingMobileNotificationProvider.notifier);

  Future<void> waitForStatus(RemoteCodingMobileNotificationStatus status) {
    return _waitUntil(
      () =>
          container.read(remoteCodingMobileNotificationProvider).status ==
          status,
    );
  }

  void dispose() {
    container.dispose();
    unawaited(gateway.tokenRefreshController.close());
    unawaited(gateway.foregroundController.close());
    unawaited(gateway.tapController.close());
  }
}

final class _FakeRemoteCodingClientNotifier extends RemoteCodingClientNotifier {
  @override
  RemoteCodingClientState build() => const RemoteCodingClientState();

  void emitTerminalNotification(RemoteCodingNotificationPayload notification) {
    state = state.copyWith(lastTerminalNotification: notification);
  }
}

final class _FakeNotificationService extends NotificationService {
  final tapController = StreamController<String>.broadcast();
  final shownNotifications = <RemoteCodingNotificationPayload>[];
  int channelPreparationCount = 0;

  @override
  Stream<String> get notificationTapPayloads => tapController.stream;

  @override
  Future<void> init() async {}

  @override
  Future<String?> getInitialNotificationTapPayload() async => null;

  @override
  Future<void> prepareRemoteCodingNotificationChannel() async {
    channelPreparationCount += 1;
  }

  @override
  Future<void> showRemoteCodingTerminalNotification(
    RemoteCodingNotificationPayload notification,
  ) async {
    shownNotifications.add(notification);
  }

  @override
  void dispose() {
    unawaited(tapController.close());
  }
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for asynchronous notification state.');
}

final class _FakeNotificationGateway
    implements RemoteCodingMobileNotificationGateway {
  _FakeNotificationGateway({required this.requestedPermission});

  final RemoteCodingNotificationPermission requestedPermission;
  final tokenRefreshController = StreamController<String>.broadcast();
  final foregroundController =
      StreamController<Map<String, dynamic>>.broadcast();
  final tapController = StreamController<Map<String, dynamic>>.broadcast();
  int permissionRequestCount = 0;
  int tokenDisableCount = 0;

  @override
  RemoteCodingRelayPlatform get platform => RemoteCodingRelayPlatform.ios;

  @override
  Future<RemoteCodingNotificationPermission> initialize() async =>
      RemoteCodingNotificationPermission.notDetermined;

  @override
  Future<RemoteCodingNotificationPermission> requestPermission() async {
    permissionRequestCount += 1;
    return requestedPermission;
  }

  @override
  Future<String> getAppCheckToken() async => 'app-check-token';

  @override
  Future<String> getFcmToken() async => 'fcm-token';

  @override
  Future<void> disableFcmToken() async {
    tokenDisableCount += 1;
  }

  @override
  Stream<String> get onTokenRefresh => tokenRefreshController.stream;

  @override
  Stream<Map<String, dynamic>> get onForegroundMessage =>
      foregroundController.stream;

  @override
  Stream<Map<String, dynamic>> get onNotificationTap => tapController.stream;

  @override
  Future<Map<String, dynamic>?> getInitialNotificationTap() async => null;
}

final class _FakeRelayClient implements RemoteCodingNotificationRelayClient {
  _FakeRelayClient(this.now);

  final DateTime now;
  int registrationCount = 0;
  int rotationCount = 0;
  int revocationFailuresRemaining = 0;
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
