import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Plan mode PM5 live gate helper', () {
    test('runs smoke suite and ping canary with PM5 defaults', () async {
      final fixture = _ScriptFixture.create();
      fixture.writeHelper(
        path: fixture.liveHelper.path,
        contents: '''
#!/usr/bin/env bash
{
  printf 'SCENARIOS:%s\\n' "\${CAVERNO_PLAN_MODE_SCENARIOS:-}"
  printf 'TAGS:%s\\n' "\${CAVERNO_PLAN_MODE_TAGS:-}"
  printf 'FAIL_ON_WARNINGS:%s\\n' "\${CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS:-}"
  printf 'DEVICE:%s\\n' "\${CAVERNO_PLAN_MODE_DEVICE:-}"
  printf 'REPORTER:%s\\n' "\${CAVERNO_PLAN_MODE_REPORTER:-}"
} > "\${LIVE_LOG}"
exit 0
''',
      );
      fixture.writeHelper(
        path: fixture.pingHelper.path,
        contents: '''
#!/usr/bin/env bash
{
  printf 'REPEAT:%s\\n' "\${CAVERNO_PLAN_MODE_REPEAT_COUNT:-}"
  printf 'FAIL_ON_WARNINGS:%s\\n' "\${CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS:-}"
  printf 'DEVICE:%s\\n' "\${CAVERNO_PLAN_MODE_DEVICE:-}"
  printf 'REPORTER:%s\\n' "\${CAVERNO_PLAN_MODE_REPORTER:-}"
  printf 'PROMPT:%s\\n' "\$*"
} > "\${PING_LOG}"
exit 0
''',
      );

      final result = await fixture.runGate(
        args: const <String>['Custom ping prompt'],
        environment: const <String, String>{
          'CAVERNO_LLM_BASE_URL': 'http://127.0.0.1:1234/v1',
          'CAVERNO_LLM_API_KEY': 'test-key',
          'CAVERNO_LLM_MODEL': 'test-model',
          'CAVERNO_PLAN_MODE_DEVICE': 'macos',
          'CAVERNO_PLAN_MODE_REPORTER': 'compact',
        },
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('PM5 Plan mode live gate completed'));
      expect(
        fixture.liveLog.readAsStringSync(),
        allOf(
          contains('SCENARIOS:\n'),
          contains('TAGS:smoke'),
          contains('FAIL_ON_WARNINGS:1'),
          contains('DEVICE:macos'),
          contains('REPORTER:compact'),
        ),
      );
      expect(
        fixture.pingLog.readAsStringSync(),
        allOf(
          contains('REPEAT:1'),
          contains('FAIL_ON_WARNINGS:1'),
          contains('DEVICE:macos'),
          contains('REPORTER:compact'),
          contains('PROMPT:Custom ping prompt'),
        ),
      );
    });

    test('uses strict one-file ping prompt by default', () async {
      final fixture = _ScriptFixture.create();
      fixture.writeHelper(
        path: fixture.liveHelper.path,
        contents: '''
#!/usr/bin/env bash
exit 0
''',
      );
      fixture.writeHelper(
        path: fixture.pingHelper.path,
        contents: '''
#!/usr/bin/env bash
printf 'PROMPT:%s\\n' "\$*" > "\${PING_LOG}"
exit 0
''',
      );

      final result = await fixture.runGate(
        environment: const <String, String>{
          'CAVERNO_LLM_BASE_URL': 'http://127.0.0.1:1234/v1',
          'CAVERNO_LLM_API_KEY': 'test-key',
          'CAVERNO_LLM_MODEL': 'test-model',
        },
      );

      expect(result.exitCode, 0);
      expect(
        fixture.pingLog.readAsStringSync(),
        allOf(
          contains('exactly one implementation task'),
          contains('only the root-level ping_cli.py file'),
          contains('Do not create README.md'),
        ),
      );
    });

    test('allows PM5 gate overrides and stops after smoke failures', () async {
      final fixture = _ScriptFixture.create();
      fixture.writeHelper(
        path: fixture.liveHelper.path,
        contents: '''
#!/usr/bin/env bash
printf 'TAGS:%s\\n' "\${CAVERNO_PLAN_MODE_TAGS:-}" > "\${LIVE_LOG}"
exit 42
''',
      );
      fixture.writeHelper(
        path: fixture.pingHelper.path,
        contents: '''
#!/usr/bin/env bash
printf 'should not run\\n' > "\${PING_LOG}"
exit 0
''',
      );

      final result = await fixture.runGate(
        environment: const <String, String>{
          'CAVERNO_LLM_BASE_URL': 'http://127.0.0.1:1234/v1',
          'CAVERNO_LLM_API_KEY': 'test-key',
          'CAVERNO_LLM_MODEL': 'test-model',
          'CAVERNO_PLAN_MODE_PM5_SMOKE_TAGS': 'smoke,recovery',
          'CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT': '3',
        },
      );

      expect(result.exitCode, 42);
      expect(
        result.stdout,
        contains('PM5 live gate triage artifacts (failed)'),
      );
      expect(result.stdout, contains('Investigation order'));
      expect(
        fixture.liveLog.readAsStringSync(),
        contains('TAGS:smoke,recovery'),
      );
      expect(fixture.pingLog.existsSync(), isFalse);
    });

    test('prints latest artifact paths when the ping canary fails', () async {
      final fixture = _ScriptFixture.create();
      fixture.writeHelper(
        path: fixture.liveHelper.path,
        contents: '''
#!/usr/bin/env bash
mkdir -p "\${CAVERNO_PLAN_MODE_REPORT_ROOT}"
printf '{"passedCount":1}\\n' > "\${CAVERNO_PLAN_MODE_REPORT_ROOT}/plan_mode_live_suite_macos_report.json"
printf '# Live suite\\n' > "\${CAVERNO_PLAN_MODE_REPORT_ROOT}/plan_mode_live_suite_macos_report.md"
exit 0
''',
      );
      fixture.writeHelper(
        path: fixture.pingHelper.path,
        contents: '''
#!/usr/bin/env bash
canary_dir="\${CAVERNO_PLAN_MODE_REPORT_ROOT}/plan_mode_ping_cli_canary_200"
mkdir -p "\${canary_dir}"
printf '{"failedCount":1}\\n' > "\${canary_dir}/canary_summary.json"
printf '# Canary summary\\n' > "\${canary_dir}/canary_summary.md"
printf '{"failedCount":1}\\n' > "\${canary_dir}/run_01_suite_report.json"
printf 'failure log\\n' > "\${canary_dir}/run_01_run.log"
exit 7
''',
      );

      final result = await fixture.runGate(
        environment: const <String, String>{
          'CAVERNO_LLM_BASE_URL': 'http://127.0.0.1:1234/v1',
          'CAVERNO_LLM_API_KEY': 'test-key',
          'CAVERNO_LLM_MODEL': 'test-model',
        },
      );

      expect(result.exitCode, 7);
      expect(
        result.stdout,
        contains('PM5 live gate triage artifacts (failed)'),
      );
      expect(result.stdout, contains('plan_mode_live_suite_macos_report.json'));
      expect(result.stdout, contains('canary_summary.json'));
      expect(result.stdout, contains('run_01_suite_report.json'));
      expect(result.stdout, contains('run_01_run.log'));
      expect(
        result.stdout,
        contains('docs/plan_mode_release_readiness_checklist.md'),
      );
      expect(
        result.stdout,
        contains('docs/plan_mode_ping_cli_stabilization_playbook.md'),
      );
      expect(result.stdout, contains('Open the latest canary_summary.md'));
    });
  });
}

