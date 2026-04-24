import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_task_drift.dart';

void main() {
  group('plan mode task drift report', () {
    test('does not flag drift without explicit expected target files', () {
      final report = buildPlanModeTaskDriftReport(
        expectedTargetFiles: const <String>[],
        savedTaskTargetFiles: const <String>['requirements.txt'],
        actualChangedFiles: const <String>['requirements.txt'],
      );

      expect(report.driftDetected, isFalse);
      expect(report.fallbackSource, planModeTaskDriftSourceNone);
      expect(report.driftReason, planModeTaskDriftReasonNone);
    });

    test('flags unexpected saved targets and changed files', () {
      final report = buildPlanModeTaskDriftReport(
        expectedTargetFiles: const <String>['README.md'],
        savedTaskTargetFiles: const <String>['README.md', 'requirements.txt'],
        actualChangedFiles: const <String>['README.md', 'requirements.txt'],
      );

      expect(report.driftDetected, isTrue);
      expect(report.fallbackSource, planModeTaskDriftSourceSavedAndActualFiles);
      expect(
        report.driftReasons,
        contains(planModeTaskDriftReasonUnexpectedSavedTaskTargetFiles),
      );
      expect(
        report.driftReasons,
        contains(planModeTaskDriftReasonUnexpectedChangedFiles),
      );
      expect(report.unexpectedSavedTaskTargetFiles, ['requirements.txt']);
      expect(report.unexpectedChangedFiles, ['requirements.txt']);
    });

    test('normalizes casing and path separators before comparing', () {
      final report = buildPlanModeTaskDriftReport(
        expectedTargetFiles: const <String>[r'Docs\README.md'],
        savedTaskTargetFiles: const <String>['docs/readme.md'],
        actualChangedFiles: const <String>['DOCS/README.md'],
      );

      expect(report.driftDetected, isFalse);
      expect(report.expectedTargetFiles, ['docs/readme.md']);
      expect(report.savedTaskTargetFiles, ['docs/readme.md']);
      expect(report.actualChangedFiles, ['docs/readme.md']);
    });
  });
}
