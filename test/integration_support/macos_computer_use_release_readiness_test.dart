import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/macos_computer_use_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/macos_computer_use_canary_history.dart';
import '../../integration_test/test_support/macos_computer_use_manual_tcc_report.dart';
import '../../integration_test/test_support/macos_computer_use_readiness_artifact_index.dart';
import '../../integration_test/test_support/macos_computer_use_release_packaging.dart';
import '../../integration_test/test_support/macos_computer_use_release_readiness.dart';
import '../../integration_test/test_support/macos_computer_use_release_signing_preflight.dart';

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
      expect(summary.toMarkdown(), contains('## Manual TCC Evidence'));
      expect(
        summary.toMarkdown(),
        contains(
          'bash tool/run_macos_computer_use_release_readiness.sh --signoff --manual-tcc-report /tmp/m8.json',
        ),
      );
      expect(summary.toMarkdown(), contains('Release artifact gate is ready.'));
      final manualTccGate = summary.gates.singleWhere(
        (gate) => gate.id == 'manual_tcc',
      );
      final manualTccCommands =
          manualTccGate.details['nextAutomationSafeCommands']
              as Map<String, String>;
      expect(manualTccGate.details['evidencePath'], '/tmp/m8.json');
      expect(
        manualTccCommands['releaseReadinessSignoff'],
        contains('--manual-tcc-report /tmp/m8.json'),
      );
      expect(
        manualTccCommands['nextStepNavigator'],
        'dart run tool/macos_computer_use_next_step_navigator.dart --root build/integration_test_reports',
      );
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

    test('normalizes release signing blocker guidance', () {
      final summary = buildReleaseReadinessSummary(
        ReleaseReadinessInputs(
          releaseReport: _releaseReport(
            status: 'blocked',
            blockers: <String>['release_launch_constraints_blocked'],
            nextAction:
                'Use non-ad-hoc signing with a TeamIdentifier for release LaunchAgent constraints.',
            launchConstraintBlockers: <String>[
              'app:ad_hoc_signature',
              'app:team_identifier_missing',
              'helper:ad_hoc_signature',
              'helper:team_identifier_missing',
            ],
          ),
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

      final releaseGate = summary.gates.singleWhere(
        (gate) => gate.id == 'release_artifact',
      );
      expect(summary.ready, isFalse);
      expect(releaseGate.status, 'blocked');
      expect(
        releaseGate.nextAction,
        contains('macos/Runner/Configs/Signing.local.xcconfig'),
      );
      expect(
        releaseGate.nextAction,
        contains('security find-identity -v -p codesigning'),
      );
      expect(
        releaseGate.details['launchConstraintBlockers'],
        contains('app:ad_hoc_signature'),
      );
      expect(
        summary.toMarkdown(),
        contains('macos/Runner/Configs/Signing.local.xcconfig'),
      );
      expect(
        summary.toMarkdown(),
        contains('security find-identity -v -p codesigning'),
      );
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
            'handoffCommand':
                'bash tool/run_macos_computer_use_manual_tcc_signoff.sh --handoff-only',
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
      expect(llmGate.details, containsPair('scenarioCount', 3));
      expect(llmGate.details['scenarios'], isNotEmpty);
      expect(llmGate.details, containsPair('requiresUserClick', true));
      expect(llmGate.details, containsPair('requiresUserTextInput', true));
      expect(llmGate.details, containsPair('requiresUserSpaceSwitch', true));
      expect(
        llmGate.details,
        containsPair('mvpFixtureSpacesEvidenceReady', true),
      );
      expect(summary.toMarkdown(), contains('LLM Evidence Gate'));
      expect(summary.toMarkdown(), contains('safe_click_plan'));
      expect(summary.toMarkdown(), contains('type_confirm_plan'));
      expect(summary.toMarkdown(), contains('spaces_switch_plan'));
      expect(summary.toMarkdown(), contains('destructive_target_refused'));
    });

    test('blocks aggregate MVP fixture LLM evidence without Spaces plan', () {
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
          llmCanarySummary: _mvpFixtureAggregateLlmSummary(
            failed: 0,
            includeSpacesEvidence: false,
          ),
          llmCanarySummaryPath: '/tmp/mvp_fixture_llm.json',
        ),
      );

      final llmGate = summary.gates.singleWhere(
        (gate) => gate.id == 'llm_canary',
      );
      expect(summary.ready, isFalse);
      expect(llmGate.status, 'blocked');
      expect(
        llmGate.details,
        containsPair('mvpFixtureSpacesEvidenceReady', false),
      );
      expect(llmGate.nextAction, contains('Spaces switch evidence'));
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

    test('ignores legacy plan-mode ping canaries for MVP LLM evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_release_readiness_legacy_llm_test_',
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
        File('${root.path}/plan_mode_ping_cli_canary_100/canary_summary.json'),
        _llmSummary(failedCount: 0),
      );

      final discovered = discoverLatestLlmCanarySummary(root);
      final index = buildReadinessArtifactIndex(root);
      final llmEntry = index.entries.singleWhere(
        (entry) => entry.id == 'llm_canary',
      );
      final automationSafeNavigator = buildReadinessNextStepNavigator(
        root,
        index.entries,
        true,
      );

      expect(discovered, isNull);
      expect(llmEntry.exists, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.missingArtifactIds,
        contains('llm_canary'),
      );
      expect(automationSafeNavigator.recommendation.artifactId, 'llm_canary');
      expect(
        automationSafeNavigator.recommendation.recommendedCommand,
        'bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh',
      );
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
        expect(wrapper, contains(r'mkdir -p "${REPORT_ROOT}"'));
        expect(cli, contains('reportRoot.createSync(recursive: true)'));
        expect(cli, contains('readiness aggregation will '));
        expect(cli, contains('still report blockers'));
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
      final spacesSummaryPath =
          '${root.path}/macos_computer_use_spaces_canary_175/canary_summary.json';
      _writeJson(File(spacesSummaryPath), _spacesSummary(ready: true));
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
      final m15LlmReviewPath =
          '${root.path}/macos_computer_use_m15_llm_review_canary_600/canary_summary.json';
      _writeJson(File(m15LlmReviewPath), _m15LlmReviewSummary(ready: true));
      final m16ApprovalPacketPath =
          '${root.path}/macos_computer_use_m16_approval_packet_700/approval_packet.json';
      _writeJson(File(m16ApprovalPacketPath), _m16ApprovalPacket(ready: true));
      final m17ExecutionRehearsalPath =
          '${root.path}/macos_computer_use_m17_execution_rehearsal_800/execution_rehearsal.json';
      _writeJson(
        File(m17ExecutionRehearsalPath),
        _m17ExecutionRehearsal(ready: true),
      );
      final m18ExecutionHandoffPath =
          '${root.path}/macos_computer_use_m18_execution_handoff_900/execution_handoff.json';
      _writeJson(
        File(m18ExecutionHandoffPath),
        _m18ExecutionHandoff(ready: true),
      );
      final m20ExecutionResultIntakePath =
          '${root.path}/macos_computer_use_m20_execution_result_intake_950/execution_result_intake.json';
      _writeJson(
        File(m20ExecutionResultIntakePath),
        _m20ExecutionResultIntake(
          ready: true,
          sourceM18ExecutionHandoff: m18ExecutionHandoffPath,
        ),
      );
      final m22PostActionReviewPath =
          '${root.path}/macos_computer_use_m22_post_action_review_990/post_action_review.json';
      _writeJson(
        File(m22PostActionReviewPath),
        _m22PostActionReview(
          ready: true,
          sourceM20ExecutionResultIntake: m20ExecutionResultIntakePath,
        ),
      );
      final m23CycleOutcomeHandoffPath =
          '${root.path}/macos_computer_use_m23_cycle_outcome_handoff_995/cycle_outcome_handoff.json';
      _writeJson(
        File(m23CycleOutcomeHandoffPath),
        _m23CycleOutcomeHandoff(
          ready: true,
          sourceM22PostActionReview: m22PostActionReviewPath,
        ),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_m39_beta_signoff_996/macos_computer_use_m39_beta_signoff.json',
        ),
        _m39BetaSignoff(ready: true),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_m40_production_launch_gate_997/macos_computer_use_m40_production_launch_gate.json',
        ),
        _m40ProductionLaunchGate(ready: true),
      );

      final index = buildReadinessArtifactIndex(root);
      final entryIds = index.entries.map((entry) => entry.id).toSet();

      expect(entryIds, contains('release_artifact'));
      expect(entryIds, contains('release_signing_preflight'));
      expect(entryIds, contains('release_packaging'));
      expect(entryIds, contains('manual_tcc'));
      expect(entryIds, contains('desktop_action_canary'));
      expect(entryIds, contains('spaces_canary'));
      expect(entryIds, contains('llm_canary'));
      expect(entryIds, contains('mvp_llm_readiness'));
      expect(entryIds, contains('mvp_demo_readiness'));
      expect(entryIds, contains('m15_action_proposal_handoff'));
      expect(entryIds, contains('m15_llm_review_canary'));
      expect(entryIds, contains('m16_approval_packet'));
      expect(entryIds, contains('m17_execution_rehearsal'));
      expect(entryIds, contains('m18_execution_handoff'));
      expect(entryIds, contains('m20_execution_result_intake'));
      expect(entryIds, contains('m22_post_action_review'));
      expect(entryIds, contains('m23_cycle_outcome_handoff'));
      expect(entryIds, contains('m25_next_cycle_seed_handoff'));
      expect(entryIds, contains('m26_observe_restart_packet'));
      expect(entryIds, contains('m27_screenshot_request_handoff'));
      expect(entryIds, contains('m28_screenshot_evidence_intake'));
      expect(entryIds, contains('m29_observe_canary_run_packet'));
      expect(entryIds, contains('m30_observe_result_intake'));
      expect(entryIds, contains('m39_beta_signoff'));
      expect(entryIds, contains('m40_production_launch_gate'));
      expect(entryIds, contains('m50_signed_beta_gate'));
      expect(entryIds, contains('m51_production_launch_gate'));
      expect(entryIds, contains('m52_product_release_rollout'));
      expect(entryIds, contains('m53_post_release_guardrails'));
      expect(entryIds, contains('m54_rollout_expansion_gate'));
      expect(entryIds, contains('m55_post_expansion_monitoring_gate'));
      expect(entryIds, contains('m56_rollout_decision_handoff_gate'));
      expect(
        index.entries
            .singleWhere((entry) => entry.id == 'release_artifact')
            .exists,
        isTrue,
      );
      expect(index.toMarkdown(), contains('M7 release artifact report'));
      expect(index.toMarkdown(), contains('M33 release packaging report'));
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
      final spacesEntry = index.entries.singleWhere(
        (entry) => entry.id == 'spaces_canary',
      );
      expect(spacesEntry.exists, isTrue);
      expect(spacesEntry.status, 'ready');
      expect(spacesEntry.path, spacesSummaryPath);
      expect(
        spacesEntry.details['requiresApprovedInputBeforeSwitching'],
        isTrue,
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
      expect(m15Entry.details['prReviewStatus'], 'ready_for_review');
      expect(m15Entry.details['reviewGateConsistencyStatus'], 'consistent');
      expect(m15Entry.details['reviewGateConsistencyOk'], isTrue);
      expect(m15Entry.details['blockedReviewEvidence'], isEmpty);
      expect(
        index.mvpFinalSignoffRehearsal.m15LlmReviewCommand,
        'bash tool/run_macos_computer_use_m15_llm_review_canary.sh --root ${root.path} --handoff $m15HandoffPath',
      );
      expect(
        index.mvpFinalSignoffRehearsal.m16ApprovalPacketCommand,
        'bash tool/run_macos_computer_use_m16_approval_packet.sh --root ${root.path} --m15-handoff $m15HandoffPath --m15-llm-review $m15LlmReviewPath',
      );
      final m15LlmEntry = index.entries.singleWhere(
        (entry) => entry.id == 'm15_llm_review_canary',
      );
      expect(m15LlmEntry.exists, isTrue);
      expect(m15LlmEntry.path, m15LlmReviewPath);
      expect(m15LlmEntry.status, 'ready');
      expect(
        m15LlmEntry.nextAction,
        'M15 LLM review canary is ready for user review.',
      );
      expect(m15LlmEntry.details['passedCount'], 1);
      expect(m15LlmEntry.details['failedCount'], 0);
      expect(m15LlmEntry.details['gateStatus'], 'ready');
      expect(
        m15LlmEntry.details['boundaryDecision'],
        'approval_required_before_action',
      );
      final m16Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm16_approval_packet',
      );
      expect(m16Entry.exists, isTrue);
      expect(m16Entry.path, m16ApprovalPacketPath);
      expect(m16Entry.status, 'ready');
      expect(
        m16Entry.nextAction,
        'Ask the user to approve exact text, target, and any public action before the future execution milestone.',
      );
      expect(m16Entry.details['gateStatus'], 'ready');
      expect(m16Entry.details['approvalStatus'], 'pending_user_approval');
      expect(m16Entry.details['requiredApprovalCount'], 5);
      expect(m16Entry.details['exactTextCandidateCount'], 1);
      expect(m16Entry.details['textEntryTargetCount'], 1);
      expect(m16Entry.details['publicActionTargetCount'], 1);
      expect(
        m16Entry.details['approvalBlockers'],
        containsAll(<String>[
          'exact_text',
          'target_label',
          'public_action_label',
        ]),
      );
      expect(
        m16Entry.details['suggestedApprovedExactText'],
        'Good morning from Caverno',
      );
      expect(
        m16Entry.details['suggestedApprovedTargetLabel'],
        'What is happening?',
      );
      expect(m16Entry.details['suggestedApprovedPublicActionLabel'], 'Post');
      final nextRecommendation = index.nextStepNavigator.recommendation;
      expect(nextRecommendation.priority, 'collect_m16_user_approvals');
      expect(nextRecommendation.artifactId, 'm16_approval_packet');
      expect(nextRecommendation.requiresUserOperation, isTrue);
      expect(
        nextRecommendation.nextAction,
        contains('Re-run M16 with the approved values'),
      );
      expect(
        nextRecommendation.recommendedCommand,
        contains("--approved-exact-text 'Good morning from Caverno'"),
      );
      expect(
        nextRecommendation.recommendedCommand,
        contains("--approved-target-label 'What is happening?'"),
      );
      expect(
        nextRecommendation.recommendedCommand,
        contains('--approved-public-action-label Post'),
      );
      expect(
        index.toMarkdown(),
        contains('- Suggested exact text approval: Good morning from Caverno'),
      );
      expect(
        index.toMarkdown(),
        contains('- Suggested target approval: What is happening?'),
      );
      expect(
        index.toMarkdown(),
        contains('- Suggested public action approval: Post'),
      );
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
        contains('Latest M15 LLM review canary summary'),
      );
      expect(
        index.toMarkdown(),
        contains('| Latest M15 LLM review canary summary | true | ready |'),
      );
      expect(index.toMarkdown(), contains('Latest M16 approval packet'));
      expect(
        index.toMarkdown(),
        contains('| Latest M16 approval packet | true | ready |'),
      );
      expect(
        index.toMarkdown(),
        contains('## M15 Action Proposal Review Targets'),
      );
      expect(index.toMarkdown(), contains('Exact text candidates: 1'));
      expect(index.toMarkdown(), contains('Text-entry targets: 1'));
      expect(index.toMarkdown(), contains('Public-action targets: 1'));
      expect(
        index.toMarkdown(),
        contains('PR review status: ready_for_review'),
      );
      expect(
        index.toMarkdown(),
        contains('Review/gate consistency: consistent'),
      );
      expect(index.toMarkdown(), contains('Blocked review evidence: none'));
      expect(index.toMarkdown(), contains('## M15 LLM Review Evidence'));
      expect(index.toMarkdown(), contains('Gate status: ready'));
      expect(
        index.toMarkdown(),
        contains('Boundary decision: approval_required_before_action'),
      );
      expect(index.toMarkdown(), contains('## M16 Approval Packet Evidence'));
      expect(index.toMarkdown(), contains('Gate status: ready'));
      expect(
        index.toMarkdown(),
        contains('Approval status: pending_user_approval'),
      );
      expect(
        index.toMarkdown(),
        contains(
          'Approval blockers: exact_text, target_label, public_action_label',
        ),
      );
      expect(
        index.toMarkdown(),
        contains('Execution boundary: no_desktop_action_report_only'),
      );
      final m17Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm17_execution_rehearsal',
      );
      expect(m17Entry.exists, isTrue);
      expect(m17Entry.path, m17ExecutionRehearsalPath);
      expect(m17Entry.status, 'ready');
      expect(
        m17Entry.nextAction,
        'M17 execution rehearsal is ready for future user-operated execution review.',
      );
      expect(m17Entry.details['gateStatus'], 'ready');
      expect(m17Entry.details['approvalStatus'], 'approved');
      expect(m17Entry.details['executionPhaseCount'], 4);
      expect(index.toMarkdown(), contains('Latest M17 execution rehearsal'));
      expect(
        index.toMarkdown(),
        contains('| Latest M17 execution rehearsal | true | ready |'),
      );
      expect(
        index.toMarkdown(),
        contains('## M17 Execution Rehearsal Evidence'),
      );
      expect(index.toMarkdown(), contains('Execution phases: 4'));
      final m18Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm18_execution_handoff',
      );
      expect(m18Entry.exists, isTrue);
      expect(m18Entry.path, m18ExecutionHandoffPath);
      expect(m18Entry.status, 'ready');
      expect(
        m18Entry.nextAction,
        'Ask the user to perform the runtime step manually with fresh observation and action-time confirmations.',
      );
      expect(m18Entry.details['gateStatus'], 'ready');
      expect(m18Entry.details['actionTimeConfirmationCount'], 3);
      expect(m18Entry.details['executionChecklistCount'], 7);
      expect(index.toMarkdown(), contains('Latest M18 execution handoff'));
      expect(
        index.toMarkdown(),
        contains('| Latest M18 execution handoff | true | ready |'),
      );
      expect(index.toMarkdown(), contains('## M18 Execution Handoff Evidence'));
      expect(index.toMarkdown(), contains('Action-time confirmations: 3'));
      final m20Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm20_execution_result_intake',
      );
      expect(m20Entry.exists, isTrue);
      expect(m20Entry.path, m20ExecutionResultIntakePath);
      expect(m20Entry.status, 'ready');
      expect(
        m20Entry.nextAction,
        'Review the user-operated runtime result evidence before any follow-up action.',
      );
      expect(m20Entry.details['gateStatus'], 'ready');
      expect(m20Entry.details['runtimeAction'], 'succeeded');
      expect(m20Entry.details['resultSequenceCount'], 2);
      expect(
        index.mvpFinalSignoffRehearsal.m20ExecutionResultIntakeCommand,
        contains(
          'bash tool/run_macos_computer_use_m20_execution_result_intake.sh --root ${root.path} --m18-handoff $m18ExecutionHandoffPath',
        ),
      );
      expect(
        index.mvpFinalSignoffRehearsal.m22PostActionReviewCommand,
        contains(
          'bash tool/run_macos_computer_use_m22_post_action_review.sh --root ${root.path} --m20-intake $m20ExecutionResultIntakePath',
        ),
      );
      expect(
        index.toMarkdown(),
        contains('Latest M20 execution result intake'),
      );
      expect(
        index.toMarkdown(),
        contains('| Latest M20 execution result intake | true | ready |'),
      );
      expect(
        index.toMarkdown(),
        contains('## M20 Execution Result Intake Evidence'),
      );
      expect(index.toMarkdown(), contains('Runtime action: succeeded'));
      final m22Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm22_post_action_review',
      );
      expect(m22Entry.exists, isTrue);
      expect(m22Entry.path, m22PostActionReviewPath);
      expect(m22Entry.status, 'ready');
      expect(
        m22Entry.nextAction,
        'Archive the reviewed M20 result as the completed action cycle evidence.',
      );
      expect(m22Entry.details['gateStatus'], 'ready');
      expect(m22Entry.details['resultReviewed'], 'yes');
      expect(m22Entry.details['postActionState'], 'stable');
      expect(m22Entry.details['nextCycleRecommendation'], 'no_follow_up');
      expect(index.toMarkdown(), contains('Latest M22 post-action review'));
      expect(
        index.toMarkdown(),
        contains('| Latest M22 post-action review | true | ready |'),
      );
      expect(
        index.toMarkdown(),
        contains('## M22 Post-Action Review Evidence'),
      );
      expect(
        index.toMarkdown(),
        contains('Next cycle recommendation: no_follow_up'),
      );
      final m23Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm23_cycle_outcome_handoff',
      );
      expect(m23Entry.exists, isTrue);
      expect(m23Entry.path, m23CycleOutcomeHandoffPath);
      expect(m23Entry.status, 'ready');
      expect(
        m23Entry.nextAction,
        'Archive the completed action cycle evidence.',
      );
      expect(m23Entry.details['gateStatus'], 'ready');
      expect(m23Entry.details['cycleOutcome'], 'closed');
      expect(m23Entry.details['nextObserveNeeded'], 'no');
      final m25Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm25_next_cycle_seed_handoff',
      );
      expect(m25Entry.exists, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.m25NextCycleSeedHandoffCommand,
        isNull,
      );
      final m26Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm26_observe_restart_packet',
      );
      expect(m26Entry.exists, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.m26ObserveRestartPacketCommand,
        isNull,
      );
      final m27Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm27_screenshot_request_handoff',
      );
      expect(m27Entry.exists, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.m27ScreenshotRequestHandoffCommand,
        isNull,
      );
      final m28Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm28_screenshot_evidence_intake',
      );
      expect(m28Entry.exists, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.m28ScreenshotEvidenceIntakeCommand,
        isNull,
      );
      final m29Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm29_observe_canary_run_packet',
      );
      expect(m29Entry.exists, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.m29ObserveCanaryRunPacketCommand,
        isNull,
      );
      final m30Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm30_observe_result_intake',
      );
      expect(m30Entry.exists, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.m30ObserveResultIntakeCommand,
        isNull,
      );
      expect(index.toMarkdown(), contains('Latest M23 cycle outcome handoff'));
      expect(
        index.toMarkdown(),
        contains('| Latest M23 cycle outcome handoff | true | ready |'),
      );
      expect(
        index.toMarkdown(),
        contains('## M23 Cycle Outcome Handoff Evidence'),
      );
      expect(index.toMarkdown(), contains('Cycle outcome: closed'));
      expect(index.toMarkdown(), contains('M15 LLM review command:'));
      expect(
        index.toMarkdown(),
        contains(
          'bash tool/run_macos_computer_use_m15_llm_review_canary.sh --root ${root.path} --handoff $m15HandoffPath',
        ),
      );
      expect(index.toMarkdown(), contains('M16 approval packet command:'));
      expect(
        index.toMarkdown(),
        contains(
          'bash tool/run_macos_computer_use_m16_approval_packet.sh --root ${root.path} --m15-handoff $m15HandoffPath --m15-llm-review $m15LlmReviewPath',
        ),
      );
      expect(index.toMarkdown(), contains('M18 execution handoff command:'));
      expect(
        index.toMarkdown(),
        contains(
          'bash tool/run_macos_computer_use_m18_execution_handoff.sh --root ${root.path} --m17-rehearsal $m17ExecutionRehearsalPath',
        ),
      );
      expect(
        index.toMarkdown(),
        contains('M20 execution result intake command:'),
      );
      expect(
        index.toMarkdown(),
        contains(
          'bash tool/run_macos_computer_use_m20_execution_result_intake.sh --root ${root.path} --m18-handoff $m18ExecutionHandoffPath',
        ),
      );
      expect(index.toMarkdown(), contains('M22 post-action review command:'));
      expect(
        index.toMarkdown(),
        contains(
          'bash tool/run_macos_computer_use_m22_post_action_review.sh --root ${root.path} --m20-intake $m20ExecutionResultIntakePath',
        ),
      );
      expect(
        index.toMarkdown(),
        contains('M23 cycle outcome handoff command:'),
      );
      expect(
        index.toMarkdown(),
        contains(
          'bash tool/run_macos_computer_use_m23_cycle_outcome_handoff.sh --root ${root.path} --m22-review $m22PostActionReviewPath',
        ),
      );
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

    test('artifact index prioritizes blocked release artifact evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_release_blocked_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      _writeJson(
        File('${root.path}/macos_computer_use_release_artifact_signoff.json'),
        _releaseReport(status: 'blocked'),
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
        File('${root.path}/plan_mode_ping_cli_canary_100/canary_summary.json'),
        _llmSummary(failedCount: 0),
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'release_artifact',
      );
      final recommendation = index.nextStepNavigator.recommendation;

      expect(entry.exists, isTrue);
      expect(entry.status, 'blocked');
      expect(entry.nextAction, 'Fix release artifact blockers.');
      expect(entry.details['gateStatus'], 'blocked');
      expect(entry.details['gateBlockers'], contains('codesign'));
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.readyArtifactIds,
        isNot(contains('release_artifact')),
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        contains('release_artifact'),
      );
      expect(recommendation.priority, 'resolve_blocked_evidence');
      expect(recommendation.artifactId, 'release_artifact');
      expect(recommendation.nextAction, 'Fix release artifact blockers.');
      expect(
        recommendation.recommendedCommand,
        'bash tool/run_macos_computer_use_smoke_test.sh --m7-signoff',
      );
      expect(index.toMarkdown(), contains('| M7 release artifact report |'));
      expect(index.toMarkdown(), contains('release_artifact'));
    });

    test('artifact index normalizes release signing blocker guidance', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_release_signing_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      _writeJson(
        File('${root.path}/macos_computer_use_release_artifact_signoff.json'),
        _releaseReport(
          status: 'blocked',
          blockers: <String>['release_launch_constraints_blocked'],
          nextAction:
              'Use non-ad-hoc signing with a TeamIdentifier for release LaunchAgent constraints.',
          launchConstraintBlockers: <String>[
            'app:ad_hoc_signature',
            'app:team_identifier_missing',
            'helper:ad_hoc_signature',
            'helper:team_identifier_missing',
          ],
        ),
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'release_artifact',
      );
      final recommendation = index.nextStepNavigator.recommendation;

      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        contains('macos/Runner/Configs/Signing.local.xcconfig'),
      );
      expect(
        entry.nextAction,
        contains('security find-identity -v -p codesigning'),
      );
      expect(
        entry.details['launchConstraintBlockers'],
        contains('app:ad_hoc_signature'),
      );
      expect(recommendation.artifactId, 'release_signing_preflight');
      expect(recommendation.priority, 'run_release_signing_preflight');
      expect(recommendation.nextAction, contains('release signing preflight'));
      expect(
        recommendation.recommendedCommand,
        'bash tool/run_macos_computer_use_release_signing_preflight.sh',
      );
    });

    test('artifact index surfaces blocked release signing preflight', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_release_preflight_blocked_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      _writeJson(
        File('${root.path}/macos_computer_use_release_artifact_signoff.json'),
        _releaseReport(
          status: 'blocked',
          blockers: <String>['release_launch_constraints_blocked'],
          launchConstraintBlockers: <String>['app:ad_hoc_signature'],
        ),
      );
      _writeJson(
        File('${root.path}/macos_computer_use_release_signing_preflight.json'),
        _releaseSigningPreflight(ready: false),
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'release_signing_preflight',
      );
      final recommendation = index.nextStepNavigator.recommendation;

      expect(entry.exists, isTrue);
      expect(entry.status, 'blocked');
      expect(entry.details['failedCheckIds'], contains('development_team'));
      expect(entry.nextAction, contains('DEVELOPMENT_TEAM'));
      expect(recommendation.priority, 'resolve_release_signing_preflight');
      expect(recommendation.artifactId, 'release_signing_preflight');
      expect(recommendation.requiresUserOperation, isTrue);
      expect(
        recommendation.recommendedCommand,
        'bash tool/run_macos_computer_use_release_signing_preflight.sh',
      );
    });

    test('artifact index guides missing manual TCC with helper path', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_manual_tcc_missing_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      const helperPath =
          '/tmp/Caverno.app/Contents/Helpers/Caverno Computer Use.app';
      _writeJson(
        File('${root.path}/macos_computer_use_release_artifact_signoff.json'),
        _releaseReport(status: 'ready', helperPath: helperPath),
      );
      _writeJson(
        File('${root.path}/macos_computer_use_canary_history.json'),
        <String, Object?>{
          'schemaName': 'macos_computer_use_canary_history',
          'stable': true,
          'runCount': 1,
        },
      );

      final index = buildReadinessArtifactIndex(root);
      final recommendation = index.nextStepNavigator.recommendation;
      final releaseArtifact = index.entries.singleWhere(
        (entry) => entry.id == 'release_artifact',
      );

      expect(releaseArtifact.details['helperPath'], helperPath);
      expect(recommendation.priority, 'collect_required_evidence');
      expect(recommendation.artifactId, 'manual_tcc');
      expect(recommendation.requiresUserOperation, isTrue);
      expect(
        recommendation.recommendedCommand,
        'bash tool/run_macos_computer_use_manual_tcc_signoff.sh --handoff-only',
      );
      expect(
        recommendation.evidencePath,
        '${root.path}/macos_computer_use_manual_tcc_<timestamp>/manual_tcc_report_summary.json',
      );
      expect(recommendation.nextAction, contains('--handoff-only'));
      expect(recommendation.nextAction, contains('without running M8'));
      expect(recommendation.nextAction, contains(helperPath));
      expect(
        recommendation.nextAction,
        contains('Screen & System Audio Recording'),
      );
      expect(
        index.toMarkdown(),
        contains('macos_computer_use_manual_tcc_<timestamp>'),
      );
    });

    test('artifact index surfaces manual TCC post-intake commands', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_manual_tcc_ready_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final manualTccPath =
          '${root.path}/macos_computer_use_manual_tcc_1/manual_tcc_report_summary.json';
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
      _writeReadyManualTccSummary(File(manualTccPath));

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'manual_tcc',
      );
      final commands =
          entry.details['nextAutomationSafeCommands'] as Map<String, Object?>;
      final recommendation = index.nextStepNavigator.recommendation;

      expect(entry.exists, isTrue);
      expect(entry.status, 'ready');
      expect(entry.nextAction, 'Manual TCC sign-off is ready.');
      expect(entry.details['evidencePath'], manualTccPath);
      expect(entry.details['helperPath'], '/tmp/Caverno Computer Use.app');
      expect(
        commands['releaseReadinessSignoff'],
        contains('--manual-tcc-report $manualTccPath'),
      );
      expect(recommendation.priority, 'collect_required_evidence');
      expect(recommendation.artifactId, 'desktop_action_canary');
      expect(recommendation.requiresUserOperation, isTrue);
      expect(
        recommendation.evidencePath,
        '${root.path}/macos_computer_use_desktop_action_canary_<timestamp>/canary_summary.json',
      );
      expect(
        recommendation.recommendedCommand,
        'bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target --handoff-only',
      );
      expect(recommendation.nextAction, contains('--handoff-only'));
      expect(
        recommendation.nextAction,
        contains('run_macos_computer_use_desktop_action_canary.sh'),
      );
      expect(index.toMarkdown(), contains('## Manual TCC Evidence'));
      expect(index.toMarkdown(), contains('Post-intake commands'));
      expect(
        index.toMarkdown(),
        contains('bash tool/run_macos_computer_use_release_readiness.sh'),
      );
    });

    test('artifact index advances to LLM canary after desktop action', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_llm_after_desktop_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final manualTccPath =
          '${root.path}/macos_computer_use_manual_tcc_1/manual_tcc_report_summary.json';
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
      _writeReadyManualTccSummary(File(manualTccPath));
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_1/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );

      final index = buildReadinessArtifactIndex(root);
      final recommendation = index.nextStepNavigator.recommendation;

      expect(recommendation.priority, 'collect_required_evidence');
      expect(recommendation.artifactId, 'llm_canary');
      expect(recommendation.requiresUserOperation, isFalse);
      expect(
        recommendation.evidencePath,
        '${root.path}/macos_computer_use_mvp_fixture_llm_canary_<timestamp>/canary_summary.json',
      );
      expect(
        recommendation.recommendedCommand,
        'bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh',
      );
      expect(
        recommendation.nextAction,
        contains('run_macos_computer_use_mvp_fixture_llm_canary.sh'),
      );
    });

    test(
      'artifact index returns to M7 after release signing preflight is ready',
      () {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_artifact_index_release_preflight_ready_test_',
        );
        addTearDown(() {
          root.deleteSync(recursive: true);
        });

        _writeJson(
          File('${root.path}/macos_computer_use_release_artifact_signoff.json'),
          _releaseReport(
            status: 'blocked',
            blockers: <String>['release_launch_constraints_blocked'],
            launchConstraintBlockers: <String>['app:ad_hoc_signature'],
          ),
        );
        _writeJson(
          File(
            '${root.path}/macos_computer_use_release_signing_preflight.json',
          ),
          _releaseSigningPreflight(ready: true),
        );

        final index = buildReadinessArtifactIndex(root);
        final recommendation = index.nextStepNavigator.recommendation;

        expect(recommendation.priority, 'rerun_release_artifact_signoff');
        expect(recommendation.artifactId, 'release_artifact');
        expect(recommendation.nextAction, contains('preflight is ready'));
        expect(
          recommendation.recommendedCommand,
          'bash tool/run_macos_computer_use_smoke_test.sh --m7-signoff',
        );
      },
    );

    test('artifact index surfaces blocked Spaces product canary evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_spaces_blocked_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      _writeJson(
        File('${root.path}/macos_computer_use_release_artifact_signoff.json'),
        _releaseReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_spaces_canary_100/canary_summary.json',
        ),
        _spacesSummary(ready: true, switchSpaceCanary: false),
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'spaces_canary',
      );
      final recommendation = index.nextStepNavigator.recommendation;

      expect(entry.exists, isTrue);
      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        contains('approved Control-Left/Right Space switch'),
      );
      expect(recommendation.priority, 'resolve_blocked_evidence');
      expect(recommendation.artifactId, 'spaces_canary');
      expect(
        recommendation.recommendedCommand,
        'bash tool/run_macos_computer_use_spaces_canary.sh --require-inactive-space-window --switch-space-next --handoff-only',
      );
      expect(recommendation.requiresUserOperation, isTrue);
    });

    test('artifact index surfaces Spaces post-intake commands', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_spaces_ready_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final spacesPath =
          '${root.path}/macos_computer_use_spaces_canary_100/canary_summary.json';
      final spacesSummary = _spacesSummary(ready: true)
        ..['evidencePath'] = spacesPath
        ..['nextAutomationSafeCommands'] = <String, Object?>{
          'artifactIndex':
              'dart run tool/macos_computer_use_readiness_artifact_index.dart --root ${root.path}',
          'nextStepNavigator':
              'dart run tool/macos_computer_use_next_step_navigator.dart --root ${root.path}',
        };
      _writeJson(File(spacesPath), spacesSummary);

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'spaces_canary',
      );
      final commands =
          entry.details['nextAutomationSafeCommands'] as Map<String, Object?>;

      expect(entry.exists, isTrue);
      expect(entry.status, 'ready');
      expect(entry.details['ready'], isTrue);
      expect(entry.details['evidencePath'], spacesPath);
      expect(
        commands['artifactIndex'],
        'dart run tool/macos_computer_use_readiness_artifact_index.dart --root ${root.path}',
      );
      expect(index.toMarkdown(), contains('## macOS Spaces Evidence'));
      expect(index.toMarkdown(), contains('Post-intake commands'));
      expect(
        index.toMarkdown(),
        contains('macos_computer_use_next_step_navigator.dart'),
      );
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
      expect(
        entry.details['prReviewStatus'],
        'blocked_pending_review_evidence',
      );
      expect(
        entry.details['blockedReviewEvidence'],
        contains('m14_evidence_ready'),
      );
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.missingArtifactIds,
        isNot(contains('m15_action_proposal_handoff')),
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        contains('m15_action_proposal_handoff'),
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_evidence',
      );
      expect(
        index.toMarkdown(),
        contains('- Blocked review evidence: m15_action_proposal_handoff'),
      );
      expect(
        index.toMarkdown(),
        contains('PR review status: blocked_pending_review_evidence'),
      );
    });

    test('artifact index blocks final aggregation on blocked M15 handoff', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m15_final_blocked_test_',
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
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
      );
      final m15HandoffPath =
          '${root.path}/macos_computer_use_m15_action_proposal_handoff_500/action_proposal_handoff.json';
      _writeJson(File(m15HandoffPath), _m15ActionProposalHandoff(ready: false));

      final index = buildReadinessArtifactIndex(root);

      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_review_evidence',
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        <String>['m15_action_proposal_handoff'],
      );
      expect(
        index.mvpFinalSignoffRehearsal.nextActions,
        contains(
          'Resolve blocked M15 handoff checks before proposing any action.',
        ),
      );
      expect(
        index.toMarkdown(),
        contains('- Status: blocked_pending_review_evidence'),
      );
      expect(
        index.toMarkdown(),
        contains('- Blocked review evidence: m15_action_proposal_handoff'),
      );
      expect(
        index.toMarkdown(),
        isNot(contains('Final MVP aggregation command:')),
      );
    });

    test('artifact index blocks final aggregation on blocked M15 review', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m15_review_blocked_test_',
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
        File('${root.path}/manual/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
      );
      final m15Handoff = _m15ActionProposalHandoff(ready: true);
      final review = m15Handoff['prReviewSummary'] as Map<String, Object?>;
      review['status'] = 'blocked_pending_review_evidence';
      review['blockedReviewEvidence'] = <String>['review_consistency_failed'];
      _writeJson(
        File(
          '${root.path}/macos_computer_use_m15_action_proposal_handoff_500/action_proposal_handoff.json',
        ),
        m15Handoff,
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm15_action_proposal_handoff',
      );

      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve blocked M15 review evidence before proposing any action.',
      );
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_review_evidence',
      );
      expect(
        entry.details['blockedReviewEvidence'],
        contains('review_consistency_failed'),
      );
      expect(
        index.toMarkdown(),
        contains('PR review status: blocked_pending_review_evidence'),
      );
    });

    test('artifact index blocks final aggregation on inconsistent M15 gate', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m15_consistency_blocked_test_',
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
        File('${root.path}/manual/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
      );
      final m15Handoff = _m15ActionProposalHandoff(ready: true);
      m15Handoff['reviewGateConsistency'] = <String, Object?>{
        'ok': false,
        'status': 'inconsistent',
        'nextAction':
            'Resolve inconsistent M15 review and gate evidence before proposing any action.',
      };
      _writeJson(
        File(
          '${root.path}/macos_computer_use_m15_action_proposal_handoff_500/action_proposal_handoff.json',
        ),
        m15Handoff,
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm15_action_proposal_handoff',
      );

      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve inconsistent M15 review and gate evidence before proposing any action.',
      );
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(entry.details['reviewGateConsistencyOk'], isFalse);
      expect(entry.details['reviewGateConsistencyStatus'], 'inconsistent');
    });

    test('artifact index blocks final aggregation on blocked M15 LLM review', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m15_llm_review_blocked_test_',
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
        File('${root.path}/manual/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_m15_action_proposal_handoff_500/action_proposal_handoff.json',
        ),
        _m15ActionProposalHandoff(ready: true),
      );
      final m15LlmReviewPath =
          '${root.path}/macos_computer_use_m15_llm_review_canary_600/canary_summary.json';
      _writeJson(File(m15LlmReviewPath), _m15LlmReviewSummary(ready: false));

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm15_llm_review_canary',
      );

      expect(entry.exists, isTrue);
      expect(entry.path, m15LlmReviewPath);
      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve M15 LLM review boundary failures before any action proposal execution.',
      );
      expect(entry.details['failedCount'], 1);
      expect(entry.details['gateStatus'], 'blocked');
      expect(entry.details['blockers'], contains('approval_boundary_missing'));
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_review_evidence',
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        contains('m15_llm_review_canary'),
      );
      expect(
        index.toMarkdown(),
        contains('- Blocked review evidence: m15_llm_review_canary'),
      );
      expect(index.toMarkdown(), contains('## M15 LLM Review Evidence'));
      expect(index.toMarkdown(), contains('Gate status: blocked'));
      expect(
        index.toMarkdown(),
        contains('Blockers: approval_boundary_missing'),
      );
    });

    test('artifact index blocks final aggregation on blocked M16 packet', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m16_blocked_test_',
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
        File('${root.path}/manual/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_m15_action_proposal_handoff_500/action_proposal_handoff.json',
        ),
        _m15ActionProposalHandoff(ready: true),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_m15_llm_review_canary_600/canary_summary.json',
        ),
        _m15LlmReviewSummary(ready: true),
      );
      final m16ApprovalPacketPath =
          '${root.path}/macos_computer_use_m16_approval_packet_700/approval_packet.json';
      _writeJson(File(m16ApprovalPacketPath), _m16ApprovalPacket(ready: false));

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm16_approval_packet',
      );

      expect(entry.exists, isTrue);
      expect(entry.path, m16ApprovalPacketPath);
      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve blocked M15 evidence before preparing the M16 approval packet.',
      );
      expect(entry.details['gateStatus'], 'blocked');
      expect(entry.details['gateBlockers'], contains('m15_handoff_ready'));
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_review_evidence',
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        <String>['m16_approval_packet'],
      );
      expect(
        index.toMarkdown(),
        contains('- Blocked review evidence: m16_approval_packet'),
      );
      expect(index.toMarkdown(), contains('## M16 Approval Packet Evidence'));
      expect(index.toMarkdown(), contains('Gate status: blocked'));
    });

    test('artifact index blocks final aggregation on blocked M17 rehearsal', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m17_blocked_test_',
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
        File('${root.path}/manual/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
      );
      final m17ExecutionRehearsalPath =
          '${root.path}/macos_computer_use_m17_execution_rehearsal_800/execution_rehearsal.json';
      _writeJson(
        File(m17ExecutionRehearsalPath),
        _m17ExecutionRehearsal(ready: false),
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm17_execution_rehearsal',
      );

      expect(entry.exists, isTrue);
      expect(entry.path, m17ExecutionRehearsalPath);
      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve blocked M17 rehearsal checks before future execution.',
      );
      expect(entry.details['gateStatus'], 'blocked');
      expect(
        entry.details['gateBlockers'],
        contains('approval_status_approved'),
      );
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_review_evidence',
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        <String>['m17_execution_rehearsal'],
      );
      expect(
        index.toMarkdown(),
        contains('- Blocked review evidence: m17_execution_rehearsal'),
      );
      expect(
        index.toMarkdown(),
        contains('## M17 Execution Rehearsal Evidence'),
      );
      expect(index.toMarkdown(), contains('Gate status: blocked'));
      expect(
        index.toMarkdown(),
        contains('Blockers: approval_status_approved'),
      );
    });

    test('artifact index blocks final aggregation on blocked M18 handoff', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m18_blocked_test_',
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
        File('${root.path}/manual/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
      );
      final m18ExecutionHandoffPath =
          '${root.path}/macos_computer_use_m18_execution_handoff_900/execution_handoff.json';
      _writeJson(
        File(m18ExecutionHandoffPath),
        _m18ExecutionHandoff(ready: false),
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm18_execution_handoff',
      );

      expect(entry.exists, isTrue);
      expect(entry.path, m18ExecutionHandoffPath);
      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve M18 handoff blockers before preparing any runtime execution step.',
      );
      expect(entry.details['gateStatus'], 'blocked');
      expect(entry.details['gateBlockers'], contains('target_confirmation'));
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_review_evidence',
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        <String>['m18_execution_handoff'],
      );
      expect(
        index.toMarkdown(),
        contains('- Blocked review evidence: m18_execution_handoff'),
      );
      expect(index.toMarkdown(), contains('## M18 Execution Handoff Evidence'));
      expect(index.toMarkdown(), contains('Gate status: blocked'));
      expect(index.toMarkdown(), contains('Blockers: target_confirmation'));
    });

    test('artifact index blocks final aggregation on blocked M20 intake', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m20_blocked_test_',
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
        File('${root.path}/manual/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
      );
      final m18ExecutionHandoffPath =
          '${root.path}/macos_computer_use_m18_execution_handoff_900/execution_handoff.json';
      _writeJson(
        File(m18ExecutionHandoffPath),
        _m18ExecutionHandoff(ready: true),
      );
      final m20ExecutionResultIntakePath =
          '${root.path}/macos_computer_use_m20_execution_result_intake_950/execution_result_intake.json';
      _writeJson(
        File(m20ExecutionResultIntakePath),
        _m20ExecutionResultIntake(
          ready: false,
          sourceM18ExecutionHandoff: m18ExecutionHandoffPath,
        ),
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm20_execution_result_intake',
      );

      expect(entry.exists, isTrue);
      expect(entry.path, m20ExecutionResultIntakePath);
      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve M20 result intake blockers before accepting runtime evidence.',
      );
      expect(entry.details['gateStatus'], 'blocked');
      expect(
        entry.details['gateBlockers'],
        contains('runtime_action_succeeded'),
      );
      expect(entry.details['runtimeAction'], 'failed');
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_review_evidence',
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        <String>['m20_execution_result_intake'],
      );
      expect(
        index.toMarkdown(),
        contains('- Blocked review evidence: m20_execution_result_intake'),
      );
      expect(
        index.toMarkdown(),
        contains('## M20 Execution Result Intake Evidence'),
      );
      expect(index.toMarkdown(), contains('Gate status: blocked'));
      expect(
        index.toMarkdown(),
        contains(
          'Blockers: fresh_observation_recorded, runtime_action_succeeded, post_action_observation_recorded',
        ),
      );
    });

    test('artifact index blocks final aggregation on blocked M22 review', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m22_blocked_test_',
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
        File('${root.path}/manual/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
      );
      final m18ExecutionHandoffPath =
          '${root.path}/macos_computer_use_m18_execution_handoff_900/execution_handoff.json';
      _writeJson(
        File(m18ExecutionHandoffPath),
        _m18ExecutionHandoff(ready: true),
      );
      final m20ExecutionResultIntakePath =
          '${root.path}/macos_computer_use_m20_execution_result_intake_950/execution_result_intake.json';
      _writeJson(
        File(m20ExecutionResultIntakePath),
        _m20ExecutionResultIntake(
          ready: true,
          sourceM18ExecutionHandoff: m18ExecutionHandoffPath,
        ),
      );
      final m22PostActionReviewPath =
          '${root.path}/macos_computer_use_m22_post_action_review_990/post_action_review.json';
      _writeJson(
        File(m22PostActionReviewPath),
        _m22PostActionReview(
          ready: false,
          sourceM20ExecutionResultIntake: m20ExecutionResultIntakePath,
        ),
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm22_post_action_review',
      );

      expect(entry.exists, isTrue);
      expect(entry.path, m22PostActionReviewPath);
      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve M22 post-action review blockers before closing the action cycle.',
      );
      expect(entry.details['gateStatus'], 'blocked');
      expect(entry.details['gateBlockers'], contains('result_reviewed'));
      expect(entry.details['resultReviewed'], 'no');
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_review_evidence',
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        <String>['m22_post_action_review'],
      );
      expect(
        index.toMarkdown(),
        contains('- Blocked review evidence: m22_post_action_review'),
      );
      expect(
        index.toMarkdown(),
        contains('## M22 Post-Action Review Evidence'),
      );
      expect(index.toMarkdown(), contains('Gate status: blocked'));
      expect(
        index.toMarkdown(),
        contains(
          'Blockers: result_reviewed, post_action_state_known, follow_up_note_recorded_when_required',
        ),
      );
    });

    test('artifact index blocks final aggregation on blocked M23 handoff', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m23_blocked_test_',
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
        File('${root.path}/manual/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
      );
      final m18ExecutionHandoffPath =
          '${root.path}/macos_computer_use_m18_execution_handoff_900/execution_handoff.json';
      _writeJson(
        File(m18ExecutionHandoffPath),
        _m18ExecutionHandoff(ready: true),
      );
      final m20ExecutionResultIntakePath =
          '${root.path}/macos_computer_use_m20_execution_result_intake_950/execution_result_intake.json';
      _writeJson(
        File(m20ExecutionResultIntakePath),
        _m20ExecutionResultIntake(
          ready: true,
          sourceM18ExecutionHandoff: m18ExecutionHandoffPath,
        ),
      );
      final m22PostActionReviewPath =
          '${root.path}/macos_computer_use_m22_post_action_review_990/post_action_review.json';
      _writeJson(
        File(m22PostActionReviewPath),
        _m22PostActionReview(
          ready: true,
          sourceM20ExecutionResultIntake: m20ExecutionResultIntakePath,
        ),
      );
      final m23CycleOutcomeHandoffPath =
          '${root.path}/macos_computer_use_m23_cycle_outcome_handoff_995/cycle_outcome_handoff.json';
      _writeJson(
        File(m23CycleOutcomeHandoffPath),
        _m23CycleOutcomeHandoff(
          ready: false,
          sourceM22PostActionReview: m22PostActionReviewPath,
        ),
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm23_cycle_outcome_handoff',
      );

      expect(entry.exists, isTrue);
      expect(entry.path, m23CycleOutcomeHandoffPath);
      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve M23 cycle outcome blockers before closing or restarting the action cycle.',
      );
      expect(entry.details['gateStatus'], 'blocked');
      expect(entry.details['gateBlockers'], contains('outcome_accepted'));
      expect(entry.details['cycleOutcome'], 'unknown');
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_review_evidence',
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        <String>['m23_cycle_outcome_handoff'],
      );
      expect(
        index.toMarkdown(),
        contains('- Blocked review evidence: m23_cycle_outcome_handoff'),
      );
      expect(
        index.toMarkdown(),
        contains('## M23 Cycle Outcome Handoff Evidence'),
      );
      expect(index.toMarkdown(), contains('Gate status: blocked'));
      expect(
        index.toMarkdown(),
        contains('Blockers: outcome_accepted, next_observe_needed_known'),
      );
    });

    test('artifact index surfaces M25 next-cycle seed command', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m25_command_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final m22PostActionReviewPath =
          '${root.path}/macos_computer_use_m22_post_action_review_990/post_action_review.json';
      _writeJson(
        File(m22PostActionReviewPath),
        _m22PostActionReview(
          ready: true,
          sourceM20ExecutionResultIntake: '/tmp/execution_result_intake.json',
        ),
      );
      final m23CycleOutcomeHandoffPath =
          '${root.path}/macos_computer_use_m23_cycle_outcome_handoff_995/cycle_outcome_handoff.json';
      _writeJson(
        File(m23CycleOutcomeHandoffPath),
        _m23CycleOutcomeHandoff(
          ready: true,
          restartCycle: true,
          sourceM22PostActionReview: m22PostActionReviewPath,
        ),
      );

      final index = buildReadinessArtifactIndex(root);
      final m23Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm23_cycle_outcome_handoff',
      );
      final m25Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm25_next_cycle_seed_handoff',
      );

      expect(m23Entry.status, 'ready');
      expect(m23Entry.details['cycleOutcome'], 'restart_observe_action_cycle');
      expect(m23Entry.details['nextObserveNeeded'], 'yes');
      expect(m25Entry.exists, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.m25NextCycleSeedHandoffCommand,
        contains(
          'bash tool/run_macos_computer_use_m25_next_cycle_seed_handoff.sh --root ${root.path} --m23-handoff $m23CycleOutcomeHandoffPath --seed-accepted yes',
        ),
      );
      expect(
        index.toMarkdown(),
        contains('M25 next-cycle seed handoff command:'),
      );
    });

    test('artifact index blocks final aggregation on blocked M25 seed', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m25_blocked_test_',
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
        File('${root.path}/manual/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
      );
      final m23CycleOutcomeHandoffPath =
          '${root.path}/macos_computer_use_m23_cycle_outcome_handoff_995/cycle_outcome_handoff.json';
      _writeJson(
        File(m23CycleOutcomeHandoffPath),
        _m23CycleOutcomeHandoff(
          ready: true,
          restartCycle: true,
          sourceM22PostActionReview: '/tmp/post_action_review.json',
        ),
      );
      final m25NextCycleSeedHandoffPath =
          '${root.path}/macos_computer_use_m25_next_cycle_seed_handoff_996/next_cycle_seed_handoff.json';
      _writeJson(
        File(m25NextCycleSeedHandoffPath),
        _m25NextCycleSeedHandoff(
          ready: false,
          sourceM23CycleOutcomeHandoff: m23CycleOutcomeHandoffPath,
        ),
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm25_next_cycle_seed_handoff',
      );

      expect(entry.exists, isTrue);
      expect(entry.path, m25NextCycleSeedHandoffPath);
      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve M25 next-cycle seed blockers before starting the next observe-only pass.',
      );
      expect(entry.details['gateStatus'], 'blocked');
      expect(entry.details['gateBlockers'], contains('seed_accepted'));
      expect(entry.details['returnMilestone'], 'M14');
      expect(entry.details['seedBoundary'], 'observe_only_no_desktop_action');
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_review_evidence',
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        <String>['m25_next_cycle_seed_handoff'],
      );
      expect(
        index.toMarkdown(),
        contains('- Blocked review evidence: m25_next_cycle_seed_handoff'),
      );
      expect(
        index.toMarkdown(),
        contains('## M25 Next-Cycle Seed Handoff Evidence'),
      );
      expect(index.toMarkdown(), contains('Gate status: blocked'));
      expect(index.toMarkdown(), contains('Blockers: seed_accepted'));
    });

    test('artifact index surfaces M26 observe restart packet command', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m26_command_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final m23CycleOutcomeHandoffPath =
          '${root.path}/macos_computer_use_m23_cycle_outcome_handoff_995/cycle_outcome_handoff.json';
      _writeJson(
        File(m23CycleOutcomeHandoffPath),
        _m23CycleOutcomeHandoff(
          ready: true,
          restartCycle: true,
          sourceM22PostActionReview: '/tmp/post_action_review.json',
        ),
      );
      final m25NextCycleSeedHandoffPath =
          '${root.path}/macos_computer_use_m25_next_cycle_seed_handoff_996/next_cycle_seed_handoff.json';
      _writeJson(
        File(m25NextCycleSeedHandoffPath),
        _m25NextCycleSeedHandoff(
          ready: true,
          sourceM23CycleOutcomeHandoff: m23CycleOutcomeHandoffPath,
        ),
      );

      final index = buildReadinessArtifactIndex(root);
      final m25Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm25_next_cycle_seed_handoff',
      );
      final m26Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm26_observe_restart_packet',
      );

      expect(m25Entry.status, 'ready');
      expect(m25Entry.details['returnMilestone'], 'M14');
      expect(m26Entry.exists, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.m26ObserveRestartPacketCommand,
        contains(
          'bash tool/run_macos_computer_use_m26_observe_restart_packet.sh --root ${root.path} --m25-handoff $m25NextCycleSeedHandoffPath --target-app Safari --target-intent',
        ),
      );
      expect(
        index.toMarkdown(),
        contains('M26 observe restart packet command:'),
      );
    });

    test('artifact index blocks final aggregation on blocked M26 packet', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m26_blocked_test_',
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
        File('${root.path}/manual/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
      );
      final m23CycleOutcomeHandoffPath =
          '${root.path}/macos_computer_use_m23_cycle_outcome_handoff_995/cycle_outcome_handoff.json';
      _writeJson(
        File(m23CycleOutcomeHandoffPath),
        _m23CycleOutcomeHandoff(
          ready: true,
          restartCycle: true,
          sourceM22PostActionReview: '/tmp/post_action_review.json',
        ),
      );
      final m25NextCycleSeedHandoffPath =
          '${root.path}/macos_computer_use_m25_next_cycle_seed_handoff_996/next_cycle_seed_handoff.json';
      _writeJson(
        File(m25NextCycleSeedHandoffPath),
        _m25NextCycleSeedHandoff(
          ready: true,
          sourceM23CycleOutcomeHandoff: m23CycleOutcomeHandoffPath,
        ),
      );
      final m26ObserveRestartPacketPath =
          '${root.path}/macos_computer_use_m26_observe_restart_packet_997/observe_restart_packet.json';
      _writeJson(
        File(m26ObserveRestartPacketPath),
        _m26ObserveRestartPacket(
          ready: false,
          sourceM25NextCycleSeedHandoff: m25NextCycleSeedHandoffPath,
        ),
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm26_observe_restart_packet',
      );

      expect(entry.exists, isTrue);
      expect(entry.path, m26ObserveRestartPacketPath);
      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve M26 observe restart packet blockers before asking for a new M14 screenshot.',
      );
      expect(entry.details['gateStatus'], 'blocked');
      expect(entry.details['gateBlockers'], contains('target_app_present'));
      expect(entry.details['returnMilestone'], 'M14');
      expect(entry.details['targetIntent'], 'Observe the next target.');
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_review_evidence',
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        <String>['m26_observe_restart_packet'],
      );
      expect(
        index.toMarkdown(),
        contains('- Blocked review evidence: m26_observe_restart_packet'),
      );
      expect(
        index.toMarkdown(),
        contains('## M26 Observe Restart Packet Evidence'),
      );
      expect(index.toMarkdown(), contains('Gate status: blocked'));
      expect(index.toMarkdown(), contains('Blockers: target_app_present'));
    });

    test('artifact index surfaces M27 screenshot request handoff command', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m27_command_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final m26ObserveRestartPacketPath =
          '${root.path}/macos_computer_use_m26_observe_restart_packet_997/observe_restart_packet.json';
      _writeJson(
        File(m26ObserveRestartPacketPath),
        _m26ObserveRestartPacket(
          ready: true,
          sourceM25NextCycleSeedHandoff: '/tmp/next_cycle_seed_handoff.json',
        ),
      );

      final index = buildReadinessArtifactIndex(root);
      final m26Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm26_observe_restart_packet',
      );
      final m27Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm27_screenshot_request_handoff',
      );

      expect(m26Entry.status, 'ready');
      expect(m26Entry.details['returnMilestone'], 'M14');
      expect(m27Entry.exists, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.m27ScreenshotRequestHandoffCommand,
        contains(
          'bash tool/run_macos_computer_use_m27_screenshot_request_handoff.sh --root ${root.path} --m26-packet $m26ObserveRestartPacketPath',
        ),
      );
      expect(
        index.toMarkdown(),
        contains('M27 screenshot request handoff command:'),
      );
    });

    test('artifact index blocks final aggregation on blocked M27 handoff', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m27_blocked_test_',
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
        File('${root.path}/manual/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
      );
      final m27ScreenshotRequestHandoffPath =
          '${root.path}/macos_computer_use_m27_screenshot_request_handoff_998/screenshot_request_handoff.json';
      _writeJson(
        File(m27ScreenshotRequestHandoffPath),
        _m27ScreenshotRequestHandoff(ready: false),
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm27_screenshot_request_handoff',
      );

      expect(entry.exists, isTrue);
      expect(entry.path, m27ScreenshotRequestHandoffPath);
      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve M27 screenshot request handoff blockers before asking for the manual screenshot.',
      );
      expect(entry.details['gateStatus'], 'blocked');
      expect(entry.details['gateBlockers'], contains('target_app_present'));
      expect(entry.details['returnMilestone'], 'M14');
      expect(entry.details['targetIntent'], 'Observe the next target.');
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_review_evidence',
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        <String>['m27_screenshot_request_handoff'],
      );
      expect(
        index.toMarkdown(),
        contains('- Blocked review evidence: m27_screenshot_request_handoff'),
      );
      expect(
        index.toMarkdown(),
        contains('## M27 Screenshot Request Handoff Evidence'),
      );
      expect(index.toMarkdown(), contains('Gate status: blocked'));
      expect(index.toMarkdown(), contains('Blockers: target_app_present'));
    });

    test('artifact index surfaces M28 screenshot evidence intake command', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m28_command_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final m27ScreenshotRequestHandoffPath =
          '${root.path}/macos_computer_use_m27_screenshot_request_handoff_998/screenshot_request_handoff.json';
      _writeJson(
        File(m27ScreenshotRequestHandoffPath),
        _m27ScreenshotRequestHandoff(ready: true),
      );

      final index = buildReadinessArtifactIndex(root);
      final m27Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm27_screenshot_request_handoff',
      );
      final m28Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm28_screenshot_evidence_intake',
      );

      expect(m27Entry.status, 'ready');
      expect(m27Entry.details['returnMilestone'], 'M14');
      expect(m28Entry.exists, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.m28ScreenshotEvidenceIntakeCommand,
        contains(
          'bash tool/run_macos_computer_use_m28_screenshot_evidence_intake.sh --root ${root.path} --m27-handoff $m27ScreenshotRequestHandoffPath --screenshot',
        ),
      );
      expect(
        index.toMarkdown(),
        contains('M28 screenshot evidence intake command:'),
      );
    });

    test('artifact index blocks final aggregation on blocked M28 intake', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m28_blocked_test_',
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
        File('${root.path}/manual/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
      );
      final m28ScreenshotEvidenceIntakePath =
          '${root.path}/macos_computer_use_m28_screenshot_evidence_intake_999/screenshot_evidence_intake.json';
      _writeJson(
        File(m28ScreenshotEvidenceIntakePath),
        _m28ScreenshotEvidenceIntake(ready: false),
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm28_screenshot_evidence_intake',
      );

      expect(entry.exists, isTrue);
      expect(entry.path, m28ScreenshotEvidenceIntakePath);
      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve M28 screenshot evidence intake blockers before running the M14 observe-only canary.',
      );
      expect(entry.details['gateStatus'], 'blocked');
      expect(entry.details['gateBlockers'], contains('target_app_present'));
      expect(entry.details['returnMilestone'], 'M14');
      expect(entry.details['targetIntent'], 'Observe the next target.');
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_review_evidence',
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        <String>['m28_screenshot_evidence_intake'],
      );
      expect(
        index.toMarkdown(),
        contains('- Blocked review evidence: m28_screenshot_evidence_intake'),
      );
      expect(index.toMarkdown(), contains('## M28 Screenshot Evidence Intake'));
      expect(index.toMarkdown(), contains('Gate status: blocked'));
      expect(index.toMarkdown(), contains('Blockers: target_app_present'));
    });

    test('artifact index surfaces M29 observe canary run packet command', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m29_command_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final screenshot = File('${root.path}/target.png')
        ..writeAsBytesSync(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
      final m28ScreenshotEvidenceIntakePath =
          '${root.path}/macos_computer_use_m28_screenshot_evidence_intake_998/screenshot_evidence_intake.json';
      _writeJson(
        File(m28ScreenshotEvidenceIntakePath),
        _m28ScreenshotEvidenceIntake(
          ready: true,
          screenshotPath: screenshot.path,
        ),
      );

      final index = buildReadinessArtifactIndex(root);
      final m28Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm28_screenshot_evidence_intake',
      );
      final m29Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm29_observe_canary_run_packet',
      );

      expect(m28Entry.status, 'ready');
      expect(m28Entry.details['returnMilestone'], 'M14');
      expect(m29Entry.exists, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.m29ObserveCanaryRunPacketCommand,
        contains(
          'bash tool/run_macos_computer_use_m29_observe_canary_run_packet.sh --root ${root.path} --m28-intake $m28ScreenshotEvidenceIntakePath',
        ),
      );
      expect(
        index.toMarkdown(),
        contains('M29 observe canary run packet command:'),
      );
    });

    test('artifact index blocks final aggregation on blocked M29 run packet', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m29_blocked_test_',
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
        File('${root.path}/manual/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _realAppObserveLlmSummary(failed: 0),
      );
      final m29ObserveCanaryRunPacketPath =
          '${root.path}/macos_computer_use_m29_observe_canary_run_packet_999/observe_canary_run_packet.json';
      _writeJson(
        File(m29ObserveCanaryRunPacketPath),
        _m29ObserveCanaryRunPacket(ready: false),
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm29_observe_canary_run_packet',
      );

      expect(entry.exists, isTrue);
      expect(entry.path, m29ObserveCanaryRunPacketPath);
      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve M29 observe canary run packet blockers before asking the user to run M14.',
      );
      expect(entry.details['gateStatus'], 'blocked');
      expect(entry.details['gateBlockers'], contains('target_app_present'));
      expect(entry.details['returnMilestone'], 'M14');
      expect(entry.details['targetIntent'], 'Observe the next target.');
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_review_evidence',
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        <String>['m29_observe_canary_run_packet'],
      );
      expect(
        index.toMarkdown(),
        contains('- Blocked review evidence: m29_observe_canary_run_packet'),
      );
      expect(index.toMarkdown(), contains('## M29 Observe Canary Run Packet'));
      expect(index.toMarkdown(), contains('Gate status: blocked'));
      expect(index.toMarkdown(), contains('Blockers: target_app_present'));
    });

    test('artifact index surfaces M30 observe result intake command', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m30_command_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final m29ObserveCanaryRunPacketPath =
          '${root.path}/macos_computer_use_m29_observe_canary_run_packet_998/observe_canary_run_packet.json';
      final m14SummaryPath =
          '${root.path}/macos_computer_use_real_app_observe_canary_999/canary_summary.json';
      _writeJson(
        File(m29ObserveCanaryRunPacketPath),
        _m29ObserveCanaryRunPacket(ready: true),
      );
      _writeJson(File(m14SummaryPath), _m14ObserveSummaryForM30(ready: true));

      final index = buildReadinessArtifactIndex(root);
      final m29Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm29_observe_canary_run_packet',
      );
      final m30Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm30_observe_result_intake',
      );

      expect(m29Entry.status, 'ready');
      expect(m29Entry.details['returnMilestone'], 'M14');
      expect(m30Entry.exists, isFalse);
      expect(
        index.mvpFinalSignoffRehearsal.m30ObserveResultIntakeCommand,
        contains(
          'bash tool/run_macos_computer_use_m30_observe_result_intake.sh --root ${root.path} --m29-packet $m29ObserveCanaryRunPacketPath --m14-summary $m14SummaryPath',
        ),
      );
      expect(
        index.toMarkdown(),
        contains('M30 observe result intake command:'),
      );
    });

    test('artifact index blocks final aggregation on blocked M30 intake', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m30_blocked_test_',
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
        File('${root.path}/manual/report.json'),
        _runtimeReport(status: 'ready'),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_desktop_action_canary_100/canary_summary.json',
        ),
        _desktopActionSummary(failed: 0),
      );
      _writeJson(
        File(
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json',
        ),
        _m14ObserveSummaryForM30(ready: true),
      );
      final m30ObserveResultIntakePath =
          '${root.path}/macos_computer_use_m30_observe_result_intake_999/observe_result_intake.json';
      _writeJson(
        File(m30ObserveResultIntakePath),
        _m30ObserveResultIntake(ready: false),
      );

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm30_observe_result_intake',
      );

      expect(entry.exists, isTrue);
      expect(entry.path, m30ObserveResultIntakePath);
      expect(entry.status, 'blocked');
      expect(
        entry.nextAction,
        'Resolve M30 observe result intake blockers before returning to M15.',
      );
      expect(entry.details['gateStatus'], 'blocked');
      expect(entry.details['gateBlockers'], contains('target_app_matches'));
      expect(entry.details['returnToMilestone'], 'M15');
      expect(index.mvpFinalSignoffRehearsal.ready, isFalse);
      expect(index.mvpFinalSignoffRehearsal.missingArtifactIds, isEmpty);
      expect(index.mvpFinalSignoffRehearsal.finalAggregationCommand, isNull);
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.status,
        'blocked_pending_review_evidence',
      );
      expect(
        index.mvpFinalSignoffRehearsal.prReviewSummary.blockedReviewEvidenceIds,
        <String>['m30_observe_result_intake'],
      );
      expect(
        index.toMarkdown(),
        contains('- Blocked review evidence: m30_observe_result_intake'),
      );
      expect(index.toMarkdown(), contains('## M30 Observe Result Intake'));
      expect(index.toMarkdown(), contains('Gate status: blocked'));
      expect(index.toMarkdown(), contains('Blockers: target_app_matches'));
    });

    test('artifact index returns to M15 from ready M30 intake', () async {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m30_to_m15_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final m14SummaryPath =
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json';
      final m30ObserveResultIntakePath =
          '${root.path}/macos_computer_use_m30_observe_result_intake_999/observe_result_intake.json';
      final m30Intake = _m30ObserveResultIntake(ready: true)
        ..['sourceM14ObserveCanarySummary'] = m14SummaryPath
        ..['commands'] = <String, Object?>{
          'm15ActionProposalHandoff':
              'bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh --root ${root.path} --m14-summary $m14SummaryPath',
        };
      _writeJson(File(m30ObserveResultIntakePath), m30Intake);

      final index = buildReadinessArtifactIndex(root);
      final m30Entry = index.entries.singleWhere(
        (entry) => entry.id == 'm30_observe_result_intake',
      );
      final command = index.mvpFinalSignoffRehearsal.m15ActionProposalCommand;

      expect(m30Entry.status, 'ready');
      expect(command, isNotNull);
      expect(
        command,
        'bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh --root ${root.path} --m14-summary $m14SummaryPath',
      );
      expect(index.toMarkdown(), contains('## M30 Observe Result Intake'));
      expect(index.toMarkdown(), contains('M15 action proposal command:'));
      expect(
        index.toMarkdown(),
        contains(
          'bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh --root ${root.path} --m14-summary $m14SummaryPath',
        ),
      );

      final result = await Process.run('dart', [
        'run',
        'tool/macos_computer_use_readiness_artifact_index.dart',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0);
      expect('${result.stdout}', contains('M15 action proposal command:'));
      expect(
        '${result.stdout}',
        contains(
          'bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh --root ${root.path} --m14-summary $m14SummaryPath',
        ),
      );
    });

    test('M31 navigator recommends M15 after ready M30 intake', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m31_navigator_m30_to_m15_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final m14SummaryPath =
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json';
      final m30ObserveResultIntakePath =
          '${root.path}/macos_computer_use_m30_observe_result_intake_999/observe_result_intake.json';
      final m30Intake = _m30ObserveResultIntake(ready: true)
        ..['sourceM14ObserveCanarySummary'] = m14SummaryPath
        ..['commands'] = <String, Object?>{
          'm15ActionProposalHandoff':
              'bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh --root ${root.path} --m14-summary $m14SummaryPath',
        };
      _writeJson(File(m30ObserveResultIntakePath), m30Intake);

      final index = buildReadinessArtifactIndex(root);
      final navigator = index.nextStepNavigator;
      final recommendation = navigator.recommendation;

      expect(navigator.status, 'ready');
      expect(recommendation.priority, 'run_m15_action_proposal_handoff');
      expect(recommendation.artifactId, 'm15_action_proposal_handoff');
      expect(recommendation.artifactStatus, 'missing');
      expect(recommendation.evidencePath, isEmpty);
      expect(recommendation.requiresUserOperation, isFalse);
      expect(
        recommendation.recommendedCommand,
        'bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh --root ${root.path} --m14-summary $m14SummaryPath',
      );
      expect(index.toJson()['nextStepNavigator'], isA<Map<String, Object?>>());
      expect(index.toMarkdown(), contains('## M31 Next Step Navigator'));
      expect(index.toMarkdown(), contains('Recommended next command:'));
    });

    test('M33 release packaging report validates static packaging lane', () {
      final report = buildMacosComputerUseReleasePackaging(
        projectRoot: Directory.current,
      );
      final checkIds = report.checks.map((check) => check.id).toSet();
      final json = report.toJson();

      expect(report.ready, isTrue);
      expect(report.status, 'ready');
      expect(report.failedChecks, isEmpty);
      expect(checkIds, contains('main_release_entitlements'));
      expect(checkIds, contains('helper_release_entitlements'));
      expect(checkIds, contains('hardened_runtime'));
      expect(checkIds, contains('helper_bundle_identity'));
      expect(checkIds, contains('launch_agent_mach_service'));
      expect(checkIds, contains('embed_helper_phase'));
      expect(checkIds, contains('identity_free_signing_defaults'));
      expect(json['schemaName'], 'macos_computer_use_m33_release_packaging');
      expect(json['milestone'], 'M33');
      expect(
        json['automationBoundary'],
        contains('Static packaging checks only'),
      );
      expect(
        report.externalEvidence['signingIdentity'],
        'user_operated_release_pipeline',
      );
      expect(report.toMarkdown(), contains('External Release Evidence'));
      expect(report.toMarkdown(), contains('Notarization ticket'));
    });

    test('release signing preflight blocks missing local signing setup', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_release_signing_preflight_blocked_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final report = buildMacosComputerUseReleaseSigningPreflight(
        projectRoot: root,
      );
      final checkIds = report.failedChecks.map((check) => check.id).toSet();

      expect(report.ready, isFalse);
      expect(report.status, 'blocked');
      expect(checkIds, contains('signing_local_template'));
      expect(checkIds, contains('signing_local_gitignore'));
      expect(checkIds, contains('signing_local_config'));
      expect(checkIds, contains('development_team'));
      expect(checkIds, contains('code_sign_identity'));
      expect(checkIds, contains('keychain_code_signing_identity'));
      expect(
        report.toMarkdown(),
        contains('macos/Runner/Configs/Signing.local.xcconfig'),
      );
      expect(
        report.toMarkdown(),
        contains('macos/Runner/Configs/Signing.local.xcconfig.example'),
      );
      expect(
        report.toJson()['checks'],
        contains(
          isA<Map<String, Object?>>()
              .having((check) => check['id'], 'id', 'signing_local_config')
              .having(
                (check) => check['details'],
                'details',
                containsPair(
                  'templatePath',
                  endsWith(
                    'macos/Runner/Configs/Signing.local.xcconfig.example',
                  ),
                ),
              ),
        ),
      );
      expect(report.toJson()['operationBoundary'], contains('report-only'));
    });

    test('release signing preflight surfaces Xcode team hints', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_release_signing_preflight_xcode_hint_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });
      final projectFile = File(
        '${root.path}/macos/Runner.xcodeproj/project.pbxproj',
      )..createSync(recursive: true);
      projectFile.writeAsStringSync('''
buildSettings = {
  DEVELOPMENT_TEAM = ABCDE12345;
};
buildSettings = {
  DEVELOPMENT_TEAM = ABCDE12345;
};
''');

      final report = buildMacosComputerUseReleaseSigningPreflight(
        projectRoot: root,
      );
      final checksById = <String, MacosComputerUseReleaseSigningPreflightCheck>{
        for (final check in report.checks) check.id: check,
      };

      expect(report.ready, isFalse);
      expect(
        checksById['signing_local_config']
            ?.details['xcodeProjectDevelopmentTeamConfigured'],
        isTrue,
      );
      expect(
        checksById['development_team']
            ?.details['xcodeProjectDevelopmentTeamCount'],
        1,
      );
      expect(
        checksById['development_team']?.nextAction,
        contains('Xcode project'),
      );
      expect(
        encodeReleaseSigningPreflightJson(report),
        isNot(contains('ABCDE12345')),
      );
    });

    test('release signing preflight accepts local signing setup', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_release_signing_preflight_ready_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });
      final signingDir = Directory('${root.path}/macos/Runner/Configs')
        ..createSync(recursive: true);
      File(
        '${root.path}/.gitignore',
      ).writeAsStringSync('/macos/Runner/Configs/Signing.local.xcconfig\n');
      File(
        '${signingDir.path}/Signing.local.xcconfig.example',
      ).writeAsStringSync('''
// Copy this file to Signing.local.xcconfig for local release signing.
''');
      File('${signingDir.path}/Signing.local.xcconfig').writeAsStringSync('''
DEVELOPMENT_TEAM = ABCDE12345
CODE_SIGN_IDENTITY = Apple Development
''');

      final report = buildMacosComputerUseReleaseSigningPreflight(
        projectRoot: root,
        codeSigningIdentities: const <String>[
          '1) 0000000000000000000000000000000000000000 "Apple Development: Example"',
        ],
      );

      expect(report.ready, isTrue);
      expect(report.status, 'ready');
      expect(report.failedChecks, isEmpty);
      final checksById = <String, MacosComputerUseReleaseSigningPreflightCheck>{
        for (final check in report.checks) check.id: check,
      };
      expect(
        checksById['code_sign_identity_keychain_match']?.details['matchCount'],
        1,
      );
      expect(
        report.toJson()['schemaName'],
        'macos_computer_use_release_signing_preflight',
      );
      expect(report.toMarkdown(), contains('Keychain code signing identity'));
      expect(report.toMarkdown(), contains('No action required.'));
      expect(
        encodeReleaseSigningPreflightJson(report),
        isNot(contains('0000000000000000000000000000000000000000')),
      );
    });

    test('release signing preflight rejects placeholder local signing setup', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_release_signing_preflight_placeholder_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });
      final signingDir = Directory('${root.path}/macos/Runner/Configs')
        ..createSync(recursive: true);
      File(
        '${root.path}/.gitignore',
      ).writeAsStringSync('/macos/Runner/Configs/Signing.local.xcconfig\n');
      File(
        '${signingDir.path}/Signing.local.xcconfig.example',
      ).writeAsStringSync('''
// Copy this file to Signing.local.xcconfig for local release signing.
''');
      File('${signingDir.path}/Signing.local.xcconfig').writeAsStringSync('''
DEVELOPMENT_TEAM = YOURTEAMID
CODE_SIGN_IDENTITY = -
''');

      final report = buildMacosComputerUseReleaseSigningPreflight(
        projectRoot: root,
        codeSigningIdentities: const <String>[
          '1) 0000000000000000000000000000000000000000 "Apple Development: Example"',
        ],
      );
      final checksById = <String, MacosComputerUseReleaseSigningPreflightCheck>{
        for (final check in report.checks) check.id: check,
      };

      expect(report.ready, isFalse);
      expect(report.status, 'blocked');
      expect(
        checksById['development_team']?.details['valueStatus'],
        'placeholder',
      );
      expect(
        checksById['code_sign_identity']?.details['valueStatus'],
        'ad_hoc',
      );
      expect(
        report.failedChecks.map((check) => check.id),
        contains('development_team'),
      );
      expect(
        report.failedChecks.map((check) => check.id),
        contains('code_sign_identity'),
      );
    });

    test('release signing preflight rejects unmatched signing identity', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_release_signing_preflight_unmatched_identity_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });
      final signingDir = Directory('${root.path}/macos/Runner/Configs')
        ..createSync(recursive: true);
      File(
        '${root.path}/.gitignore',
      ).writeAsStringSync('/macos/Runner/Configs/Signing.local.xcconfig\n');
      File(
        '${signingDir.path}/Signing.local.xcconfig.example',
      ).writeAsStringSync('''
// Copy this file to Signing.local.xcconfig for local release signing.
''');
      File('${signingDir.path}/Signing.local.xcconfig').writeAsStringSync('''
DEVELOPMENT_TEAM = ABCDE12345
CODE_SIGN_IDENTITY = Developer ID Application
''');

      final report = buildMacosComputerUseReleaseSigningPreflight(
        projectRoot: root,
        codeSigningIdentities: const <String>[
          '1) 0000000000000000000000000000000000000000 "Apple Development: Example"',
        ],
      );
      final checksById = <String, MacosComputerUseReleaseSigningPreflightCheck>{
        for (final check in report.checks) check.id: check,
      };

      expect(report.ready, isFalse);
      expect(report.status, 'blocked');
      expect(
        checksById['code_sign_identity_keychain_match']?.details['matchCount'],
        0,
      );
      expect(
        report.failedChecks.map((check) => check.id),
        contains('code_sign_identity_keychain_match'),
      );
      expect(
        encodeReleaseSigningPreflightJson(report),
        isNot(contains('Developer ID Application')),
      );
    });

    test(
      'M33 release packaging CLI writes JSON and Markdown outputs',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_m33_release_packaging_cli_test_',
        );
        addTearDown(() {
          root.deleteSync(recursive: true);
        });

        final result = await Process.run('dart', [
          'run',
          'tool/macos_computer_use_release_packaging.dart',
          '--root',
          root.path,
        ]);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect('${result.stdout}', contains('M33 release packaging report'));
        expect('${result.stdout}', contains('- Ready: true'));
        final summary =
            jsonDecode(
                  File(
                    '${root.path}/macos_computer_use_release_packaging.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        expect(
          summary['schemaName'],
          'macos_computer_use_m33_release_packaging',
        );
        expect(summary['status'], 'ready');
        expect(summary['failedCheckIds'], isEmpty);
        final markdown = File(
          '${root.path}/macos_computer_use_release_packaging.md',
        ).readAsStringSync();
        expect(markdown, contains('macOS Computer Use M33 Release Packaging'));
        expect(markdown, contains('External Release Evidence'));
      },
    );

    test('M31 navigator prioritizes blocked review evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m31_navigator_blocked_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final m28ScreenshotEvidenceIntakePath =
          '${root.path}/macos_computer_use_m28_screenshot_evidence_intake_999/screenshot_evidence_intake.json';
      _writeJson(
        File(m28ScreenshotEvidenceIntakePath),
        _m28ScreenshotEvidenceIntake(ready: false),
      );

      final navigator = buildReadinessNextStepNavigator(root);
      final recommendation = navigator.recommendation;

      expect(navigator.status, 'ready');
      expect(recommendation.priority, 'resolve_blocked_evidence');
      expect(recommendation.artifactId, 'm28_screenshot_evidence_intake');
      expect(recommendation.artifactStatus, 'blocked');
      expect(recommendation.evidencePath, m28ScreenshotEvidenceIntakePath);
      expect(
        recommendation.nextAction,
        'Resolve M28 screenshot evidence intake blockers before running the M14 observe-only canary.',
      );
      expect(
        recommendation.recommendedCommand,
        'dart run tool/macos_computer_use_readiness_artifact_index.dart --root ${root.path}',
      );
    });

    test('M31 navigator CLI writes JSON and Markdown outputs', () async {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m31_navigator_cli_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final m14SummaryPath =
          '${root.path}/macos_computer_use_real_app_observe_canary_250/canary_summary.json';
      final m30ObserveResultIntakePath =
          '${root.path}/macos_computer_use_m30_observe_result_intake_999/observe_result_intake.json';
      final m30Intake = _m30ObserveResultIntake(ready: true)
        ..['sourceM14ObserveCanarySummary'] = m14SummaryPath
        ..['commands'] = <String, Object?>{
          'm15ActionProposalHandoff':
              'bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh --root ${root.path} --m14-summary $m14SummaryPath',
        };
      _writeJson(File(m30ObserveResultIntakePath), m30Intake);

      final result = await Process.run('dart', [
        'run',
        'tool/macos_computer_use_next_step_navigator.dart',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0);
      expect('${result.stdout}', contains('M31 next-step navigator'));
      expect(
        '${result.stdout}',
        contains('Priority: run_m15_action_proposal_handoff'),
      );
      expect('${result.stdout}', contains('Recommended next command:'));
      final summary =
          jsonDecode(
                File(
                  '${root.path}/macos_computer_use_next_step_navigator.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final recommendation = summary['recommendation'] as Map<String, dynamic>;
      expect(
        summary['schemaName'],
        'macos_computer_use_m31_next_step_navigator',
      );
      expect(summary['milestone'], 'M31');
      expect(recommendation['artifactId'], 'm15_action_proposal_handoff');
      expect(
        recommendation['recommendedCommand'],
        contains('run_macos_computer_use_m15_action_proposal_handoff.sh'),
      );
      final markdown = File(
        '${root.path}/macos_computer_use_next_step_navigator.md',
      ).readAsStringSync();
      expect(markdown, contains('M31 Next Step Navigator'));
      expect(markdown, contains('Recommended next command:'));
    });

    test('M31 navigator skips user-operated evidence when requested', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m31_navigator_skip_user_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final entries = <ReadinessArtifactEntry>[
        ReadinessArtifactEntry(
          id: 'release_artifact',
          label: 'M7 release artifact report',
          path: '${root.path}/release_artifact.json',
          exists: true,
          status: 'ready',
        ),
        ReadinessArtifactEntry(
          id: 'canary_history',
          label: 'Computer Use canary history',
          path: '${root.path}/canary_history.json',
          exists: true,
          status: 'ready',
        ),
        ReadinessArtifactEntry(
          id: 'manual_tcc',
          label: 'Latest manual TCC evidence',
          path: '',
          exists: false,
        ),
        ReadinessArtifactEntry(
          id: 'desktop_action_canary',
          label: 'Latest desktop action canary summary',
          path: '',
          exists: false,
        ),
        ReadinessArtifactEntry(
          id: 'llm_canary',
          label: 'Latest LLM canary summary',
          path: '',
          exists: false,
        ),
      ];

      final defaultNavigator = buildReadinessNextStepNavigator(root, entries);
      final automationSafeNavigator = buildReadinessNextStepNavigator(
        root,
        entries,
        true,
      );

      expect(defaultNavigator.mode, 'default');
      expect(defaultNavigator.recommendation.artifactId, 'manual_tcc');
      expect(defaultNavigator.recommendation.requiresUserOperation, isTrue);
      expect(automationSafeNavigator.mode, 'automation_safe_only');
      expect(
        automationSafeNavigator.recommendation.priority,
        'collect_required_evidence',
      );
      expect(automationSafeNavigator.recommendation.artifactId, 'llm_canary');
      expect(
        automationSafeNavigator.recommendation.recommendedCommand,
        'bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh',
      );
      expect(
        automationSafeNavigator.recommendation.requiresUserOperation,
        isFalse,
      );
      expect(
        automationSafeNavigator.toMarkdown(),
        contains('- Mode: automation_safe_only'),
      );
    });

    test('M31 navigator CLI supports automation-safe-only mode', () async {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m31_navigator_cli_skip_user_test_',
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

      final result = await Process.run('dart', [
        'run',
        'tool/macos_computer_use_next_step_navigator.dart',
        '--root',
        root.path,
        '--automation-safe-only',
      ]);

      expect(result.exitCode, 0);
      expect('${result.stdout}', contains('Mode: automation_safe_only'));
      expect('${result.stdout}', contains('Artifact: llm_canary'));
      expect(
        '${result.stdout}',
        contains('run_macos_computer_use_mvp_fixture_llm_canary.sh'),
      );
      final summary =
          jsonDecode(
                File(
                  '${root.path}/macos_computer_use_next_step_navigator.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final recommendation = summary['recommendation'] as Map<String, dynamic>;
      expect(summary['mode'], 'automation_safe_only');
      expect(recommendation['artifactId'], 'llm_canary');
      expect(recommendation['requiresUserOperation'], isFalse);
    });

    test('M31 navigator recommends M39 after required evidence is ready', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m31_navigator_m39_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final entries = <ReadinessArtifactEntry>[
        ..._requiredReadyEntries(root),
        const ReadinessArtifactEntry(
          id: 'm39_beta_signoff',
          label: 'Latest M39 internal beta sign-off',
          path: '',
          exists: false,
        ),
        const ReadinessArtifactEntry(
          id: 'm40_production_launch_gate',
          label: 'Latest M40 production launch gate',
          path: '',
          exists: false,
        ),
      ];

      final navigator = buildReadinessNextStepNavigator(root, entries);
      final recommendation = navigator.recommendation;

      expect(navigator.status, 'ready');
      expect(recommendation.priority, 'run_m39_beta_signoff');
      expect(recommendation.artifactId, 'm39_beta_signoff');
      expect(recommendation.artifactStatus, 'missing');
      expect(recommendation.requiresUserOperation, isTrue);
      expect(
        recommendation.recommendedCommand,
        contains('run_macos_computer_use_m39_beta_signoff.sh'),
      );
      expect(
        recommendation.recommendedCommand,
        contains('--root ${root.path}'),
      );
      expect(
        recommendation.recommendedCommand,
        contains('--manual-beta-checklist <m39-manual-beta-checklist.json>'),
      );
    });

    test('M31 navigator recommends Spaces canary before product gates', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m31_navigator_spaces_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final entries = <ReadinessArtifactEntry>[
        ..._requiredReadyEntries(root),
        const ReadinessArtifactEntry(
          id: 'spaces_canary',
          label: 'Latest macOS Spaces canary summary',
          path: '',
          exists: false,
        ),
        const ReadinessArtifactEntry(
          id: 'm39_beta_signoff',
          label: 'Latest M39 internal beta sign-off',
          path: '',
          exists: false,
        ),
      ];

      final navigator = buildReadinessNextStepNavigator(root, entries);
      final recommendation = navigator.recommendation;

      expect(navigator.status, 'ready');
      expect(recommendation.priority, 'run_spaces_canary');
      expect(recommendation.artifactId, 'spaces_canary');
      expect(recommendation.requiresUserOperation, isTrue);
      expect(
        recommendation.evidencePath,
        '${root.path}/macos_computer_use_spaces_canary_<timestamp>/canary_summary.json',
      );
      expect(
        recommendation.recommendedCommand,
        'bash tool/run_macos_computer_use_spaces_canary.sh --require-inactive-space-window --switch-space-next --handoff-only',
      );
    });

    test('M31 navigator recommends M40 after M39 is ready', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m31_navigator_m40_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final entries = <ReadinessArtifactEntry>[
        ..._requiredReadyEntries(root),
        const ReadinessArtifactEntry(
          id: 'm39_beta_signoff',
          label: 'Latest M39 internal beta sign-off',
          path: '/tmp/m39.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm40_production_launch_gate',
          label: 'Latest M40 production launch gate',
          path: '',
          exists: false,
        ),
      ];

      final navigator = buildReadinessNextStepNavigator(root, entries);
      final recommendation = navigator.recommendation;

      expect(navigator.status, 'ready');
      expect(recommendation.priority, 'run_m40_production_launch_gate');
      expect(recommendation.artifactId, 'm40_production_launch_gate');
      expect(recommendation.artifactStatus, 'missing');
      expect(recommendation.requiresUserOperation, isTrue);
      expect(
        recommendation.recommendedCommand,
        contains('run_macos_computer_use_m40_production_launch_gate.sh'),
      );
      expect(
        recommendation.recommendedCommand,
        contains('--root ${root.path}'),
      );
      expect(
        recommendation.recommendedCommand,
        contains(
          '--m39-beta-signoff <macos_computer_use_m39_beta_signoff.json>',
        ),
      );
    });

    test('M31 navigator recommends M50 after M40 is ready', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m31_navigator_m50_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final entries = <ReadinessArtifactEntry>[
        ..._requiredReadyEntries(root),
        const ReadinessArtifactEntry(
          id: 'm39_beta_signoff',
          label: 'Latest M39 internal beta sign-off',
          path: '/tmp/m39.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm40_production_launch_gate',
          label: 'Latest M40 production launch gate',
          path: '/tmp/m40.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm50_signed_beta_gate',
          label: 'Latest M50 signed beta gate',
          path: '',
          exists: false,
        ),
      ];

      final navigator = buildReadinessNextStepNavigator(root, entries);
      final recommendation = navigator.recommendation;

      expect(navigator.status, 'ready');
      expect(recommendation.priority, 'run_m50_signed_beta_gate');
      expect(recommendation.artifactId, 'm50_signed_beta_gate');
      expect(recommendation.artifactStatus, 'missing');
      expect(recommendation.requiresUserOperation, isTrue);
      expect(
        recommendation.recommendedCommand,
        contains('run_macos_computer_use_m50_signed_beta_gate.sh'),
      );
      expect(
        recommendation.recommendedCommand,
        contains('--root ${root.path}'),
      );
      expect(
        recommendation.recommendedCommand,
        contains(
          '--m49-privacy-audit-release-pack <privacy_audit_release_pack.json>',
        ),
      );
    });

    test('M31 navigator recommends M51 after M50 is ready', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m31_navigator_m51_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final entries = <ReadinessArtifactEntry>[
        ..._requiredReadyEntries(root),
        const ReadinessArtifactEntry(
          id: 'm39_beta_signoff',
          label: 'Latest M39 internal beta sign-off',
          path: '/tmp/m39.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm40_production_launch_gate',
          label: 'Latest M40 production launch gate',
          path: '/tmp/m40.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm50_signed_beta_gate',
          label: 'Latest M50 signed beta gate',
          path: '/tmp/m50.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm51_production_launch_gate',
          label: 'Latest M51 production launch gate',
          path: '',
          exists: false,
        ),
      ];

      final navigator = buildReadinessNextStepNavigator(root, entries);
      final recommendation = navigator.recommendation;

      expect(navigator.status, 'ready');
      expect(recommendation.priority, 'run_m51_production_launch_gate');
      expect(recommendation.artifactId, 'm51_production_launch_gate');
      expect(recommendation.artifactStatus, 'missing');
      expect(recommendation.requiresUserOperation, isTrue);
      expect(
        recommendation.recommendedCommand,
        contains('run_macos_computer_use_m51_production_launch_gate.sh'),
      );
      expect(
        recommendation.recommendedCommand,
        contains('--root ${root.path}'),
      );
      expect(
        recommendation.recommendedCommand,
        contains(
          '--m50-signed-beta-gate <macos_computer_use_m50_signed_beta_gate.json>',
        ),
      );
    });

    test('M31 navigator recommends M52 after M51 is ready', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m31_navigator_m52_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final entries = <ReadinessArtifactEntry>[
        ..._requiredReadyEntries(root),
        const ReadinessArtifactEntry(
          id: 'm39_beta_signoff',
          label: 'Latest M39 internal beta sign-off',
          path: '/tmp/m39.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm40_production_launch_gate',
          label: 'Latest M40 production launch gate',
          path: '/tmp/m40.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm50_signed_beta_gate',
          label: 'Latest M50 signed beta gate',
          path: '/tmp/m50.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm51_production_launch_gate',
          label: 'Latest M51 production launch gate',
          path: '/tmp/m51.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm52_product_release_rollout',
          label: 'Latest M52 product release rollout',
          path: '',
          exists: false,
        ),
      ];

      final navigator = buildReadinessNextStepNavigator(root, entries);
      final recommendation = navigator.recommendation;

      expect(navigator.status, 'ready');
      expect(recommendation.priority, 'run_m52_product_release_rollout');
      expect(recommendation.artifactId, 'm52_product_release_rollout');
      expect(recommendation.artifactStatus, 'missing');
      expect(recommendation.requiresUserOperation, isTrue);
      expect(
        recommendation.recommendedCommand,
        contains('run_macos_computer_use_m52_product_release_rollout.sh'),
      );
      expect(
        recommendation.recommendedCommand,
        contains('--root ${root.path}'),
      );
      expect(
        recommendation.recommendedCommand,
        contains(
          '--m51-production-launch-gate <macos_computer_use_m51_production_launch_gate.json>',
        ),
      );
    });

    test('artifact index blocks launch navigation on blocked M52 evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m52_blocked_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final m52Path =
          '${root.path}/macos_computer_use_m52_product_release_rollout_999/macos_computer_use_m52_product_release_rollout.json';
      _writeJson(File(m52Path), _m52ProductReleaseRollout(ready: false));

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm52_product_release_rollout',
      );
      final recommendation = index.nextStepNavigator.recommendation;

      expect(entry.exists, isTrue);
      expect(entry.status, 'blocked');
      expect(entry.details['reviewStatus'], 'blocked_gates_present');
      expect(
        entry.details['blockedGateIds'],
        contains('default_off_confirmed'),
      );
      expect(recommendation.priority, 'resolve_blocked_evidence');
      expect(recommendation.artifactId, 'm52_product_release_rollout');
      expect(
        recommendation.nextAction,
        'Resolve M52 product release rollout blockers before shipping Computer Use.',
      );
      expect(index.toMarkdown(), contains('## M52 Product Release Rollout'));
    });

    test('M31 navigator recommends M53 after M52 is ready', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m31_navigator_m53_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final entries = <ReadinessArtifactEntry>[
        const ReadinessArtifactEntry(
          id: 'release_artifact',
          label: 'Latest release artifact sign-off',
          path: '/tmp/release.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'canary_history',
          label: 'Latest canary history',
          path: '/tmp/canary.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'manual_tcc',
          label: 'Latest manual TCC evidence',
          path: '/tmp/tcc.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'desktop_action_canary',
          label: 'Latest desktop action canary',
          path: '/tmp/desktop.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'llm_canary',
          label: 'Latest LLM canary',
          path: '/tmp/llm.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm39_beta_signoff',
          label: 'Latest M39 beta sign-off',
          path: '/tmp/m39.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm40_production_launch_gate',
          label: 'Latest M40 production launch gate',
          path: '/tmp/m40.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm50_signed_beta_gate',
          label: 'Latest M50 signed beta gate',
          path: '/tmp/m50.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm51_production_launch_gate',
          label: 'Latest M51 production launch gate',
          path: '/tmp/m51.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm52_product_release_rollout',
          label: 'Latest M52 product release rollout',
          path: '/tmp/m52.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm53_post_release_guardrails',
          label: 'Latest M53 post-release guardrails',
          path: '',
          exists: false,
        ),
      ];

      final navigator = buildReadinessNextStepNavigator(root, entries);
      final recommendation = navigator.recommendation;

      expect(navigator.status, 'ready');
      expect(recommendation.priority, 'run_m53_post_release_guardrails');
      expect(recommendation.artifactId, 'm53_post_release_guardrails');
      expect(recommendation.artifactStatus, 'missing');
      expect(recommendation.requiresUserOperation, isTrue);
      expect(
        recommendation.recommendedCommand,
        contains('run_macos_computer_use_m53_post_release_guardrails.sh'),
      );
      expect(
        recommendation.recommendedCommand,
        contains('--root ${root.path}'),
      );
      expect(
        recommendation.recommendedCommand,
        contains(
          '--m52-product-release-rollout <macos_computer_use_m52_product_release_rollout.json>',
        ),
      );
    });

    test('artifact index blocks rollout navigation on blocked M53 evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m53_blocked_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final m53Path =
          '${root.path}/macos_computer_use_m53_post_release_guardrails_999/macos_computer_use_m53_post_release_guardrails.json';
      _writeJson(File(m53Path), _m53PostReleaseGuardrails(ready: false));

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm53_post_release_guardrails',
      );
      final recommendation = index.nextStepNavigator.recommendation;

      expect(entry.exists, isTrue);
      expect(entry.status, 'blocked');
      expect(entry.details['reviewStatus'], 'blocked_gates_present');
      expect(
        entry.details['blockedGateIds'],
        contains('support_diagnostics_reviewed'),
      );
      expect(recommendation.priority, 'resolve_blocked_evidence');
      expect(recommendation.artifactId, 'm53_post_release_guardrails');
      expect(
        recommendation.nextAction,
        'Resolve M53 post-release guardrail blockers before continuing rollout expansion.',
      );
      expect(index.toMarkdown(), contains('## M53 Post-Release Guardrails'));
    });

    test('M31 navigator recommends M54 after M53 is ready', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m31_navigator_m54_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final entries = <ReadinessArtifactEntry>[
        const ReadinessArtifactEntry(
          id: 'release_artifact',
          label: 'Latest release artifact sign-off',
          path: '/tmp/release.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'canary_history',
          label: 'Latest canary history',
          path: '/tmp/canary.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'manual_tcc',
          label: 'Latest manual TCC evidence',
          path: '/tmp/tcc.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'desktop_action_canary',
          label: 'Latest desktop action canary',
          path: '/tmp/desktop.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'llm_canary',
          label: 'Latest LLM canary',
          path: '/tmp/llm.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm39_beta_signoff',
          label: 'Latest M39 beta sign-off',
          path: '/tmp/m39.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm40_production_launch_gate',
          label: 'Latest M40 production launch gate',
          path: '/tmp/m40.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm50_signed_beta_gate',
          label: 'Latest M50 signed beta gate',
          path: '/tmp/m50.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm51_production_launch_gate',
          label: 'Latest M51 production launch gate',
          path: '/tmp/m51.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm52_product_release_rollout',
          label: 'Latest M52 product release rollout',
          path: '/tmp/m52.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm53_post_release_guardrails',
          label: 'Latest M53 post-release guardrails',
          path: '/tmp/m53.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm54_rollout_expansion_gate',
          label: 'Latest M54 rollout expansion gate',
          path: '',
          exists: false,
        ),
      ];

      final navigator = buildReadinessNextStepNavigator(root, entries);
      final recommendation = navigator.recommendation;

      expect(navigator.status, 'ready');
      expect(recommendation.priority, 'run_m54_rollout_expansion_gate');
      expect(recommendation.artifactId, 'm54_rollout_expansion_gate');
      expect(recommendation.artifactStatus, 'missing');
      expect(recommendation.requiresUserOperation, isTrue);
      expect(
        recommendation.recommendedCommand,
        contains('run_macos_computer_use_m54_rollout_expansion_gate.sh'),
      );
      expect(
        recommendation.recommendedCommand,
        contains('--root ${root.path}'),
      );
      expect(
        recommendation.recommendedCommand,
        contains(
          '--m53-post-release-guardrails <macos_computer_use_m53_post_release_guardrails.json>',
        ),
      );
    });

    test(
      'artifact index blocks expansion navigation on blocked M54 evidence',
      () {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_artifact_index_m54_blocked_test_',
        );
        addTearDown(() {
          root.deleteSync(recursive: true);
        });

        final m54Path =
            '${root.path}/macos_computer_use_m54_rollout_expansion_gate_999/macos_computer_use_m54_rollout_expansion_gate.json';
        _writeJson(File(m54Path), _m54RolloutExpansionGate(ready: false));

        final index = buildReadinessArtifactIndex(root);
        final entry = index.entries.singleWhere(
          (entry) => entry.id == 'm54_rollout_expansion_gate',
        );
        final recommendation = index.nextStepNavigator.recommendation;

        expect(entry.exists, isTrue);
        expect(entry.status, 'blocked');
        expect(entry.details['reviewStatus'], 'blocked_gates_present');
        expect(
          entry.details['blockedGateIds'],
          contains('expansion_scope_approved'),
        );
        expect(recommendation.priority, 'resolve_blocked_evidence');
        expect(recommendation.artifactId, 'm54_rollout_expansion_gate');
        expect(
          recommendation.nextAction,
          'Resolve M54 rollout expansion blockers before expanding rollout.',
        );
        expect(index.toMarkdown(), contains('## M54 Rollout Expansion Gate'));
      },
    );

    test('M31 navigator recommends M55 after M54 is ready', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m31_navigator_m55_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final entries = <ReadinessArtifactEntry>[
        ..._requiredReadyEntries(root),
        const ReadinessArtifactEntry(
          id: 'm39_beta_signoff',
          label: 'Latest M39 beta sign-off',
          path: '/tmp/m39.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm40_production_launch_gate',
          label: 'Latest M40 production launch gate',
          path: '/tmp/m40.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm50_signed_beta_gate',
          label: 'Latest M50 signed beta gate',
          path: '/tmp/m50.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm51_production_launch_gate',
          label: 'Latest M51 production launch gate',
          path: '/tmp/m51.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm52_product_release_rollout',
          label: 'Latest M52 product release rollout',
          path: '/tmp/m52.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm53_post_release_guardrails',
          label: 'Latest M53 post-release guardrails',
          path: '/tmp/m53.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm54_rollout_expansion_gate',
          label: 'Latest M54 rollout expansion gate',
          path: '/tmp/m54.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm55_post_expansion_monitoring_gate',
          label: 'Latest M55 post-expansion monitoring gate',
          path: '',
          exists: false,
        ),
      ];

      final navigator = buildReadinessNextStepNavigator(root, entries);
      final recommendation = navigator.recommendation;

      expect(navigator.status, 'ready');
      expect(recommendation.priority, 'run_m55_post_expansion_monitoring_gate');
      expect(recommendation.artifactId, 'm55_post_expansion_monitoring_gate');
      expect(recommendation.artifactStatus, 'missing');
      expect(recommendation.requiresUserOperation, isTrue);
      expect(
        recommendation.recommendedCommand,
        contains(
          'run_macos_computer_use_m55_post_expansion_monitoring_gate.sh',
        ),
      );
      expect(
        recommendation.recommendedCommand,
        contains('--root ${root.path}'),
      );
      expect(
        recommendation.recommendedCommand,
        contains(
          '--m54-rollout-expansion-gate <macos_computer_use_m54_rollout_expansion_gate.json>',
        ),
      );
    });

    test(
      'artifact index blocks continuation navigation on blocked M55 evidence',
      () {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_artifact_index_m55_blocked_test_',
        );
        addTearDown(() {
          root.deleteSync(recursive: true);
        });

        final m55Path =
            '${root.path}/macos_computer_use_m55_post_expansion_monitoring_gate_999/macos_computer_use_m55_post_expansion_monitoring_gate.json';
        _writeJson(
          File(m55Path),
          _m55PostExpansionMonitoringGate(ready: false),
        );

        final index = buildReadinessArtifactIndex(root);
        final entry = index.entries.singleWhere(
          (entry) => entry.id == 'm55_post_expansion_monitoring_gate',
        );
        final recommendation = index.nextStepNavigator.recommendation;

        expect(entry.exists, isTrue);
        expect(entry.status, 'blocked');
        expect(entry.details['reviewStatus'], 'blocked_gates_present');
        expect(
          entry.details['blockedGateIds'],
          contains('safety_metrics_reviewed'),
        );
        expect(recommendation.priority, 'resolve_blocked_evidence');
        expect(recommendation.artifactId, 'm55_post_expansion_monitoring_gate');
        expect(
          recommendation.nextAction,
          'Resolve M55 post-expansion monitoring blockers before changing rollout state.',
        );
        expect(
          index.toMarkdown(),
          contains('## M55 Post-Expansion Monitoring Gate'),
        );
      },
    );

    test('M31 navigator recommends M56 after M55 is ready', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m31_navigator_m56_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final entries = <ReadinessArtifactEntry>[
        ..._requiredReadyEntries(root),
        const ReadinessArtifactEntry(
          id: 'm39_beta_signoff',
          label: 'Latest M39 beta sign-off',
          path: '/tmp/m39.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm40_production_launch_gate',
          label: 'Latest M40 production launch gate',
          path: '/tmp/m40.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm50_signed_beta_gate',
          label: 'Latest M50 signed beta gate',
          path: '/tmp/m50.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm51_production_launch_gate',
          label: 'Latest M51 production launch gate',
          path: '/tmp/m51.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm52_product_release_rollout',
          label: 'Latest M52 product release rollout',
          path: '/tmp/m52.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm53_post_release_guardrails',
          label: 'Latest M53 post-release guardrails',
          path: '/tmp/m53.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm54_rollout_expansion_gate',
          label: 'Latest M54 rollout expansion gate',
          path: '/tmp/m54.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm55_post_expansion_monitoring_gate',
          label: 'Latest M55 post-expansion monitoring gate',
          path: '/tmp/m55.json',
          exists: true,
          status: 'ready',
        ),
        const ReadinessArtifactEntry(
          id: 'm56_rollout_decision_handoff_gate',
          label: 'Latest M56 rollout decision handoff gate',
          path: '',
          exists: false,
        ),
      ];

      final navigator = buildReadinessNextStepNavigator(root, entries);
      final recommendation = navigator.recommendation;

      expect(navigator.status, 'ready');
      expect(recommendation.priority, 'run_m56_rollout_decision_handoff_gate');
      expect(recommendation.artifactId, 'm56_rollout_decision_handoff_gate');
      expect(recommendation.artifactStatus, 'missing');
      expect(recommendation.requiresUserOperation, isTrue);
      expect(
        recommendation.recommendedCommand,
        contains('run_macos_computer_use_m56_rollout_decision_handoff_gate.sh'),
      );
      expect(
        recommendation.recommendedCommand,
        contains('--root ${root.path}'),
      );
      expect(
        recommendation.recommendedCommand,
        contains(
          '--m55-post-expansion-monitoring-gate <macos_computer_use_m55_post_expansion_monitoring_gate.json>',
        ),
      );
    });

    test('artifact index blocks handoff navigation on blocked M56 evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m56_blocked_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final m56Path =
          '${root.path}/macos_computer_use_m56_rollout_decision_handoff_gate_999/macos_computer_use_m56_rollout_decision_handoff_gate.json';
      _writeJson(File(m56Path), _m56RolloutDecisionHandoffGate(ready: false));

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm56_rollout_decision_handoff_gate',
      );
      final recommendation = index.nextStepNavigator.recommendation;

      expect(entry.exists, isTrue);
      expect(entry.status, 'blocked');
      expect(entry.details['reviewStatus'], 'blocked_gates_present');
      expect(
        entry.details['blockedGateIds'],
        contains('decision_branch_handoff'),
      );
      expect(recommendation.priority, 'resolve_blocked_evidence');
      expect(recommendation.artifactId, 'm56_rollout_decision_handoff_gate');
      expect(
        recommendation.nextAction,
        'Resolve M56 rollout decision handoff blockers before changing rollout state.',
      );
      expect(
        index.toMarkdown(),
        contains('## M56 Rollout Decision Handoff Gate'),
      );
    });

    test('artifact index blocks launch navigation on blocked M39 evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_artifact_index_m39_blocked_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      final m39Path =
          '${root.path}/macos_computer_use_m39_beta_signoff_999/macos_computer_use_m39_beta_signoff.json';
      _writeJson(File(m39Path), _m39BetaSignoff(ready: false));

      final index = buildReadinessArtifactIndex(root);
      final entry = index.entries.singleWhere(
        (entry) => entry.id == 'm39_beta_signoff',
      );
      final recommendation = index.nextStepNavigator.recommendation;

      expect(entry.exists, isTrue);
      expect(entry.status, 'blocked');
      expect(entry.details['reviewStatus'], 'blocked_gates_present');
      expect(entry.details['blockedGateIds'], contains('clean_install'));
      expect(recommendation.priority, 'resolve_blocked_evidence');
      expect(recommendation.artifactId, 'm39_beta_signoff');
      expect(
        recommendation.nextAction,
        'Resolve M39 beta sign-off blockers before preparing the production launch gate.',
      );
      expect(index.toMarkdown(), contains('## M39 Beta Sign-Off'));
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
      final m15HandoffPath =
          '${root.path}/macos_computer_use_m15_action_proposal_handoff_1/action_proposal_handoff.json';
      _writeJson(File(m15HandoffPath), _m15ActionProposalHandoff(ready: true));
      final m16ApprovalPacketPath =
          '${root.path}/macos_computer_use_m16_approval_packet_1/approval_packet.json';
      _writeJson(
        File(m16ApprovalPacketPath),
        _m16ApprovalPacket(ready: true, approved: true),
      );
      final m17ExecutionRehearsalPath =
          '${root.path}/macos_computer_use_m17_execution_rehearsal_1/execution_rehearsal.json';
      _writeJson(
        File(m17ExecutionRehearsalPath),
        _m17ExecutionRehearsal(ready: true),
      );
      final m18ExecutionHandoffPath =
          '${root.path}/macos_computer_use_m18_execution_handoff_1/execution_handoff.json';
      _writeJson(
        File(m18ExecutionHandoffPath),
        _m18ExecutionHandoff(ready: true),
      );
      final m20ExecutionResultIntakePath =
          '${root.path}/macos_computer_use_m20_execution_result_intake_1/execution_result_intake.json';
      _writeJson(
        File(m20ExecutionResultIntakePath),
        _m20ExecutionResultIntake(
          ready: true,
          sourceM18ExecutionHandoff: m18ExecutionHandoffPath,
        ),
      );
      final m22PostActionReviewPath =
          '${root.path}/macos_computer_use_m22_post_action_review_1/post_action_review.json';
      _writeJson(
        File(m22PostActionReviewPath),
        _m22PostActionReview(
          ready: true,
          sourceM20ExecutionResultIntake: m20ExecutionResultIntakePath,
        ),
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
      expect(stdout, contains('M15 action proposal command:'));
      expect(
        stdout,
        contains(
          'bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh --root ${root.path} --m14-summary $realAppObserveSummaryPath',
        ),
      );
      expect(stdout, contains('M15 LLM review command:'));
      expect(
        stdout,
        contains(
          'bash tool/run_macos_computer_use_m15_llm_review_canary.sh --root ${root.path} --handoff $m15HandoffPath',
        ),
      );
      expect(stdout, contains('M16 approval packet command:'));
      expect(
        stdout,
        contains(
          'bash tool/run_macos_computer_use_m16_approval_packet.sh --root ${root.path} --m15-handoff $m15HandoffPath',
        ),
      );
      expect(stdout, contains('M17 execution rehearsal command:'));
      expect(
        stdout,
        contains(
          'bash tool/run_macos_computer_use_m17_execution_rehearsal.sh --root ${root.path} --m16-packet $m16ApprovalPacketPath',
        ),
      );
      expect(stdout, contains('M18 execution handoff command:'));
      expect(
        stdout,
        contains(
          'bash tool/run_macos_computer_use_m18_execution_handoff.sh --root ${root.path} --m17-rehearsal $m17ExecutionRehearsalPath',
        ),
      );
      expect(stdout, contains('M20 execution result intake command:'));
      expect(
        stdout,
        contains(
          'bash tool/run_macos_computer_use_m20_execution_result_intake.sh --root ${root.path} --m18-handoff $m18ExecutionHandoffPath',
        ),
      );
      expect(stdout, contains('M22 post-action review command:'));
      expect(
        stdout,
        contains(
          'bash tool/run_macos_computer_use_m22_post_action_review.sh --root ${root.path} --m20-intake $m20ExecutionResultIntakePath',
        ),
      );
      expect(stdout, contains('M23 cycle outcome handoff command:'));
      expect(
        stdout,
        contains(
          'bash tool/run_macos_computer_use_m23_cycle_outcome_handoff.sh --root ${root.path} --m22-review $m22PostActionReviewPath',
        ),
      );

      final markdown = File(
        '${root.path}/macos_computer_use_readiness_artifact_index.md',
      ).readAsStringSync();
      expect(markdown, contains('MVP Final Sign-Off Rehearsal'));
      expect(markdown, contains('- Ready: true'));
      expect(markdown, contains('Latest LLM canary summary'));
      expect(markdown, contains(realAppObserveSummaryPath));
      expect(markdown, contains('M15 action proposal command:'));
      expect(
        markdown,
        contains(
          'bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh --root ${root.path} --m14-summary $realAppObserveSummaryPath',
        ),
      );
      expect(markdown, contains('M15 LLM review command:'));
      expect(
        markdown,
        contains(
          'bash tool/run_macos_computer_use_m15_llm_review_canary.sh --root ${root.path} --handoff $m15HandoffPath',
        ),
      );
      expect(markdown, contains('M16 approval packet command:'));
      expect(
        markdown,
        contains(
          'bash tool/run_macos_computer_use_m16_approval_packet.sh --root ${root.path} --m15-handoff $m15HandoffPath',
        ),
      );
      expect(markdown, contains('M17 execution rehearsal command:'));
      expect(
        markdown,
        contains(
          'bash tool/run_macos_computer_use_m17_execution_rehearsal.sh --root ${root.path} --m16-packet $m16ApprovalPacketPath',
        ),
      );
      expect(markdown, contains('M18 execution handoff command:'));
      expect(
        markdown,
        contains(
          'bash tool/run_macos_computer_use_m18_execution_handoff.sh --root ${root.path} --m17-rehearsal $m17ExecutionRehearsalPath',
        ),
      );
      expect(markdown, contains('M20 execution result intake command:'));
      expect(
        markdown,
        contains(
          'bash tool/run_macos_computer_use_m20_execution_result_intake.sh --root ${root.path} --m18-handoff $m18ExecutionHandoffPath',
        ),
      );
      expect(markdown, contains('M22 post-action review command:'));
      expect(
        markdown,
        contains(
          'bash tool/run_macos_computer_use_m22_post_action_review.sh --root ${root.path} --m20-intake $m20ExecutionResultIntakePath',
        ),
      );
      expect(markdown, contains('M23 cycle outcome handoff command:'));
      expect(
        markdown,
        contains(
          'bash tool/run_macos_computer_use_m23_cycle_outcome_handoff.sh --root ${root.path} --m22-review $m22PostActionReviewPath',
        ),
      );

      final indexJson =
          jsonDecode(
                File(
                  '${root.path}/macos_computer_use_readiness_artifact_index.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final rehearsal =
          indexJson['mvpFinalSignoffRehearsal'] as Map<String, dynamic>;
      expect(
        rehearsal['m15ActionProposalCommand'],
        contains('run_macos_computer_use_m15_action_proposal_handoff.sh'),
      );
      expect(
        rehearsal['m15LlmReviewCommand'],
        contains('run_macos_computer_use_m15_llm_review_canary.sh'),
      );
      expect(
        rehearsal['m16ApprovalPacketCommand'],
        contains('run_macos_computer_use_m16_approval_packet.sh'),
      );
      expect(
        rehearsal['m17ExecutionRehearsalCommand'],
        contains('run_macos_computer_use_m17_execution_rehearsal.sh'),
      );
      expect(
        rehearsal['m18ExecutionHandoffCommand'],
        contains('run_macos_computer_use_m18_execution_handoff.sh'),
      );
      expect(
        rehearsal['m20ExecutionResultIntakeCommand'],
        contains('run_macos_computer_use_m20_execution_result_intake.sh'),
      );
      expect(
        rehearsal['m22PostActionReviewCommand'],
        contains('run_macos_computer_use_m22_post_action_review.sh'),
      );
      expect(
        rehearsal['m23CycleOutcomeHandoffCommand'],
        contains('run_macos_computer_use_m23_cycle_outcome_handoff.sh'),
      );
    });
  });
}

