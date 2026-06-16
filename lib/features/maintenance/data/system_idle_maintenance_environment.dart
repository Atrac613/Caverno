import '../domain/services/idle_maintenance_environment.dart';
import '../domain/services/power_state_probe.dart';

/// LL18: the real [IdleMaintenanceEnvironment].
///
/// Idle is derived from how long the app has been backgrounded
/// ([backgroundSince]): while the app is foregrounded the user is considered
/// active (idle = zero); once backgrounded, idle grows from that instant. AC
/// power comes from the injected [PowerStateProbe].
///
/// True system-wide HID idle (input idle while Caverno is foreground but the
/// user walked away) needs per-platform native code and is a later refinement;
/// the backgrounded-duration signal is a conservative proxy that never runs
/// while the user is actively in the app.
class SystemIdleMaintenanceEnvironment implements IdleMaintenanceEnvironment {
  SystemIdleMaintenanceEnvironment({
    required DateTime? Function() backgroundSince,
    required PowerStateProbe power,
    DateTime Function() clock = DateTime.now,
  }) : _backgroundSince = backgroundSince,
       _power = power,
       _clock = clock;

  final DateTime? Function() _backgroundSince;
  final PowerStateProbe _power;
  final DateTime Function() _clock;

  @override
  DateTime now() => _clock();

  @override
  Duration idleFor() {
    final since = _backgroundSince();
    if (since == null) {
      return Duration.zero;
    }
    final elapsed = _clock().difference(since);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  @override
  bool? onAcPower() => _power.onAcPower;
}
