import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../domain/entities/idle_maintenance_config.dart';

/// LL18: bridges the persisted flat `AppSettings` fields into the maintenance
/// domain's [IdleMaintenanceConfig]. The gate policy and (later) the scheduler
/// watch this rather than reading settings fields directly, so the domain
/// layer never depends on the settings entity shape.
final idleMaintenanceConfigProvider = Provider<IdleMaintenanceConfig>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  return IdleMaintenanceConfig(
    enabled: settings.idleMaintenanceEnabled,
    windowStartMinutes: settings.idleMaintenanceWindowStartMinutes,
    windowEndMinutes: settings.idleMaintenanceWindowEndMinutes,
    minIdle: Duration(minutes: settings.idleMaintenanceMinIdleMinutes),
    requireAcPower: settings.idleMaintenanceRequireAcPower,
  );
});
