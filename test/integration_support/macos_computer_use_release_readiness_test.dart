import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/macos_computer_use_canary_history.dart';
import '../../integration_test/test_support/macos_computer_use_manual_tcc_report.dart';
import '../../integration_test/test_support/macos_computer_use_readiness_artifact_index.dart';
import '../../integration_test/test_support/macos_computer_use_release_readiness.dart';

void main() {
  group('Computer Use release readiness', () {
    test('is ready when all required summaries are ready', () {
      final summary = buildReleaseReadinessSummary(
        ReleaseReadinessInputs(
          releaseReport: _releaseReport(status: 'ready'),
          releaseReportPath: '/tmp/m7.json',
          computerUseHistory: _computerUseHistory(stable: true),
          computerUseHistoryPath: '/tmp/history.json',
          desktopActionCanarySummary: _desktopActionSummary(failed: 0),
          desktopActionCanarySummaryPath: '/tmp/desktop_action.json',
          manualTccReport: _manualTccReport(status: 'ready'),
          manualTccReportPath: '/tmp/m8.json',
          llmCanarySummary: _llmSummary(failedCount: 0),
          llmCanarySummaryPath: '/tmp/llm.json',
        ),
      );

      expect(summary.ready, isTrue);
      expect(summary.status, 'ready');
      expect(
        summary.gates.map((gate) => gate.status),
        everyElement(isNot('missing')),
      );
      expect(summary.toJson()['automationBoundary'], 'read_reports_only');
      expect(summary.toJson()['readyGateIds'], contains('manual_tcc'));
      expect(summary.toJson()['blockedGateIds'], isEmpty);
      expect(summary.toMarkdown(), contains('## All Gates'));
      expect(summary.toMarkdown(), contains('Release artifact gate is ready.'));
    });

    test('marks missing manual TCC as manual required', () {
      final summary = buildReleaseReadinessSummary(
        ReleaseReadinessInputs(
          releaseReport: _releaseReport(status: 'ready'),
          releaseReportPath: '/tmp/m7.json',
          computerUseHistory: _computerUseHistory(stable: true),
          computerUseHistoryPath: '/tmp/history.json',
          desktopActionCanarySummary: _desktopActionSummary(failed: 0),
          desktopActionCanarySummaryPath: '/tmp/desktop_action.json',
          manualTccReport: null,
          manualTccReportPath: null,
          llmCanarySummary: _llmSummary(failedCount: 0),
          llmCanarySummaryPath: '/tmp/llm.json',
        ),
      );

      final manualGate = summary.gates.singleWhere(
        (gate) => gate.id == 'manual_tcc',
      );
      expect(summary.ready, isFalse);
      expect(manualGate.status, 'manual_required');
      expect(manualGate.nextAction, contains('--m8-runtime-signoff'));
      expect(summary.toJson()['readyGateIds'], isNot(contains('manual_tcc')));
      expect(summary.toJson()['blockedGateIds'], contains('manual_tcc'));
      expect(summary.toMarkdown(), contains('## Blocked Gates'));
    });

    test('surfaces manual TCC failure classes and failed checks', () {
      final manualTcc = buildManualTccReportSummary(
        _runtimeReport(status: 'blocked'),
        reportPath: '/tmp/m8.json',
      );
      final summary = buildReleaseReadinessSummary(
        ReleaseReadinessInputs(
          releaseReport: _releaseReport(status: 'ready'),
          releaseReportPath: '/tmp/m7.json',
          computerUseHistory: _computerUseHistory(stable: true),
          computerUseHistoryPath: '/tmp/history.json',
          desktopActionCanarySummary: _desktopActionSummary(failed: 0),
          desktopActionCanarySummaryPath: '/tmp/desktop_action.json',
          manualTccReport: manualTcc,
          manualTccReportPath: '/tmp/m8.json',
          llmCanarySummary: _llmSummary(failedCount: 0),
          llmCanarySummaryPath: '/tmp/llm.json',
        ),
      );

      final manualGate = summary.gates.singleWhere(
        (gate) => gate.id == 'manual_tcc',
      );
      expect(
        manualGate.details['failureClasses'],
        contains('permissions_missing'),
      );
      expect(manualGate.details['failedChecks'], isNotEmpty);
      expect(manualTcc.toMarkdown(), contains('## Failed Checks'));
    });

    test('discovers latest manual TCC and LLM reports from report root', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_release_readiness_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      _writeJson(
        File('${root.path}/release_report.json'),
        _releaseReport(status: 'ready'),
      );
      _writeJson(
        File('${root.path}/plan_mode_ping_cli_canary_100/canary_summary.json'),
        _llmSummary(failedCount: 1),
      );
      _writeJson(
        File('${root.path}/plan_mode_ping_cli_canary_200/canary_summary.json'),
        _llmSummary(failedCount: 0),
      );
      _writeJson(
        File('${root.path}/m8_old/report.json'),
        _runtimeReport(status: 'blocked'),
      );
      _writeJson(
        File('${root.path}/m8_new/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_200/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_live_canary_100/canary_summary.json',
        ),
        <String, Object?>{
          'preset': 'ci',
          'tccBoundary': 'manual_user_operated',
          'stabilityMode': true,
          'stable': true,
          'runCount': 3,
          'passed': 3,
          'failed': 0,
          'passRate': 1,
          'failureClasses': <String, int>{'passed': 3},
        },
      );

      final inputs = readReleaseReadinessInputs(reportRoot: root);
      final summary = buildReleaseReadinessSummary(inputs);

      expect(inputs.manualTccReportPath, endsWith('m8_new/report.json'));
      expect(
        inputs.llmCanarySummaryPath,
        endsWith('plan_mode_ping_cli_canary_200/canary_summary.json'),
      );
      expect(
        inputs.desktopActionCanarySummaryPath,
        endsWith(
          'macos_computer_use_desktop_action_canary_200/canary_summary.json',
        ),
      );
      expect(summary.ready, isTrue);
    });

    test('prefers ready manual TCC evidence over newer blocked evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_release_readiness_manual_priority_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final readyReport = File('${root.path}/m8_ready/report.json');
      final blockedReport = File('${root.path}/m8_blocked/report.json');
      _writeJson(readyReport, _runtimeReport(status: 'ready'));
      _writeJson(blockedReport, _runtimeReport(status: 'blocked'));
      readyReport.setLastModifiedSync(DateTime(2026, 4, 29, 10));
      blockedReport.setLastModifiedSync(DateTime(2026, 4, 29, 11));

      final discovered = discoverLatestManualTccReport(root);

      expect(discovered?.path, readyReport.path);
    });

    test('surfaces blocked LLM canary as a release blocker', () {
      final summary = buildReleaseReadinessSummary(
        ReleaseReadinessInputs(
          releaseReport: _releaseReport(status: 'ready'),
          releaseReportPath: '/tmp/m7.json',
          computerUseHistory: _computerUseHistory(stable: true),
          computerUseHistoryPath: '/tmp/history.json',
          desktopActionCanarySummary: _desktopActionSummary(failed: 0),
          desktopActionCanarySummaryPath: '/tmp/desktop_action.json',
          manualTccReport: _manualTccReport(status: 'ready'),
          manualTccReportPath: '/tmp/m8.json',
          llmCanarySummary: _llmSummary(failedCount: 1),
          llmCanarySummaryPath: '/tmp/llm.json',
        ),
      );

      final llmGate = summary.gates.singleWhere(
        (gate) => gate.id == 'llm_canary',
      );
      expect(summary.ready, isFalse);
      expect(llmGate.status, 'blocked');
      expect(llmGate.nextAction, contains('LLM canary failure classes'));
    });

    test('surfaces blocked desktop action canary as a release blocker', () {
      final summary = buildReleaseReadinessSummary(
        ReleaseReadinessInputs(
          releaseReport: _releaseReport(status: 'ready'),
          releaseReportPath: '/tmp/m7.json',
          computerUseHistory: _computerUseHistory(stable: true),
          computerUseHistoryPath: '/tmp/history.json',
          desktopActionCanarySummary: _desktopActionSummary(failed: 1),
          desktopActionCanarySummaryPath: '/tmp/desktop_action.json',
          manualTccReport: _manualTccReport(status: 'ready'),
          manualTccReportPath: '/tmp/m8.json',
          llmCanarySummary: _llmSummary(failedCount: 0),
          llmCanarySummaryPath: '/tmp/llm.json',
        ),
      );

      final desktopActionGate = summary.gates.singleWhere(
        (gate) => gate.id == 'desktop_action_canary',
      );
      expect(summary.ready, isFalse);
      expect(desktopActionGate.status, 'blocked');
      expect(
        desktopActionGate.nextAction,
        contains('prepare a safe click target'),
      );
    });

    test(
      'CLI exposes safe refresh and CI exit policy without TCC automation',
      () {
        final cli = File(
          'tool/macos_computer_use_release_readiness.dart',
        ).readAsStringSync();
        final wrapper = File(
          'tool/run_macos_computer_use_release_readiness.sh',
        ).readAsStringSync();

        expect(cli, contains('--refresh-safe-inputs'));
        expect(cli, contains('--exit-policy strict|ci'));
        expect(cli, contains('--m7-signoff'));
        expect(cli, contains('tool/macos_computer_use_canary_history.dart'));
        expect(cli, contains('Manual TCC evidence remains user-operated'));
        expect(cli, isNot(contains('--m8-runtime-signoff')));
        expect(wrapper, contains('--ci'));
        expect(wrapper, contains('--signoff'));
        expect(wrapper, contains('--manual-tcc-report'));
        expect(cli, contains('--desktop-action-canary-summary'));
        expect(wrapper, contains('--desktop-action-canary-summary'));
        expect(
          wrapper,
          contains(r'macos_computer_use_release_readiness_${PRESET}.json'),
        );
        expect(
          wrapper,
          contains(r'macos_computer_use_release_readiness_${PRESET}.md'),
        );
        expect(wrapper, contains('--refresh-llm-canary'));
        expect(
          wrapper,
          contains('tool/macos_computer_use_readiness_artifact_index.dart'),
        );
        expect(wrapper, contains('user-operated manual verification only'));
        expect(wrapper, isNot(contains('--m8-runtime-signoff')));
      },
    );

    test(
      'artifact index lists fixed readiness artifacts and latest evidence',
      () {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_artifact_index_test_',
        );
        addTearDown(() {
          root.deleteSync(recursive: true);
        });

        _writeJson(
          File('${root.path}/macos_computer_use_release_artifact_signoff.json'),
          _releaseReport(status: 'ready'),
        );
        _writeJson(
          File('${root.path}/manual/report.json'),
          _runtimeReport(status: 'ready'),
        );
        _writeJson(
          File(
            '${root.path}/plan_mode_ping_cli_canary_100/canary_summary.json',
          ),
          _llmSummary(failedCount: 0),
        );
        _writeJson(
          File(
            '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
          ),
          _desktopActionSummary(failed: 0),
        );

        final index = buildReadinessArtifactIndex(root);
        final entryIds = index.entries.map((entry) => entry.id).toSet();

        expect(entryIds, contains('release_artifact'));
        expect(entryIds, contains('manual_tcc'));
        expect(entryIds, contains('desktop_action_canary'));
        expect(entryIds, contains('llm_canary'));
        expect(
          index.entries
              .singleWhere((entry) => entry.id == 'release_artifact')
              .exists,
          isTrue,
        );
        expect(index.toMarkdown(), contains('M7 release artifact report'));
      },
    );
  });
}

