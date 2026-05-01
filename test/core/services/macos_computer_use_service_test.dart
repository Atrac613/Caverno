import 'dart:convert';

import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:caverno/core/services/macos_computer_use_setup.dart';
import 'package:caverno/core/services/macos_computer_use_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the helper transport for permission status', () async {
    final transport = _FakePermissionTransport(
      permissions: {
        'ok': true,
        'backend': 'helper',
        'helperReachable': true,
        'accessibilityGranted': true,
        'screenCaptureGranted': false,
        'systemAudioRecordingSupported': true,
      },
    );
    final service = MacosComputerUseService(permissionTransport: transport);

    final permissions =
        jsonDecode(await service.getPermissions()) as Map<String, dynamic>;

    expect(service.permissionBackendInfo, MacosComputerUseBackends.helperIpc);
    expect(transport.calledMethods, ['getPermissions']);
    expect(permissions, containsPair('backend', 'helper'));
    expect(permissions, containsPair('helperReachable', true));
    expect(permissions, containsPair('accessibilityGranted', true));
  });

  test(
    'adds a helper launch next action when the helper is unreachable',
    () async {
      final service = MacosComputerUseService(
        permissionTransport: _FakePermissionTransport(
          permissions: {
            'ok': false,
            'backend': 'helper',
            'helperReachable': false,
            'code': 'helper_unreachable',
            'error': 'Caverno Computer Use did not respond.',
          },
        ),
      );

      final permissions =
          jsonDecode(await service.getPermissions()) as Map<String, dynamic>;

      expect(permissions, containsPair('code', 'helper_unreachable'));
      expect(
        permissions,
        containsPair(
          'nextAction',
          'Launch Caverno Computer Use, then refresh permissions.',
        ),
      );
    },
  );

  test(
    'adds a restart next action when a running helper misses IPC requests',
    () async {
      final service = MacosComputerUseService(
        permissionTransport: _FakePermissionTransport(
          permissions: {
            'ok': false,
            'backend': 'helper',
            'helperReachable': false,
            'code': 'helper_unreachable',
            'error': 'Caverno Computer Use did not respond.',
            'details': {
              'helperRunning': true,
              'helperSharedDiagnostics': {
                'listenerStarted': true,
                'helperIpcEventCount': 0,
              },
            },
          },
        ),
      );

      final permissions =
          jsonDecode(await service.getPermissions()) as Map<String, dynamic>;

      expect(permissions, containsPair('code', 'helper_unreachable'));
      expect(
        permissions,
        containsPair(
          'nextAction',
          'Caverno Computer Use is running and its listener is started, but no DNC request was recorded. Restart Caverno Computer Use, then retry IPC readiness.',
        ),
      );
    },
  );

  test('waits for helper IPC readiness with retry metadata', () async {
    final transport = _FakePermissionTransport(
      permissions: {
        'ok': true,
        'backend': 'helper',
        'helperReachable': true,
        'accessibilityGranted': true,
        'screenCaptureGranted': true,
        'systemAudioRecordingSupported': true,
      },
    );
    final service = MacosComputerUseService(permissionTransport: transport);

    final result =
        jsonDecode(
              await service.waitForHelperIpcReady(
                attempts: 1,
                delay: Duration.zero,
              ),
            )
            as Map<String, dynamic>;

    expect(result, containsPair('ipcReady', true));
    expect(result, containsPair('attempts', 1));
    expect(transport.calledMethods, ['ping']);
  });

  test('launches the helper before guiding permission requests', () async {
    final transport = _FakePermissionTransport(
      permissions: {
        'ok': true,
        'backend': 'helper',
        'helperReachable': true,
        'accessibilityGranted': false,
        'screenCaptureGranted': false,
        'systemAudioRecordingSupported': true,
      },
    );
    final service = MacosComputerUseService(permissionTransport: transport);

    final result =
        jsonDecode(
              await service.requestPermissions(
                accessibility: true,
                screenCapture: false,
              ),
            )
            as Map<String, dynamic>;

    expect(transport.calledMethods, [
      'launchHelper',
      'ping',
      'showPermissionOverlay:accessibility',
      'getPermissions',
    ]);
    expect(result, containsPair('helper', isA<Map<String, dynamic>>()));
    expect(result, containsPair('helperReady', isA<Map<String, dynamic>>()));
    expect(result, containsPair('current', isA<Map<String, dynamic>>()));
  });

  test(
    'routes LaunchAgent registration through the helper transport',
    () async {
      final transport = _FakePermissionTransport(
        permissions: const <String, dynamic>{'ok': true},
      );
      final service = MacosComputerUseService(permissionTransport: transport);

      final registered =
          jsonDecode(await service.registerXpcLaunchAgent())
              as Map<String, dynamic>;
      final unregistered =
          jsonDecode(await service.unregisterXpcLaunchAgent())
              as Map<String, dynamic>;

      expect(transport.calledMethods, [
        'registerXpcLaunchAgent',
        'unregisterXpcLaunchAgent',
      ]);
      expect(registered, containsPair('xpcLaunchAgentStatus', 'enabled'));
      expect(
        unregistered,
        containsPair('xpcLaunchAgentStatus', 'not_registered'),
      );
    },
  );

  test('routes permission overlays through the helper transport', () async {
    final transport = _FakePermissionTransport(
      permissions: const <String, dynamic>{'ok': true},
    );
    final service = MacosComputerUseService(permissionTransport: transport);

    final result =
        jsonDecode(
              await service.showPermissionOverlay(
                permission: 'screenRecording',
              ),
            )
            as Map<String, dynamic>;

    expect(transport.calledMethods, [
      'launchHelper',
      'ping',
      'showPermissionOverlay:screenRecording',
    ]);
    expect(result, containsPair('permission', 'screenRecording'));
    expect(result, containsPair('overlayRequested', true));
    expect(result, containsPair('draggableTileReady', true));
    expect(result, containsPair('helperUi', isA<Map<String, dynamic>>()));
  });

  test(
    'routes onboarding permission flows through the helper transport',
    () async {
      final transport = _FakePermissionTransport(
        permissions: const <String, dynamic>{'ok': true},
      );
      final service = MacosComputerUseService(permissionTransport: transport);

      final result =
          jsonDecode(
                await service.startOnboardingPermissionFlow(
                  permission: 'screenRecording',
                ),
              )
              as Map<String, dynamic>;

      expect(transport.calledMethods, [
        'launchHelper',
        'ping',
        'startOnboardingPermissionFlow:screenRecording',
      ]);
      expect(result, containsPair('permission', 'screenRecording'));
      expect(result, containsPair('onboardingFlowRequested', true));
      expect(result, containsPair('lastOnboardingTransition', isA<Map>()));
      expect(result, containsPair('helperUi', isA<Map<String, dynamic>>()));
    },
  );

  test('packages display screenshots for vision observations', () async {
    final service = _FakeVisionMacosComputerUseService();

    final result =
        jsonDecode(
              await service.visionObserve(const {
                'target': 'display',
                'max_width': 640,
              }),
            )
            as Map<String, dynamic>;

    expect(service.calledMethods, [
      'getPermissions',
      'listWindows',
      'screenshot',
    ]);
    expect(result, containsPair('ok', true));
    expect(
      result,
      containsPair('schemaName', 'macos_computer_use_vision_observation'),
    );
    expect(result['observationId'], isA<String>());
    expect(result, containsPair('imageBase64', 'display-image'));
    expect(result['allowedNextTools'], contains('computer_click'));
    expect(result['approvalRequiredTools'], contains('computer_click'));
    expect(result['armingRequiredTools'], contains('computer_type_text'));
    expect(result['coordinateGuidance'], containsPair('sourceWidth', 640));
  });

  test(
    'resolves the first visible window for front-window vision observations',
    () async {
      final service = _FakeVisionMacosComputerUseService();

      final result =
          jsonDecode(
                await service.visionObserve(const {
                  'target': 'front_window',
                  'include_windows': true,
                }),
              )
              as Map<String, dynamic>;

      expect(service.calledMethods, [
        'getPermissions',
        'listWindows',
        'screenshotWindow',
      ]);
      expect(result, containsPair('ok', true));
      expect(result['imageBase64'], 'window-image');
      expect(result['target'], containsPair('resolved', 'window'));
      expect(result['target'], containsPair('windowId', 42));
      expect(result['coordinateGuidance'], containsPair('windowId', 42));
    },
  );
}

