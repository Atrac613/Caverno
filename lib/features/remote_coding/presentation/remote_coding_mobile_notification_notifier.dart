import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/notification_providers.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/logger.dart';
import '../data/remote_coding_mobile_notification_gateway.dart';
import '../data/remote_coding_notification_receipt_store.dart';
import '../data/remote_coding_notification_relay_mobile_registration.dart';
import '../data/remote_coding_notification_payload.dart';
import '../data/remote_coding_notification_relay_providers.dart';
import '../data/remote_coding_repository.dart';
import 'remote_coding_client_notifier.dart';

final remoteCodingMobileNotificationProvider =
    NotifierProvider<
      RemoteCodingMobileNotificationNotifier,
      RemoteCodingMobileNotificationState
    >(RemoteCodingMobileNotificationNotifier.new);

enum RemoteCodingMobileNotificationStatus {
  initializing,
  unsupported,
  unavailable,
  notDetermined,
  denied,
  disabled,
  enabling,
  enabled,
  error,
}

final class RemoteCodingMobileNotificationState {
  const RemoteCodingMobileNotificationState({
    this.status = RemoteCodingMobileNotificationStatus.initializing,
    this.message,
    this.lastForegroundNotification,
    this.pendingNotificationTap,
  });

  final RemoteCodingMobileNotificationStatus status;
  final String? message;
  final RemoteCodingNotificationPayload? lastForegroundNotification;
  final RemoteCodingNotificationPayload? pendingNotificationTap;

  bool get isEnabled => status == RemoteCodingMobileNotificationStatus.enabled;
  bool get canRetry =>
      status == RemoteCodingMobileNotificationStatus.unavailable ||
      status == RemoteCodingMobileNotificationStatus.notDetermined ||
      status == RemoteCodingMobileNotificationStatus.denied ||
      status == RemoteCodingMobileNotificationStatus.disabled ||
      status == RemoteCodingMobileNotificationStatus.error;

  RemoteCodingMobileNotificationState copyWith({
    RemoteCodingMobileNotificationStatus? status,
    String? message,
    RemoteCodingNotificationPayload? lastForegroundNotification,
    RemoteCodingNotificationPayload? pendingNotificationTap,
    bool clearMessage = false,
    bool clearPendingNotificationTap = false,
  }) {
    return RemoteCodingMobileNotificationState(
      status: status ?? this.status,
      message: clearMessage ? null : (message ?? this.message),
      lastForegroundNotification:
          lastForegroundNotification ?? this.lastForegroundNotification,
      pendingNotificationTap: clearPendingNotificationTap
          ? null
          : (pendingNotificationTap ?? this.pendingNotificationTap),
    );
  }
}

