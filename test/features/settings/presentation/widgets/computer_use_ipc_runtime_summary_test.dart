import 'package:caverno/features/settings/presentation/widgets/computer_use_ipc_runtime_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves required missing-value fallbacks', () {
    final viewModel = ComputerUseIpcRuntimeSummaryViewModel.fromRuntime({});

    expect(viewModel.status, 'using null');
    expect(viewModel.rows.map((row) => '${row.label}: ${row.value}'), [
      'Active IPC: null',
      'Preferred IPC: null',
      'XPC status: null',
      'XPC connection: null',
      'XPC registration: null',
      'XPC gate: blockers',
      'Named XPC: fallback',
      'XPC next action: null',
      'TCC owner: helper',
      'OS executor: main app',
      'OS action owner: main app',
      'Main app OS actions: blocked',
      'Next XPC parity: none',
    ]);
  });

  test('normalizes every diagnostic row in the existing order', () {
    final viewModel = ComputerUseIpcRuntimeSummaryViewModel.fromRuntime(
      _richRuntime(),
    );

    expect(viewModel.status, 'preferred XPC fell back to notification');
    expect(viewModel.rows.map((row) => row.label), [
      'Active IPC',
      'Preferred IPC',
      'XPC commands',
      'XPC status',
      'XPC connection',
      'XPC registration',
      'LaunchAgent',
      'LaunchAgent plist',
      'XPC gate',
      'Named XPC',
      'XPC blockers',
      'Signing gate',
      'Signing blockers',
      'XPC runtime',
      'XPC listener',
      'Runtime blockers',
      'Helper diagnostics',
      'Helper path',
      'Helper identity',
      'Runtime helper',
      'Release sign-off',
      'Helper path sign-off',
      'Helper runtime use',
      'M38 migration gate',
      'TCC regrant',
      'Old helper actions',
      'M38 blockers',
      'M38 next action',
      'Helper path blockers',
      'Helper path sign-off next action',
      'Helper path next action',
      'Helper runtime next action',
      'Embedded helper',
      'Running helper',
      'Existing probe',
      'Probe helper path',
      'Probe expected helper',
      'Probe running helper',
      'Probe failed checks',
      'Permission gate',
      'Permission blockers',
      'Capture gate',
      'Capture blockers',
      'Capture failure',
      'Capture steps',
      'Capture TCC owner',
      'Input gate',
      'Input blockers',
      'Audio gate',
      'Audio blockers',
      'Overlay smoke',
      'Overlay placement',
      'Overlay mode',
      'Overlay pasteboard',
      'Overlay grant targets',
      'Overlay blockers',
      'Unsafe action gate',
      'Unsafe blockers',
      'Positive smoke gate',
      'Positive smoke blockers',
      'Readiness expectations',
      'M4 sign-off',
      'M4 blockers',
      'M4 helper',
      'M4 next action',
      'Failed expectations',
      'XPC next action',
      'TCC owner',
      'TCC owner bundle',
      'OS executor',
      'OS action owner',
      'Main app OS actions',
      'Preferred attempt',
      'Preferred error',
      'Preferred elapsed',
      'XPC response before timeout',
      'XPC late response',
      'XPC late elapsed',
      'Fallback reason',
      'Fallback outcome',
      'Next XPC parity',
    ]);
  });

  test('preserves deduplication, path shortening, and derived values', () {
    final rows = _rowsByLabel(
      ComputerUseIpcRuntimeSummaryViewModel.fromRuntime(_richRuntime()),
    );

    expect(rows['XPC commands'], 'ping, screenshot');
    expect(rows['Helper diagnostics'], 'stale: shared_stale, runtime_stale');
    expect(
      rows['Runtime helper'],
      '.../Caverno.app/Contents/Helpers/Running Helper.app',
    );
    expect(rows['Probe expected helper'], '/short/helper.app');
    expect(rows['Overlay placement'], 'system_settings');
    expect(rows['Overlay mode'], 'floating, attached');
    expect(rows['Overlay pasteboard'], 'public.url, null, public.file-url');
    expect(
      rows['Overlay grant targets'],
      '.../Caverno.app/Contents/Helpers/Running Helper.app, .../Caverno.app/Contents/Helpers/Embedded Helper.app',
    );
    expect(rows['Capture failure'], 'timeout, permission');
    expect(
      rows['Capture steps'],
      'display=failed, windows=passed, window=skipped',
    );
    expect(rows['Preferred attempt'], 'xpc_timeout, fallback succeeded');
    expect(rows['Fallback outcome'], 'succeeded');
    expect(rows['Next XPC parity'], 'click, typeText');
  });

  test('ignores wrong nested types but preserves empty-map presentation', () {
    final viewModel = ComputerUseIpcRuntimeSummaryViewModel.fromRuntime({
      'selectedIpcTransport': 'xpc',
      'preferredIpcTransport': 'xpc',
      'fallbackIpcTransport': 'notification',
      'signingDiagnostics': <String, dynamic>{},
      'xpcRuntimeDiagnostics': <String, dynamic>{},
      'permissionGate': <String, dynamic>{},
      'captureGate': <String, dynamic>{'stepDiagnostics': <String, dynamic>{}},
      'inputGate': <String, dynamic>{},
      'audioGate': <String, dynamic>{},
      'overlaySmoke': <String, dynamic>{
        'accessibility': 'not a map',
        'screenRecording': 7,
      },
      'unsafeActionGate': <String, dynamic>{},
      'positiveSmokeGateSummary': <String, dynamic>{},
      'readinessExpectations': <String, dynamic>{},
      'm4SignoffGate': <String, dynamic>{'helperPath': 'not a map'},
      'helperPathMatchesRunningHelper': 'not a bool',
      'helperPathSignoffGate': <String, dynamic>{},
      'helperRuntimeUseGate': <String, dynamic>{},
      'installMigrationGuardrails': <String, dynamic>{
        'm38InstallMigrationGate': 'not a map',
      },
      'helperPathMismatchDetails': 'not a map',
      'xpcSupportedCommands': 'not a list',
      'xpcNextParityCommands': 'not a list',
      'xpcProductionNextAction': 'Review.',
    });
    final rows = _rowsByLabel(viewModel);

    expect(rows['Signing gate'], 'blockers');
    expect(rows['XPC runtime'], 'ready');
    expect(rows['XPC listener'], 'not started');
    expect(rows['Permission gate'], 'clear');
    expect(rows['Capture gate'], 'null');
    expect(rows['Capture steps'], '');
    expect(rows['Input gate'], 'null');
    expect(rows['Audio gate'], 'null');
    expect(rows['Overlay smoke'], 'null');
    expect(rows['Unsafe action gate'], 'null');
    expect(rows['Positive smoke gate'], 'null');
    expect(rows['Readiness expectations'], 'failed');
    expect(rows['M4 sign-off'], 'null');
    expect(rows['Helper path'], 'unknown');
    expect(rows['Helper path sign-off'], 'null');
    expect(rows['Helper runtime use'], 'null');
    expect(rows['M38 migration gate'], 'null');
    expect(rows, isNot(contains('XPC commands')));
    expect(rows['Next XPC parity'], 'none');
  });

  test('copies source values into an unmodifiable row list', () {
    final commands = <dynamic>['ping'];
    final captureGate = <String, dynamic>{'status': 'ready'};
    final runtime = <String, dynamic>{
      'selectedIpcTransport': 'xpc',
      'preferredIpcTransport': 'xpc',
      'fallbackIpcTransport': 'notification',
      'xpcSupportedCommands': commands,
      'captureGate': captureGate,
    };
    final viewModel = ComputerUseIpcRuntimeSummaryViewModel.fromRuntime(
      runtime,
    );

    commands.add('screenshot');
    captureGate['status'] = 'blocked';
    runtime['selectedIpcTransport'] = 'notification';

    final rows = _rowsByLabel(viewModel);
    expect(viewModel.status, 'using xpc');
    expect(rows['Active IPC'], 'xpc');
    expect(rows['XPC commands'], 'ping');
    expect(rows['Capture gate'], 'ready');
    expect(
      () => viewModel.rows.add(
        const ComputerUseIpcRuntimeInfoRow(label: 'Extra', value: 'row'),
      ),
      throwsUnsupportedError,
    );
  });

  testWidgets('renders immutable rows as ordered info chips', (tester) async {
    final viewModel = ComputerUseIpcRuntimeSummaryViewModel(
      status: 'using xpc',
      rows: const [
        ComputerUseIpcRuntimeInfoRow(label: 'Active IPC', value: 'xpc'),
        ComputerUseIpcRuntimeInfoRow(label: 'XPC gate', value: 'ready'),
      ],
    );

    await _pumpSummary(tester, viewModel);

    expect(find.text('IPC runtime: using xpc'), findsOneWidget);
    expect(find.text('Active IPC: xpc'), findsOneWidget);
    expect(find.text('XPC gate: ready'), findsOneWidget);
    expect(find.byType(Chip), findsNWidgets(2));
    expect(find.byIcon(Icons.info_outline), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Active IPC: xpc')).dx,
      lessThan(tester.getTopLeft(find.text('XPC gate: ready')).dx),
    );
  });
}

