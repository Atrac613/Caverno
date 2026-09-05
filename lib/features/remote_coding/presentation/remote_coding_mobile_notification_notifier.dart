import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

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
  /// Counted, not a flag. A keyed remount inflates the replacement before it
  /// disposes the old element, so a boolean ended up false while the page was
  /// on screen and the next approval asked the same question twice.
  int _remoteCodingPagesMounted = 0;

  /// Notifications currently on screen, by approval id.
  ///
  /// The value is the conversation the notification was keyed on, because
  /// cancelling needs the id the raise used and the client state has moved on
  /// by then. Two approvals in flight therefore keep their own notifications,
  /// which a single remembered conversation could not.
  ///
  /// The membership means "a notification for this exists right now", not
  /// "was ever raised". The earlier reading deadlocked with the withdraw path:
  /// a socket blip clears `pendingApproval`, the withdrawal cancels the
  /// banner, the reconnect re-sends the same still-unanswered approval, and a
  /// permanent set refused to raise it again — leaving no notification at all
  /// for a live blocked desktop turn.
  ///
  /// Deliberately not `RemoteCodingNotificationReceiptStore`, which the
  /// terminal notifications use: its keys are frozen to
  /// `^[A-Za-z0-9_-]{1,256}$` and an approval id need not match, and its
  /// week-long persistence exists because a *push* can be redelivered after a
  /// restart. This one arrives on a live WebSocket, so it cannot outlive the
  /// connection that carried it, and in-memory is the honest lifetime.
  final Map<String, String> _liveApprovalNotifications = <String, String>{};

  /// An approval that was suppressed because the person was looking at it.
  ///
  /// Held so the decision can be revisited: suppression was evaluated once, at
  /// arrival, and `ref.listen` never fires again for an unchanged id, so
  /// locking the phone on the Remote Coding page used to mean the notification
  /// was never raised at all and the desktop blocked indefinitely.
  RemoteCodingApproval? _suppressedApproval;

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
            unawaited(_withdrawApprovalNotification(previous.id));
          }
          return;
        }
        if (previous?.id == next.id) {
          return;
        }
        unawaited(_presentApprovalOnce(next));
      },
    );
    // Locking the phone lifts suppression as surely as leaving the page does,
    // and nothing else would notice: the client's state has not changed, so
    // the approval listener above stays silent.
    final lifecycleObserver = _SuppressionLifecycleObserver(
      _reconsiderSuppressedApproval,
    );
    WidgetsBinding.instance.addObserver(lifecycleObserver);
    ref.onDispose(
      () => WidgetsBinding.instance.removeObserver(lifecycleObserver),
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
    _remoteCodingPagesMounted = visible
        ? _remoteCodingPagesMounted + 1
        : (_remoteCodingPagesMounted - 1).clamp(0, 1 << 20);
    if (_remoteCodingPagesMounted == 0) {
      _reconsiderSuppressedApproval();
    }
  }

  /// Raises an approval that suppression held back, once it no longer applies.
  void _reconsiderSuppressedApproval() {
    final suppressed = _suppressedApproval;
    if (suppressed == null || _approvalIsAlreadyVisible) {
      return;
    }
    if (ref.read(remoteCodingClientProvider).pendingApproval?.id !=
        suppressed.id) {
      // Answered in the meantime.
      _suppressedApproval = null;
      return;
    }
    unawaited(_presentApprovalOnce(suppressed));
  }

  @visibleForTesting
  bool get debugIsRemoteCodingPageMounted => _remoteCodingPagesMounted > 0;

  /// Re-delivers an approval the way a reconnect does, without a state change.
  @visibleForTesting
  void presentApprovalForTest(RemoteCodingApproval approval) {
    unawaited(_presentApprovalOnce(approval));
  }

  /// Whether the person can already see this approval without a notification.
  ///
  /// Both halves are required. The page alone means the sheet is on the screen
  /// they are looking at; the page while the app is backgrounded means nobody
  /// is looking at anything.
  bool get _approvalIsAlreadyVisible =>
      _remoteCodingPagesMounted > 0 &&
      !ref.read(appLifecycleServiceProvider).isInBackground;

  static const int _maxRememberedApprovalIds = 128;

  Future<void> _withdrawApprovalNotification(String approvalId) async {
    _suppressedApproval = null;
    final conversationId = _liveApprovalNotifications.remove(approvalId);
    if (conversationId == null) {
      return;
    }
    appLog(
      '[RemoteCodingNotifications] withdrawing the notification for '
      'conversation "$conversationId"; approval $approvalId is gone',
    );
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

  /// Every decision on this path is logged, and that is deliberate.
  ///
  /// A notification that is not raised leaves no trace anywhere — not on the
  /// screen, not in the state, not in a test. Three separate defects here were
  /// each found only by a person reporting "nothing happened", and each cost a
  /// round trip that a single line of output would have settled.
  Future<void> _presentApprovalOnce(RemoteCodingApproval approval) async {
    appLog(
      '[RemoteCodingNotifications] approval ${approval.id} '
      '(${approval.kind.name}) is pending',
    );
    if (approval.id.isEmpty) {
      appLog(
        '[RemoteCodingNotifications] not raised: the approval carries no id, '
        'so Approve/Deny could not be routed back to it',
      );
      return;
    }
    if (_approvalIsAlreadyVisible) {
      // Held rather than forgotten: the listener will not fire again for this
      // id, so leaving the page or backgrounding the app has to be able to
      // raise it later.
      _suppressedApproval = approval;
      appLog(
        '[RemoteCodingNotifications] not raised yet: the Remote Coding page is '
        'open and foregrounded, so its own sheet is already asking',
      );
      return;
    }
    _suppressedApproval = null;
    // A dropped connection re-sends the whole snapshot, so the same pending
    // approval can arrive again while its notification is still on screen.
    if (_liveApprovalNotifications.containsKey(approval.id)) {
      appLog(
        '[RemoteCodingNotifications] not raised: ${approval.id} already has a '
        'notification on screen',
      );
      return;
    }
    try {
      final clientState = ref.read(remoteCodingClientProvider);
      final conversationId =
          clientState.currentConversationId ?? clientState.host?.id ?? '';
      _liveApprovalNotifications[approval.id] = conversationId;
      if (_liveApprovalNotifications.length > _maxRememberedApprovalIds) {
        _liveApprovalNotifications.remove(_liveApprovalNotifications.keys.first);
      }
      appLog(
        '[RemoteCodingNotifications] raising for ${approval.id} on '
        '"${clientState.host?.name.trim() ?? ''}" '
        '(conversation "$conversationId")',
      );
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
  /// `title` has to be the thing being approved, because the body reads
  /// `"<host> wants to run: <title>"`. The Remote Coding wire model does not
  /// carry it there for commands — `RemoteCodingApproval.title` is the kind's
  /// label, "Local Command Approval", and the command itself is in `detail` —
  /// so mapping the fields across verbatim produced "wants to run: Local
  /// Command Approval". That is precisely the notification WATCH1 says must
  /// not ship: a button that approves an unseen command defeats the approval
  /// gate it belongs to, and a wrist is where it is most likely to be pressed
  /// without looking. `PendingApprovalSummary` for a chat-side command puts
  /// `request.command` in `title`, and this restores that.
  ///
  /// `isSimpleDecision` is unconditionally true because the remote kinds are
  /// exhaustively `file`, `localCommand` and `gitCommand`, and every one of
  /// them is a bare yes/no. The chat side has kinds that are not — SSH connect
  /// needs credentials, computer-use needs smoke arming — which is why that
  /// flag exists at all.
  PendingApprovalSummary _summaryFor(
    RemoteCodingApproval approval,
    RemoteCodingClientState clientState,
  ) {
    // Exhaustive on purpose: a kind added to the wire model should be a
    // compile error here rather than a notification that names nothing.
    final subject = switch (approval.kind) {
      RemoteCodingApprovalKind.localCommand ||
      RemoteCodingApprovalKind.gitCommand => approval.detail,
      // The server already puts the operation in `title` and the path in
      // `subtitle` for a file, matching the chat side.
      RemoteCodingApprovalKind.file => approval.title,
    };
    final named = subject.trim().isEmpty ? approval.title : subject.trim();
    return PendingApprovalSummary(
      id: approval.id,
      kind: approval.kind.name,
      title: named,
      subtitle: approval.subtitle,
      detail: approval.detail,
      isSimpleDecision: true,
      conversationId:
          clientState.currentConversationId ?? clientState.host?.id ?? '',
    );
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


/// Tells the notifier when the app changes lifecycle state.
///
/// `AppLifecycleService` records the state but announces nothing, and the
/// suppressed approval has to be revisited the moment the person stops looking
/// at the screen that was holding it back.
final class _SuppressionLifecycleObserver with WidgetsBindingObserver {
  _SuppressionLifecycleObserver(this._onChanged);

  final void Function() _onChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _onChanged();
  }
}
