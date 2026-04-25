import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';
import 'macos_computer_use_setup.dart';

final macosComputerUseServiceProvider = Provider<MacosComputerUseService>((
  ref,
) {
  return MacosComputerUseService();
});

class MacosComputerUseService {
  static const MethodChannel _channel = MethodChannel(
    'com.caverno/macos_computer_use',
  );

  bool get isAvailable => Platform.isMacOS;

  Future<String> getPermissions() async {
    return _invokeJson('getPermissions');
  }

  Future<String> requestPermissions({
    bool accessibility = true,
    bool screenCapture = true,
  }) async {
    final responses = <String, dynamic>{};
    if (accessibility) {
      responses['accessibility'] = await _invokeMap('requestAccessibility');
    }
    if (screenCapture) {
      responses['screenCapture'] = await _invokeMap('requestScreenCapture');
    }
    responses['current'] = await _invokeMap('getPermissions');
    return jsonEncode(responses);
  }

  Future<String> openSystemSettings({required String section}) async {
    return _invokeJson('openSystemSettings', {'section': section});
  }

  Future<String> screenshot(Map<String, dynamic> arguments) async {
    return _invokeJson('screenshot', _normalizeCoordinateArguments(arguments));
  }

  Future<String> listWindows(Map<String, dynamic> arguments) async {
    return _invokeJson('listWindows', arguments);
  }

  Future<String> focusWindow(Map<String, dynamic> arguments) async {
    return _invokeJson('focusWindow', arguments);
  }

  Future<String> screenshotWindow(Map<String, dynamic> arguments) async {
    return _invokeJson('screenshotWindow', arguments);
  }

  Future<String> click(Map<String, dynamic> arguments) async {
    return _invokeJson('click', _normalizeCoordinateArguments(arguments));
  }

  Future<String> moveMouse(Map<String, dynamic> arguments) async {
    return _invokeJson('moveMouse', _normalizeCoordinateArguments(arguments));
  }

  Future<String> drag(Map<String, dynamic> arguments) async {
    return _invokeJson('drag', _normalizeCoordinateArguments(arguments));
  }

  Future<String> scroll(Map<String, dynamic> arguments) async {
    return _invokeJson('scroll', _normalizeCoordinateArguments(arguments));
  }

  Future<String> typeText(Map<String, dynamic> arguments) async {
    return _invokeJson('typeText', arguments);
  }

  Future<String> pressKey(Map<String, dynamic> arguments) async {
    final normalized = Map<String, dynamic>.from(arguments);
    final modifiers = normalized['modifiers'];
    if (modifiers is List) {
      normalized['modifiers'] = modifiers.map((value) => '$value').toList();
    }
    return _invokeJson('pressKey', normalized);
  }

  Future<String> startSystemAudioRecording(
    Map<String, dynamic> arguments,
  ) async {
    return _invokeJson('startSystemAudioRecording', arguments);
  }

  Future<String> stopSystemAudioRecording() async {
    return _invokeJson('stopSystemAudioRecording');
  }

  Map<String, dynamic> _normalizeCoordinateArguments(
    Map<String, dynamic> arguments,
  ) {
    final normalized = Map<String, dynamic>.from(arguments);
    for (final key in const [
      'x',
      'y',
      'from_x',
      'from_y',
      'to_x',
      'to_y',
      'source_width',
      'source_height',
    ]) {
      final value = normalized[key];
      if (value is num) {
        normalized[key] = value.toDouble();
      }
    }
    for (final key in const [
      'window_id',
      'windowId',
      'display_id',
      'displayId',
    ]) {
      final value = normalized[key];
      if (value is num) {
        normalized[key] = value.toInt();
      }
    }
    return normalized;
  }

  Future<String> _invokeJson(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (!Platform.isMacOS) {
      return jsonEncode({
        'ok': false,
        'code': 'unsupported_platform',
        'error': 'macOS computer use tools are only available on macOS.',
      });
    }

    try {
      final result = await _invokeMap(method, arguments);
      return jsonEncode(_withNextAction(result));
    } on MissingPluginException {
      return jsonEncode({
        'ok': false,
        'code': 'plugin_unavailable',
        'error': 'The macOS computer use plugin is not registered.',
      });
    } on PlatformException catch (error) {
      appLog('[ComputerUse] $method failed: $error');
      return jsonEncode(
        _withNextAction({
          'ok': false,
          'code': error.code,
          'error': error.message ?? error.toString(),
          if (error.details != null) 'details': error.details,
        }),
      );
    }
  }

  Future<Map<String, dynamic>> _invokeMap(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      method,
      arguments,
    );
    return result ?? const <String, dynamic>{};
  }

  Map<String, dynamic> _withNextAction(Map<String, dynamic> result) {
    final code = result['code'];
    if (code is! String || result.containsKey('nextAction')) {
      return result;
    }
    final nextAction = _nextActionForCode(code);
    if (nextAction == null) {
      return result;
    }
    return {...result, 'nextAction': nextAction};
  }

  String? _nextActionForCode(String code) {
    final permissionOwner =
        MacosComputerUseBackends.inProcessCompatibility.permissionOwnerName;
    return switch (code) {
      'accessibility_denied' =>
        'Open System Settings > Privacy & Security > Accessibility, grant $permissionOwner, then refresh permissions.',
      'screen_capture_unavailable' || 'screenshot_failed' =>
        'Open System Settings > Privacy & Security > Screen & System Audio Recording, grant $permissionOwner, then refresh permissions.',
      _ => null,
    };
  }
}
