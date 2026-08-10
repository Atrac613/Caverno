import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/remote_coding/data/remote_coding_notification_payload.dart';

/// Wrapper around [FlutterLocalNotificationsPlugin] for showing local
/// notifications (e.g. when an LLM response completes in the background).
///
/// Permissions are requested lazily on the first notification attempt
/// rather than at init, so the permission dialog appears in context.
class NotificationService {
  static const remoteCodingChannelId = 'remote_coding_completion';
  static const remoteCodingChannelName = 'Remote Coding Completion';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  bool _initialized = false;
  bool _permissionRequested = false;
  final StreamController<String> _notificationTapController =
      StreamController<String>.broadcast();

  Stream<String> get notificationTapPayloads =>
      _notificationTapController.stream;

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
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload?.trim();
        if (payload != null && payload.isNotEmpty) {
          _notificationTapController.add(payload);
        }
      },
    );
    _initialized = true;
  }

  /// Request notification permissions if not already done.
  Future<void> _ensurePermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;

    // iOS / macOS
    final darwin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await darwin?.requestPermissions(alert: true, sound: true);

    final macOS = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    await macOS?.requestPermissions(alert: true, sound: true);

    // Android 13+
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
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
  Future<void> showApprovalRequiredNotification({
    required String conversationId,
    required String title,
    required String body,
  }) async {
    await _showNotification(
      id: conversationId.hashCode & 0x7fffffff,
      title: title,
      body: body,
      channelId: 'approval_required',
      channelName: 'Approval Required',
    );
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

  Future<String?> getInitialNotificationTapPayload() async {
    await init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) {
      return null;
    }
    final payload = details?.notificationResponse?.payload?.trim();
    return payload == null || payload.isEmpty ? null : payload;
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    String? payload,
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

    const darwinDetails = DarwinNotificationDetails();

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
  }
}
