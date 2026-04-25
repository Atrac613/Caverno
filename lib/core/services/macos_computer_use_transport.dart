import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/logger.dart';
import 'macos_computer_use_setup.dart';

abstract class MacosComputerUsePermissionTransport {
  const MacosComputerUsePermissionTransport();

  MacosComputerUseBackendInfo get backendInfo;

  Future<String> ping();

  Future<String> getPermissions();

  Future<String> openSystemSettings({required String section});

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