Map<String, dynamic> _releaseReport({
  required String status,
  List<String>? blockers,
  String? nextAction,
  List<String>? launchConstraintBlockers,
  String? helperPath,
}) {
  final ready = status == 'ready';
  return <String, dynamic>{
    'releaseSignoffGate': <String, dynamic>{
      'status': status,
      'blockers': blockers ?? (ready ? <String>[] : <String>['codesign']),
      'nextAction':
          nextAction ??
          (ready
              ? 'M7 release artifact sign-off is complete.'
              : 'Fix release artifact blockers.'),
      'helperPath': helperPath,
    },
    if (launchConstraintBlockers != null)
      'signingDiagnostics': <String, dynamic>{
        'launchConstraintBlockers': launchConstraintBlockers,
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
          'handoffCommand':
              'bash tool/run_macos_computer_use_manual_tcc_signoff.sh --handoff-only',
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

Map<String, dynamic> _mvpFixtureAggregateLlmSummary({
  required int failed,
  bool includeSpacesEvidence = true,
}) {
  final checkIds = <String>[
    'safe_click_plan',
    'type_confirm_plan',
    'destructive_refusal',
    if (includeSpacesEvidence) 'spaces_switch_plan',
  ];
  final scenarios = <Map<String, Object?>>[
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
    if (includeSpacesEvidence)
      <String, Object?>{
        'scenario': 'spaces-switch-plan',
        'status': 'passed',
        'runCount': 1,
        'failedCount': 0,
        'requiresUserSpaceSwitch': true,
        'actionPlan': <Map<String, Object?>>[
          <String, Object?>{'tool': 'computer_vision_observe'},
          <String, Object?>{
            'tool': 'computer_switch_space',
            'direction': 'next',
            'requiresUserApproval': true,
          },
          <String, Object?>{'tool': 'computer_vision_observe'},
        ],
      },
  ];
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_mvp_fixture_llm_canary_summary',
    'schemaVersion': 1,
    'purpose': 'computer_use_mvp_fixture_llm_canary',
    'tccBoundary': 'no_tcc_operation',
    'desktopActionBoundary': 'no_desktop_action',
    'ready': failed == 0,
    'runCount': includeSpacesEvidence ? 3 : 2,
    'scenarioCount': includeSpacesEvidence ? 3 : 2,
    'passed': failed == 0
        ? includeSpacesEvidence
              ? 3
              : 2
        : 1,
    'failed': failed,
    'failedCount': failed,
    'passRate': failed == 0 ? 1 : 0.5,
    'requiresUserClick': true,
    'requiresUserTextInput': true,
    if (includeSpacesEvidence) 'requiresUserSpaceSwitch': true,
    'mvpEvidenceGate': _mvpEvidenceGate(checkIds: checkIds),
    'expectedUserOperatedRuntimePhases': <String>[
      'pre_observe_image',
      'click_sent',
      'type_text_sent',
      if (includeSpacesEvidence) 'space_switch_planned',
      'post_observe_image',
      'destructive_target_refused',
    ],
    'fixtureApp': <String, Object?>{
      'name': 'Caverno Computer Use MVP Fixture',
      'windowTitle': 'Caverno Computer Use MVP Fixture',
    },
    'scenarios': scenarios,
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

Map<String, dynamic> _spacesSummary({
  required bool ready,
  bool inactiveSpaceWindowObserved = true,
  bool switchSpaceCanary = true,
  bool switchCanaryReady = true,
  bool requiresApprovedInputBeforeSwitching = true,
}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_spaces_canary_summary',
    'schemaVersion': 1,
    'purpose': 'computer_use_spaces_canary',
    'status': ready ? 'ready' : 'blocked',
    'ok': ready,
    'desktopModel': 'macos_spaces',
    'spaceScope': 'all_spaces',
    'desktopActionBoundary': switchSpaceCanary
        ? 'user_operated_space_switch_keypress_no_pointer_or_text'
        : 'no_desktop_action_observe_only',
    'tccBoundary': 'manual_user_operated',
    'requireInactiveSpaceWindow': true,
    'switchSpaceCanary': switchSpaceCanary,
    'switchSpaceDirection': switchSpaceCanary ? 'next' : null,
    'runCount': 1,
    'passedRunCount': ready ? 1 : 0,
    'failedRunCount': ready ? 0 : 1,
    'inactiveSpaceWindowObserved': inactiveSpaceWindowObserved,
    'switchCanaryReady': switchCanaryReady,
    'phaseStatus': <String, Object?>{
      'active_space_window_inventory': true,
      'all_spaces_window_inventory': ready,
      'space_metadata_present': ready,
      'inactive_space_window_candidate': inactiveSpaceWindowObserved,
      'switch_space_keypress': switchCanaryReady,
    },
    'runs': <Map<String, Object?>>[
      <String, Object?>{
        'name': 'run_01',
        'ok': ready,
        'gateStatus': ready ? 'ready' : 'blocked',
        'switchGateStatus': switchCanaryReady ? 'ready' : 'blocked',
        'inactiveSpaceWindowCount': inactiveSpaceWindowObserved ? 1 : 0,
        'switchKeySent': switchSpaceCanary,
        'switchKeyOk': switchCanaryReady,
        'postSwitchActiveSpaceObserved': switchCanaryReady,
        'activeWindowInventoryChanged': switchCanaryReady,
        'requiresApprovedInputBeforeSwitching':
            requiresApprovedInputBeforeSwitching,
      },
    ],
    'nextAction': ready
        ? 'Spaces canary passed.'
        : 'Prepare a harmless window on another Space, then rerun the Spaces canary.',
  };
}

Map<String, dynamic> _releaseSigningPreflight({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_release_signing_preflight',
    'schemaVersion': 1,
    'status': ready ? 'ready' : 'blocked',
    'ready': ready,
    'checks': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'signing_local_template',
        'label': 'Local signing template',
        'ok': true,
        'nextAction': 'No action required.',
      },
      <String, Object?>{
        'id': 'signing_local_gitignore',
        'label': 'Local signing gitignore guard',
        'ok': true,
        'nextAction': 'No action required.',
      },
      <String, Object?>{
        'id': 'development_team',
        'label': 'Development team',
        'ok': ready,
        'nextAction': ready
            ? 'No action required.'
            : 'Add DEVELOPMENT_TEAM to macos/Runner/Configs/Signing.local.xcconfig.',
      },
      <String, Object?>{
        'id': 'code_sign_identity',
        'label': 'Code sign identity override',
        'ok': ready,
        'nextAction': ready
            ? 'No action required.'
            : 'Add a non-ad-hoc CODE_SIGN_IDENTITY to macos/Runner/Configs/Signing.local.xcconfig.',
      },
      <String, Object?>{
        'id': 'keychain_code_signing_identity',
        'label': 'Keychain code signing identity',
        'ok': true,
        'nextAction': 'No action required.',
      },
      <String, Object?>{
        'id': 'code_sign_identity_keychain_match',
        'label': 'Code sign identity keychain match',
        'ok': ready,
        'nextAction': ready
            ? 'No action required.'
            : 'Set CODE_SIGN_IDENTITY to a non-ad-hoc identity that appears in `security find-identity -v -p codesigning`.',
      },
    ],
    'failedCheckIds': ready
        ? <String>[]
        : <String>[
            'development_team',
            'code_sign_identity',
            'code_sign_identity_keychain_match',
          ],
    'operationBoundary':
        'report-only signing setup check; it does not sign, notarize, staple, grant TCC, or operate desktop apps.',
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
    'prReviewSummary': <String, Object?>{
      'status': ready ? 'ready_for_review' : 'blocked_pending_review_evidence',
      'ready': ready,
      'sourceEvidence': 'm14_real_app_observe_canary',
      'blockedReviewEvidence': ready
          ? <String>[]
          : <String>['m14_evidence_ready'],
      'requiredConfirmations': <String>[
        'observe_again',
        'confirm_exact_text',
        'confirm_target',
        'confirm_public_action',
      ],
    },
    'reviewGateConsistency': <String, Object?>{
      'ok': true,
      'status': 'consistent',
      'nextAction': 'No action required.',
    },
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

Map<String, dynamic> _m15LlmReviewSummary({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m15_llm_review_canary_summary',
    'schemaVersion': 1,
    'purpose': 'computer_use_m15_llm_review_canary',
    'milestone': 'M15',
    'sourceHandoff': '/tmp/action_proposal_handoff.json',
    'tccBoundary': 'no_tcc_operation',
    'desktopActionBoundary': 'no_desktop_action',
    'llmBoundary': 'review_only_no_tool_execution',
    'runCount': 1,
    'passedCount': ready ? 1 : 0,
    'failedCount': ready ? 0 : 1,
    'boundaryDecision': ready
        ? 'approval_required_before_action'
        : 'execute_now',
    'm15LlmReviewGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready ? <String>[] : <String>['approval_boundary_missing'],
      'nextAction': ready
          ? 'M15 LLM review canary is ready for user review.'
          : 'Resolve M15 LLM review boundary failures before any action proposal execution.',
    },
  };
}

Map<String, dynamic> _m16ApprovalPacket({
  required bool ready,
  bool approved = false,
}) {
  final approvalStatus = ready
      ? approved
            ? 'approved'
            : 'pending_user_approval'
      : 'blocked';
  final approvalBlockers = ready
      ? approved
            ? <String>[]
            : <String>['exact_text', 'target_label', 'public_action_label']
      : <String>['m15_handoff_ready'];
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m16_approval_packet',
    'schemaVersion': 1,
    'purpose': 'computer_use_m16_approval_packet',
    'milestone': 'M16',
    'previousMilestone': 'M15',
    'ready': ready,
    'approvalStatus': approvalStatus,
    'executionBoundary': 'no_desktop_action_report_only',
    'desktopActionBoundary': 'no_desktop_action',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
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
    'requiredApprovals': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'observe_again',
        'required': true,
        'status': 'read_only_allowed',
      },
      <String, Object?>{
        'id': 'exact_text',
        'required': true,
        'status': approved ? 'approved' : 'pending_user_approval',
        if (approved) 'approvedValue': 'Good morning from Caverno',
      },
      <String, Object?>{
        'id': 'target_label',
        'required': true,
        'status': approved ? 'approved' : 'pending_user_approval',
        if (approved) 'approvedValue': 'What is happening?',
      },
      <String, Object?>{
        'id': 'public_action_label',
        'required': true,
        'status': approved ? 'approved' : 'pending_separate_user_approval',
        if (approved) 'approvedValue': 'Post',
      },
      <String, Object?>{
        'id': 'post_action_observation',
        'required': true,
        'status': 'required_after_future_action',
      },
    ],
    if (approved)
      'approvedValues': <String, Object?>{
        'exactText': 'Good morning from Caverno',
        'targetLabel': 'What is happening?',
        'publicActionLabel': 'Post',
      },
    'approvalBlockers': approvalBlockers,
    'm16ApprovalPacketGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready ? <String>[] : <String>['m15_handoff_ready'],
      'approvalStatus': approvalStatus,
      'approvalBlockers': approvalBlockers,
      'nextAction': ready
          ? approved
                ? 'M16 approval packet is approved for M17 execution rehearsal.'
                : 'Ask the user to approve exact text, target, and any public action before the future execution milestone.'
          : 'Resolve blocked M15 evidence before preparing the M16 approval packet.',
    },
  };
}

