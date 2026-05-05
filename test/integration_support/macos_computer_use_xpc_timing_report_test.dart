import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
        'preferredAttemptResponseReceivedBeforeTimeout': false,
        'preferredAttemptResponseReceivedAfterTimeout': true,
        'preferredAttemptLateResponseElapsedMs': 2098,
      },
    }, sourcePath: 'diagnostics.json');

    expect(summary.ready, isFalse);
    expect(summary.classification, 'late_response_after_timeout');
    expect(summary.errorCode, 'helper_xpc_timeout');
    expect(summary.elapsedMs, 2002);
    expect(summary.responseReceivedBeforeTimeout, isFalse);
    expect(summary.responseReceivedAfterTimeout, isTrue);
    expect(summary.lateResponseElapsedMs, 2098);
    expect(summary.preferredFallbackSucceeded, isTrue);
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

      final result = await Process.run('dart', [
        'run',
        'tool/macos_computer_use_xpc_timing_report.dart',
        input.path,
        '--output-json',
        outputJson.path,
        '--output-md',
        outputMd.path,
      ]);

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
