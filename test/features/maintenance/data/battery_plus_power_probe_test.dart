import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:caverno/features/maintenance/data/battery_plus_power_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mapBatteryState', () {
    test('charging / full / connectedNotCharging mean on AC', () {
      expect(
        BatteryPlusPowerProbe.mapBatteryState(BatteryState.charging),
        true,
      );
      expect(BatteryPlusPowerProbe.mapBatteryState(BatteryState.full), true);
      expect(
        BatteryPlusPowerProbe.mapBatteryState(
          BatteryState.connectedNotCharging,
        ),
        true,
      );
    });

    test('discharging means on battery', () {
      expect(
        BatteryPlusPowerProbe.mapBatteryState(BatteryState.discharging),
        false,
      );
    });

    test('unknown stays unknown', () {
      expect(
        BatteryPlusPowerProbe.mapBatteryState(BatteryState.unknown),
        isNull,
      );
    });
  });

  test('caches the initial state and updates on change events', () async {
    final controller = StreamController<BatteryState>.broadcast();
    addTearDown(controller.close);
    final probe = BatteryPlusPowerProbe(
      readState: () async => BatteryState.charging,
      stateChanges: controller.stream,
    );
    addTearDown(probe.dispose);

    expect(probe.onAcPower, isNull, reason: 'unknown before start');

    await probe.start();
    expect(probe.onAcPower, isTrue, reason: 'initial read = charging');

    controller.add(BatteryState.discharging);
    await Future<void>.delayed(Duration.zero);
    expect(probe.onAcPower, isFalse, reason: 'unplugged');

    controller.add(BatteryState.full);
    await Future<void>.delayed(Duration.zero);
    expect(probe.onAcPower, isTrue);
  });

  test('a failed initial read leaves the state unknown', () async {
    final controller = StreamController<BatteryState>.broadcast();
    addTearDown(controller.close);
    final probe = BatteryPlusPowerProbe(
      readState: () async => throw Exception('no battery service'),
      stateChanges: controller.stream,
    );
    addTearDown(probe.dispose);

    await probe.start();
    expect(probe.onAcPower, isNull);
  });
}