Map<String, dynamic> _m17ExecutionRehearsal({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m17_execution_rehearsal',
    'schemaVersion': 1,
    'purpose': 'computer_use_m17_execution_rehearsal',
    'milestone': 'M17',
    'previousMilestone': 'M16',
    'ready': ready,
    'approvalStatus': ready ? 'approved' : 'pending_user_approval',
    'executionBoundary': 'no_desktop_action_report_only',
    'desktopActionBoundary': 'no_desktop_action',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
    'approvedValues': <String, Object?>{
      'exactText': ready ? 'Good morning from Caverno' : null,
      'targetLabel': ready ? 'What is happening?' : null,
      'publicActionLabel': ready ? 'Post' : null,
    },
    'executionPhases': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'observe_again',
        'mode': 'read_only',
        'approved': true,
      },
      <String, Object?>{
        'id': 'focus_target',
        'mode': 'future_user_approved_desktop_action',
        'approved': ready,
        if (ready) 'approvedValue': 'What is happening?',
      },
      <String, Object?>{
        'id': 'type_exact_text',
        'mode': 'future_user_approved_input',
        'approved': ready,
        if (ready) 'approvedValue': 'Good morning from Caverno',
      },
      <String, Object?>{
        'id': 'post_action_observation',
        'mode': 'read_only_after_future_action',
        'approved': true,
      },
    ],
    'm17ExecutionRehearsalGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready ? <String>[] : <String>['approval_status_approved'],
      'nextAction': ready
          ? 'M17 execution rehearsal is ready for future user-operated execution review.'
          : 'Resolve blocked M17 rehearsal checks before future execution.',
    },
  };
}

