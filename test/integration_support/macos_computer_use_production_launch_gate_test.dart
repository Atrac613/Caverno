import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/macos_computer_use_production_launch_gate.dart';

void main() {
  group('macOS Computer Use M40 production launch gate', () {
    test('builds a ready production launch summary from ready evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m40_launch_ready_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final checklistPath = _writeJson(
        '${root.path}/manual/m40_launch_checklist.json',
        _launchChecklist(),
      );
      final releaseArtifactPath = _writeJson(
        '${root.path}/m7/release_artifact.json',
        _releaseArtifactReport(),
      );
      final packagingPath = _writeJson(
        '${root.path}/macos_computer_use_release_packaging.json',
        _releasePackagingReport(),
      );
      final m36Path = _writeJson(
        '${root.path}/macos_computer_use_m36_live_llm_eval_1/canary_summary.json',
        _m36LiveLlmEvalSummary(),
      );
      final m39Path = _writeJson(
        '${root.path}/macos_computer_use_m39_beta_signoff_1/macos_computer_use_m39_beta_signoff.json',
        _m39BetaSignoff(),
      );
      final diagnosticsPath = _writeJson(
        '${root.path}/diagnostics/computer_use_diagnostics.json',
        _diagnostics(),
      );

      final inputs = readMacosComputerUseProductionLaunchInputs(
        reportRoot: root,
      );
      final summary = buildMacosComputerUseProductionLaunchSummary(inputs);
      final json = summary.toJson();
      final markdown = summary.toMarkdown();

      expect(inputs.launchChecklistPath, checklistPath);
      expect(inputs.releaseArtifactReportPath, releaseArtifactPath);
      expect(inputs.releasePackagingReportPath, packagingPath);
      expect(inputs.m36LiveLlmEvalSummaryPath, m36Path);
      expect(inputs.m39BetaSignoffPath, m39Path);
      expect(inputs.diagnosticsPath, diagnosticsPath);
      expect(summary.ready, isTrue);
      expect(summary.blockedGates, isEmpty);
      expect(
        json['schemaName'],
        'macos_computer_use_m40_production_launch_gate',
      );
      expect(json['automationBoundary'], 'read_reports_only');
      expect(json['userOperatedGateIds'], contains('notarization'));
      expect(json['userOperatedGateIds'], contains('support_diagnostics'));
      expect(
        summary.launchReviewSummary['status'],
        'ready_for_production_launch',
      );
      expect(markdown, contains('M40 Production Launch Gate'));
      expect(markdown, contains('Signed release artifact'));
    });

    test('blocks launch-only gates when the checklist is missing', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m40_launch_blocked_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      _writeJson(
        '${root.path}/m7/release_artifact.json',
        _releaseArtifactReport(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_release_packaging.json',
        _releasePackagingReport(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m36_live_llm_eval_1/canary_summary.json',
        _m36LiveLlmEvalSummary(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m39_beta_signoff_1/macos_computer_use_m39_beta_signoff.json',
        _m39BetaSignoff(),
      );
      _writeJson(
        '${root.path}/diagnostics/computer_use_diagnostics.json',
        _diagnostics(),
      );

      final summary = buildMacosComputerUseProductionLaunchSummary(
        readMacosComputerUseProductionLaunchInputs(reportRoot: root),
      );
      final blockedIds = summary.blockedGates
          .map((gate) => gate.id)
          .toList(growable: false);

      expect(summary.ready, isFalse);
      expect(blockedIds, contains('notarization'));
      expect(blockedIds, contains('privacy_copy'));
      expect(blockedIds, contains('support_diagnostics'));
      expect(blockedIds, isNot(contains('signed_artifact')));
      expect(blockedIds, isNot(contains('live_llm_evidence')));
      expect(
        summary.launchReviewSummary['blockedUserOperatedGateIds'],
        contains('emergency_stop'),
      );
    });

    test('uses manual TCC report evidence when checklist TCC field is absent', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m40_launch_tcc_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final checklist = _launchChecklist()..remove('manualTccRunbook');
      _writeJson('${root.path}/manual/m40_launch_checklist.json', checklist);
      _writeJson(
        '${root.path}/m7/release_artifact.json',
        _releaseArtifactReport(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_release_packaging.json',
        _releasePackagingReport(),
      );
      _writeJson(
        '${root.path}/manual/manual_tcc_report_summary.json',
        _manualTccReport(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m36_live_llm_eval_1/canary_summary.json',
        _m36LiveLlmEvalSummary(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m39_beta_signoff_1/macos_computer_use_m39_beta_signoff.json',
        _m39BetaSignoff(),
      );
      _writeJson(
        '${root.path}/diagnostics/computer_use_diagnostics.json',
        _diagnostics(),
      );

      final summary = buildMacosComputerUseProductionLaunchSummary(
        readMacosComputerUseProductionLaunchInputs(reportRoot: root),
      );

      expect(summary.ready, isTrue);
      final tccGate = summary.gates.singleWhere(
        (gate) => gate.id == 'manual_tcc_runbook',
      );
      expect(tccGate.details['manualTccReportReady'], isTrue);
    });

    test('CLI writes JSON and Markdown summaries', () async {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m40_launch_cli_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final checklistPath = _writeJson(
        '${root.path}/manual/m40_launch_checklist.json',
        _launchChecklist(),
      );
      final releaseArtifactPath = _writeJson(
        '${root.path}/m7/release_artifact.json',
        _releaseArtifactReport(),
      );
      final packagingPath = _writeJson(
        '${root.path}/packaging.json',
        _releasePackagingReport(),
      );
      final m36Path = _writeJson(
        '${root.path}/m36.json',
        _m36LiveLlmEvalSummary(),
      );
      final m39Path = _writeJson('${root.path}/m39.json', _m39BetaSignoff());
      final diagnosticsPath = _writeJson(
        '${root.path}/diagnostics.json',
        _diagnostics(),
      );
      final outputJson = '${root.path}/out/m40.json';
      final outputMd = '${root.path}/out/m40.md';

      final result = await Process.run('dart', <String>[
        'run',
        'tool/macos_computer_use_production_launch_gate.dart',
        '--root',
        root.path,
        '--launch-checklist',
        checklistPath,
        '--release-artifact-report',
        releaseArtifactPath,
        '--release-packaging-report',
        packagingPath,
        '--m36-live-llm-eval',
        m36Path,
        '--m39-beta-signoff',
        m39Path,
        '--diagnostics',
        diagnosticsPath,
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
        contains('Launch Review Summary'),
      );
    });

    test('wrapper and docs keep M40 report-only boundaries visible', () {
      final wrapper = File(
        'tool/run_macos_computer_use_m40_production_launch_gate.sh',
      ).readAsStringSync();
      final architecture = File(
        'docs/macos_computer_use_helper_architecture.md',
      ).readAsStringSync();
      final checklist = File(
        'docs/macos_computer_use_manual_process_checklist.md',
      ).readAsStringSync();

      expect(wrapper, contains('report-only'));
      expect(wrapper, contains('grant TCC'));
      expect(wrapper, contains('no desktop'));
      expect(
        architecture,
        contains('macos_computer_use_m40_production_launch_gate'),
      );
      expect(checklist, contains('M40 Production Launch Gate'));
      expect(checklist, contains('ready_for_production_launch'));
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

Map<String, Object?> _launchChecklist() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m40_launch_checklist',
    'schemaVersion': 1,
    'milestone': 'M40',
    'automationBoundary': 'user_operated_release_steps',
    'notarization': _readySection('Notarization ticket attached.'),
    'manualTccRunbook': _readySection('Manual TCC runbook completed.'),
    'auditExport': _readySection('Redacted audit export reviewed.'),
    'emergencyStop': _readySection('Emergency stop validated.'),
    'privacyCopy': _readySection('Privacy copy approved.'),
    'supportDiagnostics': _readySection('Support diagnostics exported.'),
  };
}

Map<String, Object?> _releaseArtifactReport() {
  return <String, Object?>{
    'releaseSignoffGate': <String, Object?>{
      'status': 'ready',
      'blockers': <String>[],
    },
  };
}

Map<String, Object?> _releasePackagingReport() {
  List<Map<String, Object?>> checks() {
    return <Map<String, Object?>>[
      <String, Object?>{'id': 'helper_bundle_identity', 'ok': true},
      <String, Object?>{'id': 'launch_agent_mach_service', 'ok': true},
    ];
  }

  return <String, Object?>{
    'schemaName': 'macos_computer_use_m33_release_packaging',
    'schemaVersion': 1,
    'milestone': 'M33',
    'status': 'ready',
    'ready': true,
    'checks': checks(),
  };
}

Map<String, Object?> _manualTccReport() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_manual_tcc_report_summary',
    'schemaVersion': 1,
    'status': 'ready',
    'ready': true,
  };
}

Map<String, Object?> _m36LiveLlmEvalSummary() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m36_live_llm_eval_summary',
    'schemaVersion': 1,
    'purpose': 'computer_use_m36_live_llm_eval',
    'milestone': 'M36',
    'ready': true,
    'status': 'passed',
    'tccBoundary': 'no_tcc_operation',
    'desktopActionBoundary': 'no_desktop_action',
    'm36LiveLlmEvaluationGate': <String, Object?>{
      'ok': true,
      'checks': <Object?>[],
    },
    'failureClasses': <String>[],
  };
}

Map<String, Object?> _m39BetaSignoff() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m39_beta_signoff',
    'schemaVersion': 1,
    'milestone': 'M39',
    'status': 'ready',
    'ready': true,
    'betaReviewSummary': <String, Object?>{'status': 'ready_for_internal_beta'},
    'blockedGateIds': <String>[],
  };
}

Map<String, Object?> _diagnostics() {
  return <String, Object?>{
    'auditPrivacyControls': <String, Object?>{
      'schemaName': 'macos_computer_use_audit_privacy_controls',
      'schemaVersion': 1,
      'milestone': 'M37',
      'status': 'defined',
      'defaultExportRedacted': true,
      'explicitPayloadExportRequired': true,
      'm37AuditPrivacyGate': <String, Object?>{
        'status': 'ready',
        'blockers': <String>[],
      },
    },
    'installMigrationGuardrails': <String, Object?>{
      'schemaName': 'macos_computer_use_install_migration_guardrails',
      'schemaVersion': 1,
      'milestone': 'M38',
      'status': 'ready',
      'oldHelperActionRequestsBlocked': true,
      'm38InstallMigrationGate': <String, Object?>{
        'status': 'ready',
        'blockers': <String>[],
      },
    },
  };
}