class _FakeVisionMacosComputerUseService extends MacosComputerUseService {
  final List<String> calledMethods = [];

  @override
  Future<String> getPermissions() async {
    calledMethods.add('getPermissions');
    return jsonEncode({
      'ok': true,
      'accessibilityGranted': true,
      'screenCaptureGranted': true,
      'systemAudioRecordingSupported': true,
    });
  }

  @override
  Future<String> listWindows(Map<String, dynamic> arguments) async {
    calledMethods.add('listWindows');
    return jsonEncode({
      'ok': true,
      'windows': [
        {
          'windowId': 42,
          'appName': 'Example',
          'title': 'Example Window',
          'bounds': {'x': 10, 'y': 20, 'width': 800, 'height': 600},
        },
      ],
    });
  }

  @override
  Future<String> screenshot(Map<String, dynamic> arguments) async {
    calledMethods.add('screenshot');
    return jsonEncode({
      'ok': true,
      'command': 'screenshot',
      'coordinateSpace': 'screenshot_pixels',
      'width': arguments['max_width'] ?? 900,
      'height': 360,
      'displayId': 1,
      'imageBase64': 'display-image',
      'imageMimeType': 'image/png',
    });
  }

  @override
  Future<String> screenshotWindow(Map<String, dynamic> arguments) async {
    calledMethods.add('screenshotWindow');
    return jsonEncode({
      'ok': true,
      'command': 'screenshotWindow',
      'coordinateSpace': 'window_pixels',
      'width': 900,
      'height': 600,
      'windowId': arguments['window_id'],
      'imageBase64': 'window-image',
      'imageMimeType': 'image/png',
    });
  }
}

