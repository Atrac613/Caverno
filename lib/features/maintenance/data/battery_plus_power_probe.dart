import 'dart:async';

import 'package:battery_plus/battery_plus.dart';

import '../domain/services/power_state_probe.dart';

/// LL18: [PowerStateProbe] backed by `battery_plus`. Caches the latest battery
/// state (initial read plus a subscription to state changes) so the gate can
/// query AC power synchronously.
///
/// The battery accessors are injectable so the caching/mapping is unit-testable
/// without the plugin; the live desktop behavior is exercised on device.
class BatteryPlusPowerProbe implements PowerStateProbe {
  BatteryPlusPowerProbe({
    Future<BatteryState> Function()? readState,
    Stream<BatteryState>? stateChanges,
  }) : _injectedRead = readState,
       _injectedChanges = stateChanges;

  final Future<BatteryState> Function()? _injectedRead;
  final Stream<BatteryState>? _injectedChanges;

  Battery? _battery;
  bool? _onAcPower;
  StreamSubscription<BatteryState>? _subscription;

  @override
  bool? get onAcPower => _onAcPower;

  /// Reads the current state and starts listening for changes. Failures leave
  /// the state unknown rather than throwing, so power probing can never break
  /// the scheduler.
  Future<void> start() async {
    final usePlugin = _injectedRead == null || _injectedChanges == null;
    final battery = usePlugin ? (_battery ??= Battery()) : null;
    final read = _injectedRead ?? () => battery!.batteryState;
    final changes = _injectedChanges ?? battery!.onBatteryStateChanged;

    try {
      _onAcPower = mapBatteryState(await read());
    } catch (_) {
      _onAcPower = null;
    }
    _subscription = changes.listen(
      (state) => _onAcPower = mapBatteryState(state),
      onError: (_) {},
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Maps a [BatteryState] to AC-power: charging / full / connected-not-charging
  /// mean plugged in; discharging means on battery; unknown stays unknown.
  static bool? mapBatteryState(BatteryState state) {
    return switch (state) {
      BatteryState.charging ||
      BatteryState.full ||
      BatteryState.connectedNotCharging => true,
      BatteryState.discharging => false,
      BatteryState.unknown => null,
    };
  }
}
