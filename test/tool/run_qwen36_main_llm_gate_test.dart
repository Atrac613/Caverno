import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Qwen3.6 main LLM gate helper', () {
    test('runs required canaries with Qwen defaults', () async {
      final fixture = _ScriptFixture.create();
      fixture.writeHelper(
        path: fixture.exactHelper.path,
        contents: '''
#!/usr/bin/env bash
{
  printf 'BASE:%s\\n' "\${CAVERNO_LLM_BASE_URL:-}"
  printf 'API_KEY:%s\\n' "\${CAVERNO_LLM_API_KEY:-}"
  printf 'MODEL:%s\\n' "\${CAVERNO_LLM_MODEL:-}"
  printf 'SCENARIOS:%s\\n' "\${CAVERNO_PLAN_MODE_SCENARIOS:-}"
  printf 'FAIL_ON_WARNINGS:%s\\n' "\${CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS:-}"
  printf 'DEVICE:%s\\n' "\${CAVERNO_PLAN_MODE_DEVICE:-}"
  printf 'REPORTER:%s\\n' "\${CAVERNO_PLAN_MODE_REPORTER:-}"
  printf 'PREFLIGHT_TIMEOUT:%s\\n' "\${CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS:-}"
  printf 'REPORT_ROOT:%s\\n' "\${CAVERNO_PLAN_MODE_REPORT_ROOT:-}"
} > "\${EXACT_LOG}"
exit 0
''',
      );
      fixture.writeHelper(
        path: fixture.chatHelper.path,
        contents: '''
#!/usr/bin/env bash
{
  printf 'BASE:%s\\n' "\${CAVERNO_LLM_BASE_URL:-}"
  printf 'MODEL:%s\\n' "\${CAVERNO_LLM_MODEL:-}"
  printf 'CANARY:%s\\n' "\${CAVERNO_CHAT_LIVE_CANARY_NAME:-}"
  printf 'REPORT_ROOT:%s\\n' "\${CAVERNO_CHAT_LIVE_CANARY_REPORT_ROOT:-}"
} > "\${CHAT_LOG}"
exit 0
''',
      );
      fixture.writeHelper(
        path: fixture.budgetHelper.path,
        contents: '''
#!/usr/bin/env bash
{
  printf 'BASE:%s\\n' "\${CAVERNO_LLM_BASE_URL:-}"
  printf 'MODEL:%s\\n' "\${CAVERNO_LLM_MODEL:-}"
  printf 'REPORT_ROOT:%s\\n' "\${CAVERNO_TOOL_RESULT_BUDGET_LIVE_CANARY_REPORT_ROOT:-}"
} > "\${BUDGET_LOG}"
exit 0
''',
      );
      fixture.writeHelper(
        path: fixture.pm5Helper.path,
        contents: '''
#!/usr/bin/env bash
printf 'should not run\\n' > "\${PM5_LOG}"
exit 0
''',
      );

      final result = await fixture.runGate();

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Qwen3.6 main LLM gate completed'));
      final exactLog = fixture.exactLog.readAsStringSync();
      expect(
        exactLog,
        allOf(
          contains('BASE:http://192.168.100.241:1234/v1'),
          contains('API_KEY:no-key'),
          contains('MODEL:qwen3.6-35b-a3b-vision'),
          contains('SCENARIOS:live_exact_preservation_readme'),
          contains('FAIL_ON_WARNINGS:1'),
        ),
      );
      expect(
        exactLog,
        allOf(
          contains('DEVICE:macos'),
          contains('REPORTER:compact'),
          contains('PREFLIGHT_TIMEOUT:20'),
          contains('REPORT_ROOT:${fixture.reportRoot.path}'),
        ),
      );
      expect(
        fixture.chatLog.readAsStringSync(),
        allOf(
          contains('BASE:http://192.168.100.241:1234/v1'),
          contains('MODEL:qwen3.6-35b-a3b-vision'),
          contains('CANARY:qwen36_main_llm_chat_canary'),
          contains('REPORT_ROOT:${fixture.reportRoot.path}'),
        ),
      );
      expect(
        fixture.budgetLog.readAsStringSync(),
        allOf(
          contains('BASE:http://192.168.100.241:1234/v1'),
          contains('MODEL:qwen3.6-35b-a3b-vision'),
          contains('REPORT_ROOT:${fixture.reportRoot.path}'),
        ),
      );
      expect(fixture.pm5Log.existsSync(), isFalse);
    });

    test('allows endpoint overrides and optional PM5 gate', () async {
      final fixture = _ScriptFixture.create();
      fixture.writeHelper(
        path: fixture.exactHelper.path,
        contents: '''
#!/usr/bin/env bash
exit 0
''',
      );
      fixture.writeHelper(
        path: fixture.chatHelper.path,
        contents: '''
#!/usr/bin/env bash
exit 0
''',
      );
      fixture.writeHelper(
        path: fixture.budgetHelper.path,
        contents: '''
#!/usr/bin/env bash
exit 0
''',
      );
      fixture.writeHelper(
        path: fixture.pm5Helper.path,
        contents: '''
#!/usr/bin/env bash
{
  printf 'BASE:%s\\n' "\${CAVERNO_LLM_BASE_URL:-}"
  printf 'MODEL:%s\\n' "\${CAVERNO_LLM_MODEL:-}"
  printf 'FAIL_ON_WARNINGS:%s\\n' "\${CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS:-}"
  printf 'DEVICE:%s\\n' "\${CAVERNO_PLAN_MODE_DEVICE:-}"
  printf 'REPORTER:%s\\n' "\${CAVERNO_PLAN_MODE_REPORTER:-}"
  printf 'PING_REPEAT:%s\\n' "\${CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT:-}"
  printf 'REPORT_ROOT:%s\\n' "\${CAVERNO_PLAN_MODE_REPORT_ROOT:-}"
} > "\${PM5_LOG}"
exit 0
''',
      );

      final result = await fixture.runGate(
        environment: const <String, String>{
          'CAVERNO_QWEN36_MAIN_LLM_BASE_URL': 'http://127.0.0.1:4321/v1',
          'CAVERNO_QWEN36_MAIN_LLM_API_KEY': 'override-key',
          'CAVERNO_QWEN36_MAIN_LLM_MODEL': 'override-model',
          'CAVERNO_QWEN36_MAIN_LLM_RUN_PM5': '1',
          'CAVERNO_QWEN36_MAIN_LLM_PM5_PING_REPEAT_COUNT': '2',
          'CAVERNO_QWEN36_MAIN_LLM_DEVICE': 'macos',
          'CAVERNO_QWEN36_MAIN_LLM_REPORTER': 'expanded',
        },
      );

      expect(result.exitCode, 0);
      expect(
        fixture.pm5Log.readAsStringSync(),
        allOf(
          contains('BASE:http://127.0.0.1:4321/v1'),
          contains('MODEL:override-model'),
          contains('FAIL_ON_WARNINGS:1'),
          contains('DEVICE:macos'),
          contains('REPORTER:expanded'),
          contains('PING_REPEAT:2'),
          contains('REPORT_ROOT:${fixture.reportRoot.path}'),
        ),
      );
    });

    test(
      'allows focused exact-preservation runs by skipping chat checks',
      () async {
        final fixture = _ScriptFixture.create();
        fixture.writeHelper(
          path: fixture.exactHelper.path,
          contents: '''
#!/usr/bin/env bash
printf 'exact ran\\n' > "\${EXACT_LOG}"
exit 0
''',
        );
        fixture.writeHelper(
          path: fixture.chatHelper.path,
          contents: '''
#!/usr/bin/env bash
printf 'should not run\\n' > "\${CHAT_LOG}"
exit 0
''',
        );
        fixture.writeHelper(
          path: fixture.budgetHelper.path,
          contents: '''
#!/usr/bin/env bash
printf 'should not run\\n' > "\${BUDGET_LOG}"
exit 0
''',
        );
        fixture.writeHelper(
          path: fixture.pm5Helper.path,
          contents: '''
#!/usr/bin/env bash
exit 0
''',
        );

        final result = await fixture.runGate(
          environment: const <String, String>{
            'CAVERNO_QWEN36_MAIN_LLM_SKIP_CHAT': '1',
            'CAVERNO_QWEN36_MAIN_LLM_SKIP_TOOL_RESULT_BUDGET': '1',
          },
        );

        expect(result.exitCode, 0);
        expect(fixture.exactLog.readAsStringSync(), contains('exact ran'));
        expect(result.stdout, contains('Chat live canary skipped'));
        expect(
          result.stdout,
          contains('Tool-result budget live canary skipped'),
        );
        expect(result.stdout, contains('Chat canary summary JSON: skipped'));
        expect(
          result.stdout,
          contains('Tool-result budget summary JSON: skipped'),
        );
        expect(fixture.chatLog.existsSync(), isFalse);
        expect(fixture.budgetLog.existsSync(), isFalse);
      },
    );

    test(
      'prefers report-root artifacts over stale top-level artifacts',
      () async {
        final fixture = _ScriptFixture.create();
        final repoReportRoot = fixture.createRepoReportRoot();
        final staleExactReport = fixture.createTopLevelExactReport();
        final staleBudgetSummary = fixture.createTopLevelBudgetSummary();
        final currentExactReport = File(
          '${repoReportRoot.path}/plan_mode_live_suite_macos_report.json',
        );
        final currentBudgetSummary = File(
          '${repoReportRoot.path}/tool_result_budget_live_canary_current/canary_summary.json',
        );
        fixture.writeHelper(
          path: fixture.exactHelper.path,
          contents: '''
#!/usr/bin/env bash
printf '{"suite":"exact"}\\n' > "\${CAVERNO_PLAN_MODE_REPORT_ROOT}/plan_mode_live_suite_macos_report.json"
exit 0
''',
        );
        fixture.writeHelper(
          path: fixture.chatHelper.path,
          contents: '''
#!/usr/bin/env bash
exit 0
''',
        );
        fixture.writeHelper(
          path: fixture.budgetHelper.path,
          contents: '''
#!/usr/bin/env bash
mkdir -p "\${CAVERNO_TOOL_RESULT_BUDGET_LIVE_CANARY_REPORT_ROOT}/tool_result_budget_live_canary_current"
printf '{"result":"passed"}\\n' > "\${CAVERNO_TOOL_RESULT_BUDGET_LIVE_CANARY_REPORT_ROOT}/tool_result_budget_live_canary_current/canary_summary.json"
exit 0
''',
        );
        fixture.writeHelper(
          path: fixture.pm5Helper.path,
          contents: '''
#!/usr/bin/env bash
exit 0
''',
        );

        final result = await fixture.runGate(
          environment: <String, String>{
            'CAVERNO_QWEN36_MAIN_LLM_REPORT_ROOT': repoReportRoot.path,
          },
        );

        expect(result.exitCode, 0);
        expect(result.stdout, contains(currentExactReport.path));
        expect(result.stdout, contains(currentBudgetSummary.path));
        expect(result.stdout, isNot(contains(staleExactReport.path)));
        expect(result.stdout, isNot(contains(staleBudgetSummary.path)));
      },
    );

    test('stops after exact preservation failures', () async {
      final fixture = _ScriptFixture.create();
      fixture.writeHelper(
        path: fixture.exactHelper.path,
        contents: '''
#!/usr/bin/env bash
printf 'exact failed\\n' > "\${EXACT_LOG}"
exit 17
''',
      );
      fixture.writeHelper(
        path: fixture.chatHelper.path,
        contents: '''
#!/usr/bin/env bash
printf 'should not run\\n' > "\${CHAT_LOG}"
exit 0
''',
      );
      fixture.writeHelper(
        path: fixture.budgetHelper.path,
        contents: '''
#!/usr/bin/env bash
printf 'should not run\\n' > "\${BUDGET_LOG}"
exit 0
''',
      );
      fixture.writeHelper(
        path: fixture.pm5Helper.path,
        contents: '''
#!/usr/bin/env bash
printf 'should not run\\n' > "\${PM5_LOG}"
exit 0
''',
      );

      final result = await fixture.runGate();

      expect(result.exitCode, 17);
      expect(result.stderr, contains('Exact preservation Plan Mode canary'));
      expect(
        result.stdout,
        contains('Qwen3.6 main LLM gate artifacts (failed)'),
      );
      expect(result.stdout, contains('docs/live_llm_canary_coverage.md'));
      expect(fixture.chatLog.existsSync(), isFalse);
      expect(fixture.budgetLog.existsSync(), isFalse);
      expect(fixture.pm5Log.existsSync(), isFalse);
    });
  });
}

