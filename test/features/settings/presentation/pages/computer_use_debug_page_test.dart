import 'dart:convert';

import 'package:caverno/core/services/macos_computer_use_audit_log.dart';
import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:caverno/core/services/macos_computer_use_tool_policy.dart';
import 'package:caverno/features/settings/presentation/pages/computer_use_debug_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MacosComputerUseAuditLog.instance.clear();
  });

  testWidgets('shows helper boundary while using helper IPC backend', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    expect(find.text('Computer Use App Boundary'), findsOneWidget);
    expect(find.text('Current executor'), findsOneWidget);
    expect(find.text('Permission owner now'), findsOneWidget);
    expect(find.text('Target helper'), findsOneWidget);
    expect(find.text('Caverno Computer Use (helper_ipc)'), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Reachable'), findsOneWidget);
    expect(
      find.text('Caverno Computer Use (com.noguwo.apps.caverno.computer-use)'),
      findsOneWidget,
    );
    expect(service.helperStatusCallCount, 1);
    expect(service.pingHelperCallCount, 1);
  });

  testWidgets('shows onboarding checklist progress and production XPC status', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    expect(find.text('Computer Use Onboarding'), findsOneWidget);
    expect(find.text('2 of 10 complete'), findsOneWidget);
    expect(find.text('Launch Caverno Computer Use'), findsOneWidget);
    expect(find.text('MVP Sign-Off Path'), findsOneWidget);
    expect(find.text('MVP Evidence Preflight'), findsOneWidget);
    expect(find.text('User-Operated MVP Commands'), findsOneWidget);
    expect(find.text('MVP Artifact Paths'), findsOneWidget);
    expect(
      find.textContaining(
        'release_artifact, canary_history, manual_tcc, desktop_action_canary, llm_canary',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('User-operated: manual_tcc, desktop_action_canary'),
      findsOneWidget,
    );
    expect(
      find.textContaining('run_macos_computer_use_mvp_signoff.sh'),
      findsOneWidget,
    );
    expect(find.textContaining('--final-signoff'), findsOneWidget);
    expect(find.textContaining('--manual-tcc-report'), findsOneWidget);
    expect(
      find.textContaining('--desktop-action-canary-summary'),
      findsOneWidget,
    );
    expect(find.textContaining('--llm-canary-summary'), findsOneWidget);
    expect(
      find.textContaining('run_macos_computer_use_manual_tcc_signoff.sh'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'run_macos_computer_use_desktop_action_canary.sh --fixture-target',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_mvp_handoff.md'),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_mvp_readiness.md'),
      findsOneWidget,
    );
    expect(
      find.textContaining('manual_tcc_report_summary.json'),
      findsNWidgets(2),
    );
    expect(find.textContaining('canary_summary.json'), findsNWidgets(2));
    expect(
      find.textContaining('/tmp/caverno-macos-computer-use-smoke.json'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Grant Screen & System Audio Recording to Caverno Computer Use',
      ),
      findsOneWidget,
    );
    expect(find.text('XPC Production Ready'), findsOneWidget);
    expect(find.text('XPC is production ready.'), findsOneWidget);
  });

  testWidgets('shows manual TCC handoff from the latest smoke report', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    expect(find.text('Manual TCC Handoff'), findsOneWidget);
    expect(
      find.textContaining('--m8-runtime-signoff', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'tool/macos_computer_use_manual_tcc_report.dart',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows the manual boundary before smoke sequence actions', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _scrollUntilVisible(tester, find.text('Manual Smoke Boundary'));

    expect(find.text('Manual Smoke Boundary'), findsOneWidget);
    expect(
      find.text(
        'Run Smoke Sequence uses the permissions already granted to Caverno Computer Use. TCC grants and desktop actions stay user-operated; input and audio checks run only after explicit arming.',
      ),
      findsOneWidget,
    );
    expect(find.text('Run Smoke Sequence'), findsOneWidget);
  });

  testWidgets('shows helper path mismatch next action', (tester) async {
    final service = _FakeMacosComputerUseService(helperPathMismatch: true);
    await _pumpPage(tester, service);

    expect(find.text('Helper Path Mismatch'), findsOneWidget);
    expect(
      find.textContaining(
        'Next: Keep using the currently granted helper for this session',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Sign-off: blocked until helper path matches'),
      findsOneWidget,
    );
  });

  testWidgets('shows overlay canary summary from the latest smoke report', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    expect(find.text('Overlay Canary'), findsOneWidget);
    expect(
      find.textContaining('foreground accessory_overlay_front'),
      findsOneWidget,
    );
    expect(find.textContaining('floating true'), findsOneWidget);
    expect(find.textContaining('hides false'), findsOneWidget);
  });

  testWidgets('refreshes permission and audio recording state', (tester) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Refresh');

    expect(find.text('Granted'), findsNWidgets(2));
    expect(find.text('Reachable'), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget);
    expect(
      find.text('Action required: Screen & System Audio Recording'),
      findsOneWidget,
    );

    await _tapSwitch(tester, 'System Audio Armed');
    await _tapButton(tester, 'Start Recording');

    expect(find.text('Recording active'), findsOneWidget);
    expect(service.startAudioCallCount, 1);

    await _tapButton(tester, 'Stop Recording');

    expect(find.text('Not recording'), findsOneWidget);
    expect(service.stopAudioCallCount, 1);
  });

  testWidgets('pings and stops helper work from the permission panel', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Ping Helper');
    await _tapButton(tester, 'Stop Helper Work');

    expect(service.pingHelperCallCount, 2);
    expect(service.stopHelperWorkCallCount, 1);
  });

  testWidgets('launches helper and refreshes helper-owned permissions', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Launch Helper');

    expect(service.launchHelperCallCount, 1);
    expect(service.helperStatusCallCount, 2);
    expect(service.pingHelperCallCount, 3);
    expect(service.getPermissionsCallCount, 1);
  });

  testWidgets('restarts helper and waits for IPC readiness', (tester) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Restart Helper');

    expect(service.restartHelperCallCount, 1);
    expect(service.helperStatusCallCount, 2);
    expect(service.pingHelperCallCount, 3);
    expect(service.getPermissionsCallCount, 1);
  });

  testWidgets('opens macOS permission settings shortcuts', (tester) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Open Accessibility Settings');
    await _tapButton(tester, 'Open Screen Recording Settings');

    expect(service.openedSettingsSections, [
      'accessibility',
      'screen_recording',
    ]);
  });

  testWidgets('uses display preview taps for move pointer arguments', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Capture Display');
    await _tapPreview(tester, 'computer-use-display-preview-tap-area');
    await _tapSwitch(tester, 'Input Events Armed');
    await _tapButton(tester, 'Move Pointer');

    expect(service.lastMoveArguments, isNotNull);
    expect(service.lastMoveArguments, containsPair('x', 1.0));
    expect(service.lastMoveArguments, containsPair('y', 1.0));
    expect(service.lastMoveArguments, containsPair('source_width', 1));
    expect(service.lastMoveArguments, containsPair('source_height', 1));
    expect(service.lastMoveArguments!.containsKey('window_id'), isFalse);
  });

  testWidgets('uses selected window preview taps for click arguments', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'List Windows');
    expect(find.text('Terminal - Shell (#42)'), findsOneWidget);

    await _tapButton(tester, 'Capture Selected');
    await _tapPreview(tester, 'computer-use-window-preview-tap-area');
    await _tapSwitch(tester, 'Input Events Armed');
    await _tapButton(tester, 'Click Point');

    expect(
      service.lastWindowScreenshotArguments,
      containsPair('window_id', 42),
    );
    expect(service.lastClickArguments, isNotNull);
    expect(service.lastClickArguments, containsPair('window_id', 42));
    expect(service.lastClickArguments, containsPair('x', 1.0));
    expect(service.lastClickArguments, containsPair('y', 1.0));
    expect(service.lastClickArguments, containsPair('source_width', 1));
    expect(service.lastClickArguments, containsPair('source_height', 1));
    expect(service.lastClickArguments, containsPair('button', 'left'));
    expect(service.lastClickArguments, containsPair('click_count', 1));
  });

  testWidgets('runs smoke sequence without unsafe armed actions', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapByKey(tester, 'computer-use-run-smoke-sequence');

    expect(service.launchHelperCallCount, 1);
    expect(service.pingHelperCallCount, 2);
    expect(service.getPermissionsCallCount, 1);
    expect(service.screenshotCallCount, 1);
    expect(service.listWindowsCallCount, 1);
    expect(
      service.lastWindowScreenshotArguments,
      containsPair('window_id', 42),
    );
    expect(service.lastMoveArguments, isNull);
    expect(service.startAudioCallCount, 0);
    expect(service.stopAudioCallCount, 0);
    await _scrollUntilVisible(tester, find.text('Last Native Result'));
    expect(
      find.textContaining('Input events were not armed.', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'System audio recording was not armed.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('runs armed input and audio during smoke sequence', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapSwitch(tester, 'Input Events Armed');
    await _tapSwitch(tester, 'System Audio Armed');
    await _tapByKey(
      tester,
      'computer-use-run-smoke-sequence',
      wait: const Duration(milliseconds: 500),
    );

    expect(service.lastMoveArguments, containsPair('window_id', 42));
    expect(service.lastMoveArguments, containsPair('source_width', 1));
    expect(service.lastMoveArguments, containsPair('source_height', 1));
    expect(service.startAudioCallCount, 1);
    expect(service.stopAudioCallCount, 1);
  });

  testWidgets('always attempts to stop audio during armed smoke sequence', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(startAudioSucceeds: false);
    await _pumpPage(tester, service);

    await _tapSwitch(tester, 'System Audio Armed');
    await _tapByKey(
      tester,
      'computer-use-run-smoke-sequence',
      wait: const Duration(milliseconds: 500),
    );

    expect(service.startAudioCallCount, 1);
    expect(service.stopAudioCallCount, 1);
    await _scrollUntilVisible(tester, find.text('Last Native Result'));
    expect(
      find.textContaining('"stopAttempted": true', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('copies and exports redacted diagnostics', (tester) async {
    final service = _FakeMacosComputerUseService();
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpPage(tester, service);
    await _tapButton(tester, 'Capture Display');
    await _tapByKey(tester, 'computer-use-copy-diagnostics');

    final clipboardCall = platformCalls.singleWhere(
      (call) => call.method == 'Clipboard.setData',
    );
    final arguments = clipboardCall.arguments as Map<Object?, Object?>;
    final text = arguments['text'] as String;

    expect(text, contains('"schemaName": "macos_computer_use_onboarding"'));
    expect(text, contains('"schemaVersion": 1'));
    expect(text, contains('"coordinateTarget": "display"'));
    expect(text, contains('"setupChecklist"'));
    expect(text, contains('"onboardingSmokeChecklist"'));
    expect(text, contains('"operationBoundary"'));
    expect(text, contains('"tccGrants": "user_operated"'));
    expect(text, contains('"desktopActions": "user_operated"'));
    expect(text, contains('"inputSmokeRequiresArming": true'));
    expect(text, contains('"systemAudioSmokeRequiresArming": true'));
    expect(text, contains('"id": "capture_display"'));
    expect(text, contains('"id": "run_smoke_sequence"'));
    expect(text, contains('"id": "run_input_smoke"'));
    expect(text, contains('"id": "run_audio_smoke"'));
    expect(text, contains('"manualSmokeSteps"'));
    expect(text, contains('"helperIpcProtocol"'));
    expect(text, contains('"preferredTransport": "xpc_service"'));
    expect(text, contains('"xpcReady": true'));
    expect(text, contains('"xpcProductionReady": true'));
    expect(text, contains('"xpcStatus": "production"'));
    expect(text, contains('"migratedCommands"'));
    expect(text, contains('"command": "startSystemAudioRecording"'));
    expect(text, contains('"helperStatus"'));
    expect(text, contains('"helperStatusPersistence"'));
    expect(text, contains('"xpcTimingReport"'));
    expect(
      text,
      contains('"schemaName": "macos_computer_use_xpc_timing_report_summary"'),
    );
    expect(text, contains('"auditLog"'));
    expect(text, contains('"lastLiveSmokeReport"'));
    expect(text, contains('"targetHelperName": "Caverno Computer Use"'));
    expect(text, contains('"displayScreenshot"'));
    expect(text, isNot(contains(_png1x1Base64)));

    await _pumpPage(tester, service);
    await _tapByKey(tester, 'computer-use-export-diagnostics');

    expect(
      find.textContaining('Last export:', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('shows recent audit entries in the diagnostics card', (
    tester,
  ) async {
    MacosComputerUseAuditLog.instance.record(
      toolName: 'computer_list_windows',
      policy: MacosComputerUseToolPolicy.decision('computer_list_windows'),
      approvalResult: 'not_required',
      success: true,
      result: '{"selectedIpcTransport":"xpc_service","code":"ok"}',
    );
    MacosComputerUseAuditLog.instance.record(
      toolName: 'computer_click',
      policy: MacosComputerUseToolPolicy.decision('computer_click'),
      approvalResult: 'approved',
      success: false,
      result:
          '{"selectedIpcTransport":"distributed_notification_center","preferredIpcTransport":"xpc_service","fallbackIpcTransport":"distributed_notification_center","preferredIpcAttempt":{"status":"xpc_timeout","errorCode":"helper_xpc_timeout"},"code":"click_failed"}',
      postActionObservation: const MacosComputerUsePostActionObservation(
        toolName: 'computer_screenshot',
        success: false,
        errorCode: 'screen_capture_denied',
      ),
    );

    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    expect(find.text('Recent audit entries'), findsOneWidget);
    expect(find.text('computer_list_windows'), findsOneWidget);
    expect(find.text('not_required • observe'), findsOneWidget);
    expect(find.text('computer_click'), findsOneWidget);
    expect(find.text('approved • input'), findsOneWidget);
    expect(
      find.text(
        'Transport: distributed_notification_center • Response: click_failed',
      ),
      findsOneWidget,
    );
    expect(find.text('Policy: observation'), findsOneWidget);
    expect(
      find.text('Policy: pointer_input • Requires: approval, arming'),
      findsOneWidget,
    );
    expect(
      find.text('Fallback: xpc_timeout (helper_xpc_timeout)'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Post-action observation: failed (computer_screenshot, screen_capture_denied)',
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeMacosComputerUseService service,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 3200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [macosComputerUseServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: ComputerUseDebugPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(FilledButton, label);
  await _scrollUntilVisible(tester, finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> _tapByKey(
  WidgetTester tester,
  String key, {
  Duration wait = const Duration(milliseconds: 100),
}) async {
  final finder = find.byKey(ValueKey(key));
  await _scrollUntilVisible(tester, finder);
  final widget = tester.widget(finder);
  if (widget is FilledButton) {
    expect(widget.onPressed, isNotNull);
    await tester.runAsync(() async {
      widget.onPressed!();
      await Future<void>.delayed(wait);
    });
    await tester.pumpAndSettle();
    return;
  }
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> _tapSwitch(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await _scrollUntilVisible(tester, finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> _tapPreview(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await _scrollUntilVisible(tester, finder);
  await tester.tapAt(tester.getCenter(finder));
  await tester.pumpAndSettle();
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  if (!tester.any(finder)) {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

class _FakeMacosComputerUseService extends MacosComputerUseService {
  _FakeMacosComputerUseService({
    this.startAudioSucceeds = true,
    this.helperPathMismatch = false,
  });

  final bool startAudioSucceeds;
  final bool helperPathMismatch;

  int helperStatusCallCount = 0;
  int launchHelperCallCount = 0;
  int restartHelperCallCount = 0;
  int pingHelperCallCount = 0;
  int stopHelperWorkCallCount = 0;
  int getPermissionsCallCount = 0;
  int screenshotCallCount = 0;
  int listWindowsCallCount = 0;
  int startAudioCallCount = 0;
  int stopAudioCallCount = 0;
  final List<String> openedSettingsSections = [];
  Map<String, dynamic>? lastMoveArguments;
  Map<String, dynamic>? lastClickArguments;
  Map<String, dynamic>? lastWindowScreenshotArguments;

  @override
  bool get isAvailable => true;

  @override
  Future<String> getHelperStatus() async {
    helperStatusCallCount += 1;
    return _json({
      'ok': true,
      'backend': 'helper',
      'helperDisplayName': 'Caverno Computer Use',
      'helperBundleIdentifier': 'com.noguwo.apps.caverno.computer-use',
      'helperInstalled': true,
      'helperRunning': true,
      'helperPath':
          '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
      'embeddedHelperPath':
          '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
      'runningHelperPath': helperPathMismatch
          ? '/Users/noguwo/Documents/Workspace/Flutter/caverno-worktrees/macos-computer-use/build/macos/Build/Products/Debug/Caverno Computer Use.app'
          : '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
      'helperPathMatchesRunningHelper': !helperPathMismatch,
      'helperPathMismatch': helperPathMismatch,
      if (helperPathMismatch)
        'helperPathMismatchDetails': {
          'expectedHelperPath':
              '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
          'runningHelperPath':
              '/Users/noguwo/Documents/Workspace/Flutter/caverno-worktrees/macos-computer-use/build/macos/Build/Products/Debug/Caverno Computer Use.app',
          'nextAction':
              'Keep using the currently granted helper for this session, then restart from the installed Caverno bundle before release sign-off.',
        },
      'helperStatusPersistence': _persistence,
    });
  }

  @override
  Future<String> launchHelper() async {
    launchHelperCallCount += 1;
    return _json({
      'ok': true,
      'backend': 'helper',
      'helperInstalled': true,
      'helperRunning': true,
      'launched': true,
    });
  }

  @override
  Future<String> restartHelper() async {
    restartHelperCallCount += 1;
    return _json({
      'ok': true,
      'backend': 'helper',
      'helperInstalled': true,
      'helperRunning': true,
      'restarted': true,
    });
  }

  @override
  Future<String> getPermissions() async {
    getPermissionsCallCount += 1;
    return _json({
      'backend': 'helper',
      'helperReachable': true,
      'accessibilityGranted': true,
      'screenCaptureGranted': false,
      'systemAudioRecordingSupported': true,
      'helperStatusPersistence': _persistence,
    });
  }

  @override
  Future<String> pingHelper() async {
    pingHelperCallCount += 1;
    return _json({
      'ok': true,
      'backend': 'helper',
      'helperReachable': true,
      'message': 'pong',
      'helperStatusPersistence': _persistence,
    });
  }

  @override
  Future<String> openSystemSettings({required String section}) async {
    openedSettingsSections.add(section);
    return _json({'ok': true, 'section': section});
  }

  @override
  Future<String> stopHelperWork() async {
    stopHelperWorkCallCount += 1;
    return _json({
      'ok': true,
      'backend': 'helper',
      'helperStatusPersistence': _persistence,
    });
  }

  @override
  Future<String> getLastLiveSmokeReport() async {
    return _json({
      'ok': true,
      'path': '/tmp/caverno-macos-computer-use-smoke.json',
      'report': {
        'ok': true,
        'coreOk': true,
        'captureOk': false,
        'generatedAt': '2026-04-25T12:01:00Z',
        'manualTccHandoff': {
          'status': 'manual_required',
          'manualCommand':
              'bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --m8-runtime-signoff',
          'summaryCommand':
              'dart run tool/macos_computer_use_manual_tcc_report.dart <user-produced-m8-report.json>',
          'helperPath':
              '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
        },
        'overlaySmoke': {
          'status': 'ready',
          'accessibility': {
            'status': 'ready',
            'overlayForegroundPolicy': 'accessory_overlay_front',
            'overlayIsFloatingPanel': true,
            'overlayHidesOnDeactivate': false,
          },
          'screenRecording': {
            'status': 'ready',
            'overlayForegroundPolicy': 'accessory_overlay_front',
            'overlayIsFloatingPanel': true,
            'overlayHidesOnDeactivate': false,
          },
          'blockers': <String>[],
        },
      },
    });
  }

  @override
  Future<String> getLastExistingHelperProbeReport() async {
    return _json({
      'ok': true,
      'path': '/tmp/caverno-macos-computer-use-existing-helper-probe.json',
      'report': {
        'ok': true,
        'noRebuild': true,
        'captureReady': true,
        'inputReady': true,
        'helperPathMatchesExpected': true,
        'failedRequiredChecks': <String>[],
        'helper': {
          'expectedPath':
              '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
          'runningPath':
              '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
          'pathMatchesExpected': true,
        },
      },
    });
  }

  Map<String, dynamic> get _persistence => {
    'updatedAt': '2026-04-25T12:00:30Z',
    'activeWork': {'systemAudioRecording': false},
  };

  @override
  Future<String> screenshot(Map<String, dynamic> arguments) async {
    screenshotCallCount += 1;
    return _imageResult(title: 'Display');
  }

  @override
  Future<String> listWindows(Map<String, dynamic> arguments) async {
    listWindowsCallCount += 1;
    return _json({
      'windows': [
        {
          'windowId': 42,
          'ownerPid': 100,
          'appName': 'Terminal',
          'title': 'Shell',
          'bounds': {'x': 10, 'y': 20, 'width': 800, 'height': 600},
          'layer': 0,
          'alpha': 1,
          'isOnScreen': true,
        },
      ],
      'count': 1,
      'coordinateSpace': 'window_pixels',
      'inputOrigin': 'top_left',
    });
  }

  @override
  Future<String> screenshotWindow(Map<String, dynamic> arguments) async {
    lastWindowScreenshotArguments = Map<String, dynamic>.from(arguments);
    return _imageResult(
      title: 'Shell',
      extra: {
        'windowId': 42,
        'ownerPid': 100,
        'appName': 'Terminal',
        'windowBounds': {'x': 10, 'y': 20, 'width': 800, 'height': 600},
      },
    );
  }

  @override
  Future<String> moveMouse(Map<String, dynamic> arguments) async {
    lastMoveArguments = Map<String, dynamic>.from(arguments);
    return _json({'ok': true});
  }

  @override
  Future<String> click(Map<String, dynamic> arguments) async {
    lastClickArguments = Map<String, dynamic>.from(arguments);
    return _json({'ok': true});
  }

  @override
  Future<String> startSystemAudioRecording(
    Map<String, dynamic> arguments,
  ) async {
    startAudioCallCount += 1;
    return _json({
      'ok': startAudioSucceeds,
      if (startAudioSucceeds) 'path': '/tmp/system-audio.caf',
      if (!startAudioSucceeds) 'code': 'system_audio_permission_denied',
    });
  }

  @override
  Future<String> stopSystemAudioRecording() async {
    stopAudioCallCount += 1;
    return _json({'ok': true, 'path': '/tmp/system-audio.caf'});
  }

  String _imageResult({
    required String title,
    Map<String, dynamic> extra = const {},
  }) {
    return _json({
      'imageBase64': _png1x1Base64,
      'imageMimeType': 'image/png',
      'width': 1,
      'height': 1,
      'title': title,
      'coordinateSpace': 'screenshot_pixels',
      'inputOrigin': 'top_left',
      ...extra,
    });
  }
}

String _json(Map<String, dynamic> value) => jsonEncode(value);

const _png1x1Base64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mP8z8BQDwAFgwJ/lzWj8QAAAABJRU5ErkJggg==';