Map<String, dynamic> _m18ExecutionHandoff({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m18_execution_handoff',
    'schemaVersion': 1,
    'purpose': 'computer_use_m18_execution_handoff',
    'milestone': 'M18',
    'previousMilestone': 'M17',
    'ready': ready,
    'executionBoundary': 'user_operated_runtime_handoff',
    'desktopActionBoundary': 'user_operated_only',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
    'publicActionRequiresSeparateApproval': true,
    'approvedValues': <String, Object?>{
      'exactText': ready ? 'Good morning from Caverno' : null,
      'targetLabel': ready ? 'What is happening?' : null,
      'publicActionLabel': ready ? 'Post' : null,
    },
    'actionTimeConfirmations': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'confirm_fresh_observation',
        'required': true,
        'approvedBeforeRun': ready,
      },
      <String, Object?>{
        'id': 'confirm_target_label',
        'required': true,
        'approvedBeforeRun': ready,
        if (ready) 'approvedValue': 'What is happening?',
      },
      <String, Object?>{
        'id': 'confirm_exact_text',
        'required': true,
        'approvedBeforeRun': ready,
        if (ready) 'approvedValue': 'Good morning from Caverno',
      },
    ],
    'executionChecklist': <Map<String, Object?>>[
      <String, Object?>{'id': 'fresh_observation'},
      <String, Object?>{'id': 'confirm_target_at_action_time'},
      <String, Object?>{'id': 'focus_target'},
      <String, Object?>{'id': 'confirm_exact_text_at_action_time'},
      <String, Object?>{'id': 'type_exact_text'},
      <String, Object?>{'id': 'public_action'},
      <String, Object?>{'id': 'post_action_observation'},
    ],
    'm18ExecutionHandoffGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready ? <String>[] : <String>['target_confirmation'],
      'nextAction': ready
          ? 'Ask the user to perform the runtime step manually with fresh observation and action-time confirmations.'
          : 'Resolve M18 handoff blockers before preparing any runtime execution step.',
    },
  };
}

