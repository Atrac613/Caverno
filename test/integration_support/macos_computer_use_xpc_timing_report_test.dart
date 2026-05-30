import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_tool_process.dart';

import 'package:caverno/core/services/macos_computer_use_xpc_timing_report.dart';

void main() {
  test('classifies a preferred XPC response before timeout as ready', () {
    final summary = buildXpcTimingReportSummary({
      'helperIpcRuntime': {
        'selectedIpcTransport': 'xpc_service',
        'preferredIpcTransport': 'xpc_service',
        'fallbackIpcTransport': 'distributed_notification_center',
        'preferredAttemptStatus': 'xpc_response',
        'preferredAttemptElapsedMs': 84,
        'preferredAttemptResponseReceivedBeforeTimeout': true,
      },
    }, sourcePath: 'diagnostics.json');

    expect(summary.ready, isTrue);
    expect(summary.classification, 'responded_before_timeout');
    expect(summary.elapsedMs, 84);
    expect(summary.responseReceivedBeforeTimeout, isTrue);
    expect(
      summary.nextAction,
      'Preferred XPC responded before timeout. No timeout mitigation is needed.',
    );
    expect(summary.recommendedActionId, 'none');
    expect(
      summary.userNextAction,
      'Run the Computer Use smoke sequence when ready.',
    );
    expect(
      summary.engineeringNextAction,
      'No preferred XPC timeout mitigation is needed.',
    );
  });

  test('classifies a late XPC response after timeout', () {
    final summary = buildXpcTimingReportSummary({
      'helperIpcRuntime': {
        'selectedIpcTransport': 'distributed_notification_center',
        'preferredIpcTransport': 'xpc_service',
        'fallbackIpcTransport': 'distributed_notification_center',
        'preferredFallbackSucceeded': true,
        'preferredAttemptStatus': 'xpc_timeout',
        'preferredAttemptErrorCode': 'helper_xpc_timeout',
        'preferredAttemptElapsedMs': 2002,
        'preferredAttemptTimeoutMs': 2000,
        'preferredAttemptResponseReceivedBeforeTimeout': false,
        'preferredAttemptResponseReceivedAfterTimeout': true,
        'preferredAttemptLateResponseElapsedMs': 2098,
        'preferredIpcAttempt': {
          'warmupAttempt': {
            'status': 'xpc_response',
            'elapsedMs': 41,
            'responseReceivedBeforeTimeout': true,
          },
        },
      },
    }, sourcePath: 'diagnostics.json');

    expect(summary.ready, isFalse);
    expect(summary.classification, 'late_response_within_current_budget');
    expect(summary.errorCode, 'helper_xpc_timeout');
    expect(summary.elapsedMs, 2002);
    expect(summary.timeoutMs, 2000);
    expect(summary.currentPreferredFallbackTimeoutMs, 3000);
    expect(summary.currentTimeoutHeadroomMs, 902);
    expect(summary.responseReceivedBeforeTimeout, isFalse);
    expect(summary.responseReceivedAfterTimeout, isTrue);
    expect(summary.lateResponseElapsedMs, 2098);
    expect(summary.preferredFallbackSucceeded, isTrue);
    expect(summary.warmupStatus, 'xpc_response');
    expect(summary.warmupElapsedMs, 41);
    expect(summary.warmupResponseReceivedBeforeTimeout, isTrue);
    expect(
      summary.nextAction,
      'Rerun Computer Use diagnostics with the current preferred XPC timeout.',
    );
    expect(summary.recommendedActionId, 'rerun_with_current_xpc_timeout');
    expect(
      summary.userNextAction,
      'No manual TCC action is required; recheck permissions or reopen Computer Use to collect fresh timing.',
    );
    expect(
      summary.engineeringNextAction,
      'No timeout tuning is needed unless the rerun still times out under the current budget.',
    );
  });

  test('keeps late XPC responses beyond the current budget as tuning work', () {
    final summary = buildXpcTimingReportSummary({
      'helperIpcRuntime': {
        'selectedIpcTransport': 'distributed_notification_center',
        'preferredIpcTransport': 'xpc_service',
        'fallbackIpcTransport': 'distributed_notification_center',
        'preferredFallbackSucceeded': true,
        'preferredAttemptStatus': 'xpc_timeout',
        'preferredAttemptErrorCode': 'helper_xpc_timeout',
        'preferredAttemptElapsedMs': 3001,
        'preferredAttemptTimeoutMs': 3000,
        'preferredAttemptResponseReceivedBeforeTimeout': false,
        'preferredAttemptResponseReceivedAfterTimeout': true,
        'preferredAttemptLateResponseElapsedMs': 3200,
      },
    }, sourcePath: 'diagnostics.json');

    expect(summary.ready, isFalse);
    expect(summary.classification, 'late_response_after_timeout');
    expect(summary.currentTimeoutHeadroomMs, -200);
    expect(
      summary.nextAction,
      'Tune the preferred XPC timeout or add a warmup ping before fallback.',
    );
  });

  test('reads nested helper status preferred attempt data', () {
    final summary = buildXpcTimingReportSummary({
      'lastResult': {
        'helperStatus': {
          'lastPreferredIpcAttempt': {
            'status': 'xpc_timeout',
            'errorCode': 'helper_xpc_timeout',
            'elapsedMs': 2000,
            'responseReceivedBeforeTimeout': false,
          },
        },
      },
    }, sourcePath: 'diagnostics.json');

    expect(summary.classification, 'no_response_before_timeout');
    expect(
      summary.nextAction,
      'Inspect LaunchAgent registration and helper XPC listener startup.',
    );
    expect(summary.recommendedActionId, 'inspect_launch_agent_listener');
    expect(
      summary.userNextAction,
      'Restart Caverno Computer Use from Caverno, then recheck permissions.',
    );
  });

  test('writes Markdown and JSON through the CLI parser', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_xpc_timing_report_',
    );
    try {
      final input = File('${root.path}/diagnostics.json')
        ..writeAsStringSync(
          jsonEncode({
            'helperIpcRuntime': {
              'preferredAttemptStatus': 'xpc_response',
              'preferredAttemptElapsedMs': 32,
              'preferredAttemptResponseReceivedBeforeTimeout': true,
            },
          }),
        );
      final outputJson = File('${root.path}/summary.json');
      final outputMd = File('${root.path}/summary.md');

      final result = await runDartTool(
        'tool/macos_computer_use_xpc_timing_report.dart',
        [
          input.path,
          '--output-json',
          outputJson.path,
          '--output-md',
          outputMd.path,
        ],
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final summary = jsonDecode(outputJson.readAsStringSync()) as Map;
      expect(
        summary['schemaName'],
        'macos_computer_use_xpc_timing_report_summary',
      );
      expect(summary['classification'], 'responded_before_timeout');
      expect(outputMd.readAsStringSync(), contains('XPC Timing Report'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
