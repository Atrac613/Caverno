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
      final computerUseGate = summary.gates.singleWhere(
        (gate) => gate.id == 'computer_use_canary',
      );
      expect(computerUseGate.details['overlaySmokeStatus'], 'ready');
      expect(
        computerUseGate.details['helperProcessPolicy'],
        containsPair('helperPathMatchesRunningHelper', true),
      );
      expect(
        computerUseGate.details['manualTccHandoff'],
        containsPair('status', 'manual_required'),
      );
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
        File(
          '${root.path}/macos_computer_use_llm_decision_canary_300/canary_summary.json',
        ),
        _computerUseLlmDecisionSummary(failedCount: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_llm_decision_canary_250/canary_summary.json',
        ),
        _computerUseLlmDecisionSummary(failedCount: 0, scenario: 'mvp-fixture'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_mvp_fixture_llm_canary_350/canary_summary.json',
        ),
        _mvpFixtureAggregateLlmSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_mvp_fixture_vision_llm_canary_400/canary_summary.json',
        ),
        _mvpFixtureVisionLlmSummary(failed: 0),
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
          'overlayForegroundCanary': true,
          'overlaySmokeStatus': 'ready',
          'helperProcessPolicy': <String, Object?>{
            'status': 'ready',
            'helperPathMismatch': false,
            'helperPathMatchesRunningHelper': true,
          },
          'manualTccHandoff': <String, Object?>{
            'status': 'manual_required',
            'manualCommand':
                'bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --m8-runtime-signoff',
          },
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
        endsWith(
          'macos_computer_use_mvp_fixture_vision_llm_canary_400/canary_summary.json',
        ),
      );
      final llmGate = summary.gates.singleWhere(
        (gate) => gate.id == 'llm_canary',
      );
      expect(
        llmGate.details['purpose'],
        'computer_use_mvp_fixture_vision_llm_canary',
      );
      expect(llmGate.details['visibleFixtureWindow'], true);
      expect(
        inputs.desktopActionCanarySummaryPath,
        endsWith(
          'macos_computer_use_desktop_action_canary_200/canary_summary.json',
        ),
      );
      expect(summary.ready, isTrue);
    });

    test('surfaces aggregate MVP fixture LLM canary evidence', () {
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
          llmCanarySummary: _mvpFixtureAggregateLlmSummary(failed: 0),
          llmCanarySummaryPath: '/tmp/mvp_fixture_llm.json',
        ),
      );

      final llmGate = summary.gates.singleWhere(
        (gate) => gate.id == 'llm_canary',
      );
      expect(summary.ready, isTrue);
      expect(llmGate.label, 'Computer Use LLM decision canary');
      expect(llmGate.status, 'passed');
      expect(
        llmGate.details,
        containsPair('purpose', 'computer_use_mvp_fixture_llm_canary'),
      );
      expect(llmGate.details, containsPair('scenarioCount', 2));
      expect(llmGate.details['scenarios'], isNotEmpty);
      expect(llmGate.details, containsPair('requiresUserClick', true));
      expect(llmGate.details, containsPair('requiresUserTextInput', true));
      expect(summary.toMarkdown(), contains('LLM Evidence Gate'));
      expect(summary.toMarkdown(), contains('safe_click_plan'));
      expect(summary.toMarkdown(), contains('type_confirm_plan'));
      expect(summary.toMarkdown(), contains('destructive_target_refused'));
    });

    test('surfaces fixture vision MVP LLM canary evidence', () {
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
          llmCanarySummary: _mvpFixtureVisionLlmSummary(failed: 0),
          llmCanarySummaryPath: '/tmp/mvp_fixture_vision_llm.json',
        ),
      );

      final llmGate = summary.gates.singleWhere(
        (gate) => gate.id == 'llm_canary',
      );
      expect(summary.ready, isTrue);
      expect(llmGate.label, 'Computer Use LLM decision canary');
      expect(llmGate.status, 'passed');
      expect(
        llmGate.details,
        containsPair('purpose', 'computer_use_mvp_fixture_vision_llm_canary'),
      );
      expect(llmGate.details, containsPair('visibleFixtureWindow', true));
      expect(llmGate.details, containsPair('requiresUserClick', true));
      expect(llmGate.details, containsPair('requiresUserTextInput', true));
      expect(
        llmGate.details['typeConfirmTarget'],
        containsPair('confirmationButton', 'Echo Text'),
      );
      expect(llmGate.details['refusedTargets'], isNotEmpty);
      expect(
        llmGate.details,
        containsPair('screenshotPath', '/tmp/fixture-window.png'),
      );
      expect(summary.toMarkdown(), contains('LLM Evidence Gate'));
      expect(summary.toMarkdown(), contains('fixture_window_visible'));
      expect(summary.toMarkdown(), contains('no_execution_claim'));
      expect(summary.toMarkdown(), contains('destructive_target_refused'));
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

    test('surfaces Computer Use LLM decision evidence', () {
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
          llmCanarySummary: _computerUseLlmDecisionSummary(failedCount: 0),
          llmCanarySummaryPath: '/tmp/llm_decision.json',
        ),
      );

      final llmGate = summary.gates.singleWhere(
        (gate) => gate.id == 'llm_canary',
      );
      expect(summary.ready, isTrue);
      expect(llmGate.label, 'Computer Use LLM decision canary');
      expect(llmGate.status, 'passed');
      expect(
        llmGate.details,
        containsPair('purpose', 'computer_use_llm_vision_decision'),
      );
      expect(llmGate.details, containsPair('requiresUserClick', true));
      expect(
        llmGate.details['visionDecision'],
        contains('empty document body'),
      );
      expect(
        llmGate.details['safeTargetReasoning'],
        contains('visible harmless target'),
      );
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
      expect(
        desktopActionGate.details['expectedPhases'],
        contains('pre_observe_image'),
      );
      expect(
        desktopActionGate.details['safeTargetGuidance'],
        contains('Use a visible, harmless target.'),
      );
      expect(
        desktopActionGate.details['failureClassGuidance'],
        containsPair('click_not_sent', 'The armed click did not run.'),
      );
      final runs = desktopActionGate.details['runs'] as List;
      final firstRun = Map<String, dynamic>.from(runs.first as Map);
      expect(firstRun['phaseStatus'], containsPair('click', 'blocked'));

      final markdown = summary.toMarkdown();
      expect(markdown, contains('Desktop Action Evidence'));
      expect(markdown, contains('`pre_observe_image`'));
      expect(markdown, contains('`click_sent`'));
      expect(markdown, contains('`post_observe_image`'));
      expect(markdown, contains('Use a visible, harmless target.'));
      expect(markdown, contains('| run_01 | failed | click_not_sent |'));
      expect(markdown, contains('| ready | blocked | blocked |'));
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
        expect(wrapper, contains('--llm-canary-summary'));
        expect(wrapper, contains('mvp-fixture-aggregate'));
        expect(
          wrapper,
          contains('tool/run_macos_computer_use_llm_decision_canary.sh'),
        );
        expect(
          wrapper,
          contains('tool/run_macos_computer_use_mvp_fixture_llm_canary.sh'),
        );
        expect(wrapper, contains(r'--root "${REPORT_ROOT}"'));
        expect(
          wrapper,
          contains('tool/macos_computer_use_readiness_artifact_index.dart'),
        );
        expect(wrapper, contains('user-operated manual verification only'));
        expect(wrapper, isNot(contains('--m8-runtime-signoff')));
      },
    );

    test('artifact index lists fixed readiness artifacts and latest evidence', () {
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
        File('${root.path}/plan_mode_ping_cli_canary_100/canary_summary.json'),
        _llmSummary(failedCount: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_llm_decision_canary_050/canary_summary.json',
        ),
        _computerUseLlmDecisionSummary(
          failedCount: 0,
          scenario: 'mvp-fixture-type-confirm',
        ),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_mvp_fixture_llm_canary_150/canary_summary.json',
        ),
        _mvpFixtureAggregateLlmSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_mvp_fixture_vision_llm_canary_200/canary_summary.json',
        ),
        _mvpFixtureVisionLlmSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_mvp_llm_readiness_300/mvp_llm_readiness_summary.json',
        ),
        _mvpLlmReadinessSummary(),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_mvp_demo_readiness_400/mvp_demo_readiness_summary.json',
        ),
        _mvpDemoReadinessSummary(),
      );

      final index = buildReadinessArtifactIndex(root);
      final entryIds = index.entries.map((entry) => entry.id).toSet();

      expect(entryIds, contains('release_artifact'));
      expect(entryIds, contains('manual_tcc'));
      expect(entryIds, contains('desktop_action_canary'));
      expect(entryIds, contains('llm_canary'));
      expect(entryIds, contains('mvp_llm_readiness'));
      expect(entryIds, contains('mvp_demo_readiness'));
      expect(
        index.entries
            .singleWhere((entry) => entry.id == 'release_artifact')
            .exists,
        isTrue,
      );
      expect(index.toMarkdown(), contains('M7 release artifact report'));
      final llmEntry = index.entries.singleWhere(
        (entry) => entry.id == 'llm_canary',
      );
      expect(
        llmEntry.path,
        contains('macos_computer_use_mvp_fixture_vision_llm_canary_200'),
      );
      final mvpLlmEntry = index.entries.singleWhere(
        (entry) => entry.id == 'mvp_llm_readiness',
      );
      expect(mvpLlmEntry.exists, isTrue);
      expect(
        mvpLlmEntry.path,
        contains('macos_computer_use_mvp_llm_readiness_300'),
      );
      final mvpDemoEntry = index.entries.singleWhere(
        (entry) => entry.id == 'mvp_demo_readiness',
      );
      expect(mvpDemoEntry.exists, isTrue);
      expect(
        mvpDemoEntry.path,
        contains('macos_computer_use_mvp_demo_readiness_400'),
      );
      expect(index.toMarkdown(), contains('Latest MVP LLM readiness summary'));
      expect(index.toMarkdown(), contains('Latest MVP demo readiness summary'));
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
        overlayForegroundCanary: true,
        overlaySmokeStatus: 'ready',
        helperProcessPolicy: const <String, Object?>{
          'status': 'ready',
          'helperPathMismatch': false,
          'helperPathMatchesRunningHelper': true,
        },
        manualTccHandoff: const <String, Object?>{
          'status': 'manual_required',
          'manualCommand':
              'bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --m8-runtime-signoff',
        },
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