Map<String, dynamic> _releaseReport({required String status}) {
  final ready = status == 'ready';
  return <String, dynamic>{
    'releaseSignoffGate': <String, dynamic>{
      'status': status,
      'blockers': ready ? <String>[] : <String>['codesign'],
      'nextAction': ready
          ? 'M7 release artifact sign-off is complete.'
          : 'Fix release artifact blockers.',
    },
  };
}

Map<String, dynamic> _runtimeReport({required String status}) {
  final ready = status == 'ready';
  return <String, dynamic>{
    'releaseRuntimeSignoffGate': <String, dynamic>{
      'status': status,
      'blockers': ready
          ? <String>[]
          : <String>['release_runtime_permissions_blocked'],
      'nextAction': ready
          ? 'M8 release runtime sign-off is complete.'
          : 'Ask the user to grant permissions manually.',
      'checks': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'permission_status',
          'label': 'Permission status',
          'status': status,
          'ok': ready,
          'nextAction': ready ? null : 'Grant permissions manually.',
        },
      ],
    },
  };
}

ComputerUseCanaryHistory _computerUseHistory({required bool stable}) {
  return ComputerUseCanaryHistory(
    entries: <ComputerUseCanaryHistoryEntry>[
      ComputerUseCanaryHistoryEntry(
        name: 'macos_computer_use_live_canary_100',
        directory: '/tmp/canary',
        summaryPath: '/tmp/canary/canary_summary.json',
        preset: 'ci',
        tccBoundary: 'manual_user_operated',
        stabilityMode: true,
        stable: stable,
        runCount: 3,
        passed: stable ? 3 : 2,
        failed: stable ? 0 : 1,
        passRate: stable ? 1 : 2 / 3,
        failureClasses: stable
            ? const <String, int>{'passed': 3}
            : const <String, int>{'ipc_not_ready': 1},
        modifiedAt: DateTime(2026, 4, 29),
      ),
    ],
    limit: 10,
  );
}

