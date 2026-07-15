import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production-path TODO runner selects the isolated live scenario', () {
    final runner = File(
      'tool/run_plan_mode_todo_app_live_canary.sh',
    ).readAsStringSync();

    expect(
      runner,
      contains('CAVERNO_PLAN_MODE_SCENARIOS=live_todo_app_plan_completion'),
    );
    expect(runner, contains('CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1'));
    expect(runner, contains('CAVERNO_SESSION_LOG_DIR'));
    expect(runner, contains('CAVERNO_PLAN_MODE_REPORT_ROOT'));
    expect(runner, contains('tool/run_plan_mode_live_test.sh'));
    expect(runner, contains('plan_mode_live_suite_macos_report.json'));
    expect(runner, contains('reportQualitySummary'));
    expect(runner, contains('blockerCount'));
    expect(runner, contains('quality.get("ready") is not True'));
  });
}
