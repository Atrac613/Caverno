import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/notification_providers.dart';
import '../../domain/services/maintenance_report_service.dart';

/// LL18: delivers the morning maintenance report as a local notification.
final maintenanceReportServiceProvider = Provider<MaintenanceReportService>((
  ref,
) {
  final notifications = ref.watch(notificationServiceProvider);
  return MaintenanceReportService(
    sink: notifications.showResponseCompleteNotification,
  );
});