final class _ScriptFixture {
  _ScriptFixture._(this.root);

  final Directory root;

  File get liveHelper => File('${root.path}/live_helper.sh');
  File get pingHelper => File('${root.path}/ping_helper.sh');
  File get liveLog => File('${root.path}/live.log');
  File get pingLog => File('${root.path}/ping.log');
  Directory get reportRoot => Directory('${root.path}/reports');

  static _ScriptFixture create() {
    final root = Directory.systemTemp.createTempSync('plan_mode_pm5_gate_');
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });
    return _ScriptFixture._(root);
  }

  void writeHelper({required String path, required String contents}) {
    final file = File(path)..writeAsStringSync(contents);
    final result = Process.runSync('chmod', <String>['+x', file.path]);
    expect(result.exitCode, 0);
  }

  Future<ProcessResult> runGate({
    List<String> args = const <String>[],
    required Map<String, String> environment,
  }) {
    return Process.run(
      'bash',
      <String>['tool/run_plan_mode_pm5_live_gate.sh', ...args],
      environment: <String, String>{
        ...environment,
        'CAVERNO_PLAN_MODE_LIVE_TEST_HELPER': liveHelper.path,
        'CAVERNO_PLAN_MODE_PING_CLI_CANARY_HELPER': pingHelper.path,
        'CAVERNO_PLAN_MODE_REPORT_ROOT': reportRoot.path,
        'LIVE_LOG': liveLog.path,
        'PING_LOG': pingLog.path,
      },
    );
  }
}
