import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';
import 'macos_computer_use_setup.dart';
import 'macos_computer_use_transport.dart';

final macosComputerUseServiceProvider = Provider<MacosComputerUseService>((
  ref,
) {
  return MacosComputerUseService();
});

class MacosComputerUseService {
  MacosComputerUseService({
    MacosComputerUsePermissionTransport? permissionTransport,
  }) : _permissionTransport =
           permissionTransport ?? const HelperMacosComputerUseTransport();

  static const MethodChannel _channel = MethodChannel(
    'com.caverno/macos_computer_use',
  );
  static const liveSmokeReportPath = String.fromEnvironment(
    'CAVERNO_MACOS_COMPUTER_USE_SMOKE_REPORT_PATH',
    defaultValue: '/tmp/caverno-macos-computer-use-smoke.json',
  );

  final MacosComputerUsePermissionTransport _permissionTransport;

  bool get isAvailable => Platform.isMacOS;

  MacosComputerUseBackendInfo get permissionBackendInfo =>
      _permissionTransport.backendInfo;

  Future<String> getHelperStatus() async {
    return _invokeTransportJson(_permissionTransport.helperStatus);
  }

  Future<String> launchHelper() async {
    return _invokeTransportJson(_permissionTransport.launchHelper);
  }

  Future<String> restartHelper() async {
    return _invokeTransportJson(_permissionTransport.restartHelper);
  }

  Future<String> pingHelper() async {
    return _invokeTransportJson(_permissionTransport.ping);
  }

  Future<String> waitForHelperIpcReady({
    int attempts = 2,
    Duration delay = const Duration(milliseconds: 400),
  }) async {
    final safeAttempts = attempts < 1 ? 1 : attempts;
    final startedAt = DateTime.now();
    final results = <Object>[];

    for (var index = 0; index < safeAttempts; index += 1) {
      final raw = await pingHelper();
      final decoded = _decodeMap(raw);
      results.add(decoded ?? raw);
      if (decoded != null &&
          decoded['ok'] != false &&
          decoded['helperReachable'] != false) {
        return jsonEncode({
          ...decoded,
          'ok': true,
          'helperReachable': true,
          'ipcReady': true,
          'attempts': index + 1,
          'waitedMs': DateTime.now().difference(startedAt).inMilliseconds,
        });
      }
      if (index < safeAttempts - 1) {
        await Future<void>.delayed(delay);
      }
    }

    Map<String, dynamic>? last;
    for (final result in results) {
      if (result is Map) {
        last = Map<String, dynamic>.from(result);
      }
    }
    final failed = <String, dynamic>{
      if (last != null) ...last,
      'ok': false,
      'helperReachable': false,
      'ipcReady': false,
      'code': last?['code'] ?? 'helper_unreachable',
      'error':
          last?['error'] ?? 'Caverno Computer Use IPC did not become ready.',
      'attempts': safeAttempts,
      'waitedMs': DateTime.now().difference(startedAt).inMilliseconds,
      'results': results,
    };
    return jsonEncode(_withNextAction(failed));
  }

  Future<String> getPermissions() async {
    return _invokeTransportJson(_permissionTransport.getPermissions);
  }

  Future<String> requestPermissions({
    bool accessibility = true,
    bool screenCapture = true,
  }) async {
    if (_permissionTransport.backendInfo.usesSeparateHelper) {
      final responses = <String, dynamic>{};
      responses['helper'] =
          _decodeMap(
            await _invokeTransportJson(_permissionTransport.launchHelper),
          ) ??
          const <String, dynamic>{};
      if (accessibility) {
        responses['accessibility'] =
            _decodeMap(
              await _invokeTransportJson(
                () => _permissionTransport.openSystemSettings(
                  section: 'accessibility',
                ),
              ),
            ) ??
            const <String, dynamic>{};
      }
      if (screenCapture) {
        responses['screenCapture'] =
            _decodeMap(
              await _invokeTransportJson(
                () => _permissionTransport.openSystemSettings(
                  section: 'screen_recording',
                ),
              ),
            ) ??
            const <String, dynamic>{};
      }
      responses['current'] =
          _decodeMap(
            await _invokeTransportJson(_permissionTransport.getPermissions),
          ) ??
          const <String, dynamic>{};
      return jsonEncode(responses);
    }

    final responses = <String, dynamic>{};
    if (accessibility) {
      responses['accessibility'] = await _invokeMap('requestAccessibility');
    }
    if (screenCapture) {
      responses['screenCapture'] = await _invokeMap('requestScreenCapture');
    }
    responses['current'] =
        _decodeMap(
          await _invokeTransportJson(_permissionTransport.getPermissions),
        ) ??
        const <String, dynamic>{};
    return jsonEncode(responses);
  }

