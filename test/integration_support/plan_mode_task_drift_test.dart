import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_task_drift.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('plan_mode_task_drift_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

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

  group('collectPlanModeScenarioChangedFiles', () {
    test('collects changed files while ignoring harness artifacts', () {
      File('${tempDir.path}/README.md').writeAsStringSync('# Project\n');
      Directory('${tempDir.path}/src').createSync();
      File('${tempDir.path}/src/main.py').writeAsStringSync('print("ok")\n');
      File('${tempDir.path}/scenario_report.json').writeAsStringSync('{}');
      File('${tempDir.path}/scenario_log.txt').writeAsStringSync('log\n');
      File(
        '${tempDir.path}/plan_mode_completed.png',
      ).writeAsBytesSync(const <int>[0]);
      File('${tempDir.path}/.DS_Store').writeAsStringSync('');

      expect(collectPlanModeScenarioChangedFiles(tempDir), <String>[
        'readme.md',
        'src/main.py',
      ]);
    });

    test('returns empty when scenario directory is missing', () {
      expect(
        collectPlanModeScenarioChangedFiles(
          Directory('${tempDir.path}/missing'),
        ),
        isEmpty,
      );
    });
  });

  group('buildPlanModeScenarioTaskDriftReport', () {
    test('uses collected changed files in drift comparison', () {
      File('${tempDir.path}/README.md').writeAsStringSync('# Project\n');
      File('${tempDir.path}/requirements.txt').writeAsStringSync('ping3\n');

      final report = buildPlanModeScenarioTaskDriftReport(
        expectedTargetFiles: const <String>['README.md'],
        savedTaskTargetFiles: const <String>['README.md'],
        scenarioDir: tempDir,
      );

      expect(report.driftDetected, isTrue);
      expect(report.actualChangedFiles, <String>[
        'readme.md',
        'requirements.txt',
      ]);
      expect(report.unexpectedChangedFiles, <String>['requirements.txt']);
      expect(
        report.driftReasons,
        contains(planModeTaskDriftReasonUnexpectedChangedFiles),
      );
    });
  });
}
