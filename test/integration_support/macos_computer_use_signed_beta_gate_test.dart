import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/macos_computer_use_signed_beta_gate.dart';

void main() {
  group('macOS Computer Use M50 signed beta gate', () {
    test('builds a ready signed beta summary from ready evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m50_signed_beta_ready_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final checklistPath = _writeJson(
        '${root.path}/manual/m50_signed_beta_checklist.json',
        _signedBetaChecklist(),
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
        '${root.path}/m46/canary_summary.json',
        _m46ElementGroundedLlmEvalSummary(),
      );
      final m48Path = _writeJson(
        '${root.path}/m48/user_operated_action_pilot.json',
        _m48UserOperatedActionPilot(),
      );
      final m49Path = _writeJson(
        '${root.path}/m49/privacy_audit_release_pack.json',
        _m49PrivacyAuditReleasePack(),
      );

      final inputs = readMacosComputerUseSignedBetaInputs(reportRoot: root);
      final summary = buildMacosComputerUseSignedBetaSummary(inputs);
      final json = summary.toJson();
      final markdown = summary.toMarkdown();

      expect(inputs.signedBetaChecklistPath, checklistPath);
      expect(inputs.releaseArtifactReportPath, releaseArtifactPath);
      expect(inputs.releasePackagingReportPath, packagingPath);
      expect(inputs.m46ElementGroundedLlmEvalSummaryPath, m46Path);
      expect(inputs.m48UserOperatedActionPilotPath, m48Path);
      expect(inputs.m49PrivacyAuditReleasePackPath, m49Path);
      expect(summary.ready, isTrue);
      expect(summary.blockedGates, isEmpty);
      expect(json['schemaName'], 'macos_computer_use_m50_signed_beta_gate');
      expect(json['automationBoundary'], 'read_reports_only');
      expect(json['userOperatedGateIds'], contains('notarized_beta_build'));
      expect(json['userOperatedGateIds'], contains('permission_revocation'));
      expect(
        summary.signedBetaReviewSummary['status'],
        'ready_for_signed_beta',
      );
      expect((json['m50SignedBetaGate'] as Map)['status'], 'ready');
      expect(markdown, contains('M50 Signed Beta Gate'));
      expect(markdown, contains('Signed Beta Review Summary'));
    });

    test(
      'blocks user-operated signed beta gates when checklist is missing',
      () {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_m50_signed_beta_blocked_',
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
          '${root.path}/m46/canary_summary.json',
          _m46ElementGroundedLlmEvalSummary(),
        );
        _writeJson(
          '${root.path}/m48/user_operated_action_pilot.json',
          _m48UserOperatedActionPilot(),
        );
        _writeJson(
          '${root.path}/m49/privacy_audit_release_pack.json',
          _m49PrivacyAuditReleasePack(),
        );

        final summary = buildMacosComputerUseSignedBetaSummary(
          readMacosComputerUseSignedBetaInputs(reportRoot: root),
        );
        final blockedIds = summary.blockedGates
            .map((gate) => gate.id)
            .toList(growable: false);

        expect(summary.ready, isFalse);
        expect(blockedIds, contains('notarized_beta_build'));
        expect(blockedIds, contains('clean_install'));
        expect(blockedIds, contains('permission_grant'));
        expect(blockedIds, contains('xpc_fallback_observability'));
        expect(blockedIds, isNot(contains('signed_beta_artifact')));
        expect(blockedIds, isNot(contains('privacy_audit_release_pack')));
        expect(
          summary.signedBetaReviewSummary['blockedUserOperatedGateIds'],
          contains('helper_restart'),
        );
      },
    );

    test('blocks ready checklist sections with placeholder evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m50_signed_beta_placeholder_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      _writeJson(
        '${root.path}/manual/m50_signed_beta_checklist.json',
        _signedBetaChecklistWithPlaceholderEvidence(),
      );
      _writeJson(
        '${root.path}/m7/release_artifact.json',
        _releaseArtifactReport(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_release_packaging.json',
        _releasePackagingReport(),
      );
      _writeJson(
        '${root.path}/m46/canary_summary.json',
        _m46ElementGroundedLlmEvalSummary(),
      );
      _writeJson(
        '${root.path}/m48/user_operated_action_pilot.json',
        _m48UserOperatedActionPilot(),
      );
      _writeJson(
        '${root.path}/m49/privacy_audit_release_pack.json',
        _m49PrivacyAuditReleasePack(),
      );

      final summary = buildMacosComputerUseSignedBetaSummary(
        readMacosComputerUseSignedBetaInputs(reportRoot: root),
      );
      final placeholderGate = summary.gates.singleWhere(
        (gate) => gate.id == 'notarized_beta_build',
      );
      final blockedIds = summary.blockedGates
          .map((gate) => gate.id)
          .toList(growable: false);

      expect(summary.ready, isFalse);
      expect(placeholderGate.status, 'evidence_required');
      expect(placeholderGate.details['evidenceReady'], isFalse);
      expect(blockedIds, contains('notarized_beta_build'));
      expect(blockedIds, contains('permission_grant'));
      expect(blockedIds, isNot(contains('signed_beta_artifact')));
      expect(blockedIds, isNot(contains('user_operated_action_cycle')));
    });

    test('CLI writes JSON and Markdown summaries', () async {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m50_signed_beta_cli_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final checklistPath = _writeJson(
        '${root.path}/manual/m50_signed_beta_checklist.json',
        _signedBetaChecklist(),
      );
      final releaseArtifactPath = _writeJson(
        '${root.path}/m7.json',
        _releaseArtifactReport(),
      );
      final packagingPath = _writeJson(
        '${root.path}/m33.json',
        _releasePackagingReport(),
      );
      final m46Path = _writeJson(
        '${root.path}/m46.json',
        _m46ElementGroundedLlmEvalSummary(),
      );
      final m48Path = _writeJson(
        '${root.path}/m48.json',
        _m48UserOperatedActionPilot(),
      );
      final m49Path = _writeJson(
        '${root.path}/m49.json',
        _m49PrivacyAuditReleasePack(),
      );
      final outputJson = '${root.path}/out/m50.json';
      final outputMd = '${root.path}/out/m50.md';

      final result = await Process.run('dart', <String>[
        'run',
        'tool/macos_computer_use_signed_beta_gate.dart',
        '--root',
        root.path,
        '--signed-beta-checklist',
        checklistPath,
        '--release-artifact-report',
        releaseArtifactPath,
        '--release-packaging-report',
        packagingPath,
        '--m46-element-grounded-llm-eval',
        m46Path,
        '--m48-user-operated-action-pilot',
        m48Path,
        '--m49-privacy-audit-release-pack',
        m49Path,
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
        contains('Signed Beta Review Summary'),
      );
    });

    test(
      'CLI writes a user-operated handoff with resolved artifacts',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_m50_signed_beta_handoff_',
        );
        addTearDown(() => root.deleteSync(recursive: true));

        _writeJson(
          '${root.path}/manual/m50_signed_beta_checklist.json',
          _signedBetaChecklistWithPlaceholderEvidence(),
        );
        final releaseArtifactPath = _writeJson(
          '${root.path}/m7.json',
          _releaseArtifactReport(),
        );
        final packagingPath = _writeJson(
          '${root.path}/m33.json',
          _releasePackagingReport(),
        );
        final m46Path = _writeJson(
          '${root.path}/m46.json',
          _m46ElementGroundedLlmEvalSummary(),
        );
        final m48Path = _writeJson(
          '${root.path}/m48.json',
          _m48UserOperatedActionPilot(),
        );
        final m49Path = _writeJson(
          '${root.path}/m49.json',
          _m49PrivacyAuditReleasePack(),
        );
        final outputMd = '${root.path}/handoff/m50_handoff.md';

        final result = await Process.run('dart', <String>[
          'run',
          'tool/macos_computer_use_signed_beta_gate.dart',
          '--root',
          root.path,
          '--write-handoff',
          outputMd,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final handoff = File(outputMd).readAsStringSync();
        expect(handoff, contains('M50 Signed Beta Handoff'));
        expect(handoff, contains('notarizedBetaBuild'));
        expect(handoff, contains('xpcFallbackObservability'));
        expect(handoff, contains('--signed-beta-checklist'));
        expect(handoff, contains(releaseArtifactPath));
        expect(handoff, contains(packagingPath));
        expect(handoff, contains(m46Path));
        expect(handoff, contains(m48Path));
        expect(handoff, contains(m49Path));
        expect(handoff, contains('does not sign, notarize, staple'));
      },
    );

    test('wrapper and docs keep M50 report-only boundaries visible', () {
      final wrapper = File(
        'tool/run_macos_computer_use_m50_signed_beta_gate.sh',
      ).readAsStringSync();
      final architecture = File(
        'docs/macos_computer_use_helper_architecture.md',
      ).readAsStringSync();
      final checklist = File(
        'docs/macos_computer_use_manual_process_checklist.md',
      ).readAsStringSync();

      expect(wrapper, contains('report-only'));
      expect(wrapper, contains('does not sign, notarize, staple'));
      expect(wrapper, contains('grant TCC'));
      expect(wrapper, contains('operate desktop apps'));
      expect(wrapper, contains('handoff-only'));
      expect(architecture, contains('macos_computer_use_m50_signed_beta_gate'));
      expect(checklist, contains('M50 Signed Beta Gate'));
      expect(checklist, contains('read_reports_only'));
    });
  });
}

