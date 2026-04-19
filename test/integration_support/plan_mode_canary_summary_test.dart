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
}
