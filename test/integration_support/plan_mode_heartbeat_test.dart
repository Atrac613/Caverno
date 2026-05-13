import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_heartbeat.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('plan_mode_heartbeat_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('resolves heartbeat path from an environment map', () {
    expect(
      resolvePlanModeLiveHeartbeatPath(
        environment: <String, String>{
          'CAVERNO_PLAN_MODE_HEARTBEAT_PATH': '  ${tempDir.path}/beat.json  ',
        },
      ),
      '${tempDir.path}/beat.json',
    );
    expect(
      resolvePlanModeLiveHeartbeatPath(
        environment: const <String, String>{
          'CAVERNO_PLAN_MODE_HEARTBEAT_PATH': '   ',
        },
      ),
      isNull,
    );
  });

  test('writes heartbeat payloads and reads the latest snapshot', () {
    final heartbeatFile = File('${tempDir.path}/nested/heartbeat.json');
    final phaseTrace = PlanModePhaseTrace()
      ..proposalReadyAt = DateTime.utc(2026, 5, 11, 3)
      ..firstTaskStartedAt = DateTime.utc(2026, 5, 11, 3, 1)
      ..firstTaskTitle = 'Create README';
    final budgets = _budgets();

    PlanModeLiveHeartbeatWriter(
      scenarioName: 'live_host_health_scaffold',
      path: heartbeatFile.path,
    ).write(
      phase: 'execution',
      subphase: 'savedTask',
      phaseTrace: phaseTrace,
      budgets: budgets,
      activeTaskTitle: 'Create README',
      workflowSnapshot: 'Create README:inProgress',
      toolResultCount: 2,
      fileWriteCount: 1,
      messageCount: 4,
      hasPendingApprovals: false,
      isLoading: true,
    );

    final snapshot = readPlanModeLiveHeartbeatSnapshot(
      path: heartbeatFile.path,
    );
    expect(snapshot['scenario'], 'live_host_health_scaffold');
    expect(snapshot['phase'], 'execution');
    expect(snapshot['subphase'], 'savedTask');
    expect(snapshot['activeTaskTitle'], 'Create README');
    expect(snapshot['workflowSnapshot'], 'Create README:inProgress');
    expect(snapshot['toolResultCount'], 2);
    expect(snapshot['fileWriteCount'], 1);
    expect(snapshot['messageCount'], 4);
    expect(snapshot['hasPendingApprovals'], false);
    expect(snapshot['isLoading'], true);

    final phaseTimings = snapshot['phaseTimings'] as Map<String, dynamic>;
    expect(
      phaseTimings['proposalReadyAt'],
      DateTime.utc(2026, 5, 11, 3).toIso8601String(),
    );
    expect(
      phaseTimings['firstTaskStartedAt'],
      DateTime.utc(2026, 5, 11, 3, 1).toIso8601String(),
    );

    final budgetPayload = snapshot['budgets'] as Map<String, dynamic>;
    expect(budgetPayload['planningTimeoutMs'], 1000);
    expect(budgetPayload['executionTimeoutMs'], 2000);
    expect(budgetPayload['executionStallTimeoutMs'], 3000);
    expect(budgetPayload['overallTimeoutMs'], 4000);
  });

  test('records planning-ready markers through the observer', () {
    final heartbeatFile = File('${tempDir.path}/heartbeat.json');
    final logs = <String>[
      '[Workflow] Workflow proposal ready',
      '[Workflow] Task proposal ready',
    ];
    final phaseTrace = PlanModePhaseTrace();
    final observer = PlanModePlanningReadyObserver(logs: logs)
      ..configure(
        phaseTrace: phaseTrace,
        budgets: _budgets(),
        heartbeatWriter: PlanModeLiveHeartbeatWriter(
          scenarioName: 'live_cli_entrypoint_decision',
          path: heartbeatFile.path,
        ),
        workflowSnapshotResolver: () => 'Create README:pending',
        messageCountResolver: () => 3,
      );

    observer.observe('[Workflow] Task proposal ready');

    expect(phaseTrace.taskProposalReadyAt, isNotNull);
    final snapshot = readPlanModeLiveHeartbeatSnapshot(
      path: heartbeatFile.path,
    );
    expect(snapshot['phase'], 'planning');
    expect(snapshot['subphase'], 'taskDraftReady');
    expect(snapshot['workflowSnapshot'], 'Create README:pending');
    expect(snapshot['messageCount'], 3);
    expect(snapshot['hasPendingApprovals'], false);
    expect(snapshot['isLoading'], false);
  });
}

PlanModeTimeoutBudgets _budgets() {
  return const PlanModeTimeoutBudgets(
    planningTimeout: Duration(seconds: 1),
    executionTimeout: Duration(seconds: 2),
    executionStallTimeout: Duration(seconds: 3),
    overallTimeout: Duration(seconds: 4),
  );
}
