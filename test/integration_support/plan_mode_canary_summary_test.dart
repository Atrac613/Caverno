import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_canary_summary.dart';

void main() {
  test('aggregates failure classes across run reports', () {
    final summary = buildPlanModeCanarySummary(<Map<String, dynamic>>[
      <String, dynamic>{
        'scenarios': <Map<String, dynamic>>[
          <String, dynamic>{
            'scenario': 'live_ping_cli_completion',
            'status': 'passed',
            'failureClass': 'passed',
            'budgetPhase': 'completed',
            'durationMs': 1200,
          },
        ],
      },
      <String, dynamic>{
        'scenarios': <Map<String, dynamic>>[
          <String, dynamic>{
            'scenario': 'live_ping_cli_completion',
            'status': 'failed',
            'failureClass': 'streamDisconnect',
            'budgetPhase': 'execution',
            'durationMs': 900,
            'error': 'Connection closed before full header was received',
          },
        ],
      },
    ]);

    expect(summary.runCount, 2);
    expect(summary.passedCount, 1);
    expect(summary.failedCount, 1);
    expect(summary.failureClassCounts['passed'], 1);
    expect(summary.failureClassCounts['streamDisconnect'], 1);
    expect(summary.toMarkdown(), contains('Pass rate: 50.0%'));
    expect(summary.toMarkdown(), contains('Budget Phase'));
    expect(summary.runs.last.budgetPhase, 'execution');
  });

  test('reads last heartbeat details from timeout reports', () {
    final summary = buildPlanModeCanarySummary(<Map<String, dynamic>>[
      <String, dynamic>{
        'scenarios': <Map<String, dynamic>>[
          <String, dynamic>{
            'scenario': 'live_ping_cli_completion',
            'status': 'failed',
            'failureClass': 'overallTimeout',
            'budgetPhase': 'overall',
            'durationMs': 420000,
            'error': 'Overall live run timed out after 420s.',
            'diagnostics': <String, dynamic>{
              'lastHeartbeat': <String, dynamic>{
                'phase': 'execution',
                'subphase': 'nextTask',
                'updatedAt': '2026-04-19T03:00:00.000Z',
                'activeTaskTitle': 'Multiple host ping from file works',
                'phaseTimings': <String, dynamic>{
                  'lastTaskProgressAt': '2026-04-19T02:59:50.000Z',
                },
                'budgets': <String, dynamic>{'overallTimeoutMs': 420000},
              },
            },
          },
        ],
      },
    ]);

    expect(summary.runs.single.lastKnownPhase, 'execution');
    expect(
      summary.runs.single.activeTaskTitle,
      'Multiple host ping from file works',
    );
    expect(summary.runs.single.lastUpdatedAt, '2026-04-19T03:00:00.000Z');
    expect(
      summary.runs.single.phaseTimings['lastTaskProgressAt'],
      '2026-04-19T02:59:50.000Z',
    );
    expect(
      summary.toMarkdown(),
      contains('Multiple host ping from file works'),
    );
  });

  test('prefers scenario log hints when timeout heartbeat is stale', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'plan_mode_canary_summary_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final logFile = File('${tempDir.path}/run_01_run.log');
    await logFile.writeAsString('''
[Workflow] Workflow proposal recovered on retry
[ContentTool] Detected tool_call(s): 1
''');

    final summary = buildPlanModeCanarySummary(<Map<String, dynamic>>[
      <String, dynamic>{
        'scenarios': <Map<String, dynamic>>[
          <String, dynamic>{
            'scenario': 'live_ping_cli_completion',
            'status': 'failed',
            'failureClass': 'overallTimeout',
            'budgetPhase': 'overall',
            'durationMs': 240000,
            'error': 'Overall live run timed out after 240s.',
            'scenarioLog': logFile.path,
            'diagnostics': <String, dynamic>{
              'lastHeartbeat': <String, dynamic>{
                'phase': 'planning',
                'subphase': 'promptSubmitted',
              },
              'recentLogTail': <String>[],
            },
          },
        ],
      },
    ]);

    expect(summary.runs.single.lastKnownPhase, 'execution');
    expect(summary.runs.single.logPath, logFile.path);
  });

  test('infers startup phase from build and foreground failure logs', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'plan_mode_canary_summary_startup_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final logFile = File('${tempDir.path}/run_01_run.log');
    await logFile.writeAsString('''
[CanaryRunner] stage=buildStarted at=2026-04-19T12:00:00Z
Building macOS application...
Failed to foreground app; open returned 1
''');

    final summary = buildPlanModeCanarySummary(<Map<String, dynamic>>[
      <String, dynamic>{
        'scenarios': <Map<String, dynamic>>[
          <String, dynamic>{
            'scenario': 'live_ping_cli_completion',
            'status': 'failed',
            'failureClass': 'appForegroundFailure',
            'budgetPhase': 'startup',
            'durationMs': 45000,
            'error':
                'App failed to foreground before the first live heartbeat.',
            'scenarioLog': logFile.path,
            'diagnostics': <String, dynamic>{
              'lastHeartbeat': <String, dynamic>{},
              'recentLogTail': <String>[],
            },
          },
        ],
      },
    ]);

    expect(summary.runs.single.lastKnownPhase, 'startup');
    expect(summary.runs.single.budgetPhase, 'startup');
  });

  test('prefers planning over startup when both appear in the log', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'plan_mode_canary_summary_phase_priority_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final logFile = File('${tempDir.path}/run_01_run.log');
    await logFile.writeAsString('''
[CanaryRunner] stage=buildStarted at=2026-04-19T12:00:00Z
Failed to foreground app; open returned 1
[CanaryRunner] stage=firstHeartbeatSeen at=2026-04-19T12:00:08Z
[Workflow] Planning research pass started
''');

    final summary = buildPlanModeCanarySummary(<Map<String, dynamic>>[
      <String, dynamic>{
        'scenarios': <Map<String, dynamic>>[
          <String, dynamic>{
            'scenario': 'live_ping_cli_completion',
            'status': 'failed',
            'failureClass': 'overallTimeout',
            'budgetPhase': 'overall',
            'durationMs': 240000,
            'error': 'Overall live run timed out after 240s.',
            'scenarioLog': logFile.path,
            'diagnostics': <String, dynamic>{
              'lastHeartbeat': <String, dynamic>{},
            },
          },
        ],
      },
    ]);

    expect(summary.runs.single.lastKnownPhase, 'planning');
  });

  test(
    'upgrades overall timeout into startup foreground failure from logs',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plan_mode_canary_summary_failure_class_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final logFile = File('${tempDir.path}/run_01_run.log');
      await logFile.writeAsString('''
Building macOS application...
Failed to foreground app; open returned 1
''');

      final summary = buildPlanModeCanarySummary(<Map<String, dynamic>>[
        <String, dynamic>{
          'scenarios': <Map<String, dynamic>>[
            <String, dynamic>{
              'scenario': 'live_ping_cli_completion',
              'status': 'failed',
              'failureClass': 'overallTimeout',
              'budgetPhase': 'overall',
              'durationMs': 240000,
              'error': 'Overall live run timed out after 240s.',
              'scenarioLog': logFile.path,
            },
          ],
        },
      ]);

      expect(summary.runs.single.failureClass, 'appForegroundFailure');
      expect(summary.failureClassCounts['appForegroundFailure'], 1);
    },
  );

  test('upgrades overall timeout into execution overrun from heartbeat', () {
    final summary = buildPlanModeCanarySummary(<Map<String, dynamic>>[
      <String, dynamic>{
        'scenarios': <Map<String, dynamic>>[
          <String, dynamic>{
            'scenario': 'live_ping_cli_completion',
            'status': 'failed',
            'failureClass': 'overallTimeout',
            'budgetPhase': 'overall',
            'durationMs': 240000,
            'error': 'Overall live run timed out after 240s.',
            'diagnostics': <String, dynamic>{
              'lastHeartbeat': <String, dynamic>{
                'phase': 'execution',
                'subphase': 'validation',
                'activeTaskTitle': 'Implement core ping logic',
              },
            },
          },
        ],
      },
    ]);

    expect(summary.runs.single.failureClass, 'executionOverrun');
    expect(summary.failureClassCounts['executionOverrun'], 1);
  });

  test(
    'does not upgrade overall timeout into startup failure after heartbeat recovery',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plan_mode_canary_summary_foreground_recovery_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final logFile = File('${tempDir.path}/run_01_run.log');
      await logFile.writeAsString('''
Building macOS application...
Failed to foreground app; open returned 1
[CanaryRunner] stage=firstHeartbeatSeen at=2026-04-19T12:00:08Z
[CanaryRunner] stage=foregroundRecovered at=2026-04-19T12:00:08Z
''');

      final summary = buildPlanModeCanarySummary(<Map<String, dynamic>>[
        <String, dynamic>{
          'scenarios': <Map<String, dynamic>>[
            <String, dynamic>{
              'scenario': 'live_ping_cli_completion',
              'status': 'failed',
              'failureClass': 'overallTimeout',
              'budgetPhase': 'overall',
              'durationMs': 240000,
              'error': 'Overall live run timed out after 240s.',
              'scenarioLog': logFile.path,
            },
          ],
        },
      ]);

      expect(summary.runs.single.failureClass, 'overallTimeout');
    },
  );
}
