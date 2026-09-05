import 'dart:async';
import 'dart:convert';

import 'package:caverno/core/services/app_lifecycle_service.dart';
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
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_client_notifier.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
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

  group('remote approvals reach the phone', () {
    RemoteCodingHost host() => RemoteCodingHost(
      id: 'host-1',
      name: 'studio-mac',
      host: '192.168.100.5',
      port: 8443,
      createdAt: now,
      updatedAt: now,
      certificatePin: 'pin',
    );

    // Shaped the way the server actually sends it: the title is the kind's
    // label and the command lives in the detail.
    RemoteCodingApproval approval({
      String id = 'approval-1',
      RemoteCodingApprovalKind kind = RemoteCodingApprovalKind.localCommand,
    }) => RemoteCodingApproval(
      id: id,
      kind: kind,
      title: 'Local Command Approval',
      subtitle: '/Users/dev/caverno',
      detail: 'dart analyze',
    );

    test('a blocked desktop turn raises an actionable notification', () async {
      // Before this the path did not exist: the Remote Coding server is
      // desktop-only, so a blocked desktop turn lived in
      // RemoteCodingClientState and showPendingApprovalNotification was raised
      // only from ChatNotifier.
      final fixture = await _fixture(now);
      addTearDown(fixture.dispose);
      await fixture.waitForStatus(
        RemoteCodingMobileNotificationStatus.notDetermined,
      );

      fixture.clientNotifier.emitPendingApproval(
        approval(),
        host: host(),
        currentConversationId: 'conversation-9',
      );
      await _waitUntil(
        () => fixture.notificationService.shownApprovals.isNotEmpty,
      );

      final raised = fixture.notificationService.shownApprovals.single;
      expect(raised.approvalId, 'approval-1');
      expect(raised.allowsDirectDecision, isTrue);
      expect(raised.conversationId, 'conversation-9');
      // Naming the host is load-bearing: "wants to run: dart analyze" without
      // saying which machine will run it is the failure this must not ship.
      expect(raised.title, 'studio-mac');
      expect(raised.body, contains('studio-mac'));
      // The command, not the kind's label. A button that approves an unseen
      // command defeats the approval gate it belongs to, and a wrist is where
      // it is most likely to be pressed without looking.
      expect(raised.body, contains('dart analyze'));
      expect(raised.body, isNot(contains('Local Command Approval')));
    });

    test('a git command is named by its command too', () async {
      final fixture = await _fixture(now);
      addTearDown(fixture.dispose);
      await fixture.waitForStatus(
        RemoteCodingMobileNotificationStatus.notDetermined,
      );

      fixture.clientNotifier.emitPendingApproval(
        const RemoteCodingApproval(
          id: 'approval-git',
          kind: RemoteCodingApprovalKind.gitCommand,
          title: 'Git Command Approval',
          subtitle: '/Users/dev/caverno',
          detail: 'git push --force',
        ),
        host: host(),
      );
      await _waitUntil(
        () => fixture.notificationService.shownApprovals.isNotEmpty,
      );

      expect(
        fixture.notificationService.shownApprovals.single.body,
        contains('git push --force'),
      );
    });

    test('a file approval is named by its operation and path', () async {
      // The server already puts the operation in the title for this kind, so
      // it must not be rewritten from the detail, which carries a preview.
      final fixture = await _fixture(now);
      addTearDown(fixture.dispose);
      await fixture.waitForStatus(
        RemoteCodingMobileNotificationStatus.notDetermined,
      );

      fixture.clientNotifier.emitPendingApproval(
        const RemoteCodingApproval(
          id: 'approval-file',
          kind: RemoteCodingApprovalKind.file,
          title: 'write lib/main.dart',
          subtitle: 'lib/main.dart',
          detail: 'void main() { ... }',
        ),
        host: host(),
      );
      await _waitUntil(
        () => fixture.notificationService.shownApprovals.isNotEmpty,
      );

      expect(
        fixture.notificationService.shownApprovals.single.body,
        contains('write lib/main.dart'),
      );
    });

    test('every remote kind is a truthful yes/no', () async {
      // file, localCommand and gitCommand are exhaustive on the wire and all
      // three are bare decisions, unlike the chat kinds that need credentials
      // or smoke arming.
      for (final kind in RemoteCodingApprovalKind.values) {
        final fixture = await _fixture(now);
        addTearDown(fixture.dispose);
        await fixture.waitForStatus(
          RemoteCodingMobileNotificationStatus.notDetermined,
        );

        fixture.clientNotifier.emitPendingApproval(
          approval(id: 'approval-${kind.name}', kind: kind),
          host: host(),
        );
        await _waitUntil(
          () => fixture.notificationService.shownApprovals.isNotEmpty,
        );

        expect(
          fixture.notificationService.shownApprovals.single.allowsDirectDecision,
          isTrue,
          reason: '${kind.name} must be answerable from the notification',
        );
      }
    });

    test('the same approval is not raised twice', () async {
      final fixture = await _fixture(now);
      addTearDown(fixture.dispose);
      await fixture.waitForStatus(
        RemoteCodingMobileNotificationStatus.notDetermined,
      );

      fixture.clientNotifier.emitPendingApproval(approval(), host: host());
      await _waitUntil(
        () => fixture.notificationService.shownApprovals.isNotEmpty,
      );
      fixture.clientNotifier.clearApproval();
      fixture.clientNotifier.emitPendingApproval(approval(), host: host());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(fixture.notificationService.shownApprovals, hasLength(1));
    });

    test('nothing is raised while the Remote Coding page is open', () async {
      // The page raises its own approval sheet, so a notification on top of it
      // asks the same question twice.
      final fixture = await _fixture(now);
      addTearDown(fixture.dispose);
      await fixture.waitForStatus(
        RemoteCodingMobileNotificationStatus.notDetermined,
      );
      fixture.notifier.setRemoteCodingPageVisible(true);

      fixture.clientNotifier.emitPendingApproval(approval(), host: host());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(fixture.notificationService.shownApprovals, isEmpty);
    });

    test('resolving on the desktop withdraws the notification', () async {
      // A notification whose buttons resolve nothing is worse than none: the
      // desktop already answered, and the phone would be offering a decision
      // that lands nowhere.
      final fixture = await _fixture(now);
      addTearDown(fixture.dispose);
      await fixture.waitForStatus(
        RemoteCodingMobileNotificationStatus.notDetermined,
      );

      fixture.clientNotifier.emitPendingApproval(
        approval(),
        host: host(),
        currentConversationId: 'conversation-9',
      );
      await _waitUntil(
        () => fixture.notificationService.shownApprovals.isNotEmpty,
      );
      fixture.clientNotifier.clearApproval();
      await _waitUntil(
        () => fixture
            .notificationService
            .cancelledApprovalConversationIds
            .isNotEmpty,
      );

      expect(
        fixture.notificationService.cancelledApprovalConversationIds,
        ['conversation-9'],
      );
    });

    test('nothing is withdrawn when nothing was raised', () async {
      final fixture = await _fixture(now);
      addTearDown(fixture.dispose);
      await fixture.waitForStatus(
        RemoteCodingMobileNotificationStatus.notDetermined,
      );
      fixture.notifier.setRemoteCodingPageVisible(true);

      fixture.clientNotifier.emitPendingApproval(approval(), host: host());
      fixture.clientNotifier.clearApproval();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        fixture.notificationService.cancelledApprovalConversationIds,
        isEmpty,
      );
    });

    test('a backgrounded app notifies even with the page mounted', () async {
      // Backgrounding does not dispose the page, so "the page is mounted" and
      // "the user is looking at it" are different facts. Conflating them meant
      // a phone left on the Coding tab — the tab a Remote Coding user is
      // obviously on — never notified at all.
      final fixture = await _fixture(now);
      addTearDown(fixture.dispose);
      await fixture.waitForStatus(
        RemoteCodingMobileNotificationStatus.notDetermined,
      );
      fixture.notifier.setRemoteCodingPageVisible(true);
      fixture.lifecycle.enterBackground();

      fixture.clientNotifier.emitPendingApproval(approval(), host: host());
      await _waitUntil(
        () => fixture.notificationService.shownApprovals.isNotEmpty,
      );

      expect(fixture.notificationService.shownApprovals, hasLength(1));
    });

    test('leaving the page lets the next approval through', () async {
      final fixture = await _fixture(now);
      addTearDown(fixture.dispose);
      await fixture.waitForStatus(
        RemoteCodingMobileNotificationStatus.notDetermined,
      );
      fixture.notifier.setRemoteCodingPageVisible(true);
      fixture.notifier.setRemoteCodingPageVisible(false);

      fixture.clientNotifier.emitPendingApproval(approval(), host: host());
      await _waitUntil(
        () => fixture.notificationService.shownApprovals.isNotEmpty,
      );

      expect(fixture.notificationService.shownApprovals, hasLength(1));
    });
  });
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
  bool withRelayClient = true,
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
  final lifecycle = _FakeAppLifecycleService();
  final container = ProviderContainer(
    overrides: [
      remoteCodingRepositoryProvider.overrideWithValue(repository),
      remoteCodingMobileNotificationGatewayProvider.overrideWithValue(gateway),
      remoteCodingNotificationRelayClientProvider.overrideWithValue(
        withRelayClient ? relayClient : null,
      ),
      remoteCodingNotificationReceiptStoreProvider.overrideWithValue(
        RemoteCodingNotificationReceiptStore(preferences),
      ),
      notificationServiceProvider.overrideWithValue(notificationService),
      remoteCodingClientProvider.overrideWith(() => clientNotifier),
      appLifecycleServiceProvider.overrideWithValue(lifecycle),
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
    lifecycle: lifecycle,
  );
}