Map<String, String> _rowsByLabel(
  ComputerUseIpcRuntimeSummaryViewModel viewModel,
) {
  return {for (final row in viewModel.rows) row.label: row.value};
}

Map<String, dynamic> _richRuntime() {
  const embeddedHelper =
      '/Applications/Caverno.app/Contents/Helpers/Embedded Helper.app';
  const runningHelper =
      '/Applications/Caverno.app/Contents/Helpers/Running Helper.app';
  return {
    'selectedIpcTransport': 'notification',
    'preferredIpcTransport': 'xpc',
    'fallbackIpcTransport': 'notification',
    'xpcSupportedCommands': ['ping', '', 'screenshot'],
    'xpcNextParityCommands': ['click', '', 'typeText'],
    'xpcStatus': 'production',
    'xpcConnectionMode': 'external_helper',
    'xpcRegistrationRequirement': 'launchd',
    'xpcLaunchAgentStatus': 'loaded',
    'xpcLaunchAgentPlistInstalled': true,
    'xpcProductionReadyMeasured': false,
    'xpcNamedServiceConnected': false,
    'xpcProductionBlockers': ['registration_missing'],
    'signingDiagnostics': {
      'launchConstraintLikelyAccepted': false,
      'launchConstraintBlockers': ['signature'],
    },
    'xpcRuntimeDiagnostics': {
      'blockers': ['listener'],
      'xpcListenerStarted': false,
      'xpcListenerStartAttempted': true,
      'helperDiagnosticsLatestStale': true,
      'helperDiagnosticsStaleReasons': ['shared_stale', 'runtime_stale'],
    },
    'helperSharedDiagnosticsStale': true,
    'helperSharedDiagnosticsStaleReasons': ['shared_stale', ''],
    'helperPathMatchesRunningHelper': false,
    'helperPathMismatch': true,
    'preservedMismatchedHelperPath': true,
    'helperPathSignoffGate': {
      'status': 'blocked',
      'blockers': ['helper_path_mismatch'],
      'nextAction': 'Match the helper path.',
    },
    'helperRuntimeUseGate': {
      'status': 'current_session',
      'nextAction': 'Keep the current helper.',
    },
    'installMigrationGuardrails': {
      'status': 'blocked',
      'tccRegrantRequired': true,
      'oldHelperActionRequestsBlocked': true,
      'm38InstallMigrationGate': {
        'blockers': ['helper_path_mismatch'],
      },
      'nextAction': 'Complete migration.',
    },
    'helperPathMismatchDetails': {'nextAction': 'Restart the helper.'},
    'embeddedHelperPath': embeddedHelper,
    'runningHelperPath': runningHelper,
    'existingHelperProbeOk': false,
    'existingHelperProbeHelperPathMatchesExpected': false,
    'existingHelperProbeFailedRequiredChecks': ['path_match'],
    'existingHelperProbeExpectedHelperPath': '/short/helper.app',
    'existingHelperProbeRunningHelperPath': runningHelper,
    'permissionGate': {
      'blockedByPermissions': ['screen_capture'],
    },
    'captureGate': {
      'status': 'blocked',
      'blockers': ['screen_capture_permission_missing'],
      'failureClass': 'timeout',
      'failureClasses': ['timeout', 'permission'],
      'stepDiagnostics': {
        'displayScreenshot': {'status': 'failed'},
        'listWindows': {'status': 'passed'},
        'windowCapture': {'status': 'skipped'},
      },
      'tccOwnerHelperPath': runningHelper,
    },
    'inputGate': {
      'status': 'not_armed',
      'blockers': ['unsafe_smoke_not_armed'],
    },
    'audioGate': {
      'status': 'unsupported',
      'blockers': ['audio_unavailable'],
    },
    'overlaySmoke': {
      'status': 'blocked',
      'blockers': ['overlay_missing'],
      'accessibility': {
        'overlayPlacement': 'system_settings',
        'overlayMode': 'floating',
        'dragPasteboardTypes': ['public.url', null],
        'grantTargetBundlePath': runningHelper,
        'helperBundlePath': embeddedHelper,
      },
      'screenRecording': {
        'overlayPlacement': 'system_settings',
        'overlayMode': 'attached',
        'dragPasteboardTypes': ['public.url', 'public.file-url'],
        'grantTargetBundlePath': runningHelper,
        'helperBundlePath': embeddedHelper,
      },
    },
    'unsafeActionGate': {
      'status': 'not_armed',
      'blockers': ['unsafe_smoke_not_armed'],
    },
    'positiveSmokeGateSummary': {
      'status': 'blocked',
      'blockedBy': ['capture'],
    },
    'readinessExpectations': {
      'ok': false,
      'failed': ['capture_ready'],
    },
    'm4SignoffGate': {
      'status': 'blocked',
      'blockers': ['permissions', 'capture'],
      'helperPath': {'embeddedHelperPath': embeddedHelper},
      'nextAction': 'Resolve M4 blockers.',
    },
    'xpcProductionNextAction': 'Resolve XPC blockers.',
    'mainAppOwnsTccPermissions': true,
    'tccPermissionOwnerDisplayName': 'Caverno Computer Use',
    'tccPermissionOwnerBundleIdentifier': 'com.example.helper',
    'helperActsAsOsActionExecutor': true,
    'helperOwnsUnsafeOsActions': true,
    'mainAppUnsafeOsActionsAllowed': true,
    'preferredAttemptStatus': 'xpc_timeout',
    'preferredAttemptErrorCode': 'helper_xpc_timeout',
    'preferredAttemptElapsedMs': 2001,
    'preferredAttemptResponseReceivedBeforeTimeout': false,
    'preferredAttemptResponseReceivedAfterTimeout': true,
    'preferredAttemptLateResponseElapsedMs': 2300,
    'preferredFallbackReason': 'xpc_timeout (helper_xpc_timeout)',
    'preferredFallbackSummary': 'xpc_timeout, fallback succeeded',
    'preferredFallbackActive': true,
    'preferredFallbackSucceeded': true,
  };
}

Future<void> _pumpSummary(
  WidgetTester tester,
  ComputerUseIpcRuntimeSummaryViewModel viewModel,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ComputerUseIpcRuntimeSummary(viewModel: viewModel),
        ),
      ),
    ),
  );
}
