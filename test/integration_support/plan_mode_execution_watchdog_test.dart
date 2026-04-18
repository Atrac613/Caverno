import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_execution_watchdog.dart';

void main() {
  test('resets the timer when snapshots change', () {
    final watchdog = PlanModeExecutionWatchdog(
      stallTimeout: const Duration(seconds: 10),
    );
    final startedAt = DateTime(2026, 4, 18, 23, 0);

    expect(watchdog.recordSnapshot('tasks=pending', startedAt), isNull);
    expect(
      watchdog.recordSnapshot(
        'tasks=inProgress',
        startedAt.add(const Duration(seconds: 9)),
      ),
      isNull,
    );
    expect(
      watchdog.recordSnapshot(
        'tasks=inProgress',
        startedAt.add(const Duration(seconds: 18)),
      ),
      isNull,
    );
  });

  test('returns stalled duration once the threshold is exceeded', () {
    final watchdog = PlanModeExecutionWatchdog(
      stallTimeout: const Duration(seconds: 10),
    );
    final startedAt = DateTime(2026, 4, 18, 23, 0);

    watchdog.recordSnapshot('tasks=inProgress', startedAt);
    final stalledFor = watchdog.recordSnapshot(
      'tasks=inProgress',
      startedAt.add(const Duration(seconds: 11)),
    );

    expect(stalledFor, isNotNull);
    expect(stalledFor, const Duration(seconds: 11));
  });
}