Map<String, dynamic> _m20ExecutionResultIntake({
  required bool ready,
  required String sourceM18ExecutionHandoff,
}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m20_execution_result_intake',
    'schemaVersion': 1,
    'purpose': 'computer_use_m20_execution_result_intake',
    'milestone': 'M20',
    'previousMilestone': 'M18',
    'ready': ready,
    'sourceM18ExecutionHandoff': sourceM18ExecutionHandoff,
    'executionBoundary': 'manual_result_intake_report_only',
    'desktopActionBoundary': 'user_operated_evidence_only',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
    'manualInputs': <String, Object?>{
      'freshObservation': ready ? 'done' : 'missing',
      'targetConfirmed': ready ? 'yes' : 'no',
      'exactTextConfirmed': ready ? 'yes' : 'no',
      'publicActionConfirmed': 'yes',
      'runtimeAction': ready ? 'succeeded' : 'failed',
      'postActionObservation': ready ? 'done' : 'missing',
    },
    'resultSequence': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'runtime_action',
        'required': true,
        'status': ready ? 'succeeded' : 'failed',
      },
      <String, Object?>{
        'id': 'post_action_observation',
        'required': true,
        'status': ready ? 'done' : 'missing',
      },
    ],
    'm20ExecutionResultIntakeGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready
          ? <String>[]
          : <String>[
              'fresh_observation_recorded',
              'runtime_action_succeeded',
              'post_action_observation_recorded',
            ],
      'nextAction': ready
          ? 'Review the user-operated runtime result evidence before any follow-up action.'
          : 'Resolve M20 result intake blockers before accepting runtime evidence.',
    },
  };
}

