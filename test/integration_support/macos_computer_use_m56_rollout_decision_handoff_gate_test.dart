import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_tool_process.dart';

import '../../integration_test/test_support/macos_computer_use_m56_rollout_decision_handoff_gate.dart';

void main() {
  group('macOS Computer Use M56 rollout decision handoff gate', () {
    test(
      'builds a ready rollout decision handoff summary from ready evidence',
      () {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_m56_handoff_ready_',
        );
        addTearDown(() => root.deleteSync(recursive: true));

        final checklistPath = _writeJson(
          '${root.path}/manual/m56_rollout_decision_handoff_checklist.json',
          _rolloutDecisionHandoffChecklist(),
        );
        final m55Path = _writeJson(
          '${root.path}/macos_computer_use_m55_post_expansion_monitoring_gate_1/macos_computer_use_m55_post_expansion_monitoring_gate.json',
          _m55PostExpansionMonitoringGate(),
        );

        final inputs = readMacosComputerUseM56RolloutDecisionHandoffInputs(
          reportRoot: root,
        );
        final summary = buildMacosComputerUseM56RolloutDecisionHandoffSummary(
          inputs,
        );
        final json = summary.toJson();
        final markdown = summary.toMarkdown();

        expect(inputs.rolloutDecisionHandoffChecklistPath, checklistPath);
        expect(inputs.m55PostExpansionMonitoringGatePath, m55Path);
        expect(summary.ready, isTrue);
        expect(summary.blockedGates, isEmpty);
        expect(
          json['schemaName'],
          'macos_computer_use_m56_rollout_decision_handoff_gate',
        );
        expect(json['automationBoundary'], 'read_reports_only');
        expect(json['tccBoundary'], 'user_operated');
        expect(json['desktopActionBoundary'], 'user_operated');
        expect(
          json['userOperatedGateIds'],
          contains('decision_branch_handoff'),
        );
        expect(json['rolloutContinuationDecision'], 'continue_expansion');
        expect(json['decisionHandoffType'], 'next_expansion_cycle_seed');
        expect(
          summary.rolloutDecisionHandoffSummary['status'],
          'ready_for_rollout_decision_handoff',
        );
        expect(summary.m56RolloutDecisionHandoffGate['status'], 'ready');
        expect(markdown, contains('M56 Rollout Decision Handoff Gate'));
        expect(markdown, contains('Decision branch handoff'));
        expect(markdown, contains('next_expansion_cycle_seed'));
      },
    );

    test(
      'blocks rollout decision handoff gates when the checklist is missing',
      () {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_m56_handoff_blocked_',
        );
        addTearDown(() => root.deleteSync(recursive: true));

        _writeJson(
          '${root.path}/macos_computer_use_m55_post_expansion_monitoring_gate_1/macos_computer_use_m55_post_expansion_monitoring_gate.json',
          _m55PostExpansionMonitoringGate(),
        );

        final summary = buildMacosComputerUseM56RolloutDecisionHandoffSummary(
          readMacosComputerUseM56RolloutDecisionHandoffInputs(reportRoot: root),
        );
        final blockedIds = summary.blockedGates
            .map((gate) => gate.id)
            .toList(growable: false);

        expect(summary.ready, isFalse);
        expect(blockedIds, contains('decision_scope_confirmed'));
        expect(blockedIds, contains('decision_branch_handoff'));
        expect(blockedIds, contains('handoff_owner_confirmed'));
        expect(blockedIds, contains('next_review_scheduled'));
        expect(
          blockedIds,
          isNot(contains('m55_post_expansion_monitoring_gate')),
        );
        expect(
          summary.rolloutDecisionHandoffSummary['blockedUserOperatedGateIds'],
          contains('decision_branch_handoff'),
        );
      },
    );

    test('blocks handoff when M55 post-expansion monitoring gate is blocked', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m56_handoff_m55_blocked_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      _writeJson(
        '${root.path}/manual/m56_rollout_decision_handoff_checklist.json',
        _rolloutDecisionHandoffChecklist(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m55_post_expansion_monitoring_gate_1/macos_computer_use_m55_post_expansion_monitoring_gate.json',
        _m55PostExpansionMonitoringGate(ready: false),
      );

      final summary = buildMacosComputerUseM56RolloutDecisionHandoffSummary(
        readMacosComputerUseM56RolloutDecisionHandoffInputs(reportRoot: root),
      );

      expect(summary.ready, isFalse);
      final m55Gate = summary.gates.singleWhere(
        (gate) => gate.id == 'm55_post_expansion_monitoring_gate',
      );
      expect(m55Gate.ready, isFalse);
      expect(m55Gate.details['blockers'], contains('safety_metrics_reviewed'));
    });

    test('blocks handoff when branch does not match the M55 decision', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m56_handoff_mismatch_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      _writeJson(
        '${root.path}/manual/m56_rollout_decision_handoff_checklist.json',
        _rolloutDecisionHandoffChecklist(
          decision: 'pause_rollout',
          handoffType: 'rollout_pause_handoff',
        ),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m55_post_expansion_monitoring_gate_1/macos_computer_use_m55_post_expansion_monitoring_gate.json',
        _m55PostExpansionMonitoringGate(decision: 'continue_expansion'),
      );

      final summary = buildMacosComputerUseM56RolloutDecisionHandoffSummary(
        readMacosComputerUseM56RolloutDecisionHandoffInputs(reportRoot: root),
      );

      expect(summary.ready, isFalse);
      final handoffGate = summary.gates.singleWhere(
        (gate) => gate.id == 'decision_branch_handoff',
      );
      expect(handoffGate.ready, isFalse);
      expect(
        handoffGate.details['sourceRolloutContinuationDecision'],
        'continue_expansion',
      );
      expect(
        handoffGate.details['rolloutContinuationDecision'],
        'pause_rollout',
      );
    });

    test(
      'CLI writes JSON and Markdown summaries',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_m56_handoff_cli_',
        );
        addTearDown(() => root.deleteSync(recursive: true));

        final checklistPath = _writeJson(
          '${root.path}/manual/m56_rollout_decision_handoff_checklist.json',
          _rolloutDecisionHandoffChecklist(),
        );
        final m55Path = _writeJson(
          '${root.path}/m55.json',
          _m55PostExpansionMonitoringGate(),
        );
        final outputJson = '${root.path}/out/m56.json';
        final outputMd = '${root.path}/out/m56.md';

        final result = await runDartTool(
          'tool/macos_computer_use_m56_rollout_decision_handoff_gate.dart',
          <String>[
            '--root',
            root.path,
            '--rollout-decision-handoff-checklist',
            checklistPath,
            '--m55-post-expansion-monitoring-gate',
            m55Path,
            '--output-json',
            outputJson,
            '--output-md',
            outputMd,
          ],
        );

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final summary = jsonDecode(File(outputJson).readAsStringSync()) as Map;
        expect(summary['ready'], isTrue);
        expect(
          File(outputMd).readAsStringSync(),
          contains('Rollout Decision Handoff Summary'),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('wrapper and docs keep M56 report-only boundaries visible', () {
      final wrapper = File(
        'tool/run_macos_computer_use_m56_rollout_decision_handoff_gate.sh',
      ).readAsStringSync();
      final architecture = File(
        'docs/macos_computer_use_helper_architecture.md',
      ).readAsStringSync();
      final checklist = File(
        'docs/macos_computer_use_manual_process_checklist.md',
      ).readAsStringSync();

      expect(wrapper, contains('report-only'));
      expect(wrapper, contains('rollout decision handoff checklist evidence'));
      expect(wrapper, contains('no desktop actions'));
      expect(
        architecture,
        contains('macos_computer_use_m56_rollout_decision_handoff_gate'),
      );
      expect(checklist, contains('M56 Rollout Decision Handoff Gate'));
      expect(checklist, contains('ready_for_rollout_decision_handoff'));
    });
  });
}

