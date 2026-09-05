import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/logger.dart';

import '../../features/remote_coding/data/remote_coding_notification_payload.dart';

/// Wrapper around [FlutterLocalNotificationsPlugin] for showing local
/// notifications (e.g. when an LLM response completes in the background).
///
/// Permissions are requested lazily on the first notification attempt
/// rather than at init, so the permission dialog appears in context.
/// A notification action the user chose, rather than a plain tap.
class NotificationActionEvent {
  const NotificationActionEvent({
    required this.actionId,
    required this.conversationId,
    required this.approvalId,
  });

  final String actionId;
  final String conversationId;
  final String approvalId;

  bool get isApprove => actionId == NotificationService.approveActionId;
  bool get isDeny => actionId == NotificationService.denyActionId;
}

class NotificationService {
  static const remoteCodingChannelId = 'remote_coding_completion';
  static const remoteCodingChannelName = 'Remote Coding Completion';

  /// Category carrying Approve/Deny. Registering it is what makes the buttons
  /// appear on the lock screen and, because iOS forwards notifications and
  /// their actions to a paired Apple Watch, on the wrist as well — with no
  /// watchOS code involved. That is the fallback path for when the watch app
  /// itself is not running.
  static const approvalCategoryId = 'caverno_approval';
  static const approveActionId = 'caverno_approve';
  static const denyActionId = 'caverno_deny';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  bool _initialized = false;
  /// Whether a permission request has come back granted.
  ///
  /// Not "whether we asked": an attempt that was never actually presented, or
  /// was refused, must be able to ask again.
  bool _permissionGranted = false;
  final StreamController<String> _notificationTapController =
      StreamController<String>.broadcast();
  final StreamController<NotificationActionEvent> _notificationActionController =
      StreamController<NotificationActionEvent>.broadcast();

  Stream<String> get notificationTapPayloads =>
      _notificationTapController.stream;

  /// Approve/Deny chosen from a notification, on the phone or on a paired
  /// Apple Watch.
  Stream<NotificationActionEvent> get notificationActions =>
      _notificationActionController.stream;

  /// Initialize the plugin without requesting permissions upfront.
  Future<void> init() {
    if (_initialization != null) {
      return _initialization!;
    }
    _initialization = _initialize();
    return _initialization!;
  }