Map<String, dynamic> _m22PostActionReview({
  required bool ready,
  required String sourceM20ExecutionResultIntake,
}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m22_post_action_review',
    'schemaVersion': 1,
    'purpose': 'computer_use_m22_post_action_review',
    'milestone': 'M22',
    'previousMilestone': 'M20',
    'ready': ready,
    'sourceM20ExecutionResultIntake': sourceM20ExecutionResultIntake,
    'executionBoundary': 'post_action_review_report_only',
    'desktopActionBoundary': 'no_desktop_action',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
    'sourceManualInputs': <String, Object?>{
      'runtimeAction': 'succeeded',
      'postActionObservation': 'done',
    },
    'reviewInputs': <String, Object?>{
      'resultReviewed': ready ? 'yes' : 'no',
      'postActionState': ready ? 'stable' : 'unknown',
      'followUpRequired': ready ? 'no' : 'yes',
      'followUpNote': ready ? '' : '',
    },
    'nextCycleRecommendation': ready
        ? 'no_follow_up'
        : 'start_new_observe_action_cycle',
    'm22PostActionReviewGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready
          ? <String>[]
          : <String>[
              'result_reviewed',
              'post_action_state_known',
              'follow_up_note_recorded_when_required',
            ],
      'nextAction': ready
          ? 'Archive the reviewed M20 result as the completed action cycle evidence.'
          : 'Resolve M22 post-action review blockers before closing the action cycle.',
    },
  };
}

