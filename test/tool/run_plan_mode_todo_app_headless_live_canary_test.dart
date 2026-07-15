import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('headless TODO runner selects the no-window Plan Mode lane', () {
    final runner = File(
      'tool/run_plan_mode_todo_app_headless_live_canary.sh',
    ).readAsStringSync();

    expect(
      runner,
      contains('CAVERNO_PLAN_MODE_SCENARIOS=live_todo_app_plan_completion'),
    );
    expect(runner, contains('CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1'));
    expect(runner, contains('CAVERNO_PLAN_MODE_DEVICE=headless'));
    expect(runner, contains('CAVERNO_SESSION_LOG_DIR'));
    expect(runner, contains('CAVERNO_PLAN_MODE_REPORT_ROOT'));
    expect(runner, contains('tool/run_plan_mode_live_test.sh'));
    expect(runner, contains('plan_mode_live_suite_headless_report.json'));
    expect(runner, contains('reportQualitySummary'));
    expect(runner, contains('blockerCount'));
    expect(runner, contains('quality.get("ready") is not True'));
    expect(runner, contains('plan_mode_headless_canary_summary.dart'));
    expect(runner, contains('headless_canary_summary.json'));
    expect(runner, contains('--session-log-root'));
  });
}
