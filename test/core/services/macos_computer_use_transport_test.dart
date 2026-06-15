// The transport short-circuits with an `unsupported_platform` fallback when
// `Platform.isMacOS` is false, so these assertions (which expect the native
// method channel to be invoked) only hold on macOS. Restrict the suite to
// macOS so Linux CI runners do not report a deterministic failure.
@TestOn('mac-os')
library;

import 'dart:convert';

import 'package:caverno/core/services/macos_computer_use_transport.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.caverno/macos_computer_use');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'helperStatus' => {
              'ok': true,
              'backend': 'helper',
              'helperInstalled': true,
              'helperRunning': false,
            },
            'launchHelper' => {
              'ok': true,
              'backend': 'helper',
              'helperInstalled': true,
              'helperRunning': true,
              'launched': true,
            },
            'restartHelper' => {
              'ok': true,
              'backend': 'helper',
              'helperInstalled': true,
              'helperRunning': true,
              'restarted': true,
            },
            'terminateHelperForXpcLaunchAgent' => {
              'ok': true,
              'backend': 'helper',
              'helperInstalled': true,
              'helperRunning': false,
              'terminatedForXpcLaunchAgent': true,
            },
            'registerXpcLaunchAgent' => {
              'ok': true,
              'backend': 'helper',
              'xpcLaunchAgentStatus': 'enabled',
            },
            'unregisterXpcLaunchAgent' => {
              'ok': true,
              'backend': 'helper',
              'xpcLaunchAgentStatus': 'not_registered',
            },
            'helperPing' => {
              'ok': true,
              'backend': 'helper',
              'message': 'pong',
            },
            'helperPermissionStatus' => {
              'ok': true,
              'backend': 'helper',
              'accessibilityGranted': true,
              'screenCaptureGranted': false,
              'systemAudioRecordingSupported': true,
            },
            'helperOpenSystemSettings' => {
              'ok': true,
              'backend': 'helper',
              'section': (call.arguments as Map<Object?, Object?>)['section'],
            },
            'helperShowPermissionOverlay' => {
              'ok': true,
              'backend': 'helper',
              'permission':
                  (call.arguments as Map<Object?, Object?>)['permission'],
              'settingsOpened': true,
              'overlayRequested': true,
              'overlayShown': false,
              'draggableTileReady': true,
            },
            'helperStartOnboardingPermissionFlow' => {
              'ok': true,
              'backend': 'helper',
              'permission':
                  (call.arguments as Map<Object?, Object?>)['permission'],
              'onboardingFlowRequested': true,
              'lastOnboardingTransition': {'onboardingTransitionStarted': true},
            },
            'helperStopAll' => {
              'ok': true,
              'backend': 'helper',
              'cancelledInputEvents': true,
            },
            _ => throw PlatformException(code: 'unknown_method'),
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'routes helper permission commands through the helper channel',
    () async {
      const transport = HelperMacosComputerUseTransport(channel: channel);

      final status =
          jsonDecode(await transport.helperStatus()) as Map<String, dynamic>;
      final launch =
          jsonDecode(await transport.launchHelper()) as Map<String, dynamic>;
      final restart =
          jsonDecode(await transport.restartHelper()) as Map<String, dynamic>;
      final terminated =
          jsonDecode(await transport.terminateHelperForXpcLaunchAgent())
              as Map<String, dynamic>;
      final register =
          jsonDecode(await transport.registerXpcLaunchAgent())
              as Map<String, dynamic>;
      final unregister =
          jsonDecode(await transport.unregisterXpcLaunchAgent())
              as Map<String, dynamic>;
      final ping = jsonDecode(await transport.ping()) as Map<String, dynamic>;
      final permissions =
          jsonDecode(await transport.getPermissions()) as Map<String, dynamic>;
      final settings =
          jsonDecode(
                await transport.openSystemSettings(section: 'accessibility'),
              )
              as Map<String, dynamic>;
      final overlay =
          jsonDecode(
                await transport.showPermissionOverlay(
                  permission: 'accessibility',
                ),
              )
              as Map<String, dynamic>;
      final onboardingFlow =
          jsonDecode(
                await transport.startOnboardingPermissionFlow(
                  permission: 'screenRecording',
                ),
              )
              as Map<String, dynamic>;
      final stopAll =
          jsonDecode(await transport.stopAll()) as Map<String, dynamic>;

      expect(calls.map((call) => call.method), [
        'helperStatus',
        'launchHelper',
        'restartHelper',
        'terminateHelperForXpcLaunchAgent',
        'registerXpcLaunchAgent',
        'unregisterXpcLaunchAgent',
        'helperPing',
        'helperPermissionStatus',
        'helperOpenSystemSettings',
        'helperShowPermissionOverlay',
        'helperStartOnboardingPermissionFlow',
        'helperStopAll',
      ]);
      expect(status, containsPair('helperInstalled', true));
      expect(status, containsPair('helperRunning', false));
      expect(launch, containsPair('helperRunning', true));
      expect(restart, containsPair('restarted', true));
      expect(terminated, containsPair('terminatedForXpcLaunchAgent', true));
      expect(register, containsPair('xpcLaunchAgentStatus', 'enabled'));
      expect(
        unregister,
        containsPair('xpcLaunchAgentStatus', 'not_registered'),
      );
      expect(ping, containsPair('helperReachable', true));
      expect(permissions, containsPair('accessibilityGranted', true));
      expect(permissions, containsPair('screenCaptureGranted', false));
      expect(settings, containsPair('section', 'accessibility'));
      expect(overlay, containsPair('permission', 'accessibility'));
      expect(overlay, containsPair('draggableTileReady', true));
      expect(onboardingFlow, containsPair('permission', 'screenRecording'));
      expect(stopAll, containsPair('cancelledInputEvents', true));
    },
  );

  test('marks helper unreachable when the native channel times out', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'helper_unreachable',
            message: 'Caverno Computer Use did not respond.',
          );
        });
    const transport = HelperMacosComputerUseTransport(channel: channel);

    final permissions =
        jsonDecode(await transport.getPermissions()) as Map<String, dynamic>;

    expect(permissions, containsPair('ok', false));
    expect(permissions, containsPair('helperReachable', false));
    expect(permissions, containsPair('code', 'helper_unreachable'));
  });
}