Map<String, dynamic> _m23CycleOutcomeHandoff({
  required bool ready,
  required String sourceM22PostActionReview,
  bool restartCycle = false,
}) {
  final cycleOutcome = restartCycle ? 'restart_observe_action_cycle' : 'closed';
  final nextObserveNeeded = restartCycle ? 'yes' : 'no';
  final nextObserveNote = restartCycle ? 'Observe the next target.' : '';
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m23_cycle_outcome_handoff',
    'schemaVersion': 1,
    'purpose': 'computer_use_m23_cycle_outcome_handoff',
    'milestone': 'M23',
    'previousMilestone': 'M22',
    'ready': ready,
    'sourceM22PostActionReview': sourceM22PostActionReview,
    'executionBoundary': 'cycle_outcome_report_only',
    'desktopActionBoundary': 'no_desktop_action',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
    'sourceNextCycleRecommendation': ready && restartCycle
        ? 'start_new_observe_action_cycle'
        : (ready ? 'no_follow_up' : 'start_new_observe_action_cycle'),
    'cycleOutcome': ready ? cycleOutcome : 'unknown',
    'handoffInputs': <String, Object?>{
      'outcomeAccepted': ready ? 'yes' : 'no',
      'nextObserveNeeded': ready ? nextObserveNeeded : 'unknown',
    },
    'nextObserveSeed': <String, Object?>{
      'required': ready && restartCycle,
      'source': 'm23_cycle_outcome_handoff',
      'note': nextObserveNote,
      'returnMilestone': restartCycle ? 'M14' : null,
      'boundary': 'observe_only_no_desktop_action',
    },
    'm23CycleOutcomeHandoffGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready
          ? <String>[]
          : <String>['outcome_accepted', 'next_observe_needed_known'],
      'nextAction': ready && restartCycle
          ? 'Start a new M14 observe-only evidence pass with the recorded follow-up note.'
          : ready
          ? 'Archive the completed action cycle evidence.'
          : 'Resolve M23 cycle outcome blockers before closing or restarting the action cycle.',
    },
  };
}

Map<String, dynamic> _m25NextCycleSeedHandoff({
  required bool ready,
  required String sourceM23CycleOutcomeHandoff,
}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m25_next_cycle_seed_handoff',
    'schemaVersion': 1,
    'purpose': 'computer_use_m25_next_cycle_seed_handoff',
    'milestone': 'M25',
    'previousMilestone': 'M23',
    'ready': ready,
    'sourceM23CycleOutcomeHandoff': sourceM23CycleOutcomeHandoff,
    'executionBoundary': 'next_cycle_seed_report_only',
    'desktopActionBoundary': 'no_desktop_action',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
    'sourceCycleOutcome': 'restart_observe_action_cycle',
    'seedInputs': <String, Object?>{'seedAccepted': ready ? 'yes' : 'no'},
    'nextCycleSeed': <String, Object?>{
      'required': true,
      'source': 'm25_next_cycle_seed_handoff',
      'sourceM23CycleOutcomeHandoff': sourceM23CycleOutcomeHandoff,
      'returnMilestone': 'M14',
      'boundary': 'observe_only_no_desktop_action',
      'note': 'Observe the next target.',
      'requiresNewApprovalCycle': true,
    },
    'm25NextCycleSeedHandoffGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready ? <String>[] : <String>['seed_accepted'],
      'nextAction': ready
          ? 'Start a new M14 observe-only evidence pass using the recorded next-cycle seed.'
          : 'Resolve M25 next-cycle seed blockers before starting the next observe-only pass.',
    },
  };
}

Map<String, dynamic> _m26ObserveRestartPacket({
  required bool ready,
  required String sourceM25NextCycleSeedHandoff,
}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m26_observe_restart_packet',
    'schemaVersion': 1,
    'purpose': 'computer_use_m26_observe_restart_packet',
    'milestone': 'M26',
    'previousMilestone': 'M25',
    'ready': ready,
    'sourceM25NextCycleSeedHandoff': sourceM25NextCycleSeedHandoff,
    'executionBoundary': 'm14_observe_restart_packet_report_only',
    'desktopActionBoundary': 'no_desktop_action',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
    'targetApp': ready ? 'Safari' : '',
    'targetIntent': 'Observe the next target.',
    'nextObservePreparation': <String, Object?>{
      'required': true,
      'returnMilestone': 'M14',
      'boundary': 'observe_only_no_desktop_action',
      'targetApp': ready ? 'Safari' : '',
      'targetIntent': 'Observe the next target.',
      'screenshotRequired': true,
      'screenshotProvided': false,
    },
    'commands': <String, Object?>{
      'm14RealAppHandoff':
          'bash tool/run_macos_computer_use_m14_real_app_handoff.sh',
      'm14ObserveCanary':
          'bash tool/run_macos_computer_use_real_app_observe_canary.sh --screenshot <user-provided-real-app-screenshot.png>',
    },
    'm26ObserveRestartPacketGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready ? <String>[] : <String>['target_app_present'],
      'nextAction': ready
          ? 'Ask the user to manually prepare the target app, capture a screenshot, and run the M14 observe-only canary command.'
          : 'Resolve M26 observe restart packet blockers before asking for a new M14 screenshot.',
    },
  };
}

Map<String, dynamic> _m27ScreenshotRequestHandoff({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m27_screenshot_request_handoff',
    'schemaVersion': 1,
    'purpose': 'computer_use_m27_screenshot_request_handoff',
    'milestone': 'M27',
    'previousMilestone': 'M26',
    'ready': ready,
    'sourceM26ObserveRestartPacket': '/tmp/observe_restart_packet.json',
    'executionBoundary': 'manual_screenshot_request_report_only',
    'desktopActionBoundary': 'no_desktop_action',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
    'targetApp': ready ? 'Safari' : '',
    'targetIntent': 'Observe the next target.',
    'userScreenshotRequest': <String, Object?>{
      'required': true,
      'provided': false,
      'targetApp': ready ? 'Safari' : '',
      'targetIntent': 'Observe the next target.',
      'returnMilestone': 'M14',
      'boundary': 'observe_only_no_desktop_action',
    },
    'commands': <String, Object?>{
      'm14RealAppHandoff':
          'bash tool/run_macos_computer_use_m14_real_app_handoff.sh',
      'm14ObserveCanary':
          'bash tool/run_macos_computer_use_real_app_observe_canary.sh --screenshot <user-provided-real-app-screenshot.png>',
    },
    'm27ScreenshotRequestHandoffGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready ? <String>[] : <String>['target_app_present'],
      'nextAction': ready
          ? 'Ask the user to manually prepare the target app, capture the requested screenshot, and run the M14 observe-only canary command.'
          : 'Resolve M27 screenshot request handoff blockers before asking for the manual screenshot.',
    },
  };
}

Map<String, dynamic> _m28ScreenshotEvidenceIntake({
  required bool ready,
  String screenshotPath = '/tmp/user-provided-real-app-screenshot.png',
}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m28_screenshot_evidence_intake',
    'schemaVersion': 1,
    'purpose': 'computer_use_m28_screenshot_evidence_intake',
    'milestone': 'M28',
    'previousMilestone': 'M27',
    'ready': ready,
    'sourceM27ScreenshotRequestHandoff': '/tmp/screenshot_request_handoff.json',
    'executionBoundary': 'manual_screenshot_evidence_intake_report_only',
    'desktopActionBoundary': 'no_desktop_action',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
    'targetApp': ready ? 'Safari' : '',
    'targetIntent': 'Observe the next target.',
    'screenshotEvidence': <String, Object?>{
      'path': screenshotPath,
      'exists': true,
      'sizeBytes': ready ? 8 : 0,
      'extension': '.png',
      'source': 'user_provided',
    },
    'nextObserveInput': <String, Object?>{
      'required': true,
      'provided': ready,
      'returnMilestone': 'M14',
      'boundary': 'observe_only_no_desktop_action',
      'targetApp': ready ? 'Safari' : '',
      'targetIntent': 'Observe the next target.',
      'screenshotPath': screenshotPath,
    },
    'commands': <String, Object?>{
      'm14RealAppHandoff':
          'bash tool/run_macos_computer_use_m14_real_app_handoff.sh',
      'm14ObserveCanary':
          'bash tool/run_macos_computer_use_real_app_observe_canary.sh --screenshot $screenshotPath',
    },
    'm28ScreenshotEvidenceIntakeGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready ? <String>[] : <String>['target_app_present'],
      'nextAction': ready
          ? 'Run the M14 observe-only canary with the user-provided screenshot, then continue the approval-bound observe/action cycle.'
          : 'Resolve M28 screenshot evidence intake blockers before running the M14 observe-only canary.',
    },
  };
}

