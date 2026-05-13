import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/macos_computer_use_beta_signoff.dart';

void main() {
  group('macOS Computer Use M39 beta sign-off', () {
    test('builds a ready internal beta summary from ready evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m39_beta_ready_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final checklistPath = _writeJson(
        '${root.path}/manual/m39_manual_beta_checklist.json',
        _manualChecklist(),
      );
      final m36Path = _writeJson(
        '${root.path}/macos_computer_use_m36_live_llm_eval_1/canary_summary.json',
        _m36LiveLlmEvalSummary(),
      );
      final m23Path = _writeJson(
        '${root.path}/macos_computer_use_m23_cycle_outcome_handoff_1/cycle_outcome_handoff.json',
        _m23CycleOutcomeHandoff(),
      );

      final inputs = readMacosComputerUseBetaSignoffInputs(reportRoot: root);
      final summary = buildMacosComputerUseBetaSignoffSummary(inputs);
      final json = summary.toJson();
      final markdown = summary.toMarkdown();

      expect(inputs.manualChecklistPath, checklistPath);
      expect(inputs.m36LiveLlmEvalSummaryPath, m36Path);
      expect(inputs.m23CycleOutcomeHandoffPath, m23Path);
      expect(summary.ready, isTrue);
      expect(summary.blockedGates, isEmpty);
      expect(json['schemaName'], 'macos_computer_use_m39_beta_signoff');
      expect(json['automationBoundary'], 'read_reports_only');
      expect(json['userOperatedGateIds'], contains('clean_install'));
      expect(
        json['userOperatedGateIds'],
        contains('user_operated_action_cycle'),
      );
      expect(summary.betaReviewSummary['status'], 'ready_for_internal_beta');
      expect(markdown, contains('M39 Internal Beta Sign-Off'));
      expect(markdown, contains('Live LLM observe-only canaries'));
    });

    test('blocks manual beta gates when the checklist is missing', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m39_beta_blocked_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      _writeJson(
        '${root.path}/macos_computer_use_m36_live_llm_eval_1/canary_summary.json',
        _m36LiveLlmEvalSummary(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m23_cycle_outcome_handoff_1/cycle_outcome_handoff.json',
        _m23CycleOutcomeHandoff(),
      );

      final inputs = readMacosComputerUseBetaSignoffInputs(reportRoot: root);
      final summary = buildMacosComputerUseBetaSignoffSummary(inputs);
      final blockedIds = summary.blockedGates
          .map((gate) => gate.id)
          .toList(growable: false);

      expect(summary.ready, isFalse);
      expect(blockedIds, contains('clean_install'));
      expect(blockedIds, contains('permission_revocation'));
      expect(blockedIds, isNot(contains('live_llm_observe_only_canaries')));
      expect(blockedIds, isNot(contains('user_operated_action_cycle')));
      expect(
        summary.betaReviewSummary['blockedUserOperatedGateIds'],
        contains('helper_restart'),
      );
    });

    test('accepts M38 install migration guardrails for upgrade evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m39_beta_m38_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final checklist = _manualChecklist()..remove('upgradeMigration');
      _writeJson(
        '${root.path}/manual/m39_manual_beta_checklist.json',
        checklist,
      );
      _writeJson(
        '${root.path}/macos_computer_use_m36_live_llm_eval_1/canary_summary.json',
        _m36LiveLlmEvalSummary(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m23_cycle_outcome_handoff_1/cycle_outcome_handoff.json',
        _m23CycleOutcomeHandoff(),
      );
      _writeJson(
        '${root.path}/diagnostics/computer_use_diagnostics.json',
        <String, Object?>{
          'installMigrationGuardrails': _installMigrationGuardrails(),
        },
      );

      final summary = buildMacosComputerUseBetaSignoffSummary(
        readMacosComputerUseBetaSignoffInputs(reportRoot: root),
      );

      expect(summary.ready, isTrue);
      final upgradeGate = summary.gates.singleWhere(
        (gate) => gate.id == 'upgrade_migration',
      );
      expect(
        upgradeGate.artifactPath,
        contains('computer_use_diagnostics.json'),
      );
      expect(upgradeGate.details['installMigrationGuardrailsReady'], isTrue);
    });

    test('CLI writes JSON and Markdown summaries', () async {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m39_beta_cli_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final checklistPath = _writeJson(
        '${root.path}/manual/m39_manual_beta_checklist.json',
        _manualChecklist(),
      );
      final m36Path = _writeJson(
        '${root.path}/m36/canary_summary.json',
        _m36LiveLlmEvalSummary(),
      );
      final m23Path = _writeJson(
        '${root.path}/m23/cycle_outcome_handoff.json',
        _m23CycleOutcomeHandoff(),
      );
      final outputJson = '${root.path}/out/m39.json';
      final outputMd = '${root.path}/out/m39.md';

      final result = await Process.run('dart', <String>[
        'run',
        'tool/macos_computer_use_beta_signoff.dart',
        '--root',
        root.path,
        '--manual-beta-checklist',
        checklistPath,
        '--m36-live-llm-eval',
        m36Path,
        '--m23-cycle-outcome',
        m23Path,
        '--output-json',
        outputJson,
        '--output-md',
        outputMd,
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final summary = jsonDecode(File(outputJson).readAsStringSync()) as Map;
      expect(summary['ready'], isTrue);
      expect(
        File(outputMd).readAsStringSync(),
        contains('Beta Review Summary'),
      );
    });

    test('tool wrapper and docs keep M39 report-only boundaries visible', () {
      final wrapper = File(
        'tool/run_macos_computer_use_m39_beta_signoff.sh',
      ).readAsStringSync();
      final architecture = File(
        'docs/macos_computer_use_helper_architecture.md',
      ).readAsStringSync();
      final checklist = File(
        'docs/macos_computer_use_manual_process_checklist.md',
      ).readAsStringSync();

      expect(wrapper, contains('report-only'));
      expect(wrapper, contains('not grant TCC'));
      expect(wrapper, contains('no desktop actions'));
      expect(architecture, contains('macos_computer_use_m39_beta_signoff'));
      expect(checklist, contains('M39 Internal Beta Sign-Off'));
      expect(checklist, contains('read_reports_only'));
    });
  });
}

