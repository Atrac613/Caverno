import 'package:caverno/core/services/macos_computer_use_setup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('describes the in-process compatibility backend', () {
    const backend = MacosComputerUseBackends.inProcessCompatibility;

    expect(backend.displayName, 'Caverno');
    expect(backend.permissionOwnerName, 'Caverno');
    expect(backend.targetHelperName, 'Caverno Computer Use');
    expect(backend.usesSeparateHelper, isFalse);
  });

  test('describes the helper IPC backend', () {
    const backend = MacosComputerUseBackends.helperIpc;

    expect(backend.displayName, 'Caverno Computer Use');
    expect(backend.permissionOwnerName, 'Caverno Computer Use');
    expect(backend.executionMode, 'helper_ipc');
    expect(backend.usesSeparateHelper, isTrue);
  });

  test('describes the current helper IPC transport', () {
    final info = MacosComputerUseIpc.current.toJson();

    expect(info['version'], 1);
    expect(info['transport'], 'distributed_notification_center');
    expect(info['preferredTransport'], 'xpc_service');
    expect(info['fallbackTransport'], 'distributed_notification_center');
    expect(info['requestObject'], 'com.noguwo.apps.caverno');
    expect(info['responseObject'], 'com.noguwo.apps.caverno.computer-use');
    expect(
      info['requestNotificationName'],
      'com.caverno.computer_use.helper.request',
    );
    expect(
      info['responseNotificationName'],
      'com.caverno.computer_use.helper.response',
    );
    expect(info['requestEnvelope'], contains('senderProcessIdentifier'));
    expect(info['responseEnvelope'], contains('response'));
    expect(info['timeoutsMs'], containsPair('stopAll', 8000));
    expect(info['errorCodes'], contains('helper_unreachable'));
    expect(info['errorCodes'], contains('helper_xpc_timeout'));
    expect(info['xpcServiceName'], 'com.noguwo.apps.caverno.computer-use.xpc');
    expect(info['xpcSupportedCommands'], [
      'ping',
      'permissionStatus',
      'openSettings',
      'stopAll',
      'screenshot',
      'listWindows',
    ]);
    expect(info['xpcReady'], isTrue);
    expect(info['xpcProductionReady'], isFalse);
    expect(info['xpcStatus'], 'experimental_fallback');
    expect(info['mainAppUnsafeOsActionsAllowed'], isFalse);
    expect(info['helperOwnsUnsafeOsActions'], isTrue);
    expect(info['helperOwnedActionCategories'], contains('input_events'));
    expect(
      info['helperOwnedActionCategories'],
      contains('system_audio_recording'),
    );
    expect(info['xpcNextParityCommands'], ['focusWindow', 'screenshotWindow']);
    expect(
      info['xpcProductionReadinessCriteria'],
      contains(
        'ping_permission_status_open_settings_stop_all_screenshot_list_windows_match_dnc',
      ),
    );
  });

  test('builds the onboarding diagnostics schema', () {
    const checklist = MacosComputerUseSetupChecklist(
      backend: MacosComputerUseBackends.helperIpc,
      permissions: MacosComputerUsePermissionSnapshot(
        helperReachable: true,
        accessibilityGranted: true,
        screenCaptureGranted: false,
        systemAudioRecordingSupported: true,
      ),
    );
    final diagnostics = MacosComputerUseOnboardingDiagnostics(
      generatedAt: DateTime.utc(2026, 4, 25, 12),
      setupChecklist: checklist,
      onboardingSmokeChecklist: const [
        {'id': 'launch_helper', 'label': 'Launch helper', 'complete': true},
      ],
      helperIpcProtocol: MacosComputerUseIpc.current.toJson(),
      onboardingVerification: const {
        'ok': false,
        'steps': [
          {'id': 'permissions', 'ok': true},
          {'id': 'display_screenshot', 'ok': true},
          {'id': 'window_capture', 'ok': false},
        ],
      },
      helperStatus: const {'helperRunning': true},
      helperStatusPersistence: const {
        'updatedAt': '2026-04-25T12:00:30Z',
        'activeWork': {'systemAudioRecording': false},
      },
      permissions: const {'accessibilityGranted': true},
      manualSmokeSteps: const [
        {'id': 'capture_display', 'ok': true},
      ],
      migratedCommands: const [
        {'command': 'ping', 'owner': 'helper'},
      ],
      lastLiveSmokeReport: const {
        'ok': true,
        'path': '/tmp/caverno-macos-computer-use-smoke.json',
        'report': {'coreOk': true, 'captureOk': false},
      },
      lastAction: 'Run smoke sequence',
    ).toJson();

    expect(
      diagnostics['schemaName'],
      MacosComputerUseOnboardingDiagnostics.schemaName,
    );
    expect(
      diagnostics['schemaVersion'],
      MacosComputerUseOnboardingDiagnostics.schemaVersion,
    );
    expect(diagnostics['generatedAt'], '2026-04-25T12:00:00.000Z');
    expect(diagnostics['setupChecklist'], isA<Map<String, dynamic>>());
    expect(diagnostics['onboardingVerification'], containsPair('ok', false));
    expect(diagnostics['helperStatusPersistence'], contains('activeWork'));
    expect(diagnostics['helperIpcProtocol'], containsPair('xpcReady', true));
    expect(
      diagnostics['helperIpcProtocol'],
      containsPair('xpcStatus', 'experimental_fallback'),
    );
    expect(
      diagnostics['helperIpcProtocol'],
      containsPair('mainAppUnsafeOsActionsAllowed', false),
    );
    expect(
      diagnostics['helperIpcProtocol'],
      containsPair('helperOwnsUnsafeOsActions', true),
    );
    expect(
      diagnostics['helperIpcProtocol'],
      containsPair('xpcNextParityCommands', [
        'focusWindow',
        'screenshotWindow',
      ]),
    );
    expect(diagnostics['auditLog'], isA<List<Map<String, dynamic>>>());
    expect(diagnostics['manualSmokeSteps'], isA<List<Map<String, dynamic>>>());
    expect(diagnostics['migratedCommands'], isA<List<Map<String, String>>>());
    expect(diagnostics['lastLiveSmokeReport'], containsPair('ok', true));
  });

  test('reports missing permissions before a snapshot is loaded', () {
    const checklist = MacosComputerUseSetupChecklist(
      backend: MacosComputerUseBackends.inProcessCompatibility,
      permissions: null,
    );

    expect(checklist.hasSnapshot, isFalse);
    expect(checklist.isReady, isFalse);
    expect(checklist.missingPermissionLabels, [
      'Accessibility',
      'Screen & System Audio Recording',
    ]);
    expect(checklist.title, 'Refresh permissions before running smoke checks');
  });

  test('reports helper reachability before permission labels', () {
    final permissions = MacosComputerUsePermissionSnapshot.fromMap({
      'ok': false,
      'backend': 'helper',
      'helperReachable': false,
      'code': 'helper_unreachable',
    });
    final checklist = MacosComputerUseSetupChecklist(
      backend: MacosComputerUseBackends.helperIpc,
      permissions: permissions,
    );

    expect(checklist.isReady, isFalse);
    expect(checklist.missingPermissionLabels, ['Caverno Computer Use']);
    expect(
      checklist.subtitle,
      'Launch Caverno Computer Use, then refresh permissions.',
    );
  });

  test('builds action copy for a partial permission snapshot', () {
    final permissions = MacosComputerUsePermissionSnapshot.fromMap({
      'accessibilityGranted': true,
      'screenCaptureGranted': false,
      'systemAudioRecordingSupported': true,
    });
    final checklist = MacosComputerUseSetupChecklist(
      backend: MacosComputerUseBackends.inProcessCompatibility,
      permissions: permissions,
    );

    expect(checklist.hasSnapshot, isTrue);
    expect(checklist.isReady, isFalse);
    expect(checklist.missingPermissionLabels, [
      'Screen & System Audio Recording',
    ]);
    expect(
      checklist.subtitle,
      'Open System Settings, grant Caverno, then refresh permissions.',
    );
  });

  test('marks the setup ready when required permissions are granted', () {
    final permissions = MacosComputerUsePermissionSnapshot.fromMap({
      'accessibilityGranted': true,
      'screenCaptureGranted': true,
      'systemAudioRecordingSupported': false,
    });
    final checklist = MacosComputerUseSetupChecklist(
      backend: MacosComputerUseBackends.inProcessCompatibility,
      permissions: permissions,
    );

    expect(checklist.isReady, isTrue);
    expect(checklist.missingPermissionLabels, isEmpty);
    expect(checklist.title, 'Ready for visual, input, and audio smoke checks');
  });
}
