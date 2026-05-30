import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_tool_process.dart';

import '../../integration_test/test_support/macos_computer_use_m51_production_launch_gate.dart';

void main() {
  group('macOS Computer Use M51 production launch gate', () {
    test('builds a ready production launch summary from ready evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m51_launch_ready_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final checklistPath = _writeJson(
        '${root.path}/manual/m51_launch_checklist.json',
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
      final m46Path = _writeJson(
        '${root.path}/macos_computer_use_m46_element_grounded_llm_eval_1/canary_summary.json',
        _m46ElementGroundedLlmEvalSummary(),
      );
      final m49Path = _writeJson(
        '${root.path}/macos_computer_use_m49_privacy_audit_release_pack_1/privacy_audit_release_pack.json',
        _m49PrivacyAuditReleasePack(),
      );
      final m50Path = _writeJson(
        '${root.path}/macos_computer_use_m50_signed_beta_gate_1/macos_computer_use_m50_signed_beta_gate.json',
        _m50SignedBetaGate(),
      );
      final diagnosticsPath = _writeJson(
        '${root.path}/diagnostics/computer_use_diagnostics.json',
        _diagnostics(),
      );

      final inputs = readMacosComputerUseM51ProductionLaunchInputs(
        reportRoot: root,
      );
      final summary = buildMacosComputerUseM51ProductionLaunchSummary(inputs);
      final json = summary.toJson();
      final markdown = summary.toMarkdown();

      expect(inputs.launchChecklistPath, checklistPath);
      expect(inputs.releaseArtifactReportPath, releaseArtifactPath);
      expect(inputs.releasePackagingReportPath, packagingPath);
      expect(inputs.m46ElementGroundedLlmEvalSummaryPath, m46Path);
      expect(inputs.m49PrivacyAuditReleasePackPath, m49Path);
      expect(inputs.m50SignedBetaGatePath, m50Path);
      expect(inputs.diagnosticsPath, diagnosticsPath);
      expect(summary.ready, isTrue);
      expect(summary.blockedGates, isEmpty);
      expect(
        json['schemaName'],
        'macos_computer_use_m51_production_launch_gate',
      );
      expect(json['automationBoundary'], 'read_reports_only');
      expect(json['userOperatedGateIds'], contains('notarization'));
      expect(json['userOperatedGateIds'], contains('support_diagnostics'));
      expect(
        summary.launchReviewSummary['status'],
        'ready_for_production_launch',
      );
      expect(markdown, contains('M51 Production Launch Gate'));
      expect(markdown, contains('Signed release artifact'));
      expect(markdown, contains('Element-grounded LLM evaluation'));
    });

    test('blocks launch-only gates when the checklist is missing', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m51_launch_blocked_',
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
        '${root.path}/macos_computer_use_m46_element_grounded_llm_eval_1/canary_summary.json',
        _m46ElementGroundedLlmEvalSummary(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m49_privacy_audit_release_pack_1/privacy_audit_release_pack.json',
        _m49PrivacyAuditReleasePack(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m50_signed_beta_gate_1/macos_computer_use_m50_signed_beta_gate.json',
        _m50SignedBetaGate(),
      );
      _writeJson(
        '${root.path}/diagnostics/computer_use_diagnostics.json',
        _diagnostics(),
      );

      final summary = buildMacosComputerUseM51ProductionLaunchSummary(
        readMacosComputerUseM51ProductionLaunchInputs(reportRoot: root),
      );
      final blockedIds = summary.blockedGates
          .map((gate) => gate.id)
          .toList(growable: false);

      expect(summary.ready, isFalse);
      expect(blockedIds, contains('notarization'));
      expect(blockedIds, contains('privacy_copy'));
      expect(blockedIds, contains('support_diagnostics'));
      expect(blockedIds, contains('production_launch_boundaries'));
      expect(blockedIds, isNot(contains('signed_artifact')));
      expect(blockedIds, isNot(contains('element_grounded_llm_evaluation')));
      expect(
        summary.launchReviewSummary['blockedUserOperatedGateIds'],
        contains('emergency_stop'),
      );
    });

    test('uses manual TCC report evidence when checklist TCC field is absent', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m51_launch_tcc_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final checklist = _launchChecklist()..remove('manualTccRunbook');
      _writeJson('${root.path}/manual/m51_launch_checklist.json', checklist);
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
        '${root.path}/macos_computer_use_m46_element_grounded_llm_eval_1/canary_summary.json',
        _m46ElementGroundedLlmEvalSummary(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m49_privacy_audit_release_pack_1/privacy_audit_release_pack.json',
        _m49PrivacyAuditReleasePack(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m50_signed_beta_gate_1/macos_computer_use_m50_signed_beta_gate.json',
        _m50SignedBetaGate(),
      );
      _writeJson(
        '${root.path}/diagnostics/computer_use_diagnostics.json',
        _diagnostics(),
      );

      final summary = buildMacosComputerUseM51ProductionLaunchSummary(
        readMacosComputerUseM51ProductionLaunchInputs(reportRoot: root),
      );

      expect(summary.ready, isTrue);
      final tccGate = summary.gates.singleWhere(
        (gate) => gate.id == 'manual_tcc_runbook',
      );
      expect(tccGate.details['manualTccReportReady'], isTrue);
    });

    test('CLI writes JSON and Markdown summaries', () async {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m51_launch_cli_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final checklistPath = _writeJson(
        '${root.path}/manual/m51_launch_checklist.json',
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
      final m46Path = _writeJson(
        '${root.path}/m46.json',
        _m46ElementGroundedLlmEvalSummary(),
      );
      final m49Path = _writeJson(
        '${root.path}/m49.json',
        _m49PrivacyAuditReleasePack(),
      );
      final m50Path = _writeJson('${root.path}/m50.json', _m50SignedBetaGate());
      final diagnosticsPath = _writeJson(
        '${root.path}/diagnostics.json',
        _diagnostics(),
      );
      final outputJson = '${root.path}/out/m51.json';
      final outputMd = '${root.path}/out/m51.md';

      final result = await runDartTool(
        'tool/macos_computer_use_m51_production_launch_gate.dart',
        <String>[
          '--root',
          root.path,
          '--launch-checklist',
          checklistPath,
          '--release-artifact-report',
          releaseArtifactPath,
          '--release-packaging-report',
          packagingPath,
          '--m46-element-grounded-llm-eval',
          m46Path,
          '--m49-privacy-audit-release-pack',
          m49Path,
          '--m50-signed-beta-gate',
          m50Path,
          '--diagnostics',
          diagnosticsPath,
          '--output-json',
          outputJson,
          '--output-md',
          outputMd,
        ],
      );

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final summary = jsonDecode(File(outputJson).readAsStringSync()) as Map;
      expect(summary['ready'], isTrue);
      expect(
        File(outputMd).readAsStringSync(),
        contains('Launch Review Summary'),
      );
    });

    test('wrapper and docs keep M51 report-only boundaries visible', () {
      final wrapper = File(
        'tool/run_macos_computer_use_m51_production_launch_gate.sh',
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
        contains('macos_computer_use_m51_production_launch_gate'),
      );
      expect(checklist, contains('M51 Production Launch Gate'));
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
    'schemaName': 'macos_computer_use_m51_launch_checklist',
    'schemaVersion': 1,
    'milestone': 'M51',
    'automationBoundary': 'user_operated_release_steps',
    'notarization': _readySection('Notarization ticket attached.'),
    'manualTccRunbook': _readySection('Manual TCC runbook completed.'),
    'emergencyStop': _readySection('Emergency stop validated.'),
    'privacyCopy': _readySection('Privacy copy approved.'),
    'supportDiagnostics': _readySection('Support diagnostics exported.'),
    'productionLaunchBoundaries': _readySection(
      'Default-off rollout, rollback, and support escalation reviewed.',
    ),
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

Map<String, Object?> _m46ElementGroundedLlmEvalSummary() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m46_element_grounded_llm_eval_summary',
    'schemaVersion': 1,
    'purpose': 'computer_use_m46_element_grounded_llm_eval',
    'milestone': 'M46',
    'ready': true,
    'status': 'passed',
    'tccBoundary': 'no_tcc_operation',
    'desktopActionBoundary': 'no_desktop_action',
    'm46ElementGroundedLlmEvaluationGate': <String, Object?>{
      'ok': true,
      'checks': <Object?>[],
    },
    'requiredCoverage': <Object?>[
      <String, Object?>{'id': 'semantic_label', 'ok': true},
      <String, Object?>{'id': 'bounds', 'ok': true},
    ],
    'failureClasses': <String>[],
  };
}

Map<String, Object?> _m49PrivacyAuditReleasePack() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m49_privacy_audit_release_pack',
    'schemaVersion': 1,
    'milestone': 'M49',
    'status': 'ready',
    'ready': true,
    'desktopActionBoundary': 'no_desktop_action',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
    'rawPayloadExportBoundary': 'no_raw_payload_export',
    'm49PrivacyAuditReleasePackGate': <String, Object?>{
      'status': 'ready',
      'blockers': <String>[],
    },
  };
}

Map<String, Object?> _m50SignedBetaGate() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m50_signed_beta_gate',
    'schemaVersion': 1,
    'milestone': 'M50',
    'status': 'ready',
    'ready': true,
    'signedBetaReviewSummary': <String, Object?>{
      'status': 'ready_for_signed_beta',
    },
    'm50SignedBetaGate': <String, Object?>{
      'status': 'ready',
      'ready': true,
      'blockers': <String>[],
    },
    'blockedGateIds': <String>[],
  };
}

Map<String, Object?> _diagnostics() {
  return <String, Object?>{
    'auditPrivacyControls': <String, Object?>{
      'schemaName': 'macos_computer_use_audit_privacy_controls',
      'schemaVersion': 1,
      'milestone': 'M37',
      'status': 'ready',
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