String _writeJson(String path, Map<String, Object?> json) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  return file.path;
}

Map<String, Object?> _signedBetaChecklist() {
  Map<String, Object?> readySection(String evidence) {
    return <String, Object?>{
      'status': 'ready',
      'ready': true,
      'evidence': evidence,
    };
  }

  return <String, Object?>{
    'schemaName': 'macos_computer_use_m50_signed_beta_checklist',
    'schemaVersion': 1,
    'milestone': 'M50',
    'automationBoundary': 'user_operated_signed_beta_checks',
    'notarizedBetaBuild': readySection('Notarized beta build passed.'),
    'cleanInstall': readySection('Clean install passed.'),
    'upgradeMigration': readySection('Upgrade migration passed.'),
    'permissionGrant': readySection('Permission grant passed.'),
    'permissionRevocation': readySection('Permission revocation passed.'),
    'helperRestart': readySection('Helper restart passed.'),
    'xpcFallbackObservability': readySection('XPC fallback was observable.'),
  };
}

Map<String, Object?> _signedBetaChecklistWithPlaceholderEvidence() {
  Map<String, Object?> readySection(String evidence) {
    return <String, Object?>{
      'status': 'ready',
      'ready': true,
      'evidence': evidence,
    };
  }

  return <String, Object?>{
    'schemaName': 'macos_computer_use_m50_signed_beta_checklist',
    'schemaVersion': 1,
    'milestone': 'M50',
    'automationBoundary': 'user_operated_signed_beta_checks',
    'notarizedBetaBuild': readySection(
      '<notarization ticket, stapler validation, or signed beta build note>',
    ),
    'cleanInstall': readySection('<clean install note or artifact path>'),
    'upgradeMigration': readySection(
      '<upgrade and migration note or artifact path>',
    ),
    'permissionGrant': readySection('<permission grant note or artifact path>'),
    'permissionRevocation': readySection(
      '<permission revocation recovery note or artifact path>',
    ),
    'helperRestart': readySection('<helper restart note or artifact path>'),
    'xpcFallbackObservability': readySection(
      '<XPC fallback diagnostics note or artifact path>',
    ),
  };
}

