import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/macos_computer_use_audit_log.dart';
import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:caverno/core/services/macos_computer_use_tool_policy.dart';
import 'package:caverno/features/settings/presentation/pages/advanced_settings_page.dart';
import 'package:caverno/features/settings/presentation/pages/computer_use_debug_page.dart';
import 'package:caverno/features/settings/presentation/pages/computer_use_settings_page.dart';
import 'package:caverno/features/settings/presentation/pages/settings_page.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final localeName = locale.countryCode == null || locale.countryCode!.isEmpty
        ? locale.languageCode
        : '${locale.languageCode}-${locale.countryCode}';
    final file = File('$path/$localeName.json');
    final fallbackFile = File('$path/${locale.languageCode}.json');
    final source = file.existsSync() ? file : fallbackFile;
    return jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  setUp(() {
    MacosComputerUseAuditLog.instance.clear();
  });

  testWidgets('keeps Computer Use behind the advanced settings menu', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpRootPage(tester, service);

    expect(find.text('Computer Use Ready'), findsNothing);
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Computer Use available in Advanced'), findsOneWidget);
    expect(find.text('Computer Use'), findsNothing);
    expect(
      find.text('Helper permissions, smoke checks, and manual sign-off'),
      findsNothing,
    );
    expect(service.helperStatusCallCount, 0);
    expect(service.pingHelperCallCount, 0);
    expect(service.getPermissionsCallCount, 0);

    await _tapByKey(tester, 'settings-menu-advanced');

    expect(find.byType(AdvancedSettingsPage), findsOneWidget);
    expect(find.text('Computer Use'), findsOneWidget);
    expect(
      find.text('Helper permissions, smoke checks, and manual sign-off'),
      findsOneWidget,
    );

    await _tapByKey(tester, 'settings-menu-computer-use');

    expect(find.byType(ComputerUseSettingsPage), findsOneWidget);
    expect(find.text('Helper-owned TCC, helper execution'), findsOneWidget);
    expect(
      find.text(
        'Caverno Computer Use owns Accessibility and Screen & System Audio Recording, executes approved desktop actions, and all TCC grants remain user-operated.',
      ),
      findsOneWidget,
    );
    expect(find.text('Computer Use Ready'), findsOneWidget);
    expect(service.helperStatusCallCount, 1);
    expect(service.pingHelperCallCount, 1);
    expect(service.getPermissionsCallCount, 1);
  });

  testWidgets('shows unavailable Computer Use summary without helper probes', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(isAvailable: false);
    await _pumpRootPage(tester, service);

    expect(find.text('Advanced'), findsOneWidget);
    expect(
      find.text('Computer Use unavailable on this device'),
      findsOneWidget,
    );
    expect(service.helperStatusCallCount, 0);
    expect(service.pingHelperCallCount, 0);
    expect(service.getPermissionsCallCount, 0);
  });

  testWidgets('keeps Computer Use diagnostics collapsed by default', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    expect(find.text('Computer Use Ready'), findsOneWidget);
    expect(find.text('Open Computer Use'), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Helper App: Installed'), findsNothing);
    expect(find.textContaining('Helper status saved:'), findsNothing);
    expect(find.text('Recent audit entries'), findsNothing);

    await _tapByKey(tester, 'computer-use-settings-diagnostics');

    expect(find.text('Helper App: Installed'), findsOneWidget);
    expect(find.textContaining('Helper status saved:'), findsOneWidget);
    expect(find.text('Recent audit entries'), findsOneWidget);
  });

  testWidgets('copies and exports diagnostics from the Settings card', (
    tester,
  ) async {
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
    await _tapByKey(tester, 'computer-use-settings-copy-diagnostics');

    final clipboardCall = platformCalls.singleWhere(
      (call) => call.method == 'Clipboard.setData',
    );
    final arguments = clipboardCall.arguments as Map<Object?, Object?>;
    final text = arguments['text'] as String;

    expect(text, contains('"schemaName": "macos_computer_use_onboarding"'));
    expect(text, contains('"onboardingVerification"'));
    expect(text, contains('"helperStatusPersistence"'));
    expect(text, contains('"lastLiveSmokeReport"'));
    expect(text, contains('"helperIpcRuntime"'));
    expect(text, contains('"operationBoundary"'));
    expect(text, contains('"tccGrants": "user_operated"'));
    expect(text, contains('"desktopActions": "user_operated"'));
    expect(text, contains('"inputSmokeRequiresArming": true'));
    expect(text, contains('"systemAudioSmokeRequiresArming": true'));
    expect(text, contains('"helperPathSignoffGate"'));
    expect(text, contains('"xpcTimingReport"'));
    expect(
      text,
      contains('"schemaName": "macos_computer_use_xpc_timing_report_summary"'),
    );
    expect(text, contains('"auditLog"'));
    expect(text, contains('"auditPrivacyControls"'));
    expect(
      text,
      contains('"schemaName": "macos_computer_use_audit_privacy_controls"'),
    );
    expect(text, contains('"m37AuditPrivacyGate"'));
    expect(text, contains('"explicitPayloadExportRequired": true'));
    expect(text, contains('"mainAppOwnsTccPermissions": false'));
    expect(text, contains('"helperActsAsOsActionExecutor": true'));
    expect(text, contains('"mainAppUnsafeOsActionsAllowed": false'));
    expect(text, contains('"helperOwnsUnsafeOsActions": true'));
    expect(text, contains('"xpcNextParityCommands"'));
    expect(text, contains('"id": "display_screenshot"'));
    expect(text, contains('"lastStopResult"'));
    expect(text, contains('"lastPermissionOverlayResult"'));

    expect(find.text('Diagnostics'), findsOneWidget);
    expect(
      find.text(
        'Runtime status, saved smoke reports, redacted audit log, and privacy controls.',
      ),
      findsOneWidget,
    );

    await _tapByKey(tester, 'computer-use-settings-diagnostics');

    expect(
      find.textContaining('Helper status saved:', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('Last live smoke:', skipOffstage: false),
      findsOneWidget,
    );

    await _tapByKey(tester, 'computer-use-settings-export-diagnostics');

    expect(
      find.textContaining('Last export:', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('refreshes the Settings card when the app resumes', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    expect(service.helperStatusCallCount, 1);
    expect(service.pingHelperCallCount, 1);
    expect(service.getPermissionsCallCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(service.helperStatusCallCount, 2);
    expect(service.pingHelperCallCount, 2);
    expect(service.getPermissionsCallCount, 2);
  });

  testWidgets('refreshes the Settings card after returning from smoke tests', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Open Smoke Sequence');
    expect(find.byType(ComputerUseDebugPage), findsOneWidget);

    final helperStatusBeforeReturn = service.helperStatusCallCount;
    final pingBeforeReturn = service.pingHelperCallCount;
    final permissionsBeforeReturn = service.getPermissionsCallCount;

    Navigator.of(tester.element(find.byType(ComputerUseDebugPage))).pop();
    await tester.pumpAndSettle();

    expect(service.helperStatusCallCount, helperStatusBeforeReturn + 1);
    expect(service.pingHelperCallCount, pingBeforeReturn + 1);
    expect(service.getPermissionsCallCount, permissionsBeforeReturn + 1);
  });

  testWidgets('opens Computer Use from the ready primary action', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(verificationOk: true);
    await _pumpPage(tester, service);

    expect(find.text('Computer Use Ready'), findsOneWidget);
    expect(find.text('Open Computer Use'), findsOneWidget);

    final helperStatusBeforeLaunch = service.helperStatusCallCount;
    final pingBeforeLaunch = service.pingHelperCallCount;
    final permissionsBeforeLaunch = service.getPermissionsCallCount;

    await _tapByKey(tester, 'computer-use-settings-primary-action');

    expect(service.launchHelperCallCount, 1);
    expect(
      service.helperStatusCallCount,
      greaterThan(helperStatusBeforeLaunch),
    );
    expect(service.pingHelperCallCount, greaterThan(pingBeforeLaunch));
    expect(
      service.getPermissionsCallCount,
      greaterThan(permissionsBeforeLaunch),
    );
    expect(find.text('Open Computer Use'), findsOneWidget);
    expect(
      find.textContaining('Last open: ok, launched: true, reachable: true'),
      findsOneWidget,
    );
  });

  testWidgets('keeps Computer Use open action after permissions are granted', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapByKey(tester, 'computer-use-settings-diagnostics');

    expect(find.text('Verify: Needs attention'), findsOneWidget);
    expect(find.text('Open Computer Use'), findsOneWidget);
    expect(find.text('Open Smoke Sequence'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('computer-use-settings-open-smoke-sequence')),
      findsOneWidget,
    );

    await _tapByKey(tester, 'computer-use-settings-primary-action');

    expect(service.launchHelperCallCount, 1);
    expect(find.text('Open Computer Use'), findsOneWidget);
    expect(
      find.textContaining('Last open: ok, launched: true, reachable: true'),
      findsOneWidget,
    );
  });

  testWidgets('separates helper process state from IPC readiness', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(helperReachable: false);
    await _pumpPage(tester, service);

    expect(find.text('Restart Helper'), findsOneWidget);
    expect(find.text('Open Computer Use'), findsOneWidget);
    expect(find.text('Computer Use action plan'), findsOneWidget);
    expect(find.text('Helper boundary: needs IPC'), findsOneWidget);
    expect(find.text('Accessibility permission: granted'), findsOneWidget);
    expect(find.text('Screen recording permission: granted'), findsOneWidget);
    expect(find.text('Capture smoke: blocked'), findsOneWidget);
    expect(find.text('Input smoke: not_armed'), findsOneWidget);
    expect(find.text('System audio smoke: not_armed'), findsOneWidget);
    expect(find.text('Overlay smoke: ready'), findsOneWidget);
    expect(find.text('Unsafe arms: not_armed'), findsOneWidget);

    await _tapByKey(tester, 'computer-use-settings-diagnostics');

    expect(find.text('Helper App: Installed'), findsOneWidget);
    expect(find.text('Helper Process: Running'), findsOneWidget);
    expect(find.text('IPC Ready: Timeout'), findsOneWidget);
    expect(
      find.textContaining('IPC runtime:', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('XPC status: production'), findsOneWidget);
    expect(
      find.text('XPC connection: external_helper_mach_service'),
      findsOneWidget,
    );
    expect(
      find.text('XPC registration: launchd_mach_service_registration'),
      findsOneWidget,
    );
    expect(find.text('XPC gate: blockers'), findsOneWidget);
    expect(find.text('Named XPC: fallback'), findsOneWidget);
    expect(
      find.text(
        'XPC blockers: launchd_mach_service_registration_missing, named_xpc_service_not_connected',
      ),
      findsOneWidget,
    );
    expect(find.text('OS action owner: helper'), findsOneWidget);
    expect(find.text('Main app OS actions: blocked'), findsOneWidget);
    expect(
      find.text(
        'XPC commands: ping, showMainWindow, permissionStatus, openSettings, showPermissionOverlay, startOnboardingPermissionFlow, stopAll, screenshot, listDisplays, listWindows, accessibilitySnapshot, focusWindow, screenshotWindow, moveMouse, click, drag, scroll, typeText, pressKey, startSystemAudioRecording, stopSystemAudioRecording',
      ),
      findsOneWidget,
    );
    expect(find.text('Next XPC parity: none'), findsOneWidget);
    expect(
      find.text('Fallback reason: xpc_error (helper_xpc_unavailable)'),
      findsOneWidget,
    );
    expect(find.text('Signing gate: accepted'), findsOneWidget);
    expect(find.text('XPC runtime: ready'), findsOneWidget);
    expect(find.text('XPC listener: started'), findsOneWidget);
    expect(
      find.text('Helper diagnostics: stale: helper_executable_path_mismatch'),
      findsOneWidget,
    );
    expect(find.text('Permission gate: blocked'), findsOneWidget);
    expect(
      find.text('Permission blockers: screen_capture, accessibility'),
      findsOneWidget,
    );
    expect(find.text('Live Signing: Accepted'), findsOneWidget);
    expect(find.text('Live XPC Runtime: Ready'), findsOneWidget);
    expect(find.text('Live Permissions: Blocked'), findsOneWidget);
    expect(find.text('Capture gate: blocked'), findsOneWidget);
    expect(
      find.text('Capture blockers: screen_capture_permission_missing'),
      findsOneWidget,
    );
    expect(
      find.text('Capture failure: screen_capture_permission_missing'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Capture steps: display=failed, windows=passed, window=skipped',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Capture TCC owner: .../Caverno.app/Contents/Helpers/Caverno Computer Use.app',
      ),
      findsOneWidget,
    );
    expect(find.text('Input gate: not_armed'), findsOneWidget);
    expect(find.text('Input blockers: unsafe_smoke_not_armed'), findsOneWidget);
    expect(find.text('Audio gate: not_armed'), findsOneWidget);
    expect(find.text('Audio blockers: unsafe_smoke_not_armed'), findsOneWidget);
    expect(find.text('Overlay smoke: ready'), findsAtLeastNWidgets(1));
    expect(
      find.text('Overlay placement: system_settings_window'),
      findsOneWidget,
    );
    expect(find.text('Overlay mode: floating_helper_panel'), findsOneWidget);
    expect(
      find.text(
        'Overlay pasteboard: public.file-url, public.url, public.utf8-plain-text, NSURLPboardType',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Overlay grant targets: .../Caverno.app/Contents/Helpers/Caverno Computer Use.app',
      ),
      findsOneWidget,
    );
    expect(find.text('Unsafe action gate: not_armed'), findsOneWidget);
    expect(
      find.text(
        'Unsafe blockers: unsafe_smoke_not_armed, unsafe_click_smoke_not_armed, unsafe_text_smoke_not_armed',
      ),
      findsOneWidget,
    );
    expect(find.text('Live Capture Gate: blocked'), findsOneWidget);
    expect(find.text('Live Input Gate: not_armed'), findsOneWidget);
    expect(find.text('Live Audio Gate: not_armed'), findsOneWidget);
    expect(find.text('Live Unsafe Gate: Not armed'), findsOneWidget);
    expect(find.text('Positive smoke gate: blocked'), findsOneWidget);
    expect(
      find.text('Positive smoke blockers: screen_capture'),
      findsOneWidget,
    );
    expect(find.text('Readiness expectations: failed'), findsOneWidget);
    expect(find.text('Failed expectations: capture_ready'), findsOneWidget);
    expect(find.text('M4 sign-off: blocked'), findsOneWidget);
    expect(find.text('M4 blockers: permissions, capture'), findsOneWidget);
    expect(
      find.text(
        'M4 helper: .../Caverno.app/Contents/Helpers/Caverno Computer Use.app',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'M4 next action: Resolve the failed M4 sign-off checks, then rerun --m4-signoff.',
      ),
      findsOneWidget,
    );
    expect(find.text('Live Positive Smoke: blocked'), findsOneWidget);
    expect(find.text('Live Expectations: Failed'), findsOneWidget);
    expect(find.text('Live M4 Sign-off: blocked'), findsOneWidget);
    expect(
      find.text('Live capture failure: screen_capture_permission_missing'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Live capture next action: Ask the user to grant Screen & System Audio Recording to Caverno Computer Use, then rerun smoke manually.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Live M4 helper: .../Caverno.app/Contents/Helpers/Caverno Computer Use.app',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Live M4 next action: Resolve the failed M4 sign-off checks, then rerun --m4-signoff.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('uses helper verification when live smoke has not run', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(
      verificationOk: true,
      liveSmokeReportAvailable: false,
    );
    await _pumpPage(tester, service);

    expect(find.text('Capture smoke: ready'), findsOneWidget);
    expect(
      find.text('Display and window capture passed in helper verification.'),
      findsOneWidget,
    );
    await _tapByKey(tester, 'computer-use-settings-diagnostics');
    expect(find.text('Capture gate: ready'), findsOneWidget);
    expect(
      find.text('Capture blockers: screen_capture_permission_missing'),
      findsNothing,
    );
  });

  testWidgets('points failed capture verification to the smoke sequence', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(
      liveSmokeReportAvailable: false,
    );
    await _pumpPage(tester, service);

    expect(find.text('Capture smoke: failed'), findsOneWidget);
    expect(
      find.text(
        'Open Smoke Sequence, then press Run Smoke Sequence to rerun display and window capture checks.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows recent redacted audit entries in the Settings card', (
    tester,
  ) async {
    MacosComputerUseAuditLog.instance.record(
      toolName: 'computer_click',
      policy: MacosComputerUseToolPolicy.decision('computer_click'),
      approvalResult: 'approved',
      success: true,
      result:
          '{"selectedIpcTransport":"distributed_notification_center","preferredIpcTransport":"xpc_service","fallbackIpcTransport":"distributed_notification_center","preferredIpcAttempt":{"status":"xpc_error","errorCode":"helper_xpc_unavailable"},"code":"ok","x":40,"y":40}',
      postActionObservation: const MacosComputerUsePostActionObservation(
        toolName: 'computer_screenshot',
        success: true,
        result: '{"selectedIpcTransport":"xpc_service"}',
      ),
    );
    MacosComputerUseAuditLog.instance.record(
      toolName: 'computer_start_system_audio_recording',
      policy: MacosComputerUseToolPolicy.decision(
        'computer_start_system_audio_recording',
      ),
      approvalResult: 'denied',
      success: false,
      errorCode: 'approval_denied',
    );

    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapByKey(tester, 'computer-use-settings-diagnostics');

    expect(find.text('Recent audit entries'), findsOneWidget);
    expect(find.text('computer_click'), findsOneWidget);
    expect(find.text('approved • input'), findsOneWidget);
    expect(find.text('computer_start_system_audio_recording'), findsOneWidget);
    expect(find.text('denied • sensitive'), findsOneWidget);
    expect(
      find.text('Transport: distributed_notification_center • Response: ok'),
      findsOneWidget,
    );
    expect(
      find.text('Policy: pointer_input • Requires: approval, arming'),
      findsOneWidget,
    );
    expect(
      find.text('Policy: system_audio • Requires: approval, arming'),
      findsOneWidget,
    );
    expect(
      find.text('Fallback: xpc_error (helper_xpc_unavailable)'),
      findsOneWidget,
    );
    expect(
      find.text('Post-action observation: passed (computer_screenshot)'),
      findsOneWidget,
    );
  });

  testWidgets('runs the restart primary action when IPC is unreachable', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(helperReachable: false);
    await _pumpPage(tester, service);

    await _tapByKey(tester, 'computer-use-settings-primary-action');

    expect(service.restartHelperCallCount, 1);
    await _tapByKey(tester, 'computer-use-settings-diagnostics');
    expect(find.text('IPC Ready: Reachable'), findsOneWidget);
  });

  testWidgets('keeps Computer Use open action when restart is primary', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(helperReachable: false);
    await _pumpPage(tester, service);

    expect(find.text('Restart Helper'), findsOneWidget);
    expect(find.text('Open Computer Use'), findsOneWidget);

    await _tapByKey(tester, 'computer-use-settings-open-computer-use');

    expect(service.launchHelperCallCount, 1);
  });

  testWidgets('explains preserved helper identity during path mismatch', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(helperPathMismatch: true);
    await _pumpPage(tester, service);

    expect(find.text('Recovery guidance'), findsOneWidget);
    expect(
      find.text('debug/release or standalone helper mismatch'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Restart Caverno Computer Use from Caverno, then recheck helper reachability before sign-off.',
      ),
      findsOneWidget,
    );

    await _tapByKey(tester, 'computer-use-settings-diagnostics');

    expect(find.text('Helper path: mismatch'), findsOneWidget);
    expect(
      find.text('Helper identity: preserved running helper'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Runtime helper: .../Build/Products/Debug/Caverno Computer Use.app',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Release sign-off: requires helper path match'),
      findsOneWidget,
    );
    expect(find.text('Helper path sign-off: blocked'), findsOneWidget);
    expect(find.text('Helper runtime use: current_session'), findsOneWidget);
    expect(find.text('M38 migration gate: blocked'), findsOneWidget);
    expect(find.text('TCC regrant: may be required'), findsOneWidget);
    expect(find.text('Old helper actions: blocked'), findsOneWidget);
    expect(find.text('M38 blockers: helper_path_mismatch'), findsOneWidget);
    expect(
      find.text(
        'Helper path blockers: helper_path_mismatch, preserved_mismatched_helper',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Helper path sign-off next action: Keep using the currently granted helper for this session, then restart from the installed Caverno bundle before release sign-off.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Helper runtime next action: Use the current helper for this session, then restart from Caverno before release sign-off.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows successful fallback separately from XPC timeout', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(
      preferredXpcTimeoutWithFallback: true,
      xpcLaunchAgentEnabled: true,
    );
    await _pumpPage(tester, service);

    await _tapByKey(tester, 'computer-use-settings-diagnostics');

    expect(find.text('XPC gate: ready'), findsOneWidget);
    expect(
      find.text('Preferred attempt: xpc_timeout, fallback succeeded'),
      findsOneWidget,
    );
    expect(
      find.text('Fallback reason: xpc_timeout (helper_xpc_timeout)'),
      findsOneWidget,
    );
    expect(find.text('Fallback outcome: succeeded'), findsOneWidget);
    expect(find.text('Preferred elapsed: 2001ms'), findsOneWidget);
    expect(find.text('Timeout budget: 2000ms'), findsOneWidget);
    expect(find.text('Current XPC timeout: 3000ms'), findsOneWidget);
    expect(find.text('Current headroom: 950ms'), findsOneWidget);
    expect(find.text('XPC response before timeout: no'), findsOneWidget);
    expect(find.text('XPC late response: yes'), findsOneWidget);
    expect(find.text('XPC late elapsed: 2050ms'), findsOneWidget);
    expect(find.text('Warmup status: xpc_response'), findsOneWidget);
    expect(find.text('Warmup elapsed: 43ms'), findsOneWidget);
    expect(find.text('Warmup before timeout: yes'), findsOneWidget);
    expect(
      find.text('XPC timing: late_response_within_current_budget'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Timing next action: Rerun Computer Use diagnostics with the current preferred XPC timeout.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Timing action: rerun_with_current_xpc_timeout'),
      findsOneWidget,
    );
    expect(
      find.text(
        'User next action: No manual TCC action is required; recheck permissions or reopen Computer Use to collect fresh timing.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Engineering next action: No timeout tuning is needed unless the rerun still times out under the current budget.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('XPC blockers: named_xpc_service_not_connected'),
      findsNothing,
    );
  });

  testWidgets('stops helper work from the Settings card', (tester) async {
    final service = _FakeMacosComputerUseService(helperWorkActive: true);
    await _pumpPage(tester, service);

    await _tapByKey(tester, 'computer-use-settings-diagnostics');
    expect(find.text('Helper Work: Active'), findsOneWidget);

    await _tapByKey(tester, 'computer-use-settings-stop-helper-work');

    expect(service.stopHelperWorkCallCount, 1);
    expect(find.text('Helper Work: Idle'), findsOneWidget);
    expect(
      find.textContaining('Last stop: ok', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('registers and unregisters the XPC LaunchAgent', (tester) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapByKey(tester, 'computer-use-settings-register-xpc-agent');
    await _tapByKey(tester, 'computer-use-settings-unregister-xpc-agent');

    expect(service.registerXpcLaunchAgentCallCount, 1);
    expect(service.unregisterXpcLaunchAgentCallCount, 1);
  });

  testWidgets('opens targeted permission panes for missing permissions', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(
      accessibilityGranted: false,
      screenCaptureGranted: false,
    );
    await _pumpPage(tester, service);

    expect(find.text('Open Accessibility Settings'), findsOneWidget);
    expect(find.text('Open Screen Recording Settings'), findsOneWidget);
    expect(find.text('Permission flow'), findsOneWidget);
    expect(find.text('Open Accessibility'), findsAtLeastNWidgets(1));
    expect(find.text('Open Screen Recording'), findsAtLeastNWidgets(1));

    await _tapByKey(
      tester,
      'computer-use-settings-open-accessibility',
      wait: const Duration(milliseconds: 700),
    );
    await _tapByKey(
      tester,
      'computer-use-settings-open-screen-recording',
      wait: const Duration(milliseconds: 700),
    );

    expect(service.permissionOverlays, ['accessibility', 'screenRecording']);
    expect(service.getPermissionsCallCount, greaterThanOrEqualTo(3));

    final permissionsBeforeRecheck = service.getPermissionsCallCount;
    await _tapByKey(tester, 'computer-use-settings-recheck-permissions');

    expect(service.getPermissionsCallCount, permissionsBeforeRecheck + 1);
    expect(
      find.textContaining('Last permission overlay:', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('offers helper restart after screen recording grant flow', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(screenCaptureGranted: false);
    await _pumpPage(tester, service);

    expect(find.text('Open Screen Recording'), findsAtLeastNWidgets(1));

    await _tapByKey(
      tester,
      'computer-use-settings-primary-action',
      wait: const Duration(milliseconds: 700),
    );

    expect(service.permissionOverlays, ['screenRecording']);
    expect(find.text('Restart Helper'), findsOneWidget);

    await _tapByKey(tester, 'computer-use-settings-primary-action');

    expect(service.restartHelperCallCount, 1);
    expect(find.text('Open Screen Recording'), findsAtLeastNWidgets(1));
  });

  testWidgets('distinguishes revoked permissions from missing permissions', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(
      accessibilityGranted: false,
      screenCaptureGranted: false,
      previousAccessibilityGranted: true,
      previousScreenCaptureGranted: true,
    );
    await _pumpPage(tester, service);

    expect(find.text('Recovery guidance'), findsOneWidget);
    expect(find.text('Revoked permissions'), findsOneWidget);
    expect(
      find.text('Accessibility, Screen & System Audio Recording'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Accessibility and Screen & System Audio Recording via Caverno Computer Use',
      ),
      findsOneWidget,
    );
    expect(find.text('Next recovery action'), findsOneWidget);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeMacosComputerUseService service,
) async {
  await _pumpSettingsApp(
    tester,
    service,
    home: const ComputerUseSettingsPage(),
  );
}

Future<void> _pumpRootPage(
  WidgetTester tester,
  _FakeMacosComputerUseService service,
) async {
  await _pumpSettingsApp(tester, service, home: const SettingsPage());
}

Future<void> _pumpSettingsApp(
  WidgetTester tester,
  _FakeMacosComputerUseService service, {
  required Widget home,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 2600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.runAsync(() async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        useOnlyLangCode: true,
        saveLocale: false,
        assetLoader: const _TestTranslationLoader(),
        child: Builder(
          builder: (context) {
            return ProviderScope(
              overrides: [
                macosComputerUseServiceProvider.overrideWithValue(service),
              ],
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: home,
              ),
            );
          },
        ),
      ),
    );
  });
  await tester.pumpAndSettle();
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final finder = find.text(label);
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
  if (widget is OutlinedButton) {
    expect(widget.onPressed, isNotNull);
    await tester.runAsync(() async {
      widget.onPressed!();
      await Future<void>.delayed(wait);
    });
    await tester.pumpAndSettle();
    return;
  }
  await tester.tap(finder);
  await tester.pump(wait);
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
    bool helperWorkActive = false,
    bool accessibilityGranted = true,
    bool screenCaptureGranted = true,
    bool helperReachable = true,
    bool verificationOk = false,
    bool helperPathMismatch = false,
    bool liveSmokeReportAvailable = true,
    bool preferredXpcTimeoutWithFallback = false,
    bool xpcLaunchAgentEnabled = false,
    bool isAvailable = true,
    bool previousAccessibilityGranted = false,
    bool previousScreenCaptureGranted = false,
  }) : _helperWorkActive = helperWorkActive,
       _accessibilityGranted = accessibilityGranted,
       _screenCaptureGranted = screenCaptureGranted,
       _helperReachable = helperReachable,
       _verificationOk = verificationOk,
       _helperPathMismatch = helperPathMismatch,
       _liveSmokeReportAvailable = liveSmokeReportAvailable,
       _preferredXpcTimeoutWithFallback = preferredXpcTimeoutWithFallback,
       _xpcLaunchAgentEnabled = xpcLaunchAgentEnabled,
       _previousAccessibilityGranted = previousAccessibilityGranted,
       _previousScreenCaptureGranted = previousScreenCaptureGranted,
       _isAvailable = isAvailable;

  int helperStatusCallCount = 0;
  int launchHelperCallCount = 0;
  int restartHelperCallCount = 0;
  int registerXpcLaunchAgentCallCount = 0;
  int unregisterXpcLaunchAgentCallCount = 0;
  int pingHelperCallCount = 0;
  int stopHelperWorkCallCount = 0;
  int getPermissionsCallCount = 0;
  final List<String> openedSettingsSections = [];
  final List<String> permissionOverlays = [];
  bool _helperWorkActive;
  final bool _isAvailable;
  final bool _accessibilityGranted;
  final bool _screenCaptureGranted;
  final bool _verificationOk;
  final bool _helperPathMismatch;
  final bool _liveSmokeReportAvailable;
  final bool _preferredXpcTimeoutWithFallback;
  final bool _previousAccessibilityGranted;
  final bool _previousScreenCaptureGranted;
  bool _helperReachable;
  bool _xpcLaunchAgentEnabled;

  String get _embeddedHelperPath =>
      '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app';

  String get _runningHelperPath => _helperPathMismatch
      ? '/Users/noguwo/Documents/Workspace/Flutter/caverno-worktrees/macos-computer-use/build/macos/Build/Products/Debug/Caverno Computer Use.app'
      : _embeddedHelperPath;

  @override
  bool get isAvailable => _isAvailable;

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
      'helperPath': _embeddedHelperPath,
      'embeddedHelperPath': _embeddedHelperPath,
      'runningHelperPath': _runningHelperPath,
      'helperPathMatchesRunningHelper': !_helperPathMismatch,
      'helperPathMismatch': _helperPathMismatch,
      if (_helperPathMismatch) 'preservedMismatchedHelperPath': true,
      if (_helperPathMismatch) 'mismatchedHelperPath': _runningHelperPath,
      if (_helperPathMismatch)
        'helperPathMismatchDetails': {
          'expectedHelperPath': _embeddedHelperPath,
          'runningHelperPath': _runningHelperPath,
          'nextAction':
              'Keep using the currently granted helper for this session, then restart from the installed Caverno bundle before release sign-off.',
        },
      'helperStatusPersistence': _persistence,
    });
  }

  @override
  Future<String> launchHelper() async {
    launchHelperCallCount += 1;
    _helperReachable = true;
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
    _helperReachable = true;
    return _json({
      'ok': true,
      'backend': 'helper',
      'helperInstalled': true,
      'helperRunning': true,
      'restarted': true,
    });
  }

  @override
  Future<String> registerXpcLaunchAgent() async {
    registerXpcLaunchAgentCallCount += 1;
    _xpcLaunchAgentEnabled = true;
    return _json({
      'ok': true,
      'backend': 'helper',
      'xpcLaunchAgentStatus': 'enabled',
      'xpcLaunchAgentEnabled': true,
    });
  }

  @override
  Future<String> unregisterXpcLaunchAgent() async {
    unregisterXpcLaunchAgentCallCount += 1;
    _xpcLaunchAgentEnabled = false;
    return _json({
      'ok': true,
      'backend': 'helper',
      'xpcLaunchAgentStatus': 'not_registered',
      'xpcLaunchAgentEnabled': false,
    });
  }

  @override
  Future<String> getPermissions() async {
    getPermissionsCallCount += 1;
    return _json({
      'backend': 'helper',
      'helperReachable': _helperReachable,
      'accessibilityGranted': _accessibilityGranted,
      'screenCaptureGranted': _screenCaptureGranted,
      'systemAudioRecordingSupported': true,
      'onboardingVerification': _verification,
      'helperStatusPersistence': _persistence,
    });
  }

  @override
  Future<String> openSystemSettings({required String section}) async {
    openedSettingsSections.add(section);
    return _json({'ok': true, 'backend': 'helper', 'section': section});
  }

  @override
  Future<String> showPermissionOverlay({required String permission}) async {
    permissionOverlays.add(permission);
    return _json({
      'ok': true,
      'backend': 'helper',
      'permission': permission,
      'settingsOpened': true,
      'overlayRequested': true,
      'overlayShown': false,
      'draggableTileReady': true,
      'helperBundlePath':
          '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
      'grantTargetBundlePath':
          '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
      'grantTargetDisplayName': 'Caverno Computer Use',
      'grantTargetPermissionLabel': permission == 'screenRecording'
          ? 'Screen & System Audio Recording'
          : 'Accessibility',
      'nextAction':
          'Drag Caverno Computer Use into the permission list, then recheck.',
    });
  }

  @override
  Future<String> pingHelper() async {
    pingHelperCallCount += 1;
    return _json({
      'ok': _helperReachable,
      'backend': 'helper',
      'helperReachable': _helperReachable,
      'selectedIpcTransport': 'distributed_notification_center',
      'preferredIpcTransport': 'xpc_service',
      'fallbackIpcTransport': 'distributed_notification_center',
      'embeddedHelperPath': _embeddedHelperPath,
      'runningHelperPath': _runningHelperPath,
      'helperPathMatchesRunningHelper': !_helperPathMismatch,
      'helperPathMismatch': _helperPathMismatch,
      if (_helperPathMismatch) 'preservedMismatchedHelperPath': true,
      if (_helperPathMismatch) 'mismatchedHelperPath': _runningHelperPath,
      if (_helperPathMismatch)
        'helperPathMismatchDetails': {
          'expectedHelperPath': _embeddedHelperPath,
          'runningHelperPath': _runningHelperPath,
          'nextAction':
              'Keep using the currently granted helper for this session, then restart from the installed Caverno bundle before release sign-off.',
        },
      'xpcStatus': 'production',
      'xpcProductionReady': true,
      'xpcConnectionMode': 'external_helper_mach_service',
      'xpcLaunchAgentPlistName': 'com.noguwo.apps.caverno.computer-use.plist',
      'xpcLaunchAgentRelativePath':
          'Contents/Library/LaunchAgents/com.noguwo.apps.caverno.computer-use.plist',
      'xpcLaunchAgentPlistInstalled': true,
      'xpcLaunchAgentStatus': _xpcLaunchAgentEnabled
          ? 'enabled'
          : 'not_registered',
      'xpcLaunchAgentEnabled': _xpcLaunchAgentEnabled,
      'xpcRegistrationRequirement': 'launchd_mach_service_registration',
      'xpcProductionBlockers': <String>[],
      'xpcProductionNextAction': 'XPC is production ready.',
      'mainAppUnsafeOsActionsAllowed': false,
      'helperOwnsUnsafeOsActions': true,
      'xpcSupportedCommands': [
        'ping',
        'showMainWindow',
        'permissionStatus',
        'openSettings',
        'showPermissionOverlay',
        'startOnboardingPermissionFlow',
        'stopAll',
        'screenshot',
        'listDisplays',
        'listWindows',
        'accessibilitySnapshot',
        'focusWindow',
        'screenshotWindow',
        'moveMouse',
        'click',
        'drag',
        'scroll',
        'typeText',
        'pressKey',
        'startSystemAudioRecording',
        'stopSystemAudioRecording',
      ],
      'xpcNextParityCommands': <String>[],
      'xpcProductionReadinessCriteria': [
        'named_service_connects_from_signed_main_app',
        'ping_show_main_window_permission_status_open_settings_show_permission_overlay_start_onboarding_permission_flow_stop_all_screenshot_list_displays_list_windows_accessibility_snapshot_focus_window_screenshot_window_move_mouse_click_drag_scroll_type_text_press_key_system_audio_match_dnc',
        'capture_input_audio_commands_have_parity_smoke_coverage',
        'fallback_path_is_observable_and_non_destructive',
      ],
      'helperOwnedActionCategories': [
        'accessibility',
        'screen_capture',
        'input_events',
        'system_audio_recording',
        'emergency_stop',
      ],
      if (!_helperReachable)
        'preferredIpcAttempt': {
          'status': 'xpc_error',
          'errorCode': 'helper_xpc_unavailable',
        },
      if (_preferredXpcTimeoutWithFallback)
        'preferredIpcAttempt': {
          'status': 'xpc_timeout',
          'errorCode': 'helper_xpc_timeout',
          'elapsedMs': 2001,
          'timeoutMs': 2000,
          'responseReceivedBeforeTimeout': false,
          'responseReceivedAfterTimeout': true,
          'lateResponseElapsedMs': 2050,
          'warmupAttempt': {
            'status': 'xpc_response',
            'elapsedMs': 43,
            'responseReceivedBeforeTimeout': true,
          },
        },
      if (!_helperReachable) 'code': 'helper_unreachable',
      'message': 'pong',
      'audioRecordingActive': _helperWorkActive,
      'activeWork': {'systemAudioRecording': _helperWorkActive},
      'onboardingVerification': _verification,
      'helperStatusPersistence': _persistence,
    });
  }

  @override
  Future<String> stopHelperWork() async {
    stopHelperWorkCallCount += 1;
    _helperWorkActive = false;
    return _json({
      'ok': true,
      'backend': 'helper',
      'stoppedAudioRecording': true,
      'cancelledInputEvents': true,
      'audioRecordingActive': false,
      'helperStatusPersistence': _persistence,
    });
  }

  @override
  Future<String> getLastLiveSmokeReport() async {
    if (!_liveSmokeReportAvailable) {
      return _json({'ok': false, 'code': 'no_live_smoke_report'});
    }
    return _json({
      'ok': true,
      'path': '/tmp/caverno-macos-computer-use-smoke.json',
      'report': {
        'ok': false,
        'coreOk': false,
        'captureOk': false,
        'generatedAt': '2026-04-25T12:01:00Z',
        'permissionGate': {
          'blockedByPermissions': ['screen_capture', 'accessibility'],
        },
        'captureGate': {
          'status': 'blocked',
          'blockers': ['screen_capture_permission_missing'],
          'failureClass': 'screen_capture_permission_missing',
          'failureClasses': ['screen_capture_permission_missing'],
          'stepDiagnostics': {
            'displayScreenshot': {'status': 'failed', 'passed': false},
            'listWindows': {'status': 'passed', 'passed': true, 'count': 3},
            'windowCapture': {'status': 'skipped', 'passed': false},
          },
          'tccOwnerHelperPath':
              '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
          'nextAction':
              'Ask the user to grant Screen & System Audio Recording to Caverno Computer Use, then rerun smoke manually.',
        },
        'inputGate': {
          'status': 'not_armed',
          'blockers': ['unsafe_smoke_not_armed'],
        },
        'audioGate': {
          'status': 'not_armed',
          'optional': true,
          'blockers': ['unsafe_smoke_not_armed'],
          'nextAction':
              'Rerun smoke with unsafe arming for system audio checks.',
        },
        'overlaySmoke': {
          'status': 'ready',
          'required': true,
          'accessibility': {
            'permission': 'accessibility',
            'status': 'ready',
            'settingsOpened': true,
            'overlayShown': true,
            'draggableTileReady': true,
            'reportedPermission': 'accessibility',
            'overlayPlacement': 'system_settings_window',
            'overlayMode': 'floating_helper_panel',
            'helperBundlePath':
                '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
            'grantTargetBundlePath':
                '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
            'grantTargetDisplayName': 'Caverno Computer Use',
            'grantTargetPermissionLabel': 'Accessibility',
            'dragPasteboardTypes': [
              'public.file-url',
              'public.url',
              'public.utf8-plain-text',
              'NSURLPboardType',
            ],
            'blockers': <String>[],
          },
          'screenRecording': {
            'permission': 'screenRecording',
            'status': 'ready',
            'settingsOpened': true,
            'overlayShown': true,
            'draggableTileReady': true,
            'reportedPermission': 'screenRecording',
            'overlayPlacement': 'system_settings_window',
            'overlayMode': 'floating_helper_panel',
            'helperBundlePath':
                '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
            'grantTargetBundlePath':
                '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
            'grantTargetDisplayName': 'Caverno Computer Use',
            'grantTargetPermissionLabel': 'Screen & System Audio Recording',
            'dragPasteboardTypes': [
              'public.file-url',
              'public.url',
              'public.utf8-plain-text',
              'NSURLPboardType',
            ],
            'blockers': <String>[],
          },
          'blockers': <String>[],
          'nextAction':
              'Permission overlays are ready for hands-on drag validation.',
        },
        'unsafeActionGate': {
          'status': 'not_armed',
          'unsafeArmed': false,
          'nextAction':
              'Rerun smoke with only the explicit unsafe arms needed for the next check.',
          'blockers': [
            'unsafe_smoke_not_armed',
            'unsafe_click_smoke_not_armed',
            'unsafe_text_smoke_not_armed',
          ],
        },
        'positiveSmokeGateSummary': {
          'status': 'blocked',
          'blockedBy': ['screen_capture'],
          'requiredCount': 2,
          'passedRequiredCount': 0,
          'failedRequiredCount': 2,
          'failedRequiredGateIds': ['display_screenshot', 'window_capture'],
        },
        'readinessExpectations': {
          'ok': false,
          'failed': ['capture_ready'],
        },
        'm4SignoffGate': {
          'status': 'blocked',
          'blockers': ['permissions', 'capture'],
          'helperPath': {
            'embeddedHelperPath':
                '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
          },
          'nextAction':
              'Resolve the failed M4 sign-off checks, then rerun --m4-signoff.',
        },
        'signingDiagnostics': {
          'launchConstraintLikelyAccepted': true,
          'launchConstraintBlockers': <String>[],
        },
        'xpcRuntimeDiagnostics': {
          'xpcListenerStarted': true,
          'xpcListenerStartAttempted': true,
          'helperDiagnosticsLatestStale': true,
          'helperDiagnosticsStaleReasons': ['helper_executable_path_mismatch'],
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
        'ok': false,
        'noRebuild': true,
        'captureReady': true,
        'inputReady': true,
        'helperPathMatchesExpected': false,
        'failedRequiredChecks': ['helper_path_match'],
        'helper': {
          'expectedPath':
              '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
          'runningPath': '/Applications/Caverno Computer Use.app',
          'pathMatchesExpected': false,
        },
      },
    });
  }

  Map<String, dynamic> get _persistence => {
    'updatedAt': '2026-04-25T12:00:30Z',
    'activeWork': {'systemAudioRecording': _helperWorkActive},
    'onboardingVerification': _verification,
  };

  Map<String, dynamic> get _verification => {
    'ok': _verificationOk,
    'generatedAt': '2026-04-25T12:00:00Z',
    'summary': _verificationOk
        ? 'Verification complete'
        : 'Verification incomplete',
    'permissions': {
      'accessibilityGranted': _previousAccessibilityGranted,
      'screenCaptureGranted': _previousScreenCaptureGranted,
      'systemAudioRecordingSupported': true,
    },
    'steps': [
      {
        'id': 'permissions',
        'label': 'Permissions',
        'ok': true,
        'status': 'done',
        'detail': 'Ready',
      },
      {
        'id': 'display_screenshot',
        'label': 'Display Screenshot',
        'ok': true,
        'status': 'done',
        'detail': '1 x 1 px',
      },
      {
        'id': 'window_capture',
        'label': 'Window Capture',
        'ok': _verificationOk,
        'status': _verificationOk ? 'done' : 'failed',
        'detail': _verificationOk ? 'Ready' : 'No visible window',
      },
    ],
  };
}

String _json(Map<String, dynamic> value) => jsonEncode(value);
