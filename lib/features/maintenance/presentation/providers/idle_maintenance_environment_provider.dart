import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/notification_providers.dart';
import '../../data/battery_plus_power_probe.dart';
import '../../data/system_idle_maintenance_environment.dart';
import '../../domain/services/idle_maintenance_environment.dart';
import '../../domain/services/power_state_probe.dart';

/// LL18: AC-power probe (battery_plus). Started on creation; the cached state
/// answers the gate synchronously.
final powerStateProbeProvider = Provider<PowerStateProbe>((ref) {
  final probe = BatteryPlusPowerProbe();
  // Fire-and-forget: the cached state populates shortly; until then it reads as
  // unknown (null), which the gate treats as satisfying the AC requirement.
  probe.start();
  ref.onDispose(probe.dispose);
  return probe;
});

/// LL18: the real environment feeding the idle-maintenance gate/scheduler.
final idleMaintenanceEnvironmentProvider = Provider<IdleMaintenanceEnvironment>(
  (ref) {
    final lifecycle = ref.watch(appLifecycleServiceProvider);
    final power = ref.watch(powerStateProbeProvider);
    return SystemIdleMaintenanceEnvironment(
      backgroundSince: () => lifecycle.backgroundSince,
      power: power,
    );
  },
);
