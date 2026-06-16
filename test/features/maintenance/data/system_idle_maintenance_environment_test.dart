import 'package:caverno/features/maintenance/data/system_idle_maintenance_environment.dart';
import 'package:caverno/features/maintenance/domain/services/power_state_probe.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePowerProbe implements PowerStateProbe {
  _FakePowerProbe(this.onAcPower);
  @override
  bool? onAcPower;
}

void main() {
  test('idle is zero while the app is foregrounded', () {
    final env = SystemIdleMaintenanceEnvironment(
      backgroundSince: () => null,
      power: _FakePowerProbe(true),
      clock: () => DateTime(2026, 6, 16, 3),
    );
    expect(env.idleFor(), Duration.zero);
  });

  test('idle grows from the backgrounded instant', () {
    final env = SystemIdleMaintenanceEnvironment(
      backgroundSince: () => DateTime(2026, 6, 16, 2, 30),
      power: _FakePowerProbe(true),
      clock: () => DateTime(2026, 6, 16, 3),
    );
    expect(env.idleFor(), const Duration(minutes: 30));
  });

  test('a clock earlier than backgroundSince clamps idle to zero', () {
    final env = SystemIdleMaintenanceEnvironment(
      backgroundSince: () => DateTime(2026, 6, 16, 3, 30),
      power: _FakePowerProbe(true),
      clock: () => DateTime(2026, 6, 16, 3),
    );
    expect(env.idleFor(), Duration.zero);
  });

  test('exposes the probe power state and clock now', () {
    final probe = _FakePowerProbe(false);
    final env = SystemIdleMaintenanceEnvironment(
      backgroundSince: () => null,
      power: probe,
      clock: () => DateTime(2026, 6, 16, 3),
    );
    expect(env.onAcPower(), isFalse);
    expect(env.now(), DateTime(2026, 6, 16, 3));

    probe.onAcPower = null;
    expect(env.onAcPower(), isNull);
  });
}
