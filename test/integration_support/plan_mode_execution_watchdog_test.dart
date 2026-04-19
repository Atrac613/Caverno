import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_execution_watchdog.dart';

void main() {
  test('resets the timer when snapshots change', () {
    final watchdog = PlanModeExecutionWatchdog(
      stallTimeout: const Duration(seconds: 10),
    );
    final startedAt = DateTime(2026, 4, 18, 23, 0);

    expect(
      watchdog.recordHeartbeat(
        const PlanModeExecutionHeartbeat(
          activeTaskTitle: 'Config loader',
          workflowSnapshot: 'Config loader:pending',
          toolResultCount: 0,
          fileWriteCount: 0,
          hasPendingApprovals: false,
          isLoading: true,
        ),
        startedAt,
      ),
      isNull,
    );
    expect(
      watchdog.recordHeartbeat(
        const PlanModeExecutionHeartbeat(
          activeTaskTitle: 'Config loader',
          workflowSnapshot: 'Config loader:inProgress',
          toolResultCount: 1,
          fileWriteCount: 0,
          hasPendingApprovals: false,
          isLoading: true,
        ),
        startedAt.add(const Duration(seconds: 9)),
      ),
      isNull,
    );
    expect(
      watchdog.recordHeartbeat(
        const PlanModeExecutionHeartbeat(
          activeTaskTitle: 'Config loader',
          workflowSnapshot: 'Config loader:inProgress',
          toolResultCount: 2,
          fileWriteCount: 0,
          hasPendingApprovals: false,
          isLoading: true,
        ),
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

    watchdog.recordHeartbeat(
      const PlanModeExecutionHeartbeat(
        activeTaskTitle: 'Config loader',
        workflowSnapshot: 'Config loader:inProgress',
        toolResultCount: 1,
        fileWriteCount: 1,
        hasPendingApprovals: false,
        isLoading: true,
      ),
      startedAt,
    );
    final stalledSample = watchdog.recordHeartbeat(
      const PlanModeExecutionHeartbeat(
        activeTaskTitle: 'Config loader',
        workflowSnapshot: 'Config loader:inProgress',
        toolResultCount: 1,
        fileWriteCount: 1,
        hasPendingApprovals: false,
        isLoading: true,
      ),
      startedAt.add(const Duration(seconds: 11)),
    );

    expect(stalledSample, isNotNull);
    expect(stalledSample!.stalledFor, const Duration(seconds: 11));
    expect(stalledSample.heartbeat.activeTaskTitle, 'Config loader');
    expect(stalledSample.heartbeat.toolResultCount, 1);
  });
}