String _writeJson(String path, Map<String, Object?> json) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  return file.path;
}

Map<String, Object?> _manualChecklist() {
  Map<String, Object?> readySection(String evidence) {
    return <String, Object?>{
      'status': 'ready',
      'ready': true,
      'evidence': evidence,
    };
  }

  return <String, Object?>{
    'schemaName': 'macos_computer_use_m39_manual_beta_checklist',
    'schemaVersion': 1,
    'milestone': 'M39',
    'automationBoundary': 'user_operated_runtime_checks',
    'cleanInstall': readySection('Clean install passed.'),
    'upgradeMigration': readySection('Upgrade migration passed.'),
    'permissionGrant': readySection('Permission grant passed.'),
    'permissionRevocation': readySection('Permission revocation passed.'),
    'helperRestart': readySection('Helper restart passed.'),
    'xpcFallbackObservability': readySection('XPC fallback was observable.'),
  };
}

Map<String, Object?> _m36LiveLlmEvalSummary() {
  final coverage = <String>[
    'fixture_screenshot',
    'saved_real_app_screenshot',
    'refusal_cases',
    'target_ambiguity',
    'exact_text_preservation',
    'public_action_boundary_preservation',
    'stale_or_blocked_evidence_recovery',
  ];
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m36_live_llm_eval_summary',
    'schemaVersion': 1,
    'purpose': 'computer_use_m36_live_llm_eval',
    'milestone': 'M36',
    'ready': true,
    'status': 'passed',
    'tccBoundary': 'no_tcc_operation',
    'desktopActionBoundary': 'no_desktop_action',
    'requiredCoverage': coverage
        .map(
          (id) => <String, Object?>{
            'id': id,
            'ok': true,
            'scenarioIds': <String>['scenario_$id'],
          },
        )
        .toList(growable: false),
    'm36LiveLlmEvaluationGate': <String, Object?>{
      'ok': true,
      'checks': <Object?>[],
    },
    'failureClasses': <String>[],
  };
}

Map<String, Object?> _m23CycleOutcomeHandoff() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m23_cycle_outcome_handoff',
    'schemaVersion': 1,
    'purpose': 'computer_use_m23_cycle_outcome_handoff',
    'milestone': 'M23',
    'ready': true,
    'status': 'ready',
    'desktopActionBoundary': 'no_desktop_action',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
    'cycleOutcome': 'closed',
    'nextObserveNeeded': 'no',
    'm23CycleOutcomeHandoffGate': <String, Object?>{
      'status': 'ready',
      'ready': true,
      'blockers': <String>[],
    },
  };
}

Map<String, Object?> _installMigrationGuardrails() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_install_migration_guardrails',
    'schemaVersion': 1,
    'milestone': 'M38',
    'status': 'ready',
    'oldHelperActionRequestsBlocked': true,
    'm38InstallMigrationGate': <String, Object?>{
      'status': 'ready',
      'ready': true,
      'blockers': <String>[],
    },
  };
}
