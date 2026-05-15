import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/macos_computer_use_m52_product_release_rollout.dart';

void main() {
  group('macOS Computer Use M52 product release rollout', () {
    test('builds a ready product release summary from ready evidence', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m52_release_ready_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final checklistPath = _writeJson(
        '${root.path}/manual/m52_product_release_checklist.json',
        _productReleaseChecklist(),
      );
      final m51Path = _writeJson(
        '${root.path}/macos_computer_use_m51_production_launch_gate_1/macos_computer_use_m51_production_launch_gate.json',
        _m51ProductionLaunchGate(),
      );

      final inputs = readMacosComputerUseM52ProductReleaseInputs(
        reportRoot: root,
      );
      final summary = buildMacosComputerUseM52ProductReleaseSummary(inputs);
      final json = summary.toJson();
      final markdown = summary.toMarkdown();

      expect(inputs.productReleaseChecklistPath, checklistPath);
      expect(inputs.m51ProductionLaunchGatePath, m51Path);
      expect(summary.ready, isTrue);
      expect(summary.blockedGates, isEmpty);
      expect(
        json['schemaName'],
        'macos_computer_use_m52_product_release_rollout',
      );
      expect(json['automationBoundary'], 'read_reports_only');
      expect(json['tccBoundary'], 'user_operated');
      expect(json['desktopActionBoundary'], 'user_operated');
      expect(json['userOperatedGateIds'], contains('default_off_confirmed'));
      expect(
        summary.releaseRolloutSummary['status'],
        'ready_for_product_release',
      );
      expect(summary.m52ProductReleaseGate['status'], 'ready');
      expect(markdown, contains('M52 Product Release Rollout'));
      expect(markdown, contains('Default-off release'));
      expect(markdown, contains('Advanced settings entry point'));
    });

    test('blocks product release gates when the checklist is missing', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m52_release_blocked_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      _writeJson(
        '${root.path}/macos_computer_use_m51_production_launch_gate_1/macos_computer_use_m51_production_launch_gate.json',
        _m51ProductionLaunchGate(),
      );

      final summary = buildMacosComputerUseM52ProductReleaseSummary(
        readMacosComputerUseM52ProductReleaseInputs(reportRoot: root),
      );
      final blockedIds = summary.blockedGates
          .map((gate) => gate.id)
          .toList(growable: false);

      expect(summary.ready, isFalse);
      expect(blockedIds, contains('default_off_confirmed'));
      expect(blockedIds, contains('advanced_settings_confirmed'));
      expect(blockedIds, contains('rollback_runbook_ready'));
      expect(blockedIds, contains('support_runbook_ready'));
      expect(blockedIds, isNot(contains('m51_production_launch_gate')));
      expect(
        summary.releaseRolloutSummary['blockedUserOperatedGateIds'],
        contains('rollout_monitoring_ready'),
      );
    });

    test('blocks rollout when M51 production launch evidence is blocked', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_m52_release_m51_blocked_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      _writeJson(
        '${root.path}/manual/m52_product_release_checklist.json',
        _productReleaseChecklist(),
      );
      _writeJson(
        '${root.path}/macos_computer_use_m51_production_launch_gate_1/macos_computer_use_m51_production_launch_gate.json',
        _m51ProductionLaunchGate(ready: false),
      );

      final summary = buildMacosComputerUseM52ProductReleaseSummary(
        readMacosComputerUseM52ProductReleaseInputs(reportRoot: root),
      );

      expect(summary.ready, isFalse);
      final m51Gate = summary.gates.singleWhere(
        (gate) => gate.id == 'm51_production_launch_gate',
      );
      expect(m51Gate.ready, isFalse);
      expect(m51Gate.details['blockers'], contains('support_diagnostics'));
    });

    test(
      'CLI writes JSON and Markdown summaries',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'computer_use_m52_release_cli_',
        );
        addTearDown(() => root.deleteSync(recursive: true));

        final checklistPath = _writeJson(
          '${root.path}/manual/m52_product_release_checklist.json',
          _productReleaseChecklist(),
        );
        final m51Path = _writeJson(
          '${root.path}/m51.json',
          _m51ProductionLaunchGate(),
        );
        final outputJson = '${root.path}/out/m52.json';
        final outputMd = '${root.path}/out/m52.md';

        final result = await Process.run('dart', <String>[
          'run',
          'tool/macos_computer_use_m52_product_release_rollout.dart',
          '--root',
          root.path,
          '--product-release-checklist',
          checklistPath,
          '--m51-production-launch-gate',
          m51Path,
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
          contains('Product Release Summary'),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('wrapper and docs keep M52 report-only boundaries visible', () {
      final wrapper = File(
        'tool/run_macos_computer_use_m52_product_release_rollout.sh',
      ).readAsStringSync();
      final architecture = File(
        'docs/macos_computer_use_helper_architecture.md',
      ).readAsStringSync();
      final checklist = File(
        'docs/macos_computer_use_manual_process_checklist.md',
      ).readAsStringSync();

      expect(wrapper, contains('report-only'));
      expect(wrapper, contains('Advanced settings rollout'));
      expect(wrapper, contains('no desktop actions'));
      expect(
        architecture,
        contains('macos_computer_use_m52_product_release_rollout'),
      );
      expect(checklist, contains('M52 Product Release Rollout'));
      expect(checklist, contains('ready_for_product_release'));
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

Map<String, Object?> _productReleaseChecklist() {
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m52_product_release_checklist',
    'schemaVersion': 1,
    'milestone': 'M52',
    'automationBoundary': 'user_operated_release_steps',
    'defaultOffConfirmed': _readySection('Computer Use remains default off.'),
    'advancedSettingsConfirmed': _readySection(
      'Settings > Advanced enablement verified.',
    ),
    'reversibleDisablePath': _readySection(
      'Disable path and emergency stop verified.',
    ),
    'rollbackRunbookReady': _readySection('Rollback runbook approved.'),
    'supportRunbookReady': _readySection('Support runbook approved.'),
    'privacyReleaseNotesReady': _readySection(
      'Privacy copy and release notes approved.',
    ),
    'supportDiagnosticsReady': _readySection(
      'Support diagnostics handoff verified.',
    ),
    'rolloutMonitoringReady': _readySection(
      'Rollout owner, monitoring, and escalation confirmed.',
    ),
  };
}

Map<String, Object?> _m51ProductionLaunchGate({bool ready = true}) {
  final blockedGateIds = ready ? <String>[] : <String>['support_diagnostics'];
  return <String, Object?>{
    'schemaName': 'macos_computer_use_m51_production_launch_gate',
    'schemaVersion': 1,
    'milestone': 'M51',
    'status': ready ? 'ready' : 'blocked',
    'ready': ready,
    'readyGateIds': ready
        ? <String>['signed_artifact', 'production_launch_boundaries']
        : <String>['signed_artifact'],
    'blockedGateIds': blockedGateIds,
    'launchReviewSummary': <String, Object?>{
      'status': ready ? 'ready_for_production_launch' : 'blocked_gates_present',
      'readyGateIds': ready
          ? <String>['signed_artifact', 'production_launch_boundaries']
          : <String>['signed_artifact'],
      'blockedGateIds': blockedGateIds,
      'blockedUserOperatedGateIds': blockedGateIds,
      'blockedAutomationSafeGateIds': <String>[],
      'operationBoundarySummary':
          'M51 reads release evidence only; release steps remain user-operated.',
    },
    'gates': <Object?>[],
  };
}
