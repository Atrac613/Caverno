import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CLI0 TODO comparison runner', () {
    test('runs the configured headless count before one macOS run', () async {
      final fixture = _ComparisonFixture.create();
      addTearDown(fixture.dispose);

      final result = await fixture.run(repeatCount: '3');

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(fixture.headlessLog.readAsLinesSync(), hasLength(3));
      expect(fixture.macosLog.readAsLinesSync(), hasLength(1));
      expect(
        fixture.headlessLog.readAsLinesSync(),
        everyElement(contains('|900|1380')),
      );
      expect(fixture.macosLog.readAsStringSync(), contains('|900|1380'));
      final summaryArguments = fixture.summaryLog.readAsStringSync();
      expect(summaryArguments, contains('--headless-root'));
      expect(summaryArguments, contains('--macos-suite-report'));
      expect(summaryArguments, contains('--macos-session-log-root'));
      expect(summaryArguments, contains('--expected-headless-count'));
      expect(summaryArguments, contains('\n3\n'));
      expect(summaryArguments, contains('--out'));
      expect(
        result.stdout,
        contains('CLI0 headless and macOS comparison passed'),
      );
    });

    test(
      'rejects an invalid headless repeat count before running a lane',
      () async {
        final fixture = _ComparisonFixture.create();
        addTearDown(fixture.dispose);

        final result = await fixture.run(repeatCount: '0');

        expect(result.exitCode, 2);
        expect(result.stderr, contains('must be a positive integer'));
        expect(fixture.headlessLog.existsSync(), isFalse);
        expect(fixture.macosLog.existsSync(), isFalse);
      },
    );

    test('keeps the production summarizer and lane wrappers as defaults', () {
      final runner = File(
        'tool/run_plan_mode_todo_app_cli0_comparison.sh',
      ).readAsStringSync();

      expect(runner, contains('CAVERNO_CLI0_HEADLESS_REPEAT_COUNT:-3'));
      expect(runner, contains('CAVERNO_CLI0_EXECUTION_TIMEOUT_SECONDS:-900'));
      expect(runner, contains('CAVERNO_CLI0_RUN_TIMEOUT_SECONDS:-1380'));
      expect(
        runner,
        contains('run_plan_mode_todo_app_headless_live_canary.sh'),
      );
      expect(runner, contains('run_plan_mode_todo_app_live_canary.sh'));
      expect(runner, contains('plan_mode_cli0_comparison_summary.dart'));
      expect(runner, contains('cli0_comparison_summary.json'));
    });
  });
}

class _ComparisonFixture {
  _ComparisonFixture._({
    required this.root,
    required this.headlessRunner,
    required this.macosRunner,
    required this.summaryRunner,
    required this.headlessLog,
    required this.macosLog,
    required this.summaryLog,
    required this.reportRoot,
  });

  final Directory root;
  final File headlessRunner;
  final File macosRunner;
  final File summaryRunner;
  final File headlessLog;
  final File macosLog;
  final File summaryLog;
  final Directory reportRoot;

  static _ComparisonFixture create() {
    final root = Directory.systemTemp.createTempSync('caverno_cli0_gate_');
    final fixture = _ComparisonFixture._(
      root: root,
      headlessRunner: File('${root.path}/headless.sh'),
      macosRunner: File('${root.path}/macos.sh'),
      summaryRunner: File('${root.path}/summary.sh'),
      headlessLog: File('${root.path}/headless.log'),
      macosLog: File('${root.path}/macos.log'),
      summaryLog: File('${root.path}/summary.log'),
      reportRoot: Directory('${root.path}/reports'),
    );
    fixture._writeHelpers();
    return fixture;
  }

  void _writeHelpers() {
    headlessRunner.writeAsStringSync(
      '''
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s|%s\n' "\${CAVERNO_PLAN_MODE_TODO_HEADLESS_REPORT_ROOT}" "\${CAVERNO_PLAN_MODE_EXECUTION_TIMEOUT_SECONDS}" "\${CAVERNO_PLAN_MODE_RUN_TIMEOUT_SECONDS}" >> "\${HEADLESS_LOG}"
'''
          .trimLeft(),
    );
    macosRunner.writeAsStringSync(
      '''
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s|%s\n' "\${CAVERNO_PLAN_MODE_TODO_REPORT_ROOT}" "\${CAVERNO_PLAN_MODE_EXECUTION_TIMEOUT_SECONDS}" "\${CAVERNO_PLAN_MODE_RUN_TIMEOUT_SECONDS}" >> "\${MACOS_LOG}"
report_dir="\${CAVERNO_PLAN_MODE_TODO_REPORT_ROOT}/fake/plan_mode"
mkdir -p "\${report_dir}"
printf '{}\n' > "\${report_dir}/plan_mode_live_suite_macos_report.json"
'''
          .trimLeft(),
    );
    summaryRunner.writeAsStringSync(
      '''
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$@" > "\${SUMMARY_LOG}"
output_path=""
while [[ "\$#" -gt 0 ]]; do
  if [[ "\$1" == "--out" ]]; then
    output_path="\$2"
    break
  fi
  shift
done
mkdir -p "\$(dirname "\${output_path}")"
printf '{"status":"passed"}\n' > "\${output_path}"
'''
          .trimLeft(),
    );
    for (final file in <File>[headlessRunner, macosRunner, summaryRunner]) {
      final result = Process.runSync('chmod', <String>['+x', file.path]);
      if (result.exitCode != 0) {
        throw StateError('Failed to make ${file.path} executable.');
      }
    }
  }

  Future<ProcessResult> run({required String repeatCount}) {
    return Process.run(
      'bash',
      <String>['tool/run_plan_mode_todo_app_cli0_comparison.sh'],
      workingDirectory: Directory.current.path,
      environment: <String, String>{
        'CAVERNO_LLM_BASE_URL': 'http://127.0.0.1:1234/v1',
        'CAVERNO_LLM_API_KEY': 'test-key',
        'CAVERNO_LLM_MODEL': 'test-model',
        'CAVERNO_CLI0_HEADLESS_REPEAT_COUNT': repeatCount,
        'CAVERNO_PLAN_MODE_TODO_CLI0_COMPARISON_REPORT_ROOT': reportRoot.path,
        'CAVERNO_CLI0_HEADLESS_RUNNER': headlessRunner.path,
        'CAVERNO_CLI0_MACOS_RUNNER': macosRunner.path,
        'CAVERNO_CLI0_COMPARISON_SUMMARY_RUNNER': summaryRunner.path,
        'HEADLESS_LOG': headlessLog.path,
        'MACOS_LOG': macosLog.path,
        'SUMMARY_LOG': summaryLog.path,
      },
    );
  }

  void dispose() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }
}
