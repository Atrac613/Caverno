import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/logger.dart';
import 'macos_computer_use_setup.dart';

abstract class MacosComputerUsePermissionTransport {
  const MacosComputerUsePermissionTransport();

  MacosComputerUseBackendInfo get backendInfo;

  Future<String> helperStatus();

  Future<String> launchHelper();

  Future<String> restartHelper();

  Future<String> terminateHelperForXpcLaunchAgent();

  Future<String> registerXpcLaunchAgent();

  Future<String> unregisterXpcLaunchAgent();

  Future<String> ping();

  Future<String> getPermissions();

  Future<String> openSystemSettings({required String section});

  Future<String> showPermissionOverlay({required String permission});

  Future<String> stopAll();
}

class HelperMacosComputerUseTransport
    extends MacosComputerUsePermissionTransport {
  const HelperMacosComputerUseTransport({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.caverno/macos_computer_use',
  );

  final MethodChannel _channel;

  @override
  MacosComputerUseBackendInfo get backendInfo =>
      MacosComputerUseBackends.helperIpc;

  @override
  Future<String> helperStatus() {
    return _invokeJson('helperStatus');
  }

  @override
  Future<String> launchHelper() {
    return _invokeJson('launchHelper');
  }

  @override
  Future<String> restartHelper() {
    return _invokeJson('restartHelper');
  }

  @override
  Future<String> terminateHelperForXpcLaunchAgent() {
    return _invokeJson('terminateHelperForXpcLaunchAgent');
  }

  @override
  Future<String> registerXpcLaunchAgent() {
    return _invokeJson('registerXpcLaunchAgent');
  }

  @override
  Future<String> unregisterXpcLaunchAgent() {
    return _invokeJson('unregisterXpcLaunchAgent');
  }

  @override
  Future<String> ping() {
    return _invokeJson('helperPing');
  }

  @override
  Future<String> getPermissions() {
    return _invokeJson('helperPermissionStatus');
  }

  @override
  Future<String> openSystemSettings({required String section}) {
    return _invokeJson('helperOpenSystemSettings', {'section': section});
  }

  @override
  Future<String> showPermissionOverlay({required String permission}) {
    return _invokeJson('helperShowPermissionOverlay', {
      'permission': permission,
    });
  }

  @override
  Future<String> stopAll() {
    return _invokeJson('helperStopAll');
  }

  Future<String> _invokeJson(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (!Platform.isMacOS) {
      return jsonEncode({
        'ok': false,
        'backend': 'helper',
        'helperReachable': false,
        'code': 'unsupported_platform',
        'error': 'macOS computer use helper tools are only available on macOS.',
      });
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        method,
        arguments,
      );
      return jsonEncode({'helperReachable': true, ...?result});
    } on MissingPluginException {
      return jsonEncode({
        'ok': false,
        'backend': 'helper',
        'helperReachable': false,
        'code': 'plugin_unavailable',
        'error': 'The macOS computer use plugin is not registered.',
      });
    } on PlatformException catch (error) {
      appLog('[ComputerUseHelper] $method failed: $error');
      return jsonEncode({
        'ok': false,
        'backend': 'helper',
        'helperReachable': false,
        'code': error.code,
        'error': error.message ?? error.toString(),
        if (error.details != null) 'details': error.details,
      });
    }
  }
}

class InProcessMacosComputerUseTransport
    extends MacosComputerUsePermissionTransport {
  const InProcessMacosComputerUseTransport({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.caverno/macos_computer_use',
  );

  final MethodChannel _channel;

  @override
  MacosComputerUseBackendInfo get backendInfo =>
      MacosComputerUseBackends.inProcessCompatibility;

  @override
  Future<String> helperStatus() async {
    return jsonEncode({
      'ok': true,
      'backend': 'in_process',
      'helperInstalled': false,
      'helperRunning': false,
    });
  }

  @override
  Future<String> launchHelper() async {
    return jsonEncode({
      'ok': false,
      'backend': 'in_process',
      'code': 'helper_not_used',
      'error': 'The in-process backend does not launch a helper app.',
    });
  }

  @override
  Future<String> restartHelper() async {
    return jsonEncode({
      'ok': false,
      'backend': 'in_process',
      'code': 'helper_not_used',
      'error': 'The in-process backend does not restart a helper app.',
    });
  }

  @override
  Future<String> terminateHelperForXpcLaunchAgent() async {
    return jsonEncode({
      'ok': false,
      'backend': 'in_process',
      'code': 'helper_not_used',
      'error':
          'The in-process backend does not terminate a helper app for XPC launch.',
    });
  }

  @override
  Future<String> registerXpcLaunchAgent() async {
    return jsonEncode({
      'ok': false,
      'backend': 'in_process',
      'code': 'helper_not_used',
      'error': 'The in-process backend does not register a helper LaunchAgent.',
    });
  }

  @override
  Future<String> unregisterXpcLaunchAgent() async {
    return jsonEncode({
      'ok': false,
      'backend': 'in_process',
      'code': 'helper_not_used',
      'error':
          'The in-process backend does not unregister a helper LaunchAgent.',
    });
  }

  @override
  Future<String> ping() async {
    return jsonEncode({'ok': true, 'backend': 'in_process', 'message': 'pong'});
  }

  @override
  Future<String> getPermissions() {
    return _invokeJson('getPermissions');
  }

  @override
  Future<String> openSystemSettings({required String section}) {
    return _invokeJson('openSystemSettings', {'section': section});
  }

  @override
  Future<String> showPermissionOverlay({required String permission}) async {
    return jsonEncode({
      'ok': false,
      'backend': 'in_process',
      'permission': permission,
      'overlayRequested': true,
      'overlayShown': false,
      'draggableTileReady': false,
      'code': 'helper_overlay_unavailable',
      'error': 'Permission overlays are owned by Caverno Computer Use.',
      'nextAction':
          'Launch Caverno Computer Use to show the permission overlay.',
    });
  }

  @override
  Future<String> stopAll() async {
    return jsonEncode({
      'ok': true,
      'backend': 'in_process',
      'stoppedAudioRecording': false,
      'cancelledInputEvents': true,
    });
  }

  Future<String> _invokeJson(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (!Platform.isMacOS) {
      return jsonEncode({
        'ok': false,
        'backend': 'in_process',
        'code': 'unsupported_platform',
        'error': 'macOS computer use tools are only available on macOS.',
      });
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        method,
        arguments,
      );
      return jsonEncode(result ?? const <String, dynamic>{});
    } on MissingPluginException {
      return jsonEncode({
        'ok': false,
        'backend': 'in_process',
        'code': 'plugin_unavailable',
        'error': 'The macOS computer use plugin is not registered.',
      });
    } on PlatformException catch (error) {
      appLog('[ComputerUse] $method failed: $error');
      return jsonEncode({
        'ok': false,
        'backend': 'in_process',
        'code': error.code,
        'error': error.message ?? error.toString(),
        if (error.details != null) 'details': error.details,
      });
    }
  }
}
