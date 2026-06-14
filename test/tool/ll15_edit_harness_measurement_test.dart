import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ll15_edit_harness_measurement.dart';

void main() {
  test('parses options for compare mode', () {
    final options = Ll15EditHarnessMeasurementOptions.parse([
      '--baseline-summary',
      '/tmp/baseline/canary_summary.json',
      '--current-summary=/tmp/current/canary_summary.json',
      '--format',
      'json',
      '--output',
      '/tmp/ll15.json',
    ]);

    expect(options, isNotNull);
    expect(options!.baselineSummaryPath, '/tmp/baseline/canary_summary.json');
    expect(options.currentSummaryPath, '/tmp/current/canary_summary.json');
    expect(options.outputPath, '/tmp/ll15.json');
    expect(options.format, Ll15MeasurementOutputFormat.json);
  });

  test('loads LL15 snapshots from Flutter JSON reporter logs', () async {
    final directory = Directory.systemTemp.createTempSync(
      'll15-edit-harness-snapshot-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final log = File('${directory.path}/flutter_test.jsonl');
    await log.writeAsString(
      [
        jsonEncode({
          'type': 'print',
          'message':
              '[LL15] edit_harness_snapshot ${jsonEncode(_snapshot(attempts: 2, failures: 1, harnessPrompted: true))}',
        }),
        '[LL15] edit_harness_snapshot ${jsonEncode(_snapshot(attempts: 1, failures: 0, harnessPrompted: false))}',
      ].join('\n'),
    );

    final snapshots = await loadLl15EditHarnessSnapshots(log.path);

    expect(snapshots, hasLength(2));
    expect(snapshots.first.harnessPrompted, isTrue);
    expect(snapshots.first.attempts, 2);
    expect(snapshots.first.failures, 1);
    expect(snapshots.last.harnessPrompted, isFalse);
  });

  test('compares baseline and current edit failure rates', () async {
    final directory = Directory.systemTemp.createTempSync(
      'll15-edit-harness-measurement-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final baselineLog = File('${directory.path}/baseline.jsonl');
    final currentLog = File('${directory.path}/current.jsonl');
    await baselineLog.writeAsString(
      '[LL15] edit_harness_snapshot ${jsonEncode(_snapshot(attempts: 4, failures: 2, harnessPrompted: false))}\n',
    );
    await currentLog.writeAsString(
      '[LL15] edit_harness_snapshot ${jsonEncode(_snapshot(attempts: 4, failures: 1, harnessPrompted: true))}\n',
    );
    final baselineSummary = File('${directory.path}/baseline_summary.json');
    final currentSummary = File('${directory.path}/current_summary.json');
    await baselineSummary.writeAsString(
      jsonEncode(_summary(logPath: baselineLog.path, passedCount: 3)),
    );
    await currentSummary.writeAsString(
      jsonEncode(_summary(logPath: currentLog.path, passedCount: 4)),
    );

    final measurement = await buildLl15EditHarnessMeasurement(
      baselineSummaryPath: baselineSummary.path,
      currentSummaryPath: currentSummary.path,
      generatedAt: DateTime.utc(2026, 6, 14, 2, 3, 4),
    );

    expect(measurement.baseline.failureRate, 0.5);
    expect(measurement.current.failureRate, 0.25);
    expect(measurement.failureRateDelta, -0.25);
    expect(measurement.failureRateReduced, isTrue);
    expect(measurement.passRateDelta, 0.25);
    expect(
      measurement.toJson()['schemaName'],
      'caverno_ll15_edit_harness_measurement',
    );
    expect(measurement.toJson()['schemaVersion'], 2);
    expect(measurement.toMarkdown(), contains('LL15 Weak-Model Edit Harness'));
    expect(measurement.toMarkdown(), contains('Failure rate reduced: `true`'));
  });

  test('classifies failed canary tests by failure mode', () async {
    final directory = Directory.systemTemp.createTempSync(
      'll15-edit-harness-failure-class-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final log = File('${directory.path}/current.jsonl');
    await log.writeAsString(
      '[LL15] edit_harness_snapshot ${jsonEncode(_snapshot(attempts: 2, failures: 0, harnessPrompted: true))}\n',
    );
    final summary = File('${directory.path}/current_summary.json');
    await summary.writeAsString(
      jsonEncode(
        _summary(
          logPath: log.path,
          passedCount: 2,
          failedTests: [
            _failedTest(
              name: 'live LLM edits code',
              message:
                  'Expected: contains CODING_GOAL_EDIT_TEST_OK\n'
                  'toolCalls={"name":"read_file"}',
            ),
            _failedTest(
              name: 'live LLM initializes git',
              message:
                  'Expected: contains all of [revert --no-edit HEAD]\n'
                  'Actual: successfulGitCommands missing revert',
            ),
          ],
        ),
      ),
    );

    final run = await loadLl15CanaryRunSummary(summaryPath: summary.path);

    expect(run.failedTests, hasLength(2));
    expect(run.failureClassCounts, {
      'no_edit': 1,
      'git_lifecycle_incomplete': 1,
    });
    expect(run.toJson()['failureClasses'], {
      'no_edit': 1,
      'git_lifecycle_incomplete': 1,
    });
    expect(
      Ll15EditHarnessMeasurementSummary(
        generatedAt: DateTime.utc(2026, 6, 14),
        baseline: run,
        current: run,
      ).toMarkdown(),
      contains('Failure classes: `no_edit:1, git_lifecycle_incomplete:1`'),
    );
  });
}

Map<String, dynamic> _summary({
  required String logPath,
  required int passedCount,
  List<Map<String, dynamic>> failedTests = const [],
}) {
  return {
    'schemaName': 'live_llm_canary_summary',
    'schemaVersion': 1,
    'logPath': logPath,
    'result': passedCount == 4 ? 'passed' : 'failed',
    'runnerSuccess': passedCount == 4,
    'testCount': 4,
    'passedCount': passedCount,
    'failedCount': failedTests.isEmpty ? 4 - passedCount : failedTests.length,
    'skippedCount': 0,
    'tests': failedTests,
  };
}

Map<String, dynamic> _failedTest({
  required String name,
  required String message,
}) {
  return {'name': name, 'result': 'failed', 'failureMessage': message};
}

Map<String, dynamic> _snapshot({
  required int attempts,
  required int failures,
  required bool harnessPrompted,
}) {
  return {
    'schemaName': 'll15_edit_harness_canary_snapshot',
    'schemaVersion': 1,
    'harnessPrompted': harnessPrompted,
    'attempts': attempts,
    'successes': attempts - failures,
    'failures': failures,
    'failureRate': attempts == 0 ? 0 : failures / attempts,
    'lastOutcome': failures > 0 ? 'editMismatch' : 'success',
    'editToolCallCount': attempts,
    'writeToolCallCount': 0,
  };
}
