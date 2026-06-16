import 'package:caverno/features/maintenance/domain/entities/idle_maintenance_config.dart';
import 'package:caverno/features/maintenance/domain/services/idle_maintenance_window_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = IdleMaintenanceWindowPolicy();

  // 02:00-06:00 window, 10 min idle, AC required, enabled.
  const enabledConfig = IdleMaintenanceConfig(
    enabled: true,
    windowStartMinutes: 120,
    windowEndMinutes: 360,
    minIdle: Duration(minutes: 10),
    requireAcPower: true,
  );

  DateTime at(int hour, int minute) => DateTime(2026, 6, 16, hour, minute);

  test('blocks when maintenance is disabled', () {
    final result = policy.evaluate(
      config: enabledConfig.copyWith(enabled: false),
      now: at(3, 0),
      idleFor: const Duration(hours: 1),
      onAcPower: true,
    );
    expect(result.allowed, isFalse);
    expect(result.reason, IdleMaintenanceBlockReason.disabled);
  });

  test('blocks outside the window', () {
    final result = policy.evaluate(
      config: enabledConfig,
      now: at(12, 0),
      idleFor: const Duration(hours: 1),
      onAcPower: true,
    );
    expect(result.reason, IdleMaintenanceBlockReason.outsideWindow);
  });

  test('blocks when the user has not been idle long enough', () {
    final result = policy.evaluate(
      config: enabledConfig,
      now: at(3, 0),
      idleFor: const Duration(minutes: 2),
      onAcPower: true,
    );
    expect(result.reason, IdleMaintenanceBlockReason.insufficientIdle);
  });

  test('blocks on battery when AC power is required', () {
    final result = policy.evaluate(
      config: enabledConfig,
      now: at(3, 0),
      idleFor: const Duration(hours: 1),
      onAcPower: false,
    );
    expect(result.reason, IdleMaintenanceBlockReason.onBattery);
  });

  test('allows on battery when AC power is not required', () {
    final result = policy.evaluate(
      config: enabledConfig.copyWith(requireAcPower: false),
      now: at(3, 0),
      idleFor: const Duration(hours: 1),
      onAcPower: false,
    );
    expect(result.allowed, isTrue);
  });

  test('treats unknown power state as satisfying the AC requirement', () {
    final result = policy.evaluate(
      config: enabledConfig,
      now: at(3, 0),
      idleFor: const Duration(hours: 1),
      onAcPower: null,
    );
    expect(result.allowed, isTrue);
  });

  test('allows when every gate passes', () {
    final result = policy.evaluate(
      config: enabledConfig,
      now: at(3, 0),
      idleFor: const Duration(minutes: 30),
      onAcPower: true,
    );
    expect(result.allowed, isTrue);
    expect(result.reason, isNull);
  });

  group('window boundaries', () {
    test('start is inclusive, end is exclusive', () {
      expect(
        policy
            .evaluate(
              config: enabledConfig,
              now: at(2, 0),
              idleFor: const Duration(hours: 1),
              onAcPower: true,
            )
            .allowed,
        isTrue,
        reason: 'start minute is inside the window',
      );
      expect(
        policy
            .evaluate(
              config: enabledConfig,
              now: at(6, 0),
              idleFor: const Duration(hours: 1),
              onAcPower: true,
            )
            .reason,
        IdleMaintenanceBlockReason.outsideWindow,
        reason: 'end minute is outside the window',
      );
    });

    test('a window that wraps past midnight includes both sides', () {
      // 23:00 -> 06:00
      const overnight = IdleMaintenanceConfig(
        enabled: true,
        windowStartMinutes: 23 * 60,
        windowEndMinutes: 6 * 60,
        minIdle: Duration(minutes: 10),
        requireAcPower: false,
      );
      const idle = Duration(hours: 1);
      expect(
        policy
            .evaluate(config: overnight, now: at(23, 30), idleFor: idle)
            .allowed,
        isTrue,
      );
      expect(
        policy
            .evaluate(config: overnight, now: at(2, 0), idleFor: idle)
            .allowed,
        isTrue,
      );
      expect(
        policy
            .evaluate(config: overnight, now: at(12, 0), idleFor: idle)
            .reason,
        IdleMaintenanceBlockReason.outsideWindow,
      );
    });

    test('an all-day window (start == end) never blocks on time', () {
      const allDay = IdleMaintenanceConfig(
        enabled: true,
        windowStartMinutes: 0,
        windowEndMinutes: 0,
        minIdle: Duration(minutes: 10),
        requireAcPower: false,
      );
      expect(
        policy
            .evaluate(
              config: allDay,
              now: at(14, 0),
              idleFor: const Duration(hours: 1),
            )
            .allowed,
        isTrue,
      );
    });
  });
}