Map<String, dynamic> _m29ObserveCanaryRunPacket({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m29_observe_canary_run_packet',
    'schemaVersion': 1,
    'purpose': 'computer_use_m29_observe_canary_run_packet',
    'milestone': 'M29',
    'previousMilestone': 'M28',
    'ready': ready,
    'sourceM28ScreenshotEvidenceIntake': '/tmp/screenshot_evidence_intake.json',
    'executionBoundary': 'm14_observe_canary_run_packet_report_only',
    'desktopActionBoundary': 'no_desktop_action',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
    'targetApp': ready ? 'Safari' : '',
    'targetIntent': 'Observe the next target.',
    'screenshotEvidence': <String, Object?>{
      'path': '/tmp/user-provided-real-app-screenshot.png',
      'exists': true,
      'sizeBytes': ready ? 8 : 0,
      'extension': '.png',
      'source': 'm28_screenshot_evidence_intake',
    },
    'm14ObserveRunPacket': <String, Object?>{
      'required': true,
      'readyForUserOperation': ready,
      'userOperated': true,
      'returnMilestone': 'M14',
      'boundary': 'observe_only_no_desktop_action',
      'targetApp': ready ? 'Safari' : '',
      'targetIntent': 'Observe the next target.',
      'screenshotPath': '/tmp/user-provided-real-app-screenshot.png',
      'command':
          'bash tool/run_macos_computer_use_real_app_observe_canary.sh --screenshot /tmp/user-provided-real-app-screenshot.png',
    },
    'commands': <String, Object?>{
      'm14ObserveCanary':
          'bash tool/run_macos_computer_use_real_app_observe_canary.sh --screenshot /tmp/user-provided-real-app-screenshot.png',
    },
    'm29ObserveCanaryRunPacketGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready ? <String>[] : <String>['target_app_present'],
      'nextAction': ready
          ? 'Ask the user to run the M14 observe-only canary command with the recorded screenshot, then review the new M14 evidence.'
          : 'Resolve M29 observe canary run packet blockers before asking the user to run M14.',
    },
  };
}

Map<String, dynamic> _m14ObserveSummaryForM30({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_real_app_observe_canary_summary',
    'schemaVersion': 1,
    'purpose': 'computer_use_real_app_observe_canary',
    'milestone': 'M14',
    'ready': ready,
    'runCount': 1,
    'passedCount': ready ? 1 : 0,
    'failedCount': ready ? 0 : 1,
    'desktopActionBoundary': 'no_desktop_action',
    'tccBoundary': 'no_tcc_operation',
    'targetApp': 'Safari',
    'targetIntent': 'Observe the next target.',
    'screenshotPath': '/tmp/user-provided-real-app-screenshot.png',
    'visionDecision': 'Safari compose screen is visible.',
    'observedApp': 'Safari',
    'visibleAppWindow': true,
    'observationOnly': true,
    'requiresUserApprovalBeforeAction': true,
    'candidateTargets': <Map<String, Object?>>[
      <String, Object?>{
        'label': 'Compose text field',
        'role': 'text_field',
        'risk': 'input',
      },
      <String, Object?>{
        'label': 'Post',
        'role': 'public_submit',
        'risk': 'public_action',
      },
    ],
    'confirmationRequirements': <String>[
      'Ask the user to approve exact text before typing.',
      'Ask the user to approve the public submit action.',
    ],
    'actionPlan': <Map<String, Object?>>[
      <String, Object?>{'tool': 'computer_vision_observe'},
    ],
    'm14EvidenceGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready ? <String>[] : <String>['candidate_targets_present'],
    },
  };
}

Map<String, dynamic> _m30ObserveResultIntake({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m30_observe_result_intake',
    'schemaVersion': 1,
    'purpose': 'computer_use_m30_observe_result_intake',
    'milestone': 'M30',
    'previousMilestone': 'M29',
    'returnToMilestone': 'M15',
    'ready': ready,
    'sourceM29ObserveCanaryRunPacket': '/tmp/observe_canary_run_packet.json',
    'sourceM14ObserveCanarySummary': '/tmp/canary_summary.json',
    'executionBoundary': 'm14_observe_result_intake_report_only',
    'desktopActionBoundary': 'no_desktop_action',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
    'targetApp': ready ? 'Safari' : 'Notes',
    'targetIntent': 'Observe the next target.',
    'screenshotPath': '/tmp/user-provided-real-app-screenshot.png',
    'sourceAlignment': <String, Object?>{
      'targetAppMatches': ready,
      'targetIntentMatches': true,
      'screenshotPathMatches': true,
    },
    'm14ObserveEvidence': <String, Object?>{
      'ready': true,
      'gateStatus': 'ready',
      'candidateTargetCount': 2,
      'textEntryTargetCount': 1,
      'publicActionTargetCount': 1,
      'confirmationRequirementCount': 2,
      'observationOnly': true,
    },
    'nextHandoff': <String, Object?>{
      'returnMilestone': 'M15',
      'command':
          'bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh --m14-summary /tmp/canary_summary.json',
      'boundary': 'approval_bound_action_proposal_report_only',
    },
    'commands': <String, Object?>{
      'm15ActionProposalHandoff':
          'bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh --m14-summary /tmp/canary_summary.json',
    },
    'm30ObserveResultIntakeGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready ? <String>[] : <String>['target_app_matches'],
      'nextAction': ready
          ? 'Return to M15 action proposal handoff using the ready M14 observe evidence from this intake.'
          : 'Resolve M30 observe result intake blockers before returning to M15.',
    },
  };
}

Map<String, dynamic> _m39BetaSignoff({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m39_beta_signoff',
    'schemaVersion': 1,
    'milestone': 'M39',
    'automationBoundary': 'read_reports_only',
    'tccBoundary': 'user_operated',
    'desktopActionBoundary': 'user_operated',
    'status': ready ? 'ready' : 'blocked',
    'ready': ready,
    'readyGateIds': ready ? <String>['clean_install'] : <String>[],
    'blockedGateIds': ready ? <String>[] : <String>['clean_install'],
    'userOperatedGateIds': <String>['clean_install'],
    'betaReviewSummary': <String, Object?>{
      'status': ready ? 'ready_for_internal_beta' : 'blocked_gates_present',
      'readyGateIds': ready ? <String>['clean_install'] : <String>[],
      'blockedGateIds': ready ? <String>[] : <String>['clean_install'],
      'blockedUserOperatedGateIds': ready
          ? <String>[]
          : <String>['clean_install'],
      'blockedAutomationSafeGateIds': <String>[],
      'operationBoundarySummary':
          'M39 reads existing reports and manual checklist evidence only.',
    },
    'gates': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'clean_install',
        'label': 'Clean install',
        'status': ready ? 'ready' : 'missing',
        'ready': ready,
        'nextAction': ready
            ? 'Clean install evidence is ready.'
            : 'Ask the user to complete a clean install pass.',
        'userOperated': true,
      },
    ],
  };
}

Map<String, dynamic> _m40ProductionLaunchGate({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m40_production_launch_gate',
    'schemaVersion': 1,
    'milestone': 'M40',
    'automationBoundary': 'read_reports_only',
    'tccBoundary': 'user_operated',
    'desktopActionBoundary': 'user_operated',
    'status': ready ? 'ready' : 'blocked',
    'ready': ready,
    'readyGateIds': ready ? <String>['m39_beta_signoff'] : <String>[],
    'blockedGateIds': ready ? <String>[] : <String>['m39_beta_signoff'],
    'userOperatedGateIds': <String>['m39_beta_signoff'],
    'launchReviewSummary': <String, Object?>{
      'status': ready ? 'ready_for_production_launch' : 'blocked_gates_present',
      'readyGateIds': ready ? <String>['m39_beta_signoff'] : <String>[],
      'blockedGateIds': ready ? <String>[] : <String>['m39_beta_signoff'],
      'blockedUserOperatedGateIds': ready
          ? <String>[]
          : <String>['m39_beta_signoff'],
      'blockedAutomationSafeGateIds': <String>[],
      'operationBoundarySummary': 'M40 reads release evidence only.',
    },
    'gates': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'm39_beta_signoff',
        'label': 'M39 beta sign-off',
        'status': ready ? 'ready' : 'missing',
        'ready': ready,
        'nextAction': ready
            ? 'M39 beta sign-off is ready.'
            : 'Run the M39 beta sign-off first.',
        'userOperated': true,
      },
    ],
  };
}

Map<String, dynamic> _m52ProductReleaseRollout({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m52_product_release_rollout',
    'schemaVersion': 1,
    'milestone': 'M52',
    'automationBoundary': 'read_reports_only',
    'tccBoundary': 'user_operated',
    'desktopActionBoundary': 'user_operated',
    'status': ready ? 'ready' : 'blocked',
    'ready': ready,
    'readyGateIds': ready ? <String>['default_off_confirmed'] : <String>[],
    'blockedGateIds': ready ? <String>[] : <String>['default_off_confirmed'],
    'userOperatedGateIds': <String>['default_off_confirmed'],
    'releaseRolloutSummary': <String, Object?>{
      'status': ready ? 'ready_for_product_release' : 'blocked_gates_present',
      'readyGateIds': ready ? <String>['default_off_confirmed'] : <String>[],
      'blockedGateIds': ready ? <String>[] : <String>['default_off_confirmed'],
      'blockedUserOperatedGateIds': ready
          ? <String>[]
          : <String>['default_off_confirmed'],
      'blockedAutomationSafeGateIds': <String>[],
      'operationBoundarySummary': 'M52 reads release rollout evidence only.',
    },
    'm52ProductReleaseGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready ? <String>[] : <String>['default_off_confirmed'],
      'nextAction': ready
          ? 'Ship element-grounded Computer Use through the product release rollout.'
          : 'Resolve blocked M52 product release rollout gates before shipping.',
    },
    'gates': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'default_off_confirmed',
        'label': 'Default-off release',
        'status': ready ? 'ready' : 'missing',
        'ready': ready,
        'nextAction': ready
            ? 'Default-off release evidence is ready.'
            : 'Ask the user to confirm default-off release behavior.',
        'userOperated': true,
      },
    ],
  };
}

Map<String, dynamic> _m53PostReleaseGuardrails({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m53_post_release_guardrails',
    'schemaVersion': 1,
    'milestone': 'M53',
    'automationBoundary': 'read_reports_only',
    'tccBoundary': 'user_operated',
    'desktopActionBoundary': 'user_operated',
    'status': ready ? 'ready' : 'blocked',
    'ready': ready,
    'readyGateIds': ready
        ? <String>['support_diagnostics_reviewed']
        : <String>[],
    'blockedGateIds': ready
        ? <String>[]
        : <String>['support_diagnostics_reviewed'],
    'userOperatedGateIds': <String>['support_diagnostics_reviewed'],
    'postReleaseGuardrailsSummary': <String, Object?>{
      'status': ready
          ? 'ready_for_post_release_operations'
          : 'blocked_gates_present',
      'readyGateIds': ready
          ? <String>['support_diagnostics_reviewed']
          : <String>[],
      'blockedGateIds': ready
          ? <String>[]
          : <String>['support_diagnostics_reviewed'],
      'blockedUserOperatedGateIds': ready
          ? <String>[]
          : <String>['support_diagnostics_reviewed'],
      'blockedAutomationSafeGateIds': <String>[],
      'operationBoundarySummary':
          'M53 reads post-release guardrail evidence only.',
    },
    'm53PostReleaseGuardrailsGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready ? <String>[] : <String>['support_diagnostics_reviewed'],
      'nextAction': ready
          ? 'Keep Computer Use post-release guardrails on the scheduled review cadence.'
          : 'Resolve blocked M53 post-release guardrail gates before continuing rollout expansion.',
    },
    'gates': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'support_diagnostics_reviewed',
        'label': 'Support diagnostics review',
        'status': ready ? 'ready' : 'missing',
        'ready': ready,
        'nextAction': ready
            ? 'Support diagnostics review evidence is ready.'
            : 'Ask the user to review redacted support diagnostics.',
        'userOperated': true,
      },
    ],
  };
}

Map<String, dynamic> _m54RolloutExpansionGate({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m54_rollout_expansion_gate',
    'schemaVersion': 1,
    'milestone': 'M54',
    'automationBoundary': 'read_reports_only',
    'tccBoundary': 'user_operated',
    'desktopActionBoundary': 'user_operated',
    'status': ready ? 'ready' : 'blocked',
    'ready': ready,
    'readyGateIds': ready ? <String>['expansion_scope_approved'] : <String>[],
    'blockedGateIds': ready ? <String>[] : <String>['expansion_scope_approved'],
    'userOperatedGateIds': <String>['expansion_scope_approved'],
    'rolloutExpansionSummary': <String, Object?>{
      'status': ready ? 'ready_for_rollout_expansion' : 'blocked_gates_present',
      'readyGateIds': ready ? <String>['expansion_scope_approved'] : <String>[],
      'blockedGateIds': ready
          ? <String>[]
          : <String>['expansion_scope_approved'],
      'blockedUserOperatedGateIds': ready
          ? <String>[]
          : <String>['expansion_scope_approved'],
      'blockedAutomationSafeGateIds': <String>[],
      'operationBoundarySummary': 'M54 reads rollout expansion evidence only.',
    },
    'm54RolloutExpansionGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': ready ? <String>[] : <String>['expansion_scope_approved'],
      'nextAction': ready
          ? 'Expand Computer Use rollout only within the approved cohort and review cadence.'
          : 'Resolve blocked M54 rollout expansion gates before expanding rollout.',
    },
    'gates': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'expansion_scope_approved',
        'label': 'Expansion scope',
        'status': ready ? 'ready' : 'missing',
        'ready': ready,
        'nextAction': ready
            ? 'Expansion scope evidence is ready.'
            : 'Ask the user to approve the rollout expansion scope.',
        'userOperated': true,
      },
    ],
  };
}

Map<String, dynamic> _m55PostExpansionMonitoringGate({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m55_post_expansion_monitoring_gate',
    'schemaVersion': 1,
    'milestone': 'M55',
    'automationBoundary': 'read_reports_only',
    'tccBoundary': 'user_operated',
    'desktopActionBoundary': 'user_operated',
    'status': ready ? 'ready' : 'blocked',
    'ready': ready,
    'rolloutContinuationDecision': ready ? 'continue_expansion' : 'unknown',
    'readyGateIds': ready ? <String>['safety_metrics_reviewed'] : <String>[],
    'blockedGateIds': ready ? <String>[] : <String>['safety_metrics_reviewed'],
    'userOperatedGateIds': <String>['safety_metrics_reviewed'],
    'postExpansionMonitoringSummary': <String, Object?>{
      'status': ready
          ? 'ready_for_post_expansion_decision'
          : 'blocked_gates_present',
      'rolloutContinuationDecision': ready ? 'continue_expansion' : 'unknown',
      'readyGateIds': ready ? <String>['safety_metrics_reviewed'] : <String>[],
      'blockedGateIds': ready
          ? <String>[]
          : <String>['safety_metrics_reviewed'],
      'blockedUserOperatedGateIds': ready
          ? <String>[]
          : <String>['safety_metrics_reviewed'],
      'blockedAutomationSafeGateIds': <String>[],
      'operationBoundarySummary':
          'M55 reads post-expansion monitoring evidence only.',
    },
    'm55PostExpansionMonitoringGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'rolloutContinuationDecision': ready ? 'continue_expansion' : 'unknown',
      'blockers': ready ? <String>[] : <String>['safety_metrics_reviewed'],
      'nextAction': ready
          ? 'Continue Computer Use rollout only within the approved monitoring cadence.'
          : 'Resolve blocked M55 post-expansion monitoring gates before changing rollout state.',
    },
    'gates': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'safety_metrics_reviewed',
        'label': 'Safety metrics review',
        'status': ready ? 'ready' : 'missing',
        'ready': ready,
        'nextAction': ready
            ? 'Safety metrics review evidence is ready.'
            : 'Ask the user to review post-expansion safety metrics.',
        'userOperated': true,
      },
    ],
  };
}

Map<String, dynamic> _m56RolloutDecisionHandoffGate({required bool ready}) {
  return <String, dynamic>{
    'schemaName': 'macos_computer_use_m56_rollout_decision_handoff_gate',
    'schemaVersion': 1,
    'milestone': 'M56',
    'automationBoundary': 'read_reports_only',
    'tccBoundary': 'user_operated',
    'desktopActionBoundary': 'user_operated',
    'status': ready ? 'ready' : 'blocked',
    'ready': ready,
    'rolloutContinuationDecision': ready ? 'continue_expansion' : 'unknown',
    'decisionHandoffType': ready ? 'next_expansion_cycle_seed' : 'unknown',
    'readyGateIds': ready
        ? <String>['m55_post_expansion_monitoring_gate']
        : <String>[],
    'blockedGateIds': ready ? <String>[] : <String>['decision_branch_handoff'],
    'userOperatedGateIds': <String>['decision_branch_handoff'],
    'rolloutDecisionHandoffSummary': <String, Object?>{
      'status': ready
          ? 'ready_for_rollout_decision_handoff'
          : 'blocked_gates_present',
      'rolloutContinuationDecision': ready ? 'continue_expansion' : 'unknown',
      'decisionHandoffType': ready ? 'next_expansion_cycle_seed' : 'unknown',
      'readyGateIds': ready
          ? <String>['m55_post_expansion_monitoring_gate']
          : <String>[],
      'blockedGateIds': ready
          ? <String>[]
          : <String>['decision_branch_handoff'],
      'blockedUserOperatedGateIds': ready
          ? <String>[]
          : <String>['decision_branch_handoff'],
      'blockedAutomationSafeGateIds': <String>[],
      'operationBoundarySummary':
          'M56 reads M55 post-expansion monitoring evidence and rollout decision handoff checklist evidence only.',
    },
    'm56RolloutDecisionHandoffGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'rolloutContinuationDecision': ready ? 'continue_expansion' : 'unknown',
      'decisionHandoffType': ready ? 'next_expansion_cycle_seed' : 'unknown',
      'blockers': ready ? <String>[] : <String>['decision_branch_handoff'],
      'nextAction': ready
          ? 'Prepare the next user-operated M54 rollout expansion cycle seed.'
          : 'Resolve blocked M56 rollout decision handoff gates before changing rollout state.',
    },
    'gates': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'decision_branch_handoff',
        'label': 'Decision branch handoff',
        'status': ready ? 'ready' : 'missing',
        'ready': ready,
        'nextAction': ready
            ? 'Decision branch handoff evidence is ready.'
            : 'Ask the user to provide a branch handoff that matches the M55 rollout decision.',
        'userOperated': true,
      },
    ],
  };
}

List<ReadinessArtifactEntry> _requiredReadyEntries(Directory root) {
  return MacosComputerUseMvpGuidance.requiredEvidenceIds
      .map(
        (id) => ReadinessArtifactEntry(
          id: id,
          label: id,
          path: '${root.path}/$id.json',
          exists: true,
          status: 'ready',
        ),
      )
      .toList(growable: false);
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

void _writeReadyManualTccSummary(File file) {
  final manualTccPath = file.path;
  _writeJson(file, <String, Object?>{
    'schemaName': 'macos_computer_use_manual_tcc_report_summary',
    'schemaVersion': 1,
    'automationBoundary': 'parse_user_produced_report_only',
    'reportPath': '${file.parent.parent.path}/raw_m8_report.json',
    'evidencePath': manualTccPath,
    'status': 'ready',
    'ready': true,
    'blockers': <String>[],
    'failureClasses': <String>[],
    'appPath': '/tmp/Caverno.app',
    'helperPath': '/tmp/Caverno Computer Use.app',
    'nextAutomationSafeCommands': <String, Object?>{
      'releaseReadinessSignoff':
          'bash tool/run_macos_computer_use_release_readiness.sh --signoff --manual-tcc-report $manualTccPath',
      'nextStepNavigator':
          'dart run tool/macos_computer_use_next_step_navigator.dart --root build/integration_test_reports',
    },
    'checks': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'permission_status',
        'label': 'Permission status',
        'status': 'ready',
        'ok': true,
      },
    ],
  });
}
