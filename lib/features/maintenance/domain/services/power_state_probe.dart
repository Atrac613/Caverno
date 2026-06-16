/// LL18: a port exposing the machine's AC-power state to the idle-maintenance
/// gate, so the domain stays independent of the battery plugin.
///
/// Implementations cache the latest state and answer synchronously; `null`
/// means unknown (not yet probed, or a desktop with no battery), which the gate
/// treats as satisfying the AC requirement.
abstract interface class PowerStateProbe {
  bool? get onAcPower;
}