final class RemoteCodingMobileNotificationNotifier
    extends Notifier<RemoteCodingMobileNotificationState> {
  late final RemoteCodingRepository _repository;
  late final RemoteCodingMobileNotificationGateway _gateway;
  late final RemoteCodingNotificationReceiptStore _receiptStore;
  late final NotificationService _notificationService;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<Map<String, dynamic>>? _foregroundMessageSubscription;
  StreamSubscription<Map<String, dynamic>>? _notificationTapSubscription;
  StreamSubscription<String>? _localNotificationTapSubscription;
  bool _operationInProgress = false;

  @override
  RemoteCodingMobileNotificationState build() {
    _repository = ref.read(remoteCodingRepositoryProvider);
    _gateway = ref.read(remoteCodingMobileNotificationGatewayProvider);
    _receiptStore = ref.read(remoteCodingNotificationReceiptStoreProvider);
    _notificationService = ref.read(notificationServiceProvider);
    ref.listen<RemoteCodingNotificationPayload?>(
      remoteCodingClientProvider.select(
        (clientState) => clientState.lastTerminalNotification,
      ),
      (previous, next) {
        if (next == null) {
          return;
        }
        unawaited(_handleWebSocketNotification(next));
      },
    );
    _listenForLocalNotificationTaps();
    unawaited(_loadInitialLocalNotificationTap());
    ref.onDispose(() {
      unawaited(_tokenRefreshSubscription?.cancel());
      unawaited(_foregroundMessageSubscription?.cancel());
      unawaited(_notificationTapSubscription?.cancel());
      unawaited(_localNotificationTapSubscription?.cancel());
    });
    Future<void>.microtask(initialize);
    return const RemoteCodingMobileNotificationState();
  }

  Future<void> initialize() async {
    if (_operationInProgress) {
      return;
    }
    final platform = _gateway.platform;
    if (platform == null) {
      state = const RemoteCodingMobileNotificationState(
        status: RemoteCodingMobileNotificationStatus.unsupported,
        message: 'Push notifications require iOS or Android.',
      );
      return;
    }
    if (ref.read(remoteCodingNotificationRelayClientProvider) == null) {
      state = const RemoteCodingMobileNotificationState(
        status: RemoteCodingMobileNotificationStatus.unavailable,
        message: 'Notification relay is not configured.',
      );
      return;
    }
    _operationInProgress = true;
    try {
      final permission = await _gateway.initialize();
      if (!_repository.loadMobileRelayNotificationsEnabled()) {
        state = RemoteCodingMobileNotificationState(
          status: _disabledStatus(permission),
          message: _permissionMessage(permission),
        );
        return;
      }
      if (!_isAuthorized(permission)) {
        state = RemoteCodingMobileNotificationState(
          status: _disabledStatus(permission),
          message: _permissionMessage(permission),
        );
        return;
      }
      await _ensureRegistration();
      _listenForTokenRefresh();
      await _listenForMessages();
      state = const RemoteCodingMobileNotificationState(
        status: RemoteCodingMobileNotificationStatus.enabled,
      );
    } catch (error, stackTrace) {
      appLog(
        '[RemoteCodingNotifications] initialize failed: $error\n$stackTrace',
      );
      state = const RemoteCodingMobileNotificationState(
        status: RemoteCodingMobileNotificationStatus.unavailable,
        message: 'Firebase notifications are unavailable in this build.',
      );
    } finally {
      _operationInProgress = false;
    }
  }

  Future<bool> enable() async {
    if (_operationInProgress) {
      return false;
    }
    if (_gateway.platform == null ||
        ref.read(remoteCodingNotificationRelayClientProvider) == null) {
      await initialize();
      return false;
    }
    _operationInProgress = true;
    state = const RemoteCodingMobileNotificationState(
      status: RemoteCodingMobileNotificationStatus.enabling,
    );
    try {
      var permission = await _gateway.initialize();
      if (!_isAuthorized(permission)) {
        permission = await _gateway.requestPermission();
      }
      if (!_isAuthorized(permission)) {
        state = RemoteCodingMobileNotificationState(
          status: _disabledStatus(permission),
          message: _permissionMessage(permission),
        );
        return false;
      }
      await _ensureRegistration();
      await _repository.saveMobileRelayNotificationsEnabled(true);
      _listenForTokenRefresh();
      await _listenForMessages();
      state = const RemoteCodingMobileNotificationState(
        status: RemoteCodingMobileNotificationStatus.enabled,
      );
      return true;
    } catch (error, stackTrace) {
      appLog('[RemoteCodingNotifications] enable failed: $error\n$stackTrace');
      state = const RemoteCodingMobileNotificationState(
        status: RemoteCodingMobileNotificationStatus.error,
        message: 'Completion notifications could not be enabled.',
      );
      return false;
    } finally {
      _operationInProgress = false;
    }
  }

  Future<bool> disable() async {
    if (_operationInProgress) {
      return false;
    }
    final relayClient = ref.read(remoteCodingNotificationRelayClientProvider);
    if (relayClient == null) {
      return false;
    }
    _operationInProgress = true;
    try {
      await RemoteCodingMobileRelayRegistrationCoordinator(
        repository: _repository,
        relayClient: relayClient,
        clock: DateTime.now,
      ).revokeRegistration();
      await _repository.saveMobileRelayNotificationsEnabled(false);
      try {
        await _gateway.disableFcmToken();
      } catch (error) {
        // Relay revocation remains authoritative if local token cleanup fails.
        appLog(
          '[RemoteCodingNotifications] local FCM token cleanup failed: $error',
        );
      }
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = null;
      await _foregroundMessageSubscription?.cancel();
      _foregroundMessageSubscription = null;
      await _notificationTapSubscription?.cancel();
      _notificationTapSubscription = null;
      state = const RemoteCodingMobileNotificationState(
        status: RemoteCodingMobileNotificationStatus.disabled,
        message: 'Completion notifications are disabled.',
      );
      return true;
    } catch (error, stackTrace) {
      appLog('[RemoteCodingNotifications] disable failed: $error\n$stackTrace');
      state = const RemoteCodingMobileNotificationState(
        status: RemoteCodingMobileNotificationStatus.error,
        message: 'Notification relay cleanup will need to be retried.',
      );
      return false;
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> _ensureRegistration() async {
    final relayClient = ref.read(remoteCodingNotificationRelayClientProvider);
    final platform = _gateway.platform;
    if (relayClient == null || platform == null) {
      throw StateError('Mobile notification relay is unavailable.');
    }
    await _notificationService.prepareRemoteCodingNotificationChannel();
    final fcmToken = await _gateway.getFcmToken();
    final appCheckToken = await _gateway.getAppCheckToken();
    await RemoteCodingMobileRelayRegistrationCoordinator(
      repository: _repository,
      relayClient: relayClient,
      clock: DateTime.now,
    ).ensureRegistered(
      platform: platform,
      fcmRegistrationToken: fcmToken,
      appCheckToken: appCheckToken,
    );
  }

  void _listenForTokenRefresh() {
    if (_tokenRefreshSubscription != null) {
      return;
    }
    _tokenRefreshSubscription = _gateway.onTokenRefresh.listen(
      (token) => unawaited(_handleTokenRefresh(token)),
      onError: (_) {
        if (ref.mounted) {
          state = const RemoteCodingMobileNotificationState(
            status: RemoteCodingMobileNotificationStatus.error,
            message: 'FCM token refresh needs to be retried.',
          );
        }
      },
    );
  }

  Future<void> _listenForMessages() async {
    _foregroundMessageSubscription ??= _gateway.onForegroundMessage.listen(
      (data) => unawaited(_recordForegroundMessage(data)),
    );
    _notificationTapSubscription ??= _gateway.onNotificationTap.listen(
      (data) => _recordNotificationTap(data),
    );
    final initialTap = await _gateway.getInitialNotificationTap();
    if (initialTap != null) {
      _recordNotificationTap(initialTap);
    }
  }

  void _listenForLocalNotificationTaps() {
    _localNotificationTapSubscription ??= _notificationService
        .notificationTapPayloads
        .listen(_recordLocalNotificationTap);
  }

  Future<void> _loadInitialLocalNotificationTap() async {
    try {
      final payload = await _notificationService
          .getInitialNotificationTapPayload();
      if (payload != null) {
        _recordLocalNotificationTap(payload);
      }
    } catch (error) {
      // Local notification launch details are optional recovery context.
      appLog(
        '[RemoteCodingNotifications] initial local tap lookup failed: $error',
      );
    }
  }

  Future<void> _recordForegroundMessage(Map<String, dynamic> data) async {
    try {
      final notification = RemoteCodingNotificationPayload.fromFcmData(data);
      await _presentNotificationOnce(notification);
    } on FormatException {
      // Ignore messages outside the frozen Remote Coding notification contract.
    }
  }

  Future<void> _handleWebSocketNotification(
    RemoteCodingNotificationPayload notification,
  ) async {
    ref
        .read(remoteCodingClientProvider.notifier)
        .clearLastTerminalNotification();
    if (_repository.loadMobileRelayNotificationsEnabled()) {
      return;
    }
    await _presentNotificationOnce(notification);
  }

  Future<void> _presentNotificationOnce(
    RemoteCodingNotificationPayload notification,
  ) async {
    try {
      final claimed = await _receiptStore.claim(
        notification.eventId,
        DateTime.now(),
      );
      if (!claimed) {
        return;
      }
      await _notificationService.showRemoteCodingTerminalNotification(
        notification,
      );
      if (ref.mounted) {
        state = state.copyWith(lastForegroundNotification: notification);
      }
    } catch (error, stackTrace) {
      // Notification delivery is best effort and must not affect the session.
      appLog(
        '[RemoteCodingNotifications] presenting a terminal notification '
        'failed: $error\n$stackTrace',
      );
    }
  }

  void _recordNotificationTap(Map<String, dynamic> data) {
    try {
      final notification = RemoteCodingNotificationPayload.fromFcmData(data);
      if (ref.mounted) {
        state = state.copyWith(pendingNotificationTap: notification);
      }
    } on FormatException {
      // Ignore messages outside the frozen Remote Coding notification contract.
    }
  }

  void _recordLocalNotificationTap(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        return;
      }
      _recordNotificationTap(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // Ignore local notifications outside the frozen contract.
    }
  }

  void clearPendingNotificationTap() {
    state = state.copyWith(clearPendingNotificationTap: true);
  }

  @visibleForTesting
  void applyNotificationTapForTest(Map<String, dynamic> data) {
    _recordNotificationTap(data);
  }

  Future<void> _handleTokenRefresh(String token) async {
    if (!_repository.loadMobileRelayNotificationsEnabled()) {
      return;
    }
    final relayClient = ref.read(remoteCodingNotificationRelayClientProvider);
    if (relayClient == null) {
      return;
    }
    try {
      await RemoteCodingMobileRelayRegistrationCoordinator(
        repository: _repository,
        relayClient: relayClient,
        clock: DateTime.now,
      ).rotateToken(token);
      if (ref.mounted) {
        state = const RemoteCodingMobileNotificationState(
          status: RemoteCodingMobileNotificationStatus.enabled,
        );
      }
    } catch (error, stackTrace) {
      appLog(
        '[RemoteCodingNotifications] FCM token rotation failed: '
        '$error\n$stackTrace',
      );
      if (ref.mounted) {
        state = const RemoteCodingMobileNotificationState(
          status: RemoteCodingMobileNotificationStatus.error,
          message: 'FCM token refresh needs to be retried.',
        );
      }
    }
  }
}

bool _isAuthorized(RemoteCodingNotificationPermission permission) {
  return permission == RemoteCodingNotificationPermission.authorized ||
      permission == RemoteCodingNotificationPermission.provisional;
}

RemoteCodingMobileNotificationStatus _disabledStatus(
  RemoteCodingNotificationPermission permission,
) {
  return switch (permission) {
    RemoteCodingNotificationPermission.notDetermined =>
      RemoteCodingMobileNotificationStatus.notDetermined,
    RemoteCodingNotificationPermission.denied =>
      RemoteCodingMobileNotificationStatus.denied,
    RemoteCodingNotificationPermission.authorized ||
    RemoteCodingNotificationPermission.provisional =>
      RemoteCodingMobileNotificationStatus.disabled,
  };
}

String _permissionMessage(RemoteCodingNotificationPermission permission) {
  return switch (permission) {
    RemoteCodingNotificationPermission.notDetermined =>
      'Enable notifications to receive remote coding completion alerts.',
    RemoteCodingNotificationPermission.denied =>
      'Notification permission is denied in system settings.',
    RemoteCodingNotificationPermission.authorized ||
    RemoteCodingNotificationPermission.provisional =>
      'Completion notifications are disabled.',
  };
}