final class _ScriptFixture {
  _ScriptFixture._(this.root);

  final Directory root;

  File get exactHelper => File('${root.path}/exact_helper.sh');
  File get pm5Helper => File('${root.path}/pm5_helper.sh');
  File get chatHelper => File('${root.path}/chat_helper.sh');
  File get budgetHelper => File('${root.path}/budget_helper.sh');
  File get exactLog => File('${root.path}/exact.log');
  File get pm5Log => File('${root.path}/pm5.log');
  File get chatLog => File('${root.path}/chat.log');
  File get budgetLog => File('${root.path}/budget.log');
  Directory get reportRoot => Directory('${root.path}/reports');

  static _ScriptFixture create() {
    final root = Directory.systemTemp.createTempSync('qwen36_main_llm_gate_');
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

  Directory createRepoReportRoot() {
    final path =
        'build/integration_test_reports/qwen36_main_llm_gate_test_${DateTime.now().microsecondsSinceEpoch}';
    final directory = Directory(path).absolute..createSync(recursive: true);
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    return directory;
  }

  File createTopLevelBudgetSummary() {
    final directory = Directory(
      'build/integration_test_reports/tool_result_budget_live_canary_stale_${DateTime.now().microsecondsSinceEpoch}',
    ).absolute..createSync(recursive: true);
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    return File('${directory.path}/canary_summary.json')
      ..writeAsStringSync('{"result":"stale"}\n');
  }

  File createTopLevelExactReport() {
    final directory = Directory(
      'build/integration_test_reports/zz_qwen36_exact_stale_${DateTime.now().microsecondsSinceEpoch}',
    ).absolute..createSync(recursive: true);
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    return File('${directory.path}/plan_mode_live_suite_macos_report.json')
      ..writeAsStringSync('{"suite":"stale"}\n');
  }

  Future<ProcessResult> runGate({
    Map<String, String> environment = const <String, String>{},
  }) {
    return Process.run(
      'bash',
      <String>['tool/run_qwen36_main_llm_gate.sh'],
      environment: <String, String>{
        'CAVERNO_QWEN36_MAIN_LLM_REPORT_ROOT': reportRoot.path,
        ...environment,
        'CAVERNO_QWEN36_MAIN_LLM_EXACT_HELPER': exactHelper.path,
        'CAVERNO_QWEN36_MAIN_LLM_PM5_HELPER': pm5Helper.path,
        'CAVERNO_QWEN36_MAIN_LLM_CHAT_HELPER': chatHelper.path,
        'CAVERNO_QWEN36_MAIN_LLM_TOOL_RESULT_BUDGET_HELPER': budgetHelper.path,
        'EXACT_LOG': exactLog.path,
        'PM5_LOG': pm5Log.path,
        'CHAT_LOG': chatLog.path,
        'BUDGET_LOG': budgetLog.path,
      },
    );
  }
}
