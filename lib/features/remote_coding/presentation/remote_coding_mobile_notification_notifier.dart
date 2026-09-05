import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/notification_providers.dart';
import '../../../core/services/notification_service.dart';
import '../../chat/domain/services/pending_approval_summary.dart';
import '../../chat/presentation/providers/pending_approval_resolution.dart';
import '../../../core/utils/logger.dart';
import '../data/remote_coding_mobile_notification_gateway.dart';
import '../data/remote_coding_notification_receipt_store.dart';
import '../data/remote_coding_notification_relay_mobile_registration.dart';
import '../data/remote_coding_notification_payload.dart';
import '../data/remote_coding_notification_relay_providers.dart';
import '../data/remote_coding_repository.dart';
import '../domain/remote_coding_models.dart';
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

  /// Whether the Remote Coding page is mounted.
  ///
  /// The page raises its own approval sheet, so a notification on top of it
  /// would ask the same question twice. This mirrors `ChatNotifier`, which
  /// notifies only for a thread other than the one being looked at; the
  /// difference is only that a page, not a thread, is the visible surface
  /// here.
  ///
  /// Mounted is not the same as looked at. Backgrounding the app does not
  /// dispose the page, so this alone silenced a phone left on the Coding
  /// tab — which is the tab a Remote Coding user is obviously on, and the
  /// state the notification exists to serve. It is only a suppression signal
  /// together with the app being foregrounded.
  bool _isRemoteCodingPageMounted = false;

  /// Approvals already raised, so a reconnect does not notify twice.
  ///
  /// Deliberately not `RemoteCodingNotificationReceiptStore`, which the
  /// terminal notifications use: its keys are frozen to
  /// `^[A-Za-z0-9_-]{1,256}$` and an approval id need not match, and its
  /// week-long persistence exists because a *push* can be redelivered after a
  /// restart. This one arrives on a live WebSocket, so it cannot outlive the
  /// connection that carried it, and in-memory is the honest lifetime.
  final Set<String> _raisedApprovalIds = <String>{};

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
    // A blocked desktop turn reached the phone through no path at all before
    // this: the Remote Coding server is desktop-only, so its approvals live in
    // `RemoteCodingClientState` and `showPendingApprovalNotification` was
    // raised only from `ChatNotifier`. This needs no push contract — the
    // client holds a live WebSocket and the approval arrives on it — and iOS
    // forwards the notification and its actions to a paired watch with no
    // watchOS code involved.
    ref.listen<RemoteCodingApproval?>(
      remoteCodingClientProvider.select(
        (clientState) => clientState.pendingApproval,
      ),
      (previous, next) {
        if (next == null) {
          // Answered on the desktop, or withdrawn. A notification whose
          // buttons resolve nothing is worse than no notification.
          if (previous != null) {
            unawaited(_withdrawApprovalNotification());
          }
          return;
        }
        if (previous?.id == next.id) {
          return;
        }
        unawaited(_presentApprovalOnce(next));
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

  /// Tells the notifier whether the Remote Coding page is mounted.
  ///
  /// Called by the page itself rather than inferred, because no state this
  /// notifier holds says which screen is on top.
  void setRemoteCodingPageVisible(bool visible) {
    _isRemoteCodingPageMounted = visible;
  }

  /// Whether the person can already see this approval without a notification.
  ///
  /// Both halves are required. The page alone means the sheet is on the screen
  /// they are looking at; the page while the app is backgrounded means nobody
  /// is looking at anything.
  bool get _approvalIsAlreadyVisible =>
      _isRemoteCodingPageMounted &&
      !ref.read(appLifecycleServiceProvider).isInBackground;

  static const int _maxRememberedApprovalIds = 128;

  /// The conversation the last raised approval notification was keyed on.
  ///
  /// Held here rather than re-derived, because the client state has already
  /// moved on by the time the approval is withdrawn and the notification is
  /// keyed on where it *was*.
  String? _raisedApprovalConversationId;

  Future<void> _withdrawApprovalNotification() async {
    final conversationId = _raisedApprovalConversationId;
    if (conversationId == null) {
      return;
    }
    _raisedApprovalConversationId = null;
    try {
      await _notificationService.cancelApprovalRequiredNotification(
        conversationId,
      );
    } catch (error, stackTrace) {
      appLog(
        '[RemoteCodingNotifications] withdrawing an approval notification '
        'failed: $error\n$stackTrace',
      );
    }
  }

  Future<void> _presentApprovalOnce(RemoteCodingApproval approval) async {
    if (_approvalIsAlreadyVisible || approval.id.isEmpty) {
      return;
    }
    // A dropped connection re-sends the whole snapshot, so the same pending
    // approval arrives again with the first notification still on screen.
    if (!_raisedApprovalIds.add(approval.id)) {
      return;
    }
    if (_raisedApprovalIds.length > _maxRememberedApprovalIds) {
      _raisedApprovalIds.remove(_raisedApprovalIds.first);
    }
    try {
      final clientState = ref.read(remoteCodingClientProvider);
      final conversationId =
          clientState.currentConversationId ?? clientState.host?.id ?? '';
      _raisedApprovalConversationId = conversationId;
      await showPendingApprovalNotification(
        _notificationService,
        conversationId: conversationId,
        // The host name, not a thread title. "wants to run: dart analyze"
        // without saying which machine will run it is exactly the failure this
        // must not ship.
        threadTitle: clientState.host?.name.trim() ?? '',
        summary: _summaryFor(approval, clientState),
      );
    } catch (error, stackTrace) {
      // Notification delivery is best effort and must not affect the session.
      appLog(
        '[RemoteCodingNotifications] presenting an approval notification '
        'failed: $error\n$stackTrace',
      );
    }
  }

  /// Flattens a remote approval into the shape the notification path takes.
  ///
  /// `isSimpleDecision` is unconditionally true because the remote kinds are
  /// exhaustively `file`, `localCommand` and `gitCommand`, and every one of
  /// them is a bare yes/no. The chat side has kinds that are not — SSH connect
  /// needs credentials, computer-use needs smoke arming — which is why that
  /// flag exists at all.
  PendingApprovalSummary _summaryFor(
    RemoteCodingApproval approval,
    RemoteCodingClientState clientState,
  ) => PendingApprovalSummary(
    id: approval.id,
    kind: approval.kind.name,
    title: approval.title,
    subtitle: approval.subtitle,
    detail: approval.detail,
    isSimpleDecision: true,
    conversationId:
        clientState.currentConversationId ?? clientState.host?.id ?? '',
  );

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
