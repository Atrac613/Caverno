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
    expect(info['requestObject'], 'com.noguwo.apps.caverno');
    expect(info['responseObject'], 'com.noguwo.apps.caverno.computer-use');
    expect(info['xpcReady'], isFalse);
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