String _writeJson(String path, Map<String, Object?> json) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  return file.path;
}

Map<String, Object?> _readySection(String evidence) {
  return <String, Object?>{
    'status': 'ready',
    'ready': true,
    'evidence': evidence,
  };
}

Map<String, Object?> _rolloutDecisionHandoffChecklist({
  String decision = 'continue_expansion',
  String handoffType = 'next_expansion_cycle_seed',
}) {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m56_rollout_decision_handoff_checklist',
    'schemaVersion': 1,
    'milestone': 'M56',
    'automationBoundary': 'user_operated_rollout_decision_handoff_steps',
    'decisionScopeConfirmed': _readySection(
      'M55 decision scope and affected cohort confirmed.',
    ),
    'decisionBranchHandoff': <String, Object?>{
      ..._readySection('Decision branch handoff reviewed.'),
      'decision': decision,
      'handoffType': handoffType,
    },
    'handoffOwnerConfirmed': _readySection('Handoff owner confirmed.'),
    'evidenceArchiveReady': _readySection('M55 evidence archive is ready.'),
    'userCommunicationReviewed': _readySection(
      'Decision branch communication reviewed.',
    ),
    'riskControlsConfirmed': _readySection('Branch risk controls confirmed.'),
    'nextReviewScheduled': _readySection('Next handoff review scheduled.'),
  };
}

Map<String, Object?> _m55PostExpansionMonitoringGate({
  bool ready = true,
  String decision = 'continue_expansion',
}) {
  final blockedGateIds = ready
      ? <String>[]
      : <String>['safety_metrics_reviewed'];
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m55_post_expansion_monitoring_gate',
    'schemaVersion': 1,
    'milestone': 'M55',
    'status': ready ? 'ready' : 'blocked',
    'ready': ready,
    'rolloutContinuationDecision': ready ? decision : 'unknown',
    'readyGateIds': ready
        ? <String>['m54_rollout_expansion_gate', 'safety_metrics_reviewed']
        : <String>['m54_rollout_expansion_gate'],
    'blockedGateIds': blockedGateIds,
    'postExpansionMonitoringSummary': <String, Object?>{
      'status': ready
          ? 'ready_for_post_expansion_decision'
          : 'blocked_gates_present',
      'rolloutContinuationDecision': ready ? decision : 'unknown',
      'readyGateIds': ready
          ? <String>['m54_rollout_expansion_gate', 'safety_metrics_reviewed']
          : <String>['m54_rollout_expansion_gate'],
      'blockedGateIds': blockedGateIds,
      'blockedUserOperatedGateIds': blockedGateIds,
      'blockedAutomationSafeGateIds': <String>[],
      'operationBoundarySummary':
          'M55 reads post-expansion monitoring evidence only.',
    },
    'm55PostExpansionMonitoringGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'rolloutContinuationDecision': ready ? decision : 'unknown',
      'blockers': blockedGateIds,
      'nextAction': ready
          ? 'Continue Computer Use rollout only within the approved monitoring cadence.'
          : 'Resolve blocked M55 post-expansion monitoring gates before changing rollout state.',
    },
    'gates': <Object?>[],
  };
}
