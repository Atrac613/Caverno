import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/macos_computer_use_canary_history.dart';
import '../../integration_test/test_support/macos_computer_use_manual_tcc_report.dart';

void main() {
  group('Computer Use canary history', () {
    test('summarizes latest stability and pass-rate delta', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_canary_history_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      _writeCanarySummary(
        root,
        name: 'macos_computer_use_live_canary_100',
        passRate: 0,
        passed: 0,
        failed: 1,
        stable: false,
        failureClasses: const <String, int>{'ipc_not_ready': 1},
      );
      _writeCanarySummary(
        root,
        name: 'macos_computer_use_live_canary_200',
        passRate: 1,
        passed: 3,
        failed: 0,
        stable: true,
        stabilityMode: true,
        failureClasses: const <String, int>{'passed': 3},
      );

      final history = buildComputerUseCanaryHistory(root);

      expect(history.entries, hasLength(2));
      expect(history.latest?.name, 'macos_computer_use_live_canary_200');
      expect(history.latest?.stable, isTrue);
      expect(history.latest?.overlayForegroundCanary, isTrue);
      expect(history.latest?.overlaySmokeStatus, 'ready');
      expect(
        history.latest?.helperProcessPolicy['helperPathMatchesRunningHelper'],
        isTrue,
      );
      expect(
        history.latest?.manualTccHandoff['manualCommand'],
        contains('--m8-runtime-signoff'),
      );
      expect(
        history.latest?.manualTccHandoff['handoffCommand'],
        contains('--handoff-only'),
      );
      expect(history.latestPassRateDelta, 1);
      expect(history.toJson()['latestStatus'], 'stable');
      expect(history.toMarkdown(), contains('ipc_not_ready: 1'));
      expect(history.toMarkdown(), contains('Latest pass-rate delta: +100.0%'));
      expect(history.toMarkdown(), contains('Overlay smoke status: ready'));
      expect(history.toMarkdown(), contains('Helper path match: true'));
      expect(history.toMarkdown(), contains('Manual TCC handoff command'));
      expect(history.toMarkdown(), contains('--handoff-only'));
    });

    test('honors the requested history limit', () {
      final root = Directory.systemTemp.createTempSync(
        'computer_use_canary_history_limit_test_',
      );
      addTearDown(() {
        root.deleteSync(recursive: true);
      });

      _writeCanarySummary(
        root,
        name: 'macos_computer_use_live_canary_100',
        passRate: 1,
        passed: 1,
        failed: 0,
        stable: true,
      );
      _writeCanarySummary(
        root,
        name: 'macos_computer_use_live_canary_200',
        passRate: 1,
        passed: 1,
        failed: 0,
        stable: true,
      );

      final history = buildComputerUseCanaryHistory(root, limit: 1);

      expect(history.entries, hasLength(1));
      expect(history.latest?.name, 'macos_computer_use_live_canary_200');
    });
  });

  group('manual TCC report parser', () {
    test('marks a user-produced ready report as ready', () {
      final summary = buildManualTccReportSummary(<String, dynamic>{
        'releaseRuntimeSignoffGate': <String, dynamic>{
          'status': 'ready',
          'blockers': <String>[],
          'appPath': '/tmp/Caverno.app',
          'helperPath': '/tmp/Caverno Computer Use.app',
          'checks': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'permission_status',
              'label': 'Permission status',
              'status': 'ready',
              'ok': true,
            },
          ],
        },
      }, reportPath: '/tmp/report.json');

      expect(summary.ready, isTrue);
      expect(
        summary.toJson()['automationBoundary'],
        'parse_user_produced_report_only',
      );
      expect(summary.toJson()['failureClasses'], isEmpty);
      expect(summary.toMarkdown(), contains('Automation boundary'));
    });

    test('surfaces blocked checks and next actions', () {
      final summary = buildManualTccReportSummary(<String, dynamic>{
        'releaseRuntimeSignoffGate': <String, dynamic>{
          'status': 'blocked',
          'blockers': <String>['release_runtime_permissions_blocked'],
          'nextAction': 'Ask the user to grant the release helper.',
          'checks': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'permission_status',
              'label': 'Permission status',
              'status': 'blocked',
              'ok': false,
              'nextAction': 'Grant permissions manually.',
            },
          ],
        },
        'captureGate': <String, dynamic>{
          'failureClasses': <String>['screen_capture_permission_missing'],
          'nextAction': 'Ask the user to rerun capture after manual TCC.',
        },
      }, reportPath: '/tmp/report.json');

      expect(summary.ready, isFalse);
      expect(summary.blockers, contains('release_runtime_permissions_blocked'));
      expect(summary.failureClasses, contains('permissions_missing'));
      expect(
        summary.captureFailureClasses,
        contains('screen_capture_permission_missing'),
      );
      expect(summary.toJson()['failedChecks'], isNotEmpty);
      expect(
        summary.toJson()['captureFailureClasses'],
        contains('screen_capture_permission_missing'),
      );
      expect(summary.toMarkdown(), contains('## Failed Checks'));
      expect(summary.toMarkdown(), contains('Grant permissions manually.'));
      expect(
        summary.toMarkdown(),
        contains('Capture failure classes: screen_capture_permission_missing'),
      );
    });
  });
}

void _writeCanarySummary(
  Directory root, {
  required String name,
  required double passRate,
  required int passed,
  required int failed,
  required bool stable,
  bool stabilityMode = false,
  Map<String, int> failureClasses = const <String, int>{},
}) {
  final directory = Directory('${root.path}/$name')..createSync();
  final summary = File('${directory.path}/canary_summary.json');
  summary.writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaName': 'macos_computer_use_live_canary_summary',
      'schemaVersion': 1,
      'purpose': 'computer_use_helper_runtime_canary',
      'tccBoundary': 'manual_user_operated',
      'overlayForegroundCanary': true,
      'overlaySmokeStatus': 'ready',
      'helperProcessPolicy': <String, Object?>{
        'status': 'ready',
        'helperPathMismatch': false,
        'helperPathMatchesRunningHelper': true,
        'preservedMismatchedHelperPath': false,
      },
      'manualTccHandoff': <String, Object?>{
        'status': 'manual_required',
        'handoffCommand':
            'bash tool/run_macos_computer_use_manual_tcc_signoff.sh --handoff-only',
        'manualCommand':
            'bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --m8-runtime-signoff',
        'summaryCommand':
            'dart run tool/macos_computer_use_manual_tcc_report.dart <user-produced-m8-report.json>',
      },
      'preset': 'ci',
      'stabilityMode': stabilityMode,
      'stable': stable,
      'runCount': passed + failed,
      'passed': passed,
      'failed': failed,
      'passRate': passRate,
      'failureClasses': failureClasses,
      'runs': const <Object>[],
    }),
  );
}