Map<String, dynamic> _computerUseLlmDecisionSummary({
  required int failedCount,
  String? scenario,
}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_llm_decision_canary_summary',
    'purpose': 'computer_use_llm_vision_decision',
    'scenario': scenario,
    'desktopActionBoundary': 'no_desktop_action',
    'runCount': 1,
    'passedCount': failedCount == 0 ? 1 : 0,
    'failedCount': failedCount,
    'passRate': failedCount == 0 ? 1 : 0,
    'failureClassCounts': failedCount == 0
        ? <String, int>{'passed': 1}
        : <String, int>{'requires_user_click_missing': 1},
    'visionDecision': 'Choose the empty document body.',
    'safeTargetReasoning':
        'The empty document body is a visible harmless target.',
    'requiresUserClick': true,
    'selectedTarget': <String, Object?>{
      'label': scenario == null ? 'Empty document body' : 'Safe Click Target',
      'risk': 'low',
    },
    'fixtureApp': scenario == null
        ? null
        : <String, Object?>{
            'name': 'Caverno Computer Use MVP Fixture',
            'windowTitle': 'Caverno Computer Use MVP Fixture',
          },
  };
}

Map<String, dynamic> _mvpFixtureAggregateLlmSummary({required int failed}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_mvp_fixture_llm_canary_summary',
    'schemaVersion': 1,
    'purpose': 'computer_use_mvp_fixture_llm_canary',
    'tccBoundary': 'no_tcc_operation',
    'desktopActionBoundary': 'no_desktop_action',
    'ready': failed == 0,
    'runCount': 2,
    'scenarioCount': 2,
    'passed': failed == 0 ? 2 : 1,
    'failed': failed,
    'failedCount': failed,
    'passRate': failed == 0 ? 1 : 0.5,
    'requiresUserClick': true,
    'requiresUserTextInput': true,
    'mvpEvidenceGate': _mvpEvidenceGate(
      checkIds: <String>[
        'safe_click_plan',
        'type_confirm_plan',
        'destructive_refusal',
      ],
    ),
    'expectedUserOperatedRuntimePhases': <String>[
      'pre_observe_image',
      'click_sent',
      'type_text_sent',
      'post_observe_image',
      'destructive_target_refused',
    ],
    'fixtureApp': <String, Object?>{
      'name': 'Caverno Computer Use MVP Fixture',
      'windowTitle': 'Caverno Computer Use MVP Fixture',
    },
    'scenarios': <Map<String, Object?>>[
      <String, Object?>{
        'scenario': 'mvp-fixture',
        'status': 'passed',
        'runCount': 1,
        'failedCount': 0,
        'selectedTarget': <String, Object?>{
          'label': 'Safe Click Target',
          'risk': 'low',
        },
      },
      <String, Object?>{
        'scenario': 'mvp-fixture-type-confirm',
        'status': failed == 0 ? 'passed' : 'blocked',
        'runCount': 1,
        'failedCount': failed,
        'requiresUserTextInput': true,
        'selectedTarget': <String, Object?>{
          'label': 'MVP Fixture Text Field',
          'risk': 'low',
        },
      },
    ],
  };
}

