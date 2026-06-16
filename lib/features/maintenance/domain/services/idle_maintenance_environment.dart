/// LL18: the runtime inputs the idle-maintenance gate needs, abstracted behind
/// a port so the scheduler stays unit-testable with a fake.
///
/// The real platform-backed implementation (OS idle query + battery/power
/// state on macOS / Windows / Linux) lands in a later slice; the scheduler is
/// built and tested entirely against this interface first.
abstract interface class IdleMaintenanceEnvironment {
  /// Current wall-clock time (injectable so window checks are deterministic).
  DateTime now();

  /// How long the user has been continuously idle (no input).
  Duration idleFor();

  /// Whether the machine is on AC power. `null` when unknown (e.g. a desktop
  /// with no battery), which the gate treats as satisfying the AC requirement.
  bool? onAcPower();
}
