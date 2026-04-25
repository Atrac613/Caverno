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
}

class _FakePermissionTransport extends MacosComputerUsePermissionTransport {
  _FakePermissionTransport({required this.permissions});

  final Map<String, dynamic> permissions;
  final List<String> calledMethods = [];

  @override
  MacosComputerUseBackendInfo get backendInfo =>
      MacosComputerUseBackends.helperIpc;

  @override
  Future<String> getPermissions() async {
    calledMethods.add('getPermissions');
    return jsonEncode(permissions);
  }

  @override
  Future<String> openSystemSettings({required String section}) async {
    calledMethods.add('openSystemSettings');
    return jsonEncode({'ok': true, 'section': section});
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