  Future<void> _initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // Do not request permissions at init — defer to first notification.
    // Not const: DarwinNotificationAction.plain is not a const constructor.
    final darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          approvalCategoryId,
          actions: [
            DarwinNotificationAction.plain(approveActionId, 'Approve'),
            DarwinNotificationAction.plain(
              denyActionId,
              'Deny',
              options: {DarwinNotificationActionOption.destructive},
            ),
          ],
          // The buttons must be reachable without unlocking, or the feature
          // solves nothing that opening the app does not already solve.
          options: {DarwinNotificationCategoryOption.hiddenPreviewShowTitle},
        ),
      ],
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        // Logged before any filtering. Everything downstream of this point is
        // ours to fix; nothing upstream of it is visible from Dart at all, so
        // the presence or absence of this line is what says which side of the
        // platform boundary a lost button press was lost on.
        appLog(
          '[Notifications] response actionId=${response.actionId} '
          'hasPayload=${(response.payload?.trim().isNotEmpty) ?? false}',
        );
        final payload = response.payload?.trim();
        if (payload == null || payload.isEmpty) return;
        final actionId = response.actionId?.trim() ?? '';
        if (actionId == approveActionId || actionId == denyActionId) {
          final action = _decodeApprovalAction(actionId, payload);
          if (action != null) {
            _notificationActionController.add(action);
          }
          return;
        }
        _notificationTapController.add(payload);
      },
    );
    _initialized = true;
  }

  /// Request notification permissions, retrying until one is actually granted.
  ///
  /// The request is made lazily, on the first notification rather than at
  /// launch, so the prompt appears next to something the person asked for. That
  /// timing has a trap: iOS shows the prompt only while the app is
  /// foregrounded, and this used to mark the request done before awaiting its
  /// result. A first notification raised in the background therefore consumed
  /// the only attempt without ever asking, permission stayed undetermined, and
  /// every later notification was posted into a void — the log said it was
  /// raised and nothing appeared. Latching on the *answer* instead means a
  /// refused-or-never-asked attempt is retried the next time, which is when the
  /// app is more likely to be in front of someone.
  Future<void> _ensurePermission() async {
    if (_permissionGranted) return;

    // iOS / macOS
    final darwin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (darwin != null) {
      _permissionGranted =
          await darwin.requestPermissions(alert: true, sound: true) ?? false;
      return;
    }

    final macOS = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    if (macOS != null) {
      _permissionGranted =
          await macOS.requestPermissions(alert: true, sound: true) ?? false;
      return;
    }

    // Android 13+
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      _permissionGranted =
          await android.requestNotificationsPermission() ?? false;
    }
  }

  /// Show a notification indicating that the LLM response is ready.
  ///
  /// Uses a fixed ID so successive completions replace each other rather than
  /// stacking in the notification shade. Requests permissions on first call.
  Future<void> showResponseCompleteNotification(
    String title,
    String body,
  ) async {
    await _showNotification(
      id: 0,
      title: title,
      body: body,
      channelId: 'llm_response',
      channelName: 'LLM Response',
    );
  }

  /// Show a notification that a thread the user is not looking at has stopped
  /// to ask for approval. Keyed per thread so two waiting threads both show.
  ///
  /// When [approvalId] is known and [allowsDirectDecision] is true, the
  /// notification carries Approve/Deny buttons. Both are required: without the
  /// id the decision could land on the wrong request once a second approval
  /// queues up behind the first, and kinds needing structured input (SSH
  /// credentials, computer-use arming) cannot be answered with a button at all.
  Future<void> showApprovalRequiredNotification({
    required String conversationId,
    required String title,
    required String body,
    String? approvalId,
    bool allowsDirectDecision = false,
  }) async {
    final actionable =
        allowsDirectDecision && (approvalId?.isNotEmpty ?? false);
    // Whether the buttons were asked for is not observable from the phone: a
    // notification without them looks exactly like one iOS chose not to
    // expand. Saying so here separates "the app did not request actions" from
    // "iOS did not show the ones it was given".
    appLog(
      '[Notifications] approval $approvalId actionable=$actionable '
      'category=${actionable ? approvalCategoryId : 'none'}',
    );
    await _showNotification(
      id: conversationId.hashCode & 0x7fffffff,
      title: title,
      body: body,
      channelId: 'approval_required',
      channelName: 'Approval Required',
      payload: jsonEncode({
        'kind': 'approval_required',
        'conversationId': conversationId,
        'approvalId': ?approvalId,
      }),
      darwinCategoryId: actionable ? approvalCategoryId : null,
    );
  }

  /// Withdraws the approval notification raised for [conversationId].
  ///
  /// A request answered somewhere else — the desktop that asked it, or the
  /// phone's own dialog — must not leave a notification whose buttons resolve
  /// nothing. The id derivation matches
  /// [showApprovalRequiredNotification] exactly; two threads keep their own
  /// notifications, so withdrawing one leaves the other alone.
  Future<void> cancelApprovalRequiredNotification(
    String conversationId,
  ) async {
    await _plugin.cancel(id: conversationId.hashCode & 0x7fffffff);
  }

  NotificationActionEvent? _decodeApprovalAction(
    String actionId,
    String payload,
  ) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      final approvalId = (decoded['approvalId'] as String?)?.trim() ?? '';
      if (approvalId.isEmpty) return null;
      return NotificationActionEvent(
        actionId: actionId,
        conversationId: (decoded['conversationId'] as String?)?.trim() ?? '',
        approvalId: approvalId,
      );
    } on FormatException {
      return null;
    }
  }

  /// Show a notification for a scheduled routine completion.
  Future<void> showRoutineCompletionNotification({
    required String routineId,
    required String routineName,
    required bool isSuccessful,
    required String body,
  }) async {
    final title = isSuccessful ? routineName : '$routineName failed';
    await _showNotification(
      id: routineId.hashCode & 0x7fffffff,
      title: title,
      body: body,
      channelId: 'routine_completion',
      channelName: 'Routine Completion',
    );
  }

  /// Show a notification for a finished background subagent task.
  Future<void> showSubagentCompletionNotification({
    required String taskId,
    required String description,
    required bool isSuccessful,
    required String body,
  }) async {
    final title = isSuccessful
        ? 'Subagent: $description'
        : 'Subagent failed: $description';
    await _showNotification(
      id: 'subagent_$taskId'.hashCode & 0x7fffffff,
      title: title,
      body: body,
      channelId: 'subagent_completion',
      channelName: 'Subagent Completion',
    );
  }

  Future<void> showRemoteCodingTerminalNotification(
    RemoteCodingNotificationPayload notification,
  ) async {
    await _showNotification(
      id: notification.eventId.hashCode & 0x7fffffff,
      title: notification.title,
      body: notification.body,
      channelId: remoteCodingChannelId,
      channelName: remoteCodingChannelName,
      payload: jsonEncode(notification.toFcmData()),
    );
  }

  Future<void> prepareRemoteCodingNotificationChannel() async {
    await init();
    if (!_initialized) {
      return;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        remoteCodingChannelId,
        remoteCodingChannelName,
        importance: Importance.defaultImportance,
      ),
    );
  }

  /// The notification that launched the app, if one did.
  ///
  /// An Approve or Deny pressed while the app was not running arrives here
  /// rather than on [notificationActions]: the stream only exists once a Dart
  /// isolate does. Dropping the action identifier — which this did — lost the
  /// decision silently on the two surfaces the buttons exist for, a lock
  /// screen and a paired watch, where the app is least likely to be running.
  /// An action is emitted as an action and returns no tap payload, so it is
  /// answered rather than merely navigated to.
  Future<String?> getInitialNotificationTapPayload() async {
    await init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) {
      return null;
    }
    final payload = details?.notificationResponse?.payload?.trim();
    if (payload == null || payload.isEmpty) {
      return null;
    }
    final actionId = details?.notificationResponse?.actionId?.trim() ?? '';
    if (actionId == approveActionId || actionId == denyActionId) {
      final action = _decodeApprovalAction(actionId, payload);
      if (action != null) {
        appLog(
          '[Notifications] launch response carried action $actionId for '
          '${action.approvalId}',
        );
        _notificationActionController.add(action);
        return null;
      }
    }
    return payload;
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    String? payload,
    String? darwinCategoryId,
  }) async {
    await init();
    if (!_initialized) return;
    await _ensurePermission();

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    // Presentation is stated per notification rather than left to the
    // defaults persisted at plugin initialization. Those defaults are read
    // from `NSUserDefaults` when the content is built, and they are only one
    // of two paths that decide whether anything appears while the app is in
    // front — the other being whichever plugin ends up owning
    // `UNUserNotificationCenter.delegate`. Stating them here removes this
    // notification's dependence on both.
    //
    // Foreground presentation is wanted for every kind raised here: the
    // answer-ready notification is already gated on the app being in the
    // background, and an approval is raised precisely because the person is
    // not looking at the surface that owns it.
    final darwinDetails = DarwinNotificationDetails(
      categoryIdentifier: darwinCategoryId,
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  void dispose() {
    unawaited(_notificationTapController.close());
    unawaited(_notificationActionController.close());
  }
}