ManualTccReportSummary _manualTccReport({required String status}) {
  final ready = status == 'ready';
  return ManualTccReportSummary(
    reportPath: '/tmp/m8.json',
    status: status,
    ready: ready,
    blockers: ready
        ? const <String>[]
        : const <String>['release_runtime_permissions_blocked'],
    failureClasses: ready
        ? const <String>[]
        : const <String>['permissions_missing'],
    appPath: '/tmp/Caverno.app',
    helperPath: '/tmp/Caverno Computer Use.app',
    nextAction: ready
        ? 'M8 release runtime sign-off is complete.'
        : 'Ask the user to grant permissions manually.',
    checks: const <ManualTccCheckSummary>[],
  );
}

Map<String, dynamic> _llmSummary({required int failedCount}) {
  return <String, dynamic>{
    'runCount': 1,
    'passedCount': failedCount == 0 ? 1 : 0,
    'failedCount': failedCount,
    'passRate': failedCount == 0 ? 1 : 0,
    'failureClassCounts': failedCount == 0
        ? <String, int>{'passed': 1}
        : <String, int>{'tool_loop_blocked': 1},
  };
}

Map<String, dynamic> _desktopActionSummary({required int failed}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_desktop_action_canary_summary',
    'purpose': 'computer_use_desktop_action_canary',
    'tccBoundary': 'manual_user_operated',
    'stable': failed == 0,
    'runCount': 1,
    'passed': failed == 0 ? 1 : 0,
    'failed': failed,
    'passRate': failed == 0 ? 1 : 0,
    'failureClasses': failed == 0
        ? <String, int>{'passed': 1}
        : <String, int>{'click_failed_or_skipped': 1},
  };
}

void _writeJson(File file, Map<String, dynamic> json) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(json));
}
