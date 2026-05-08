import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/macos_computer_use_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/macos_computer_use_canary_history.dart';
import '../../integration_test/test_support/macos_computer_use_manual_tcc_report.dart';
import '../../integration_test/test_support/macos_computer_use_readiness_artifact_index.dart';
import '../../integration_test/test_support/macos_computer_use_release_readiness.dart';

const _manualTccNextAction = MacosComputerUseMvpGuidance.manualTccNextAction;
const _desktopActionNextAction =
    MacosComputerUseMvpGuidance.desktopActionCanaryNextAction;
const _llmCanaryNextAction = MacosComputerUseMvpGuidance.llmCanaryNextAction;

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
      final prReviewSummary =
          summary.toJson()['prReviewSummary'] as Map<String, Object?>;
      expect(prReviewSummary['status'], 'ready_for_release_signoff');
      expect(prReviewSummary['blockedGateIds'], isEmpty);
      expect(prReviewSummary['pendingUserOperatedEvidenceIds'], isEmpty);
      expect(summary.toMarkdown(), contains('## All Gates'));
      expect(summary.toMarkdown(), contains('## PR Review Summary'));
      expect(
        summary.toMarkdown(),
        contains('- Status: ready_for_release_signoff'),
      );
      expect(
        summary.toMarkdown(),
        contains('- Pending user-operated evidence: none'),
      );
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
      expect(manualGate.nextAction, _manualTccNextAction);
      expect(summary.toJson()['readyGateIds'], isNot(contains('manual_tcc')));
      expect(summary.toJson()['blockedGateIds'], contains('manual_tcc'));
      final prReviewSummary =
          summary.toJson()['prReviewSummary'] as Map<String, Object?>;
      expect(prReviewSummary['status'], 'blocked_gates_present');
      expect(
        prReviewSummary['pendingUserOperatedEvidenceIds'],
        contains('manual_tcc'),
      );
      expect(
        summary.toMarkdown(),
        contains('- Pending user-operated evidence: manual_tcc'),
      );
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
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_500/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
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
          'macos_computer_use_real_app_observe_canary_500/canary_summary.json',
        ),
      );
      final llmGate = summary.gates.singleWhere(
        (gate) => gate.id == 'llm_canary',
      );
      expect(
        llmGate.details['purpose'],
        'computer_use_real_app_observe_canary',
      );
      expect(llmGate.details['observedApp'], 'Safari');
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

    test('surfaces M14 real app observe evidence', () {
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
          llmCanarySummary: _realAppObserveLlmSummary(failed: 0),
          llmCanarySummaryPath: '/tmp/real_app_observe.json',
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
        containsPair('purpose', 'computer_use_real_app_observe_canary'),
      );
      expect(llmGate.details, containsPair('targetApp', 'Safari'));
      expect(llmGate.details, containsPair('observedApp', 'Safari'));
      expect(llmGate.details, containsPair('candidateTargetCount', 2));
      expect(llmGate.details['confirmationRequirements'], isNotEmpty);
      expect(summary.toMarkdown(), contains('M14 Evidence Gate'));
      expect(summary.toMarkdown(), contains('M14 evidence gate: ready'));
      expect(summary.toMarkdown(), contains('text_field_targets_classified'));
      expect(summary.toMarkdown(), contains('observe_only_no_mutation'));
    });

    test('surfaces blocked M14 real app observe evidence', () {
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
          llmCanarySummary: _realAppObserveLlmSummary(failed: 1),
          llmCanarySummaryPath: '/tmp/real_app_observe.json',
        ),
      );

      final llmGate = summary.gates.singleWhere(
        (gate) => gate.id == 'llm_canary',
      );
      expect(summary.ready, isFalse);
      expect(llmGate.status, 'blocked');
      expect(
        summary.toMarkdown(),
        contains('confirmation_requirements_missing'),
      );
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
      expect(desktopActionGate.nextAction, _desktopActionNextAction);
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
        File('${root.path}/macos_computer_use_canary_history.json'),
        <String, Object?>{
          'schemaName': 'macos_computer_use_canary_history',
          'stable': true,
          'runCount': 1,
        },
      );
      final manualSummaryPath = '${root.path}/manual/report.json';
      _writeJson(File(manualSummaryPath), _runtimeReport(status: 'ready'));
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
      final llmSummaryPath =
          '${root.path}/macos_computer_use_mvp_fixture_vision_llm_canary_200/canary_summary.json';
      _writeJson(File(llmSummaryPath), _mvpFixtureVisionLlmSummary(failed: 0));
      final realAppObserveSummaryPath =
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json';
      _writeJson(
        File(realAppObserveSummaryPath),
        _realAppObserveLlmSummary(failed: 0),
      );
      final desktopSummaryPath =
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json';
      _writeJson(File(desktopSummaryPath), _desktopActionSummary(failed: 0));
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
      final m15HandoffPath =
          '${root.path}/macos_computer_use_m15_action_proposal_handoff_500/action_proposal_handoff.json';
      _writeJson(File(m15HandoffPath), _m15ActionProposalHandoff(ready: true));

      final index = buildReadinessArtifactIndex(root);
      final entryIds = index.entries.map((entry) => entry.id).toSet();

      expect(entryIds, contains('release_artifact'));
      expect(entryIds, contains('manual_tcc'));
      expect(entryIds, contains('desktop_action_canary'));
      expect(entryIds, contains('llm_canary'));
      expect(entryIds, contains('mvp_llm_readiness'));
      expect(entryIds, contains('mvp_demo_readiness'));
      expect(entryIds, contains('m15_action_proposal_handoff'));
      expect(
        index.entries
            .singleWhere((entry) => entry.id == 'release_artifact')
            .exists,
        isTrue,
      );
      expect(index.toMarkdown(), contains('M7 release artifact report'));
      expect(index.mvpFinalSignoffRehearsal.ready, isTrue);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(
        index.mvpFinalSignoffRehearsal.finalAggregationCommand,
        contains('bash tool/run_macos_computer_use_mvp_signoff.sh'),
      );
      expect(
        index.mvpFinalSignoffRehearsal.finalAggregationCommand,
        contains('--final-signoff'),
      );
      expect(
        index.mvpFinalSignoffRehearsal.finalAggregationCommand,
        contains('--manual-tcc-report $manualSummaryPath'),
      );
      expect(
        index.mvpFinalSignoffRehearsal.finalAggregationCommand,
        contains('--desktop-action-canary-summary $desktopSummaryPath'),
      );
      expect(
        index.mvpFinalSignoffRehearsal.finalAggregationCommand,
        contains('--llm-canary-summary $realAppObserveSummaryPath'),
      );
      expect(index.toMarkdown(), contains('MVP Final Sign-Off Rehearsal'));
      expect(index.toMarkdown(), contains('- Ready: true'));
      expect(index.toMarkdown(), contains('PR Review Summary'));
      expect(
        index.toMarkdown(),
        contains('- Status: ready_for_final_aggregation'),
      );
      expect(
        index.toMarkdown(),
        contains(
          '- Report-only preflight command: `bash tool/run_macos_computer_use_mvp_readiness_preflight.sh --root ${root.path}`',
        ),
      );
      expect(
        index.toMarkdown(),
        contains('- Pending user-operated evidence: none'),
      );
      expect(
        index.mvpFinalSignoffRehearsal.reportOnlyPreflightCommand,
        'bash tool/run_macos_computer_use_mvp_readiness_preflight.sh --root ${root.path}',
      );
      expect(index.toMarkdown(), contains('Final MVP aggregation command:'));
      expect(
        index.toMarkdown(),
        contains('bash tool/run_macos_computer_use_mvp_signoff.sh'),
      );
      expect(
        index.toMarkdown(),
        contains(
          'All required input evidence is present. Run final MVP sign-off aggregation.',
        ),
      );
      final llmEntry = index.entries.singleWhere(
        (entry) => entry.id == 'llm_canary',
      );
      expect(
        llmEntry.path,
        contains('macos_computer_use_real_app_observe_canary_250'),
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
      final m15Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm15_action_proposal_handoff',
      );
      expect(m15Entry.exists, isTrue);
      expect(m15Entry.path, m15HandoffPath);
      expect(m15Entry.status, 'ready');
      expect(
        m15Entry.nextAction,
        'M15 action proposal handoff is ready for user review.',
      );
      expect(m15Entry.details['exactTextCandidateCount'], 1);
      expect(m15Entry.details['textEntryTargetCount'], 1);
      expect(m15Entry.details['publicActionTargetCount'], 1);
      expect(index.toMarkdown(), contains('Latest MVP LLM readiness summary'));
      expect(index.toMarkdown(), contains('Latest MVP demo readiness summary'));
      expect(index.toMarkdown(), contains('Latest LLM canary summary'));
      expect(
        index.toMarkdown(),
        contains('Latest M15 action proposal handoff'),
      );
      expect(
        index.toMarkdown(),
        contains('| Latest M15 action proposal handoff | true | ready |'),
      );
      expect(
        index.toMarkdown(),
        contains('## M15 Action Proposal Review Targets'),
      );
      expect(index.toMarkdown(), contains('Exact text candidates: 1'));
      expect(index.toMarkdown(), contains('Text-entry targets: 1'));
      expect(index.toMarkdown(), contains('Public-action targets: 1'));
    });

    test('artifact index surfaces MVP sign-off rehearsal blockers', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_missing_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      _writeJson(
        File('${root.path}/macos_computer_use_release_artifact_signoff.json'),
        _releaseReport(status: 'ready'),
      );

      final index = buildReadinessArtifactIndex(root);

      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_evidence',
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.readyArtifactIds,
        contains('release_artifact'),
      );
      expect(
        index
            .mvpFinalSignoffRehearsal
            .prReviewSummary
            .pendingUserOperatedEvidenceIds,
        containsAll(<String>['manual_tcc', 'desktop_action_canary']),
      );
      expect(
        index
            .mvpFinalSignoffRehearsal
            .prReviewSummary
            .pendingAutomationSafeEvidenceIds,
        containsAll(<String>['canary_history', 'llm_canary']),
      );
      expect(
        index.mvpFinalSignoffRehearsal.missingArtifactIds,
        containsAll(<String>[
          'canary_history',
          'manual_tcc',
          'desktop_action_canary',
          'llm_canary',
        ]),
      );
      expect(
        index.mvpFinalSignoffRehearsal.missingArtifactActions.map(
          (action) => action.artifactId,
        ),
        containsAll(<String>[
          'canary_history',
          'manual_tcc',
          'desktop_action_canary',
          'llm_canary',
        ]),
      );
      expect(index.toMarkdown(), contains('- Ready: false'));
      expect(index.toMarkdown(), contains('PR Review Summary'));
      expect(
        index.toMarkdown(),
        contains('- Status: blocked_pending_evidence'),
      );
      expect(
        index.toMarkdown(),
        contains(
          '- Pending user-operated evidence: manual_tcc, desktop_action_canary',
        ),
      );
      expect(
        index.toMarkdown(),
        contains(
          '- Pending automation-safe evidence: canary_history, llm_canary',
        ),
      );
      expect(
        index.toMarkdown(),
        contains('Missing Required Artifact Checklist'),
      );
      expect(index.toMarkdown(), contains('| `manual_tcc` |'));
      expect(index.toMarkdown(), contains('| `desktop_action_canary` |'));
      expect(index.toMarkdown(), contains('Operation boundary:'));
      expect(index.toMarkdown(), contains('`tccGrants`: user_operated'));
      expect(index.toMarkdown(), contains('`desktopActions`: user_operated'));
      expect(index.toMarkdown(), contains('`inputSmokeRequiresArming`: true'));
      expect(
        index.toMarkdown(),
        contains('`systemAudioSmokeRequiresArming`: true'),
      );
      expect(
        index.mvpFinalSignoffRehearsal.toJson()['operationBoundary'],
        MacosComputerUseOperationBoundary.values,
      );
      final missingActions =
          index.mvpFinalSignoffRehearsal.toJson()['missingArtifactActions']
              as List<Object?>;
      expect(
        missingActions.cast<Map<String, Object?>>().map(
          (action) => action['artifactId'],
        ),
        contains('manual_tcc'),
      );
      final prReviewSummary =
          index.mvpFinalSignoffRehearsal.toJson()['prReviewSummary']
              as Map<String, Object?>;
      expect(prReviewSummary['status'], 'blocked_pending_evidence');
      expect(
        index.mvpFinalSignoffRehearsal.toJson()['reportOnlyPreflightCommand'],
        'bash tool/run_macos_computer_use_mvp_readiness_preflight.sh --root ${root.path}',
      );
      expect(
        prReviewSummary['pendingUserOperatedEvidenceIds'],
        containsAll(<String>['manual_tcc', 'desktop_action_canary']),
      );
      expect(index.toMarkdown(), contains(_manualTccNextAction));
      expect(index.toMarkdown(), contains(_desktopActionNextAction));
      expect(index.toMarkdown(), contains(_llmCanaryNextAction));
    });

    test('artifact index surfaces blocked M15 action proposal handoff', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m15_blocked_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final m15HandoffPath =
          '${root.path}/macos_computer_use_m15_action_proposal_handoff_1/action_proposal_handoff.json';
      _writeJson(File(m15HandoffPath), _m15ActionProposalHandoff(ready: false));

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm15_action_proposal_handoff',
      );

      expect(entry.exists, isTrue);
      expect(entry.path, m15HandoffPath);
      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve blocked M15 handoff checks before proposing any action.',
      );
      expect(
        index.toMarkdown(),
        contains('Latest M15 action proposal handoff'),
      );
      expect(
        index.toMarkdown(),
        contains('| Latest M15 action proposal handoff | true | blocked |'),
      );
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.missingArtifactIds,
        isNot(contains('m15_action_proposal_handoff')),
      );
    });

    test('artifact index CLI prints MVP sign-off rehearsal status', () async {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_cli_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      _writeJson(
        File('${root.path}/macos_computer_use_release_artifact_signoff.json'),
        _releaseReport(status: 'ready'),
      );

      final result = await Process.run('dart', [
        'run',
        'tool/macos_computer_use_readiness_artifact_index.dart',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final stdout = '${result.stdout}';
      expect(stdout, contains('Readiness artifact index written under'));
      expect(stdout, contains('Artifact index outputs:'));
      expect(
        stdout,
        contains(
          '- JSON: ${root.path}/macos_computer_use_readiness_artifact_index.json',
        ),
      );
      expect(
        stdout,
        contains(
          '- Markdown: ${root.path}/macos_computer_use_readiness_artifact_index.md',
        ),
      );
      expect(
        stdout,
        contains(
          'Artifact index PR Review Summary: ${root.path}/macos_computer_use_readiness_artifact_index.md',
        ),
      );
      expect(stdout, contains('MVP final sign-off rehearsal: blocked'));
      expect(
        stdout,
        contains(
          'Missing MVP artifacts: canary_history, manual_tcc, desktop_action_canary, llm_canary',
        ),
      );
      expect(stdout, contains('Required artifact paths:'));
      expect(stdout, contains('- release_artifact:'));
      expect(stdout, contains('- llm_canary: missing'));
      expect(stdout, contains('PR review summary:'));
      expect(stdout, contains('- Status: blocked_pending_evidence'));
      expect(stdout, contains('- Ready artifacts: release_artifact'));
      expect(
        stdout,
        contains(
          '- Report-only preflight command: bash tool/run_macos_computer_use_mvp_readiness_preflight.sh --root ${root.path}',
        ),
      );
      expect(
        stdout,
        contains(
          '- Pending user-operated evidence: manual_tcc, desktop_action_canary',
        ),
      );
      expect(
        stdout,
        contains(
          '- Pending automation-safe evidence: canary_history, llm_canary',
        ),
      );
      expect(stdout, contains('Operation boundary:'));
      expect(stdout, contains('- tccGrants: user_operated'));
      expect(stdout, contains('- desktopActions: user_operated'));
      expect(stdout, contains('- inputSmokeRequiresArming: true'));
      expect(stdout, contains('- systemAudioSmokeRequiresArming: true'));
      expect(stdout, contains('Missing MVP artifact checklist:'));
      expect(stdout, contains('- manual_tcc (Latest manual TCC evidence):'));
      expect(
        stdout,
        contains(
          '- desktop_action_canary (Latest desktop action canary summary):',
        ),
      );
      expect(stdout, contains('MVP rehearsal next actions:'));
      expect(stdout, contains(_manualTccNextAction));
      expect(stdout, contains(_desktopActionNextAction));
      expect(stdout, contains(_llmCanaryNextAction));
      expect(
        File(
          '${root.path}/macos_computer_use_readiness_artifact_index.json',
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          '${root.path}/macos_computer_use_readiness_artifact_index.md',
        ).existsSync(),
        isTrue,
      );
    });

    test('artifact index CLI prints M14 ready rehearsal evidence', () async {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m14_ready_cli_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      _writeJson(
        File('${root.path}/macos_computer_use_release_artifact_signoff.json'),
        _releaseReport(status: 'ready'),
      );
      _writeJson(
        File('${root.path}/macos_computer_use_canary_history.json'),
        <String, Object?>{
          'schemaName': 'macos_computer_use_canary_history',
          'stable': true,
          'runCount': 1,
        },
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_manual_tcc_1/manual_tcc_report_summary.json',
        ),
        <String, Object?>{
          'schemaName': 'macos_computer_use_manual_tcc_report_summary',
          'ready': true,
          'status': 'ready',
          'blockers': <String>[],
          'checks': <Object?>[],
        },
      );
      final desktopSummaryPath =
          '${root.path}/macos_computer_use_desktop_action_canary_1/canary_summary.json';
      _writeJson(File(desktopSummaryPath), _desktopActionSummary(failed: 0));
      final realAppObserveSummaryPath =
          '${root.path}/macos_computer_use_real_app_observe_canary_1/canary_summary.json';
      _writeJson(
        File(realAppObserveSummaryPath),
        _realAppObserveLlmSummary(failed: 0),
      );

      final result = await Process.run('dart', [
        'run',
        'tool/macos_computer_use_readiness_artifact_index.dart',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final stdout = '${result.stdout}';
      expect(stdout, contains('MVP final sign-off rehearsal: ready'));
      expect(stdout, contains('Missing MVP artifacts: none'));
      expect(stdout, contains('Required artifact paths:'));
      expect(stdout, contains('- llm_canary: $realAppObserveSummaryPath'));
      expect(stdout, contains('- Status: ready_for_final_aggregation'));
      expect(stdout, contains('- Missing artifacts: none'));
      expect(stdout, contains('- Pending automation-safe evidence: none'));
      expect(stdout, contains('Final MVP aggregation command:'));
      expect(
        stdout,
        contains('--desktop-action-canary-summary $desktopSummaryPath'),
      );
      expect(
        stdout,
        contains('--llm-canary-summary $realAppObserveSummaryPath'),
      );

      final markdown = File(
        '${root.path}/macos_computer_use_readiness_artifact_index.md',
      ).readAsStringSync();
      expect(markdown, contains('MVP Final Sign-Off Rehearsal'));
      expect(markdown, contains('- Ready: true'));
      expect(markdown, contains('Latest LLM canary summary'));
      expect(markdown, contains(realAppObserveSummaryPath));
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

Map<String, dynamic> _realAppObserveLlmSummary({required int failed}) {
  final ready = failed == 0;
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_real_app_observe_canary_summary',
    'schemaVersion': 1,
    'purpose': 'computer_use_real_app_observe_canary',
    'milestone': 'M14',
    'tccBoundary': 'no_tcc_operation',
    'desktopActionBoundary': 'no_desktop_action',
    'ready': ready,
    'runCount': 1,
    'passedCount': ready ? 1 : 0,
    'failedCount': failed,
    'passed': ready ? 1 : 0,
    'failed': failed,
    'targetApp': 'Safari',
    'targetIntent': 'Observe Safari for a future X post task.',
    'observedApp': 'Safari',
    'candidateTargetCount': 2,
    'confirmationRequirements': ready
        ? <String>[
            'Ask the user to approve exact text before typing.',
            'Ask the user to approve the public submit action.',
          ]
        : <String>[],
    'm14EvidenceGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'checks': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'safari_style_target_context',
          'ok': true,
          'nextAction': 'No action required.',
        },
        <String, Object?>{
          'id': 'text_field_targets_classified',
          'ok': true,
          'nextAction': 'No action required.',
        },
        <String, Object?>{
          'id': 'public_submit_boundary_classified',
          'ok': true,
          'nextAction': 'No action required.',
        },
        <String, Object?>{
          'id': 'confirmation_requirements_documented',
          'ok': ready,
          'nextAction': ready
              ? 'No action required.'
              : 'Document confirmation requirements before future actions.',
        },
        <String, Object?>{
          'id': 'observe_only_no_mutation',
          'ok': ready,
          'nextAction': ready
              ? 'No action required.'
              : 'Remove executable desktop actions from the plan.',
        },
      ],
      'blockers': ready
          ? <String>[]
          : <String>[
              'confirmation_requirements_missing',
              'executable_action_planned',
            ],
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

Map<String, dynamic> _m15ActionProposalHandoff({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m15_action_proposal_handoff',
    'schemaVersion': 1,
    'purpose': 'computer_use_m15_action_proposal_handoff',
    'milestone': 'M15',
    'previousMilestone': 'M14',
    'ready': ready,
    'tccBoundary': 'no_tcc_operation',
    'desktopActionBoundary': 'no_desktop_action',
    'llmBoundary': 'no_llm_call',
    'sourceM14Summary': '/tmp/canary_summary.json',
    'targetApp': 'Safari',
    'observedApp': 'Safari',
    'targetIntent': 'Prepare an approval-bound plan.',
    'exactTextCandidates': <Map<String, Object?>>[
      <String, Object?>{
        'source': 'targetIntent',
        'text': 'Good morning from Caverno',
        'status': 'requires_user_approval',
      },
    ],
    'textEntryTargets': <Map<String, Object?>>[
      <String, Object?>{
        'label': 'What is happening?',
        'role': 'compose_text_field',
        'risk': 'input',
      },
    ],
    'publicActionTargets': <Map<String, Object?>>[
      <String, Object?>{
        'label': 'Post',
        'role': 'public_submit',
        'risk': 'public_action',
      },
    ],
    'candidateTargets': <Map<String, Object?>>[
      <String, Object?>{
        'label': 'Post',
        'role': 'public_submit',
        'risk': 'public_action',
      },
    ],
    'approvalBoundActionProposal': <Map<String, Object?>>[
      <String, Object?>{
        'phase': 'confirm_public_action',
        'status': 'requires_separate_user_approval',
      },
    ],
    'm15ActionProposalGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'checks': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'm14_evidence_ready',
          'ok': ready,
          'nextAction': ready
              ? 'No action required.'
              : 'Run the M14 real-app observe canary until ready.',
        },
      ],
      'blockers': ready ? <String>[] : <String>['m14_evidence_ready'],
      'nextAction': ready
          ? 'M15 action proposal handoff is ready for user review.'
          : 'Resolve blocked M15 handoff checks before proposing any action.',
    },
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
