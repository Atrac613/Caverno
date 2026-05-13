import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_screenshot_policy.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_screenshot_policy_test_',
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('captures screenshots only for deterministic scenarios', () {
    expect(shouldCapturePlanModeScenarioScreenshot(usesLiveLlm: false), isTrue);
    expect(shouldCapturePlanModeScenarioScreenshot(usesLiveLlm: true), isFalse);
  });

  test('builds stable screenshot names for each phase', () {
    expect(
      planModeScenarioScreenshotName(
        scenarioName: 'cli_entrypoint_decision',
        phase: PlanModeScreenshotPhase.decision,
        decisionIndex: 2,
      ),
      'plan_mode_cli_entrypoint_decision_decision_2',
    );
    expect(
      planModeScenarioScreenshotName(
        scenarioName: 'host_health',
        phase: PlanModeScreenshotPhase.proposal,
      ),
      'plan_mode_host_health_proposal',
    );
    expect(
      planModeScenarioScreenshotName(
        scenarioName: 'host_health',
        phase: PlanModeScreenshotPhase.completed,
      ),
      'plan_mode_host_health_completed',
    );
  });

  test('requires a decision index for decision screenshots', () {
    expect(
      () => planModeScenarioScreenshotName(
        scenarioName: 'cli_entrypoint_decision',
        phase: PlanModeScreenshotPhase.decision,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('builds live skip logs with phase labels', () {
    expect(
      planModeScreenshotSkippedForLiveLog(
        phase: PlanModeScreenshotPhase.proposal,
        scenarioName: 'live_host_health_scaffold',
      ),
      '[Screenshot] Proposal screenshot skipped for live scenario '
      'live_host_health_scaffold',
    );
  });

  test('lists only PNG screenshots in sorted order', () {
    File('${tempDir.path}/z.png').writeAsStringSync('z');
    File('${tempDir.path}/a.PNG').writeAsStringSync('a');
    File('${tempDir.path}/notes.txt').writeAsStringSync('notes');
    Directory('${tempDir.path}/nested').createSync();
    File('${tempDir.path}/nested/ignored.png').writeAsStringSync('ignored');

    expect(listPlanModeScenarioScreenshotPaths(tempDir), <String>[
      '${tempDir.path}/a.PNG',
      '${tempDir.path}/z.png',
    ]);
  });
}
