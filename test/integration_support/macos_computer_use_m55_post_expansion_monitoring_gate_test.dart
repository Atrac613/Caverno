import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/macos_computer_use_m55_post_expansion_monitoring_gate.dart';

void main() {
  group('macOS Computer Use M55 post-expansion monitoring gate', () {
    test(
      'builds a ready post-expansion monitoring summary from ready evidence',
      () {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_m55_monitoring_ready_',
        );
        addTearDown(() => root.deleteSync(recursive: true));

        final checklistPath = _writeJson(
          '${root.path}/manual/m55_post_expansion_monitoring_checklist.json',
          _postExpansionMonitoringChecklist(),
        );
        final m54Path = _writeJson(
          '${root.path}/macos_computer_use_m54_rollout_expansion_gate_1/macos_computer_use_m54_rollout_expansion_gate.json',
          _m54RolloutExpansionGate(),
        );

        final inputs = readMacosComputerUseM55PostExpansionMonitoringInputs(
          reportRoot: root,
        );
        final summary = buildMacosComputerUseM55PostExpansionMonitoringSummary(
          inputs,
        );
        final json = summary.toJson();
        final markdown = summary.toMarkdown();

        expect(inputs.postExpansionMonitoringChecklistPath, checklistPath);
        expect(inputs.m54RolloutExpansionGatePath, m54Path);
        expect(summary.ready, isTrue);
        expect(summary.blockedGates, isEmpty);
        expect(
          json['schemaName'],
          'macos_computer_use_m55_post_expansion_monitoring_gate',
        );
        expect(json['automationBoundary'], 'read_reports_only');
        expect(json['tccBoundary'], 'user_operated');
        expect(json['desktopActionBoundary'], 'user_operated');
        expect(
          json['userOperatedGateIds'],
          contains('expansion_scope_observed'),
        );
        expect(json['rolloutContinuationDecision'], 'continue_expansion');
        expect(
          summary.postExpansionMonitoringSummary['status'],
          'ready_for_post_expansion_decision',
        );
        expect(summary.m55PostExpansionMonitoringGate['status'], 'ready');
        expect(markdown, contains('M55 Post-Expansion Monitoring Gate'));
        expect(markdown, contains('Expansion scope observed'));
        expect(markdown, contains('Support load review'));
      },
    );

    test(
      'blocks post-expansion monitoring gates when the checklist is missing',
      () {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_m55_monitoring_blocked_',
        );
        addTearDown(() => root.deleteSync(recursive: true));

        _writeJson(
          '${root.path}/macos_computer_use_m54_rollout_expansion_gate_1/macos_computer_use_m54_rollout_expansion_gate.json',
          _m54RolloutExpansionGate(),
        );

        final summary = buildMacosComputerUseM55PostExpansionMonitoringSummary(
          readMacosComputerUseM55PostExpansionMonitoringInputs(
            reportRoot: root,
          ),
        );
        final blockedIds = summary.blockedGates
            .map((gate) => gate.id)
            .toList(growable: false);

        expect(summary.ready, isFalse);
        expect(blockedIds, contains('expansion_scope_observed'));
        expect(blockedIds, contains('support_load_reviewed'));
        expect(blockedIds, contains('continuation_decision_approved'));
        expect(blockedIds, contains('next_review_scheduled'));
        expect(blockedIds, isNot(contains('m54_rollout_expansion_gate')));
        expect(
          summary.postExpansionMonitoringSummary['blockedUserOperatedGateIds'],
          contains('safety_metrics_reviewed'),
        );
      },
    );

    test('blocks monitoring when M54 rollout expansion gate is blocked', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m55_monitoring_m54_blocked_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      _writeJson(
        '${root.path}/manual/m55_post_expansion_monitoring_checklist.json',
        _postExpansionMonitoringChecklist(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m54_rollout_expansion_gate_1/macos_computer_use_m54_rollout_expansion_gate.json',
        _m54RolloutExpansionGate(ready: false),
      );

      final summary = buildMacosComputerUseM55PostExpansionMonitoringSummary(
        readMacosComputerUseM55PostExpansionMonitoringInputs(reportRoot: root),
      );

      expect(summary.ready, isFalse);
      final m54Gate = summary.gates.singleWhere(
        (gate) => gate.id == 'm54_rollout_expansion_gate',
      );
      expect(m54Gate.ready, isFalse);
      expect(m54Gate.details['blockers'], contains('safety_metrics_reviewed'));
    });

    test(
      'CLI writes JSON and Markdown summaries',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_m55_monitoring_cli_',
        );
        addTearDown(() => root.deleteSync(recursive: true));

        final checklistPath = _writeJson(
          '${root.path}/manual/m55_post_expansion_monitoring_checklist.json',
          _postExpansionMonitoringChecklist(),
        );
        final m54Path = _writeJson(
          '${root.path}/m54.json',
          _m54RolloutExpansionGate(),
        );
        final outputJson = '${root.path}/out/m55.json';
        final outputMd = '${root.path}/out/m55.md';

        final result = await Process.run('dart', <String>[
          'run',
          'tool/macos_computer_use_m55_post_expansion_monitoring_gate.dart',
          '--root',
          root.path,
          '--post-expansion-monitoring-checklist',
          checklistPath,
          '--m54-rollout-expansion-gate',
          m54Path,
          '--output-json',
          outputJson,
          '--output-md',
          outputMd,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final summary = jsonDecode(File(outputJson).readAsStringSync()) as Map;
        expect(summary['ready'], isTrue);
        expect(
          File(outputMd).readAsStringSync(),
          contains('Post-Expansion Monitoring Summary'),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('wrapper and docs keep M55 report-only boundaries visible', () {
      final wrapper = File(
        'tool/run_macos_computer_use_m55_post_expansion_monitoring_gate.sh',
      ).readAsStringSync();
      final architecture = File(
        'docs/macos_computer_use_helper_architecture.md',
      ).readAsStringSync();
      final checklist = File(
        'docs/macos_computer_use_manual_process_checklist.md',
      ).readAsStringSync();

      expect(wrapper, contains('report-only'));
      expect(wrapper, contains('post-expansion monitoring checklist evidence'));
      expect(wrapper, contains('no desktop actions'));
      expect(
        architecture,
        contains('macos_computer_use_m55_post_expansion_monitoring_gate'),
      );
      expect(checklist, contains('M55 Post-Expansion Monitoring Gate'));
      expect(checklist, contains('ready_for_post_expansion_decision'));
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

Map<String, Object?> _postExpansionMonitoringChecklist() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m55_post_expansion_monitoring_checklist',
    'schemaVersion': 1,
    'milestone': 'M55',
    'automationBoundary': 'user_operated_post_expansion_monitoring_steps',
    'expansionScopeObserved': _readySection(
      'Expanded cohort and monitoring window observed.',
    ),
    'safetyMetricsReviewed': _readySection(
      'Post-expansion safety metrics reviewed.',
    ),
    'supportLoadReviewed': _readySection(
      'Support volume, response time, and escalation load reviewed.',
    ),
    'incidentComplaintReviewed': _readySection(
      'Incidents, complaints, regressions, and user-impacting failures reviewed.',
    ),
    'rollbackPauseReviewed': _readySection(
      'Rollback, rollout pause, disable path, hotfix, and emergency stop reviewed.',
    ),
    'continuationDecisionApproved': <String, Object?>{
      ..._readySection('Continuation decision approved.'),
      'decision': 'continue_expansion',
    },
    'ownerFollowupReviewed': _readySection(
      'Rollout owner, support owner, follow-up, and escalation handoff reviewed.',
    ),
    'nextReviewScheduled': _readySection('Next monitoring review scheduled.'),
  };
}

Map<String, Object?> _m54RolloutExpansionGate({bool ready = true}) {
  final blockedGateIds = ready
      ? <String>[]
      : <String>['safety_metrics_reviewed'];
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m54_rollout_expansion_gate',
    'schemaVersion': 1,
    'milestone': 'M54',
    'status': ready ? 'ready' : 'blocked',
    'ready': ready,
    'readyGateIds': ready
        ? <String>['m53_post_release_guardrails', 'safety_metrics_reviewed']
        : <String>['m53_post_release_guardrails'],
    'blockedGateIds': blockedGateIds,
    'rolloutExpansionSummary': <String, Object?>{
      'status': ready ? 'ready_for_rollout_expansion' : 'blocked_gates_present',
      'readyGateIds': ready
          ? <String>['m53_post_release_guardrails', 'safety_metrics_reviewed']
          : <String>['m53_post_release_guardrails'],
      'blockedGateIds': blockedGateIds,
      'blockedUserOperatedGateIds': blockedGateIds,
      'blockedAutomationSafeGateIds': <String>[],
      'operationBoundarySummary': 'M54 reads rollout expansion evidence only.',
    },
    'm54RolloutExpansionGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': blockedGateIds,
      'nextAction': ready
          ? 'Expand Computer Use rollout only within the approved cohort and review cadence.'
          : 'Resolve blocked M54 rollout expansion gates before expanding rollout.',
    },
    'gates': <Object?>[],
  };
}
