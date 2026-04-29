import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/macos_computer_use_canary_history.dart';
import '../../integration_test/test_support/macos_computer_use_manual_tcc_report.dart';
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
      expect(summary.toMarkdown(), contains('Release artifact gate is ready.'));
    });

    test('marks missing manual TCC as manual required', () {
      final summary = buildReleaseReadinessSummary(
        ReleaseReadinessInputs(
          releaseReport: _releaseReport(status: 'ready'),
          releaseReportPath: '/tmp/m7.json',
          computerUseHistory: _computerUseHistory(stable: true),
          computerUseHistoryPath: '/tmp/history.json',
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
      expect(summary.ready, isTrue);
    });

    test('surfaces blocked LLM canary as a release blocker', () {
      final summary = buildReleaseReadinessSummary(
        ReleaseReadinessInputs(
          releaseReport: _releaseReport(status: 'ready'),
          releaseReportPath: '/tmp/m7.json',
          computerUseHistory: _computerUseHistory(stable: true),
          computerUseHistoryPath: '/tmp/history.json',
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

void _writeJson(File file, Map<String, dynamic> json) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(json));
}
