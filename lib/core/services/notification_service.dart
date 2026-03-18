import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Wrapper around [FlutterLocalNotificationsPlugin] for showing local
/// notifications (e.g. when an LLM response completes in the background).
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Initialize the plugin with platform-specific settings and request
  /// runtime permissions on Android 13+.
  Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: true,
      requestBadgePermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);

    // Request POST_NOTIFICATIONS permission on Android 13+.
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  /// Show a notification indicating that the LLM response is ready.
  ///
  /// Uses a fixed ID so successive completions replace each other rather than
  /// stacking in the notification shade.
  Future<void> showResponseCompleteNotification(
    String title,
    String body,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'llm_response',
      'LLM Response',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(0, title, body, details);
  }

  void dispose() {}
}