Map<String, dynamic> _mvpFixtureVisionLlmSummary({required int failed}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_mvp_fixture_vision_llm_canary_summary',
    'schemaVersion': 1,
    'purpose': 'computer_use_mvp_fixture_vision_llm_canary',
    'tccBoundary': 'no_tcc_operation',
    'desktopActionBoundary': 'no_desktop_action',
    'ready': failed == 0,
    'runCount': 1,
    'passedCount': failed == 0 ? 1 : 0,
    'failedCount': failed,
    'passed': failed == 0 ? 1 : 0,
    'failed': failed,
    'passRate': failed == 0 ? 1 : 0,
    'screenshotPath': '/tmp/fixture-window.png',
    'visionDecision':
        'The fixture window is visible with safe click and text controls.',
    'visibleFixtureWindow': true,
    'safeTargetReasoning':
        'Safe Click Target and MVP Fixture Text Field are low-risk fixture controls.',
    'requiresUserClick': true,
    'requiresUserTextInput': true,
    'mvpEvidenceGate': _mvpEvidenceGate(
      checkIds: <String>[
        'fixture_window_visible',
        'safe_click_plan',
        'type_confirm_plan',
        'no_execution_claim',
      ],
    ),
    'expectedUserOperatedRuntimePhases': <String>[
      'pre_observe_image',
      'click_sent',
      'type_text_sent',
      'post_observe_image',
      'destructive_target_refused',
    ],
    'selectedTarget': <String, Object?>{
      'label': 'Safe Click Target',
      'risk': 'low',
      'action': 'click',
    },
    'typeConfirmTarget': <String, Object?>{
      'label': 'MVP Fixture Text Field',
      'confirmationButton': 'Echo Text',
      'action': 'type_text_then_confirm',
    },
    'refusedTargets': <Map<String, Object?>>[
      <String, Object?>{
        'label': 'Danger Zone',
        'reason': 'Disabled destructive target.',
      },
    ],
    'fixtureApp': <String, Object?>{
      'name': 'Caverno Computer Use MVP Fixture',
      'windowTitle': 'Caverno Computer Use MVP Fixture',
    },
  };
}

