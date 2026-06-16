/// LL18 idle/overnight maintenance gating configuration.
///
/// Plain immutable value object (no Hive/Freezed yet): the first slice wires
/// the gate decision; persistence in `AppSettings` and the settings UI follow
/// in a later slice. Times are minutes since local midnight, matching how
/// routines model `timeOfDayMinutes`.
class IdleMaintenanceConfig {
  const IdleMaintenanceConfig({
    this.enabled = false,
    this.windowStartMinutes = _defaultWindowStartMinutes,
    this.windowEndMinutes = _defaultWindowEndMinutes,
    this.minIdle = _defaultMinIdle,
    this.requireAcPower = true,
  });

  /// Opt-in: maintenance never runs unless the user enables it.
  final bool enabled;

  /// Maintenance window start, minutes since local midnight (inclusive).
  final int windowStartMinutes;

  /// Maintenance window end, minutes since local midnight (exclusive). When it
  /// is less than [windowStartMinutes] the window wraps past midnight (e.g.
  /// 23:00 -> 06:00). When equal to the start the window spans the whole day.
  final int windowEndMinutes;

  /// Minimum continuous user-idle duration before maintenance may start.
  final Duration minIdle;

  /// Require the machine to be on AC power (laptops). Ignored when the power
  /// state is unknown (e.g. a desktop with no battery).
  final bool requireAcPower;

  static const int _defaultWindowStartMinutes = 2 * 60; // 02:00
  static const int _defaultWindowEndMinutes = 6 * 60; // 06:00
  static const Duration _defaultMinIdle = Duration(minutes: 10);

  /// Whether [windowStartMinutes] / [windowEndMinutes] span past midnight.
  bool get windowWrapsMidnight => windowEndMinutes < windowStartMinutes;

  /// Whether the window covers the entire day (no time restriction).
  bool get windowIsAllDay => windowStartMinutes == windowEndMinutes;

  IdleMaintenanceConfig copyWith({
    bool? enabled,
    int? windowStartMinutes,
    int? windowEndMinutes,
    Duration? minIdle,
    bool? requireAcPower,
  }) {
    return IdleMaintenanceConfig(
      enabled: enabled ?? this.enabled,
      windowStartMinutes: windowStartMinutes ?? this.windowStartMinutes,
      windowEndMinutes: windowEndMinutes ?? this.windowEndMinutes,
      minIdle: minIdle ?? this.minIdle,
      requireAcPower: requireAcPower ?? this.requireAcPower,
    );
  }
}
