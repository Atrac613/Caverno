import '../entities/idle_maintenance_config.dart';

/// Why the idle-maintenance gate refused to run, for diagnostics and the
/// morning report.
enum IdleMaintenanceBlockReason {
  /// Maintenance is not enabled in settings.
  disabled,

  /// The current time is outside the configured maintenance window.
  outsideWindow,

  /// The machine has not been idle long enough (the user may be active).
  insufficientIdle,

  /// The machine is on battery and the config requires AC power.
  onBattery,
}

/// The decision of [IdleMaintenanceWindowPolicy]: whether maintenance may run,
/// and if not, the first gate that blocked it.
class IdleMaintenanceGateResult {
  const IdleMaintenanceGateResult.allowed() : allowed = true, reason = null;

  const IdleMaintenanceGateResult.blocked(this.reason) : allowed = false;

  final bool allowed;
  final IdleMaintenanceBlockReason? reason;
}

/// LL18 keystone gate: decides whether the idle/overnight maintenance
/// orchestrator may run *now*, given the user config, current time, idle
/// duration, and power state.
///
/// Pure and deterministic so the gate is unit-testable without platform idle /
/// power probing; the actual idle/power detection and the scheduler that polls
/// this gate land in later slices. The orchestrator must re-check this gate
/// before every stage so a returning user immediately blocks further work.
class IdleMaintenanceWindowPolicy {
  const IdleMaintenanceWindowPolicy();

  /// Evaluates the gate. [onAcPower] is `null` when the power state is unknown
  /// (e.g. a desktop without a battery), in which case the AC requirement is
  /// treated as satisfied.
  IdleMaintenanceGateResult evaluate({
    required IdleMaintenanceConfig config,
    required DateTime now,
    required Duration idleFor,
    bool? onAcPower,
  }) {
    if (!config.enabled) {
      return const IdleMaintenanceGateResult.blocked(
        IdleMaintenanceBlockReason.disabled,
      );
    }

    if (!_isWithinWindow(config, now)) {
      return const IdleMaintenanceGateResult.blocked(
        IdleMaintenanceBlockReason.outsideWindow,
      );
    }

    if (idleFor < config.minIdle) {
      return const IdleMaintenanceGateResult.blocked(
        IdleMaintenanceBlockReason.insufficientIdle,
      );
    }

    if (config.requireAcPower && onAcPower == false) {
      return const IdleMaintenanceGateResult.blocked(
        IdleMaintenanceBlockReason.onBattery,
      );
    }

    return const IdleMaintenanceGateResult.allowed();
  }

  bool _isWithinWindow(IdleMaintenanceConfig config, DateTime now) {
    if (config.windowIsAllDay) {
      return true;
    }
    final minuteOfDay = now.hour * 60 + now.minute;
    final start = config.windowStartMinutes;
    final end = config.windowEndMinutes;
    if (config.windowWrapsMidnight) {
      // e.g. 23:00 -> 06:00: in-window when after start OR before end.
      return minuteOfDay >= start || minuteOfDay < end;
    }
    return minuteOfDay >= start && minuteOfDay < end;
  }
}
