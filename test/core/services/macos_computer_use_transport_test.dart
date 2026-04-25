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

      final ping = jsonDecode(await transport.ping()) as Map<String, dynamic>;
      final permissions =
          jsonDecode(await transport.getPermissions()) as Map<String, dynamic>;
      final settings =
          jsonDecode(
                await transport.openSystemSettings(section: 'accessibility'),
              )
              as Map<String, dynamic>;
      final stopAll =
          jsonDecode(await transport.stopAll()) as Map<String, dynamic>;

      expect(calls.map((call) => call.method), [
        'helperPing',
        'helperPermissionStatus',
        'helperOpenSystemSettings',
        'helperStopAll',
      ]);
      expect(ping, containsPair('helperReachable', true));
      expect(permissions, containsPair('accessibilityGranted', true));
      expect(permissions, containsPair('screenCaptureGranted', false));
      expect(settings, containsPair('section', 'accessibility'));
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