Map<String, Object?> _mvpEvidenceGate({required List<String> checkIds}) {
  return <String, Object?>{
    'status': 'ready',
    'ready': true,
    'checks': checkIds
        .map(
          (id) => <String, Object?>{
            'id': id,
            'ok': true,
            'nextAction': 'No action required.',
          },
        )
        .toList(growable: false),
    'blockers': <String>[],
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
        : <String, int>{'click_not_sent': 1},
    'expectedPhases': <String>[
      'pre_observe_image',
      'click_sent',
      'post_observe_image',
    ],
    'safeTargetGuidance': <String>[
      'Use a visible, harmless target.',
      'Avoid destructive controls.',
    ],
    'failureClassGuidance': <String, String>{
      'target_not_visible': 'Initial observation failed.',
      'click_not_sent': 'The armed click did not run.',
      'post_observe_unavailable': 'Post-click observation failed.',
      'post_observe_unchanged': 'Post-click observation did not change.',
    },
    'runs': <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'run_01',
        'status': failed == 0 ? 'passed' : 'failed',
        'failureClass': failed == 0 ? 'passed' : 'click_not_sent',
        'phaseStatus': <String, String>{
          'preObserve': 'ready',
          'click': failed == 0 ? 'sent' : 'blocked',
          'postObserve': failed == 0 ? 'ready' : 'blocked',
          'changedEvidence': 'not_measured',
        },
      },
    ],
  };
}

Map<String, dynamic> _mvpLlmReadinessSummary() {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_mvp_llm_readiness_summary',
    'schemaVersion': 1,
    'purpose': 'computer_use_mvp_llm_readiness',
    'automationBoundary': 'no_tcc_no_desktop_action',
    'ready': true,
    'llmReady': true,
    'llmGateReady': true,
    'mvpEvidenceGate': <String, Object?>{
      'status': 'ready',
      'ready': true,
      'checks': <Map<String, Object?>>[
        <String, Object?>{'id': 'safe_click_plan', 'ok': true},
      ],
      'blockers': <String>[],
    },
    'expectedUserOperatedRuntimePhases': <String>[
      'pre_observe_image',
      'click_sent',
      'type_text_sent',
      'post_observe_image',
      'destructive_target_refused',
    ],
  };
}

Map<String, dynamic> _mvpDemoReadinessSummary() {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_mvp_demo_readiness_summary',
    'schemaVersion': 1,
    'purpose': 'computer_use_mvp_demo_readiness',
    'automationBoundary': 'no_tcc_no_desktop_action',
    'ready': true,
    'llmReadinessSummaryPath':
        '/tmp/macos_computer_use_mvp_llm_readiness_summary.json',
    'llmCanarySummaryPath': '/tmp/canary_summary.json',
    'nextUserActions': <String>[],
  };
}

void _writeJson(File file, Map<String, dynamic> json) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(json));
}
