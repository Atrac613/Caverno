import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_tool_process.dart';

import '../../integration_test/test_support/macos_computer_use_m54_rollout_expansion_gate.dart';

void main() {
  group('macOS Computer Use M54 rollout expansion gate', () {
    test('builds a ready rollout expansion summary from ready evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m54_expansion_ready_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final checklistPath = _writeJson(
        '${root.path}/manual/m54_rollout_expansion_checklist.json',
        _rolloutExpansionChecklist(),
      );
      final m53Path = _writeJson(
        '${root.path}/macos_computer_use_m53_post_release_guardrails_1/macos_computer_use_m53_post_release_guardrails.json',
        _m53PostReleaseGuardrails(),
      );

      final inputs = readMacosComputerUseM54RolloutExpansionInputs(
        reportRoot: root,
      );
      final summary = buildMacosComputerUseM54RolloutExpansionSummary(inputs);
      final json = summary.toJson();
      final markdown = summary.toMarkdown();

      expect(inputs.rolloutExpansionChecklistPath, checklistPath);
      expect(inputs.m53PostReleaseGuardrailsPath, m53Path);
      expect(summary.ready, isTrue);
      expect(summary.blockedGates, isEmpty);
      expect(
        json['schemaName'],
        'macos_computer_use_m54_rollout_expansion_gate',
      );
      expect(json['automationBoundary'], 'read_reports_only');
      expect(json['tccBoundary'], 'user_operated');
      expect(json['desktopActionBoundary'], 'user_operated');
      expect(json['userOperatedGateIds'], contains('expansion_scope_approved'));
      expect(
        summary.rolloutExpansionSummary['status'],
        'ready_for_rollout_expansion',
      );
      expect(summary.m54RolloutExpansionGate['status'], 'ready');
      expect(markdown, contains('M54 Rollout Expansion Gate'));
      expect(markdown, contains('Expansion scope'));
      expect(markdown, contains('Support capacity'));
    });

    test('blocks rollout expansion gates when the checklist is missing', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m54_expansion_blocked_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      _writeJson(
        '${root.path}/macos_computer_use_m53_post_release_guardrails_1/macos_computer_use_m53_post_release_guardrails.json',
        _m53PostReleaseGuardrails(),
      );

      final summary = buildMacosComputerUseM54RolloutExpansionSummary(
        readMacosComputerUseM54RolloutExpansionInputs(reportRoot: root),
      );
      final blockedIds = summary.blockedGates
          .map((gate) => gate.id)
          .toList(growable: false);

      expect(summary.ready, isFalse);
      expect(blockedIds, contains('expansion_scope_approved'));
      expect(blockedIds, contains('cohort_risk_reviewed'));
      expect(blockedIds, contains('support_capacity_reviewed'));
      expect(blockedIds, contains('next_review_scheduled'));
      expect(blockedIds, isNot(contains('m53_post_release_guardrails')));
      expect(
        summary.rolloutExpansionSummary['blockedUserOperatedGateIds'],
        contains('safety_metrics_reviewed'),
      );
    });

    test('blocks expansion when M53 post-release guardrails are blocked', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m54_expansion_m53_blocked_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      _writeJson(
        '${root.path}/manual/m54_rollout_expansion_checklist.json',
        _rolloutExpansionChecklist(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m53_post_release_guardrails_1/macos_computer_use_m53_post_release_guardrails.json',
        _m53PostReleaseGuardrails(ready: false),
      );

      final summary = buildMacosComputerUseM54RolloutExpansionSummary(
        readMacosComputerUseM54RolloutExpansionInputs(reportRoot: root),
      );

      expect(summary.ready, isFalse);
      final m53Gate = summary.gates.singleWhere(
        (gate) => gate.id == 'm53_post_release_guardrails',
      );
      expect(m53Gate.ready, isFalse);
      expect(
        m53Gate.details['blockers'],
        contains('support_diagnostics_reviewed'),
      );
    });

    test(
      'CLI writes JSON and Markdown summaries',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_m54_expansion_cli_',
        );
        addTearDown(() => root.deleteSync(recursive: true));

        final checklistPath = _writeJson(
          '${root.path}/manual/m54_rollout_expansion_checklist.json',
          _rolloutExpansionChecklist(),
        );
        final m53Path = _writeJson(
          '${root.path}/m53.json',
          _m53PostReleaseGuardrails(),
        );
        final outputJson = '${root.path}/out/m54.json';
        final outputMd = '${root.path}/out/m54.md';

        final result = await runDartTool(
          'tool/macos_computer_use_m54_rollout_expansion_gate.dart',
          <String>[
            '--root',
            root.path,
            '--rollout-expansion-checklist',
            checklistPath,
            '--m53-post-release-guardrails',
            m53Path,
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
          contains('Rollout Expansion Summary'),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('wrapper and docs keep M54 report-only boundaries visible', () {
      final wrapper = File(
        'tool/run_macos_computer_use_m54_rollout_expansion_gate.sh',
      ).readAsStringSync();
      final architecture = File(
        'docs/macos_computer_use_helper_architecture.md',
      ).readAsStringSync();
      final checklist = File(
        'docs/macos_computer_use_manual_process_checklist.md',
      ).readAsStringSync();

      expect(wrapper, contains('report-only'));
      expect(wrapper, contains('rollout expansion checklist evidence'));
      expect(wrapper, contains('no desktop actions'));
      expect(
        architecture,
        contains('macos_computer_use_m54_rollout_expansion_gate'),
      );
      expect(checklist, contains('M54 Rollout Expansion Gate'));
      expect(checklist, contains('ready_for_rollout_expansion'));
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

Map<String, Object?> _rolloutExpansionChecklist() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m54_rollout_expansion_checklist',
    'schemaVersion': 1,
    'milestone': 'M54',
    'automationBoundary': 'user_operated_rollout_expansion_steps',
    'expansionScopeApproved': _readySection(
      'Approved cohort expansion scope confirmed.',
    ),
    'cohortRiskReviewed': _readySection(
      'Cohort risk and excluded segments reviewed.',
    ),
    'supportCapacityReviewed': _readySection(
      'Support capacity and escalation coverage reviewed.',
    ),
    'safetyMetricsReviewed': _readySection(
      'Safety, incident, complaint, and regression metrics reviewed.',
    ),
    'rollbackPauseReady': _readySection(
      'Rollback, rollout pause, disable path, and emergency stop remain ready.',
    ),
    'communicationsReviewed': _readySection(
      'Release notes, support copy, and user communication reviewed.',
    ),
    'ownerEscalationReviewed': _readySection(
      'Rollout owner, support owner, and escalation handoff reviewed.',
    ),
    'nextReviewScheduled': _readySection(
      'Next post-expansion review scheduled.',
    ),
  };
}

Map<String, Object?> _m53PostReleaseGuardrails({bool ready = true}) {
  final blockedGateIds = ready
      ? <String>[]
      : <String>['support_diagnostics_reviewed'];
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m53_post_release_guardrails',
    'schemaVersion': 1,
    'milestone': 'M53',
    'status': ready ? 'ready' : 'blocked',
    'ready': ready,
    'readyGateIds': ready
        ? <String>[
            'm52_product_release_rollout',
            'support_diagnostics_reviewed',
          ]
        : <String>['m52_product_release_rollout'],
    'blockedGateIds': blockedGateIds,
    'postReleaseGuardrailsSummary': <String, Object?>{
      'status': ready
          ? 'ready_for_post_release_operations'
          : 'blocked_gates_present',
      'readyGateIds': ready
          ? <String>[
              'm52_product_release_rollout',
              'support_diagnostics_reviewed',
            ]
          : <String>['m52_product_release_rollout'],
      'blockedGateIds': blockedGateIds,
      'blockedUserOperatedGateIds': blockedGateIds,
      'blockedAutomationSafeGateIds': <String>[],
      'operationBoundarySummary':
          'M53 reads post-release guardrail evidence only.',
    },
    'm53PostReleaseGuardrailsGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': blockedGateIds,
      'nextAction': ready
          ? 'Keep Computer Use post-release guardrails on the scheduled review cadence.'
          : 'Resolve blocked M53 post-release guardrail gates before continuing rollout expansion.',
    },
    'gates': <Object?>[],
  };
}