class _FakePermissionTransport extends MacosComputerUsePermissionTransport {
  _FakePermissionTransport({required this.permissions});

  final Map<String, dynamic> permissions;
  final List<String> calledMethods = [];

  @override
  MacosComputerUseBackendInfo get backendInfo =>
      MacosComputerUseBackends.helperIpc;

  @override
  Future<String> helperStatus() async {
    calledMethods.add('helperStatus');
    return jsonEncode({
      'ok': true,
      'helperInstalled': true,
      'helperRunning': true,
    });
  }

  @override
  Future<String> launchHelper() async {
    calledMethods.add('launchHelper');
    return jsonEncode({'ok': true, 'helperRunning': true});
  }

  @override
  Future<String> restartHelper() async {
    calledMethods.add('restartHelper');
    return jsonEncode({'ok': true, 'helperRunning': true, 'restarted': true});
  }

  @override
  Future<String> terminateHelperForXpcLaunchAgent() async {
    calledMethods.add('terminateHelperForXpcLaunchAgent');
    return jsonEncode({
      'ok': true,
      'helperRunning': false,
      'terminatedForXpcLaunchAgent': true,
    });
  }

  @override
  Future<String> registerXpcLaunchAgent() async {
    calledMethods.add('registerXpcLaunchAgent');
    return jsonEncode({'ok': true, 'xpcLaunchAgentStatus': 'enabled'});
  }

  @override
  Future<String> unregisterXpcLaunchAgent() async {
    calledMethods.add('unregisterXpcLaunchAgent');
    return jsonEncode({'ok': true, 'xpcLaunchAgentStatus': 'not_registered'});
  }

  @override
  Future<String> getPermissions() async {
    calledMethods.add('getPermissions');
    return jsonEncode(permissions);
  }

  @override
  Future<String> openSystemSettings({required String section}) async {
    calledMethods.add('openSystemSettings:$section');
    return jsonEncode({'ok': true, 'section': section});
  }

  @override
  Future<String> showPermissionOverlay({required String permission}) async {
    calledMethods.add('showPermissionOverlay:$permission');
    return jsonEncode({
      'ok': true,
      'permission': permission,
      'settingsOpened': true,
      'overlayRequested': true,
      'overlayShown': false,
      'draggableTileReady': true,
    });
  }

  @override
  Future<String> startOnboardingPermissionFlow({
    required String permission,
  }) async {
    calledMethods.add('startOnboardingPermissionFlow:$permission');
    return jsonEncode({
      'ok': true,
      'permission': permission,
      'onboardingFlowRequested': true,
      'lastOnboardingTransition': {
        'onboardingTransitionStarted': true,
        'transitionSourcePermission': permission,
        'transitionPlaceholderShown': true,
        'transitionAnimationTarget': 'permission_overlay_window',
      },
    });
  }

  @override
  Future<String> ping() async {
    calledMethods.add('ping');
    return jsonEncode({'ok': true, 'message': 'pong'});
  }

  @override
  Future<String> stopAll() async {
    calledMethods.add('stopAll');
    return jsonEncode({'ok': true});
  }
}