/// Stands in for the observer-backed service so a test can background the app
/// without a widget binding.
final class _FakeAppLifecycleService implements AppLifecycleService {
  bool _isInBackground = false;
  DateTime? _backgroundSince;

  void enterBackground() {
    _isInBackground = true;
    _backgroundSince = DateTime.now();
  }

  @override
  bool get isInBackground => _isInBackground;

  @override
  DateTime? get backgroundSince => _backgroundSince;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final class _Fixture {
  const _Fixture({
    required this.container,
    required this.repository,
    required this.gateway,
    required this.relayClient,
    required this.notificationService,
    required this.clientNotifier,
    required this.lifecycle,
  });

  final ProviderContainer container;
  final RemoteCodingRepository repository;
  final _FakeNotificationGateway gateway;
  final _FakeRelayClient relayClient;
  final _FakeNotificationService notificationService;
  final _FakeRemoteCodingClientNotifier clientNotifier;
  final _FakeAppLifecycleService lifecycle;

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
  final resolvedApprovals = <({String id, bool approved})>[];

  @override
  RemoteCodingClientState build() => const RemoteCodingClientState();

  void emitTerminalNotification(RemoteCodingNotificationPayload notification) {
    state = state.copyWith(lastTerminalNotification: notification);
  }

  void emitPendingApproval(
    RemoteCodingApproval approval, {
    RemoteCodingHost? host,
    String? currentConversationId,
  }) {
    state = state.copyWith(
      pendingApproval: approval,
      host: host ?? state.host,
      currentConversationId: currentConversationId,
    );
  }

  void clearApproval() {
    state = state.copyWith(clearPendingApproval: true);
  }

  @override
  Future<void> resolveApproval({
    required String approvalId,
    required bool approved,
  }) async {
    resolvedApprovals.add((id: approvalId, approved: approved));
  }
}

final class _FakeNotificationService extends NotificationService {
  final tapController = StreamController<String>.broadcast();
  final shownNotifications = <RemoteCodingNotificationPayload>[];
  final shownApprovals =
      <({
        String conversationId,
        String title,
        String body,
        String? approvalId,
        bool allowsDirectDecision,
      })>[];
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

  final cancelledApprovalConversationIds = <String>[];

  @override
  Future<void> cancelApprovalRequiredNotification(
    String conversationId,
  ) async {
    cancelledApprovalConversationIds.add(conversationId);
  }

  @override
  Future<void> showApprovalRequiredNotification({
    required String conversationId,
    required String title,
    required String body,
    String? approvalId,
    bool allowsDirectDecision = false,
  }) async {
    shownApprovals.add((
      conversationId: conversationId,
      title: title,
      body: body,
      approvalId: approvalId,
      allowsDirectDecision: allowsDirectDecision,
    ));
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