Map<String, Object?> _releaseArtifactReport() {
  return <String, Object?>{
    'releaseSignoffGate': <String, Object?>{
      'status': 'ready',
      'blockers': <String>[],
      'nextAction': 'M7 release artifact sign-off is complete.',
    },
  };
}

Map<String, Object?> _releasePackagingReport() {
  final ids = <String>[
    'main_release_entitlements',
    'helper_release_entitlements',
    'hardened_runtime',
    'helper_bundle_identity',
    'launch_agent_mach_service',
    'embed_helper_phase',
    'identity_free_signing_defaults',
  ];
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m33_release_packaging',
    'schemaVersion': 1,
    'milestone': 'M33',
    'status': 'ready',
    'ready': true,
    'checks': ids
        .map(
          (id) => <String, Object?>{
            'id': id,
            'ok': true,
            'nextAction': 'No action required.',
          },
        )
        .toList(growable: false),
  };
}

Map<String, Object?> _m46ElementGroundedLlmEvalSummary() {
  final coverage = <String>[
    'element_target_disambiguation',
    'exact_text_target_pairing',
    'public_action_approval_blocker',
    'high_risk_target_refusal',
    'stale_observation_recovery',
    'coordinate_only_fallback_refusal',
  ];
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m46_element_grounded_llm_eval_summary',
    'schemaVersion': 1,
    'milestone': 'M46',
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
    'm46ElementGroundedLlmEvaluationGate': <String, Object?>{
      'ok': true,
      'checks': <Object?>[],
    },
    'failureClasses': <String>[],
  };
}

Map<String, Object?> _m48UserOperatedActionPilot() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m48_user_operated_action_pilot',
    'schemaVersion': 1,
    'milestone': 'M48',
    'ready': true,
    'status': 'ready',
    'desktopActionBoundary': 'user_operated_evidence_only',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
    'm48UserOperatedActionPilotGate': <String, Object?>{
      'status': 'ready',
      'blockers': <String>[],
      'checks': <Object?>[],
    },
  };
}

Map<String, Object?> _m49PrivacyAuditReleasePack() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m49_privacy_audit_release_pack',
    'schemaVersion': 1,
    'milestone': 'M49',
    'ready': true,
    'status': 'ready',
    'desktopActionBoundary': 'no_desktop_action',
    'tccBoundary': 'no_tcc_operation',
    'llmBoundary': 'no_llm_call',
    'rawPayloadExportBoundary': 'no_raw_payload_export',
    'm49PrivacyAuditReleasePackGate': <String, Object?>{
      'status': 'ready',
      'blockers': <String>[],
      'checks': <Object?>[],
    },
  };
}
