import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/macos_computer_use_m53_post_release_guardrails.dart';

void main() {
  group('macOS Computer Use M53 post-release guardrails', () {
    test('builds a ready post-release summary from ready evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m53_guardrails_ready_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final checklistPath = _writeJson(
        '${root.path}/manual/m53_post_release_checklist.json',
        _postReleaseChecklist(),
      );
      final m52Path = _writeJson(
        '${root.path}/macos_computer_use_m52_product_release_rollout_1/macos_computer_use_m52_product_release_rollout.json',
        _m52ProductReleaseRollout(),
      );

      final inputs = readMacosComputerUseM53PostReleaseInputs(reportRoot: root);
      final summary = buildMacosComputerUseM53PostReleaseSummary(inputs);
      final json = summary.toJson();
      final markdown = summary.toMarkdown();

      expect(inputs.postReleaseChecklistPath, checklistPath);
      expect(inputs.m52ProductReleaseRolloutPath, m52Path);
      expect(summary.ready, isTrue);
      expect(summary.blockedGates, isEmpty);
      expect(
        json['schemaName'],
        'macos_computer_use_m53_post_release_guardrails',
      );
      expect(json['automationBoundary'], 'read_reports_only');
      expect(json['tccBoundary'], 'user_operated');
      expect(json['desktopActionBoundary'], 'user_operated');
      expect(json['userOperatedGateIds'], contains('review_cadence_confirmed'));
      expect(
        summary.postReleaseGuardrailsSummary['status'],
        'ready_for_post_release_operations',
      );
      expect(summary.m53PostReleaseGuardrailsGate['status'], 'ready');
      expect(markdown, contains('M53 Post-Release Guardrails'));
      expect(markdown, contains('Review cadence'));
      expect(markdown, contains('Hotfix triggers'));
    });

    test('blocks post-release gates when the checklist is missing', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m53_guardrails_blocked_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      _writeJson(
        '${root.path}/macos_computer_use_m52_product_release_rollout_1/macos_computer_use_m52_product_release_rollout.json',
        _m52ProductReleaseRollout(),
      );

      final summary = buildMacosComputerUseM53PostReleaseSummary(
        readMacosComputerUseM53PostReleaseInputs(reportRoot: root),
      );
      final blockedIds = summary.blockedGates
          .map((gate) => gate.id)
          .toList(growable: false);

      expect(summary.ready, isFalse);
      expect(blockedIds, contains('review_cadence_confirmed'));
      expect(blockedIds, contains('default_off_still_confirmed'));
      expect(blockedIds, contains('support_diagnostics_reviewed'));
      expect(blockedIds, contains('hotfix_triggers_reviewed'));
      expect(blockedIds, isNot(contains('m52_product_release_rollout')));
      expect(
        summary.postReleaseGuardrailsSummary['blockedUserOperatedGateIds'],
        contains('known_issues_reviewed'),
      );
    });

    test('blocks guardrails when M52 product release evidence is blocked', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m53_guardrails_m52_blocked_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      _writeJson(
        '${root.path}/manual/m53_post_release_checklist.json',
        _postReleaseChecklist(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m52_product_release_rollout_1/macos_computer_use_m52_product_release_rollout.json',
        _m52ProductReleaseRollout(ready: false),
      );

      final summary = buildMacosComputerUseM53PostReleaseSummary(
        readMacosComputerUseM53PostReleaseInputs(reportRoot: root),
      );

      expect(summary.ready, isFalse);
      final m52Gate = summary.gates.singleWhere(
        (gate) => gate.id == 'm52_product_release_rollout',
      );
      expect(m52Gate.ready, isFalse);
      expect(m52Gate.details['blockers'], contains('default_off_confirmed'));
    });

    test(
      'CLI writes JSON and Markdown summaries',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_m53_guardrails_cli_',
        );
        addTearDown(() => root.deleteSync(recursive: true));

        final checklistPath = _writeJson(
          '${root.path}/manual/m53_post_release_checklist.json',
          _postReleaseChecklist(),
        );
        final m52Path = _writeJson(
          '${root.path}/m52.json',
          _m52ProductReleaseRollout(),
        );
        final outputJson = '${root.path}/out/m53.json';
        final outputMd = '${root.path}/out/m53.md';

        final result = await Process.run('dart', <String>[
          'run',
          'tool/macos_computer_use_m53_post_release_guardrails.dart',
          '--root',
          root.path,
          '--post-release-checklist',
          checklistPath,
          '--m52-product-release-rollout',
          m52Path,
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
          contains('Post-Release Guardrails Summary'),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('wrapper and docs keep M53 report-only boundaries visible', () {
      final wrapper = File(
        'tool/run_macos_computer_use_m53_post_release_guardrails.sh',
      ).readAsStringSync();
      final architecture = File(
        'docs/macos_computer_use_helper_architecture.md',
      ).readAsStringSync();
      final checklist = File(
        'docs/macos_computer_use_manual_process_checklist.md',
      ).readAsStringSync();

      expect(wrapper, contains('report-only'));
      expect(wrapper, contains('post-release checklist evidence'));
      expect(wrapper, contains('no desktop actions'));
      expect(
        architecture,
        contains('macos_computer_use_m53_post_release_guardrails'),
      );
      expect(checklist, contains('M53 Post-Release Guardrails'));
      expect(checklist, contains('ready_for_post_release_operations'));
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

Map<String, Object?> _postReleaseChecklist() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m53_post_release_checklist',
    'schemaVersion': 1,
    'milestone': 'M53',
    'automationBoundary': 'user_operated_post_release_steps',
    'reviewCadenceConfirmed': _readySection(
      'Scheduled post-release review cadence confirmed.',
    ),
    'defaultOffStillConfirmed': _readySection(
      'Computer Use remains default off after release.',
    ),
    'advancedOnlyStillConfirmed': _readySection(
      'Settings > Advanced remains the only enablement path.',
    ),
    'supportDiagnosticsReviewed': _readySection(
      'Redacted support diagnostics reviewed.',
    ),
    'knownIssuesReviewed': _readySection('Known issues reviewed.'),
    'incidentReviewComplete': _readySection(
      'Incidents, complaints, and regressions reviewed.',
    ),
    'rollbackStillReady': _readySection(
      'Rollback and emergency stop remain ready.',
    ),
    'hotfixTriggersReviewed': _readySection(
      'Hotfix and rollout pause triggers reviewed.',
    ),
  };
}

Map<String, Object?> _m52ProductReleaseRollout({bool ready = true}) {
  final blockedGateIds = ready ? <String>[] : <String>['default_off_confirmed'];
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m52_product_release_rollout',
    'schemaVersion': 1,
    'milestone': 'M52',
    'status': ready ? 'ready' : 'blocked',
    'ready': ready,
    'readyGateIds': ready
        ? <String>['m51_production_launch_gate', 'default_off_confirmed']
        : <String>['m51_production_launch_gate'],
    'blockedGateIds': blockedGateIds,
    'releaseRolloutSummary': <String, Object?>{
      'status': ready ? 'ready_for_product_release' : 'blocked_gates_present',
      'readyGateIds': ready
          ? <String>['m51_production_launch_gate', 'default_off_confirmed']
          : <String>['m51_production_launch_gate'],
      'blockedGateIds': blockedGateIds,
      'blockedUserOperatedGateIds': blockedGateIds,
      'blockedAutomationSafeGateIds': <String>[],
      'operationBoundarySummary': 'M52 reads release rollout evidence only.',
    },
    'm52ProductReleaseGate': <String, Object?>{
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'blockers': blockedGateIds,
      'nextAction': ready
          ? 'Ship element-grounded Computer Use through the product release rollout.'
          : 'Resolve blocked M52 product release rollout gates before shipping.',
    },
    'gates': <Object?>[],
  };
}