  Future<String> openSystemSettings({required String section}) async {
    return _invokeTransportJson(
      () => _permissionTransport.openSystemSettings(section: section),
    );
  }

  Future<String> stopHelperWork() async {
    return _invokeTransportJson(_permissionTransport.stopAll);
  }

  Future<String> getLastLiveSmokeReport() async {
    if (!Platform.isMacOS) {
      return jsonEncode({
        'ok': false,
        'code': 'unsupported_platform',
        'error':
            'macOS computer use live smoke reports are only available on macOS.',
        'path': liveSmokeReportPath,
      });
    }

    final file = File(liveSmokeReportPath);
    try {
      if (!await file.exists()) {
        return jsonEncode({
          'ok': false,
          'code': 'live_smoke_report_missing',
          'error':
              'No macOS computer use live smoke report has been written yet.',
          'path': liveSmokeReportPath,
        });
      }

      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return jsonEncode({
          'ok': true,
          'path': liveSmokeReportPath,
          'report': Map<String, dynamic>.from(decoded),
        });
      }
      return jsonEncode({
        'ok': false,
        'code': 'live_smoke_report_invalid',
        'error':
            'The macOS computer use live smoke report is not a JSON object.',
        'path': liveSmokeReportPath,
      });
    } catch (error) {
      return jsonEncode({
        'ok': false,
        'code': 'live_smoke_report_read_failed',
        'error': error.toString(),
        'path': liveSmokeReportPath,
      });
    }
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

  Future<String> _invokeTransportJson(Future<String> Function() invoke) async {
    final raw = await invoke();
    final decoded = _decodeMap(raw);
    if (decoded == null) {
      return raw;
    }
    return jsonEncode(_withNextAction(decoded));
  }

  Map<String, dynamic>? _decodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _withNextAction(Map<String, dynamic> result) {
    final code = result['code'];
    if (code is! String || result.containsKey('nextAction')) {
      return result;
    }
    final nextAction = _nextActionForCode(code, result);
    if (nextAction == null) {
      return result;
    }
    return {...result, 'nextAction': nextAction};
  }

  String? _nextActionForCode(String code, Map<String, dynamic> result) {
    final permissionOwner = permissionBackendInfo.permissionOwnerName;
    return switch (code) {
      'helper_unreachable' => _helperUnreachableNextAction(result),
      'helper_not_installed' =>
        'Build Caverno with the bundled Caverno Computer Use helper, then launch it from the permissions panel.',
      'accessibility_denied' =>
        'Open System Settings > Privacy & Security > Accessibility, grant $permissionOwner, then refresh permissions.',
      'screen_capture_unavailable' || 'screenshot_failed' =>
        'Open System Settings > Privacy & Security > Screen & System Audio Recording, grant $permissionOwner, then refresh permissions.',
      _ => null,
    };
  }

  String _helperUnreachableNextAction(Map<String, dynamic> result) {
    final details = result['details'];
    final helperRunning =
        result['helperRunning'] == true ||
        (details is Map && details['helperRunning'] == true);
    final helperDiagnostics = details is Map
        ? details['helperSharedDiagnostics']
        : result['helperSharedDiagnostics'];
    if (helperRunning &&
        helperDiagnostics is Map &&
        helperDiagnostics['listenerStarted'] == true &&
        helperDiagnostics['lastHelperIpcRequest'] == null) {
      return 'Caverno Computer Use is running and its listener is started, but no DNC request was recorded. Restart Caverno Computer Use, then retry IPC readiness.';
    }
    if (helperRunning) {
      return 'Caverno Computer Use is running, but IPC did not respond. Restart Caverno Computer Use, then retry IPC readiness.';
    }
    return 'Launch ${MacosComputerUseBackends.helperDisplayName}, then refresh permissions.';
  }
}
