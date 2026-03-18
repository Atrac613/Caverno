import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_lifecycle_service.dart';
import 'background_task_service.dart';
import 'notification_service.dart';

/// Notification service provider.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  service.init();
  ref.onDispose(() => service.dispose());
  return service;
});

/// App lifecycle observer provider.
final appLifecycleServiceProvider = Provider<AppLifecycleService>((ref) {
  final service = AppLifecycleService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// iOS background task provider.
final backgroundTaskServiceProvider = Provider<BackgroundTaskService>((ref) {
  final service = BackgroundTaskService();
  ref.onDispose(() => service.dispose());
  return service;
});
