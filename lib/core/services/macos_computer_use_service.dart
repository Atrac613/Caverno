import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';
import 'macos_computer_use_setup.dart';
import 'macos_computer_use_tool_policy.dart';
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
  static const existingHelperProbeReportPath = String.fromEnvironment(
    'CAVERNO_MACOS_COMPUTER_USE_EXISTING_HELPER_REPORT_PATH',
    defaultValue: '/tmp/caverno-macos-computer-use-existing-helper-probe.json',
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

  Future<String> terminateHelperForXpcLaunchAgent() async {
    return _invokeTransportJson(
      _permissionTransport.terminateHelperForXpcLaunchAgent,
    );
  }

  Future<String> registerXpcLaunchAgent() async {
    return _invokeTransportJson(_permissionTransport.registerXpcLaunchAgent);
  }

  Future<String> unregisterXpcLaunchAgent() async {
    return _invokeTransportJson(_permissionTransport.unregisterXpcLaunchAgent);
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
                () => _permissionTransport.showPermissionOverlay(
                  permission: 'accessibility',
                ),
              ),
            ) ??
            const <String, dynamic>{};
      }
      if (screenCapture) {
        responses['screenCapture'] =
            _decodeMap(
              await _invokeTransportJson(
                () => _permissionTransport.showPermissionOverlay(
                  permission: 'screenRecording',
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

  Future<String> showPermissionOverlay({required String permission}) async {
    return _invokeTransportJson(
      () => _permissionTransport.showPermissionOverlay(permission: permission),
    );
  }

  Future<String> startOnboardingPermissionFlow({
    required String permission,
  }) async {
    return _invokeTransportJson(
      () => _permissionTransport.startOnboardingPermissionFlow(
        permission: permission,
      ),
    );
  }

  Future<String> stopHelperWork() async {
    return _invokeTransportJson(_permissionTransport.stopAll);
  }

  Future<String> getLastLiveSmokeReport() async {
    return _readJsonReport(
      path: liveSmokeReportPath,
      unsupportedError:
          'macOS computer use live smoke reports are only available on macOS.',
      missingCode: 'live_smoke_report_missing',
      missingError:
          'No macOS computer use live smoke report has been written yet.',
      invalidCode: 'live_smoke_report_invalid',
      invalidError:
          'The macOS computer use live smoke report is not a JSON object.',
      readFailedCode: 'live_smoke_report_read_failed',
    );
  }

  Future<String> getLastExistingHelperProbeReport() async {
    return _readJsonReport(
      path: existingHelperProbeReportPath,
      unsupportedError:
          'macOS computer use existing-helper probe reports are only available on macOS.',
      missingCode: 'existing_helper_probe_report_missing',
      missingError:
          'No macOS computer use existing-helper probe report has been written yet.',
      invalidCode: 'existing_helper_probe_report_invalid',
      invalidError:
          'The macOS computer use existing-helper probe report is not a JSON object.',
      readFailedCode: 'existing_helper_probe_report_read_failed',
    );
  }

  Future<String> _readJsonReport({
    required String path,
    required String unsupportedError,
    required String missingCode,
    required String missingError,
    required String invalidCode,
    required String invalidError,
    required String readFailedCode,
  }) async {
    if (!Platform.isMacOS) {
      return jsonEncode({
        'ok': false,
        'code': 'unsupported_platform',
        'error': unsupportedError,
        'path': path,
      });
    }

    final file = File(path);
    try {
      if (!await file.exists()) {
        return jsonEncode({
          'ok': false,
          'code': missingCode,
          'error': missingError,
          'path': path,
        });
      }

      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return jsonEncode({
          'ok': true,
          'path': path,
          'report': Map<String, dynamic>.from(decoded),
        });
      }
      return jsonEncode({
        'ok': false,
        'code': invalidCode,
        'error': invalidError,
        'path': path,
      });
    } catch (error) {
      return jsonEncode({
        'ok': false,
        'code': readFailedCode,
        'error': error.toString(),
        'path': path,
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

  Future<String> visionObserve(Map<String, dynamic> arguments) async {
    final target = _stringValue(arguments['target']).isNotEmpty
        ? _stringValue(arguments['target'])
        : arguments['window_id'] != null || arguments['windowId'] != null
        ? 'window'
        : 'display';
    final includeWindows =
        arguments['include_windows'] != false &&
        arguments['includeWindows'] != false;
    final maxWidth = _intValue(
      arguments['max_width'] ?? arguments['maxWidth'],
    )?.clamp(200, 1600);
    final requestedWindowId = _intValue(
      arguments['window_id'] ?? arguments['windowId'],
    );
    final requestedDisplayId = _intValue(
      arguments['display_id'] ?? arguments['displayId'],
    );

    final permissions = _decodeMap(await getPermissions());
    Map<String, dynamic>? windowsResult;
    if (includeWindows || target == 'front_window') {
      windowsResult = _decodeMap(
        await listWindows({
          'include_current_app': false,
          'max_windows': _intValue(arguments['max_windows']) ?? 20,
        }),
      );
    }

    final resolvedWindowId = target == 'front_window'
        ? _firstWindowId(windowsResult)
        : requestedWindowId;
    final captureArguments = <String, dynamic>{};
    if (maxWidth != null) {
      captureArguments['max_width'] = maxWidth;
    }
    if (requestedDisplayId != null) {
      captureArguments['display_id'] = requestedDisplayId;
    }

    final captureTarget = switch (target) {
      'window' || 'front_window' when resolvedWindowId != null => 'window',
      _ => 'display',
    };
    if (captureTarget == 'window') {
      captureArguments['window_id'] = resolvedWindowId;
    }

    final captureRaw = captureTarget == 'window'
        ? await screenshotWindow(captureArguments)
        : await screenshot(captureArguments);
    final capture =
        _decodeMap(captureRaw) ??
        {
          'ok': false,
          'code': 'invalid_capture_response',
          'error':
              'Computer vision observation did not receive JSON capture data.',
          'raw': captureRaw,
        };
    final captureOk = capture['ok'] != false;
    final imageBase64 = capture['imageBase64'];
    final imageMimeType = capture['imageMimeType'] as String? ?? 'image/png';
    final captureMetadata = Map<String, dynamic>.from(capture)
      ..remove('imageBase64');

    final targetSummary = <String, dynamic>{
      'requested': target,
      'resolved': captureTarget,
    };
    if (resolvedWindowId != null) {
      targetSummary['windowId'] = resolvedWindowId;
    }
    if (requestedDisplayId != null) {
      targetSummary['displayId'] = requestedDisplayId;
    }

    final result = <String, dynamic>{
      'ok': captureOk && imageBase64 is String && imageBase64.isNotEmpty,
      'schemaName': 'macos_computer_use_vision_observation',
      'schemaVersion': 1,
      'target': targetSummary,
      'coordinateSpace': capture['coordinateSpace'] ?? 'screenshot_pixels',
      'coordinateGuidance': {
        'useLatestObservation': true,
        'includeSourceSize': true,
        'sourceWidth': capture['width'],
        'sourceHeight': capture['height'],
        'windowId': capture['windowId'] ?? resolvedWindowId,
        'displayId': capture['displayId'] ?? requestedDisplayId,
      },
      'permissions': permissions ?? const <String, dynamic>{},
      if (windowsResult != null)
        'windows': _redactedWindowsResult(windowsResult),
      'observation': captureMetadata,
      if (imageBase64 is String && imageBase64.isNotEmpty)
        'imageBase64': imageBase64,
      'imageMimeType': imageMimeType,
      'allowedNextTools': _visionAllowedNextTools,
      'approvalRequiredTools': _visionApprovalRequiredTools,
      'armingRequiredTools': _visionArmingRequiredTools,
      'nextAction': _visionNextAction(
        captureOk: captureOk,
        imageAttached: imageBase64 is String && imageBase64.isNotEmpty,
        capture: capture,
      ),
    };

    if (result['ok'] != true) {
      result['code'] = capture['code'] ?? 'vision_observation_failed';
      result['error'] =
          capture['error'] ?? 'Computer vision observation failed.';
    }
    return jsonEncode(result);
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

  String _stringValue(Object? value) {
    return value is String ? value.trim() : '';
  }

  int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  int? _firstWindowId(Map<String, dynamic>? windowsResult) {
    final windows = windowsResult?['windows'];
    if (windows is! List) return null;
    for (final window in windows) {
      if (window is! Map) continue;
      final id = _intValue(window['windowId'] ?? window['window_id']);
      if (id != null) return id;
    }
    return null;
  }

  Map<String, dynamic> _redactedWindowsResult(Map<String, dynamic> result) {
    final redacted = Map<String, dynamic>.from(result);
    final windows = redacted['windows'];
    if (windows is List) {
      redacted['windows'] = windows
          .whereType<Map>()
          .map((window) => Map<String, dynamic>.from(window))
          .toList(growable: false);
    }
    return redacted;
  }

  String _visionNextAction({
    required bool captureOk,
    required bool imageAttached,
    required Map<String, dynamic> capture,
  }) {
    final captureNextAction = capture['nextAction'];
    if (!captureOk || !imageAttached) {
      if (captureNextAction is String && captureNextAction.isNotEmpty) {
        return captureNextAction;
      }
      return 'Resolve the observation failure, then run computer_vision_observe again.';
    }
    return 'Use the attached screenshot to decide whether to answer, observe again, or request an approved computer-use action.';
  }

  static final List<String> _visionAllowedNextTools = List.unmodifiable([
    'computer_vision_observe',
    'computer_list_windows',
    'computer_screenshot',
    'computer_screenshot_window',
    'computer_focus_window',
    'computer_move_mouse',
    'computer_click',
    'computer_drag',
    'computer_scroll',
    'computer_type_text',
    'computer_press_key',
    'computer_start_system_audio_recording',
    'computer_stop_system_audio_recording',
  ]);

  static final List<String> _visionApprovalRequiredTools = List.unmodifiable(
    _visionAllowedNextTools.where(
      MacosComputerUseToolPolicy.requiresUserApproval,
    ),
  );

  static final List<String> _visionArmingRequiredTools = List.unmodifiable(
    _visionAllowedNextTools.where(
      MacosComputerUseToolPolicy.requiresSmokeArming,
    ),
  );

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
