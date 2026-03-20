import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Wrapper around [FlutterLocalNotificationsPlugin] for showing local
/// notifications (e.g. when an LLM response completes in the background).
///
/// Permissions are requested lazily on the first notification attempt
/// rather than at init, so the permission dialog appears in context.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _permissionRequested = false;

  /// Initialize the plugin without requesting permissions upfront.
  Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

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

    await _plugin.initialize(settings);
    _initialized = true;
  }

  /// Request notification permissions if not already done.
  Future<void> _ensurePermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;

    // iOS / macOS
    final darwin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await darwin?.requestPermissions(alert: true, sound: true);

    final macOS = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    await macOS?.requestPermissions(alert: true, sound: true);

    // Android 13+
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
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
    if (!_initialized) return;
    await _ensurePermission();

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
