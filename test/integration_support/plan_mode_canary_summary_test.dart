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
  });
}
