import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _strict = bool.fromEnvironment('CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT');
const _unsafeArmed = bool.fromEnvironment(
  'CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_ARMED',
);
const _unsafeClickArmed = bool.fromEnvironment(
  'CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_CLICK_ARMED',
);
const _unsafeTextArmed = bool.fromEnvironment(
  'CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_TEXT_ARMED',
);
const _reportPath = String.fromEnvironment(
  'CAVERNO_MACOS_COMPUTER_USE_SMOKE_REPORT_PATH',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('runs the macOS computer-use helper smoke sequence', (
    tester,
  ) async {
    final service = MacosComputerUseService();
    final report = <String, dynamic>{
      'schemaName': 'macos_computer_use_live_smoke',
      'schemaVersion': 1,
      'generatedAt': DateTime.now().toIso8601String(),
      'strict': _strict,
      'unsafeArmed': _unsafeArmed,
      'unsafeClickArmed': _unsafeClickArmed,
      'unsafeTextArmed': _unsafeTextArmed,
      'unsafeSafety': {
        'inputClickRequiresExtraArm': true,
        'inputTextRequiresExtraArm': true,
        'audioMaxDurationMs': 250,
        'audioStopAlwaysAttempted': true,
      },
      'platform': Platform.operatingSystem,
      'steps': <Map<String, dynamic>>[],
    };
    final steps = report['steps'] as List<Map<String, dynamic>>;

    if (!service.isAvailable) {
      report['ok'] = !_strict;
      report['skipped'] = true;
      report['reason'] = 'macOS computer use smoke checks require macOS.';
      _printReport(report);
      if (_strict) {
        fail(report['reason'] as String);
      }
      return;
    }

    final helperStatus = await _runStep(
      steps,
      'helper_status',
      'Read bundled helper status',
      service.getHelperStatus,
    );
    final launch = await _runStep(
      steps,
      'launch_helper',
      'Launch Caverno Computer Use',
      service.launchHelper,
    );
    await tester.pump(const Duration(milliseconds: 500));
    final restart = await _runStep(
      steps,
      'restart_helper',
      'Restart Caverno Computer Use',
      service.restartHelper,
    );
    await tester.pump(const Duration(milliseconds: 800));
    final readiness = await _runStep(
      steps,
      'wait_helper_ipc_ready',
      'Wait for helper IPC readiness',
      () => service.waitForHelperIpcReady(
        attempts: 4,
        delay: const Duration(milliseconds: 500),
      ),
    );
    final ping = await _runStep(
      steps,
      'ping_helper',
      'Ping Caverno Computer Use',
      service.pingHelper,
    );
    final permissions = await _runStep(
      steps,
      'permission_status',
      'Read helper-owned permission status',
      service.getPermissions,
    );
    final displayScreenshot = await _runStep(
      steps,
      'display_screenshot',
      'Capture a display screenshot',
      () => service.screenshot(const {'max_width': 400}),
    );
    final windows = await _runStep(
      steps,
      'list_windows',
      'List visible windows',
      () => service.listWindows(const {
        'max_windows': 20,
        'include_current_app': false,
      }),
    );
    final firstWindowId = _firstWindowId(windows);
    if (firstWindowId == null) {
      steps.add({
        'id': 'window_capture',
        'label': 'Capture the first visible window',
        'ok': false,
        'skipped': true,
        'detail': 'No visible windows were returned.',
      });
    } else {
      await _runStep(
        steps,
        'window_capture',
        'Capture the first visible window',
        () => service.screenshotWindow({
          'window_id': firstWindowId,
          'max_width': 400,
        }),
      );
    }
    if (_unsafeArmed && permissions?['accessibilityGranted'] == true) {
      final inputArguments = _smokeInputArguments(displayScreenshot);
      await _runStep(
        steps,
        'input_move_pointer',
        'Move pointer after explicit smoke arming',
        () => service.moveMouse(inputArguments),
      );
    } else {
      _skipStep(
        steps,
        'input_move_pointer',
        'Move pointer after explicit smoke arming',
        _unsafeArmed
            ? 'Accessibility permission is not granted.'
            : 'Unsafe smoke actions are not armed.',
      );
    }
    if (_unsafeArmed && permissions?['accessibilityGranted'] == true) {
      await _runStep(
        steps,
        'input_drag_pointer',
        'Drag pointer after explicit smoke arming',
        () => service.drag(_smokeDragArguments(displayScreenshot)),
      );
    } else {
      _skipStep(
        steps,
        'input_drag_pointer',
        'Drag pointer after explicit smoke arming',
        _unsafeArmed
            ? 'Accessibility permission is not granted.'
            : 'Unsafe smoke actions are not armed.',
      );
    }
    if (_unsafeArmed && permissions?['accessibilityGranted'] == true) {
      await _runStep(
        steps,
        'input_scroll',
        'Scroll after explicit smoke arming',
        () => service.scroll({
          ..._smokeInputArguments(displayScreenshot),
          'delta_x': 0,
          'delta_y': 0,
        }),
      );
    } else {
      _skipStep(
        steps,
        'input_scroll',
        'Scroll after explicit smoke arming',
        _unsafeArmed
            ? 'Accessibility permission is not granted.'
            : 'Unsafe smoke actions are not armed.',
      );
    }
    if (_unsafeArmed && permissions?['accessibilityGranted'] == true) {
      await _runStep(
        steps,
        'input_press_key',
        'Press Escape after explicit smoke arming',
        () => service.pressKey({
          'key': 'escape',
          'reason':
              'Live smoke was explicitly armed for key input verification.',
        }),
      );
    } else {
      _skipStep(
        steps,
        'input_press_key',
        'Press Escape after explicit smoke arming',
        _unsafeArmed
            ? 'Accessibility permission is not granted.'
            : 'Unsafe smoke actions are not armed.',
      );
    }
    if (_unsafeArmed &&
        _unsafeTextArmed &&
        permissions?['accessibilityGranted'] == true) {
      await _runStep(
        steps,
        'input_type_text',
        'Type text after explicit text smoke arming',
        () => service.typeText({
          'text': 'caverno-smoke',
          'reason':
              'Live smoke was explicitly armed for text input verification.',
        }),
      );
    } else {
      _skipStep(
        steps,
        'input_type_text',
        'Type text after explicit text smoke arming',
        !_unsafeTextArmed
            ? 'Text smoke actions require unsafe text arming.'
            : _unsafeArmed
            ? 'Accessibility permission is not granted.'
            : 'Unsafe smoke actions are not armed.',
      );
    }
    if (_unsafeArmed &&
        _unsafeClickArmed &&
        permissions?['accessibilityGranted'] == true &&
        permissions?['screenCaptureGranted'] == true) {
      await _runStep(
        steps,
        'input_click',
        'Click once after explicit click smoke arming',
        () => service.click({
          ..._smokeInputArguments(displayScreenshot),
          'button': 'left',
          'click_count': 1,
        }),
      );
    } else {
      _skipStep(
        steps,
        'input_click',
        'Click once after explicit click smoke arming',
        _unsafeClickArmed
            ? 'Accessibility or Screen Recording permission is not granted.'
            : 'Click smoke actions require unsafe click arming.',
      );
    }
    if (_unsafeArmed &&
        permissions?['screenCaptureGranted'] == true &&
        permissions?['systemAudioRecordingSupported'] == true) {
      await _runStep(
        steps,
        'system_audio_recording',
        'Start and stop system audio after explicit smoke arming',
        () => _startAndStopSystemAudio(service),
      );
    } else {
      _skipStep(
        steps,
        'system_audio_recording',
        'Start and stop system audio after explicit smoke arming',
        _unsafeArmed
            ? 'Screen & System Audio Recording permission is not granted or audio is unsupported.'
            : 'Unsafe smoke actions are not armed.',
      );
    }
    final stop = await _runStep(
      steps,
      'stop_helper_work',
      'Stop helper work',
      service.stopHelperWork,
    );

    final coreOk =
        _stepPassed(helperStatus) &&
        _stepPassed(launch) &&
        _stepPassed(restart) &&
        _stepPassed(readiness) &&
        _stepPassed(ping) &&
        _stepPassed(permissions) &&
        _stepPassed(stop);
    final captureOk =
        _stepPassed(displayScreenshot) &&
        _stepPassed(windows) &&
        steps.any(
          (step) => step['id'] == 'window_capture' && step['ok'] == true,
        );
    report['ok'] = _strict ? coreOk && captureOk : coreOk;
    report['coreOk'] = coreOk;
    report['captureOk'] = captureOk;
    report['restartOk'] = _stepPassed(restart);
    report['ipcReadyOk'] = _stepPassed(readiness);
    report['permissionSummary'] = {
      'accessibilityGranted': permissions?['accessibilityGranted'],
      'screenCaptureGranted': permissions?['screenCaptureGranted'],
      'systemAudioRecordingSupported':
          permissions?['systemAudioRecordingSupported'],
    };
    report['permissionGate'] = {
      'captureExpected': permissions?['screenCaptureGranted'] == true,
      'inputExpected': permissions?['accessibilityGranted'] == true,
      'audioExpected':
          permissions?['screenCaptureGranted'] == true &&
          permissions?['systemAudioRecordingSupported'] == true,
      'blockedByPermissions': [
        if (permissions?['screenCaptureGranted'] != true) 'screen_capture',
        if (permissions?['accessibilityGranted'] != true) 'accessibility',
      ],
    };
    report['xpcProductionGate'] = _xpcProductionGate(steps);
    report['unsafeOperationSummary'] = _unsafeOperationSummary(steps);
    final positiveSmokeGates = _positiveSmokeGates(
      steps,
      permissions: permissions,
      unsafeArmed: _unsafeArmed,
    );
    final requiredPositiveSmokeOk = positiveSmokeGates
        .where((gate) => gate['required'] == true)
        .every((gate) => gate['passed'] == true);
    report['positiveSmokeGates'] = positiveSmokeGates;
    report['requiredPositiveSmokeOk'] = requiredPositiveSmokeOk;
    if (_strict && !requiredPositiveSmokeOk) {
      report['ok'] = false;
    }
    _printReport(report);

    if (_strict) {
      expect(coreOk, isTrue, reason: 'Core helper smoke steps must pass.');
      expect(captureOk, isTrue, reason: 'Capture smoke steps must pass.');
      expect(
        requiredPositiveSmokeOk,
        isTrue,
        reason: 'Required positive smoke gates must pass.',
      );
    }
  });
}

Map<String, dynamic> _xpcProductionGate(List<Map<String, dynamic>> steps) {
  final results = steps
      .map((step) => step['result'])
      .whereType<Map>()
      .map((result) => Map<String, dynamic>.from(result))
      .toList();
  final nextParityCommands = <String>{
    for (final result in results)
      for (final command in _stringList(result['xpcNextParityCommands']))
        command,
  }.toList();
  final preferredStatuses = <String>{
    for (final result in results)
      if (_preferredAttemptStatus(result) != null)
        _preferredAttemptStatus(result)!,
  }.toList();
  final namedServiceConnected = results.any(
    (result) =>
        result['selectedIpcTransport'] == 'xpc_service' &&
        result['ok'] != false,
  );
  final launchAgentStatuses = results
      .map((result) => result['xpcLaunchAgentStatus'])
      .whereType<String>()
      .toList(growable: false);
  final launchAgentStatus = launchAgentStatuses.isEmpty
      ? null
      : launchAgentStatuses.last;
  final launchAgentEnabled = results.any(
    (result) =>
        result['xpcLaunchAgentEnabled'] == true ||
        result['xpcLaunchAgentRegistered'] == true ||
        result['xpcLaunchAgentStatus'] == 'enabled',
  );
  final launchAgentPlistInstalled = results.any(
    (result) => result['xpcLaunchAgentPlistInstalled'] == true,
  );
  final fallbackObservable = results.any(
    (result) =>
        result['preferredIpcTransport'] == 'xpc_service' &&
        result['selectedIpcTransport'] == 'distributed_notification_center' &&
        _preferredAttemptStatus(result)?.startsWith('xpc_') == true,
  );
  final blockers = [
    if (!launchAgentPlistInstalled) 'launch_agent_plist_missing',
    if (!launchAgentEnabled) 'launchd_mach_service_registration_missing',
    if (!namedServiceConnected) 'named_xpc_service_not_connected',
    if (nextParityCommands.isNotEmpty) 'command_parity_pending',
  ];
  final productionReady = blockers.isEmpty;
  final gate = <String, dynamic>{
    'productionReady': productionReady,
    'namedServiceConnected': namedServiceConnected,
    'launchAgentPlistInstalled': launchAgentPlistInstalled,
    'launchAgentEnabled': launchAgentEnabled,
    'commandParityComplete': nextParityCommands.isEmpty,
    'fallbackObservable': fallbackObservable,
    'nextParityCommands': nextParityCommands,
    'preferredAttemptStatuses': preferredStatuses,
    'blockers': blockers,
    'nextAction': productionReady
        ? 'XPC is production ready.'
        : 'Resolve XPC production blockers before marking production ready.',
  };
  if (launchAgentStatus != null) {
    gate['launchAgentStatus'] = launchAgentStatus;
  }
  return gate;
}

String? _preferredAttemptStatus(Map<String, dynamic> result) {
  final status = _preferredAttempt(result)?['status'];
  return status is String && status.isNotEmpty ? status : null;
}

Map<String, dynamic>? _preferredAttempt(Map<String, dynamic> result) {
  final attempt = result['preferredIpcAttempt'];
  if (attempt is Map) {
    return Map<String, dynamic>.from(attempt);
  }
  return null;
}

Future<Map<String, dynamic>?> _runStep(
  List<Map<String, dynamic>> steps,
  String id,
  String label,
  Future<String> Function() invoke,
) async {
  final startedAt = DateTime.now();
  try {
    final raw = await invoke();
    final decoded = _decodeMap(raw);
    final ok = decoded != null && _responseLooksSuccessful(decoded);
    final step = <String, dynamic>{
      'id': id,
      'label': label,
      'ok': ok,
      'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
      'result': _compactReportValue(decoded ?? raw),
    };
    steps.add(step);
    return decoded;
  } catch (error) {
    steps.add({
      'id': id,
      'label': label,
      'ok': false,
      'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
      'error': error.toString(),
    });
    return null;
  }
}

void _skipStep(
  List<Map<String, dynamic>> steps,
  String id,
  String label,
  String reason,
) {
  steps.add({
    'id': id,
    'label': label,
    'ok': true,
    'skipped': true,
    'reason': reason,
  });
}

Map<String, dynamic> _unsafeOperationSummary(List<Map<String, dynamic>> steps) {
  final operations = [
    _unsafeOperation(
      steps,
      id: 'input_move_pointer',
      category: 'input',
      requiresArming: 'unsafe',
    ),
    _unsafeOperation(
      steps,
      id: 'input_click',
      category: 'input',
      requiresArming: 'unsafe_click',
    ),
    _unsafeOperation(
      steps,
      id: 'input_drag_pointer',
      category: 'input',
      requiresArming: 'unsafe',
    ),
    _unsafeOperation(
      steps,
      id: 'input_scroll',
      category: 'input',
      requiresArming: 'unsafe',
    ),
    _unsafeOperation(
      steps,
      id: 'input_press_key',
      category: 'input',
      requiresArming: 'unsafe',
    ),
    _unsafeOperation(
      steps,
      id: 'input_type_text',
      category: 'input',
      requiresArming: 'unsafe_text',
    ),
    _unsafeOperation(
      steps,
      id: 'system_audio_recording',
      category: 'audio',
      requiresArming: 'unsafe',
    ),
  ];
  return {
    'executedCount': operations
        .where((operation) => operation['executed'] == true)
        .length,
    'skippedCount': operations
        .where((operation) => operation['skipped'] == true)
        .length,
    'failedCount': operations
        .where(
          (operation) =>
              operation['executed'] == true && operation['passed'] != true,
        )
        .length,
    'operations': operations,
  };
}

Map<String, dynamic> _unsafeOperation(
  List<Map<String, dynamic>> steps, {
  required String id,
  required String category,
  required String requiresArming,
}) {
  final step = steps.cast<Map<String, dynamic>?>().firstWhere(
    (step) => step?['id'] == id,
    orElse: () => null,
  );
  final skipped = step?['skipped'] == true;
  return {
    'id': id,
    'category': category,
    'requiresArming': requiresArming,
    'executed': step != null && !skipped,
    'skipped': skipped,
    'passed': step?['ok'] == true && !skipped,
    if (step?['reason'] != null) 'reason': step?['reason'],
    if (step?['error'] != null) 'error': step?['error'],
  };
}

Future<String> _startAndStopSystemAudio(MacosComputerUseService service) async {
  Map<String, dynamic>? start;
  Object? startError;
  Map<String, dynamic>? stop;
  Object? stopError;
  var started = false;
  var stopAttempted = false;

  try {
    final startRaw = await service.startSystemAudioRecording({
      'exclude_current_process_audio': true,
      'reason':
          'Live smoke was explicitly armed for system audio verification.',
    });
    start = _decodeMap(startRaw);
    started = start?['ok'] == true;
    if (started) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  } catch (error) {
    startError = error;
  } finally {
    try {
      stopAttempted = true;
      final stopRaw = await service.stopSystemAudioRecording();
      stop = _decodeMap(stopRaw) ?? {'raw': stopRaw};
    } catch (error) {
      stopError = error;
    }
  }

  return jsonEncode({
    'ok': started && stop?['ok'] == true,
    'start': start,
    if (startError != null) 'startError': startError.toString(),
    'stop': stop,
    if (stopError != null) 'stopError': stopError.toString(),
    'stopAttempted': stopAttempted,
  });
}

Map<String, dynamic> _smokeInputArguments(Map<String, dynamic>? screenshot) {
  final sourceWidth = _intValue(screenshot?['width']);
  final sourceHeight = _intValue(screenshot?['height']);
  final x = sourceWidth == null ? 8.0 : (sourceWidth * 0.05).clamp(8, 48);
  final y = sourceHeight == null ? 8.0 : (sourceHeight * 0.05).clamp(8, 48);
  final arguments = <String, dynamic>{
    'x': x.toDouble(),
    'y': y.toDouble(),
    'reason': 'Live smoke was explicitly armed for input verification.',
  };
  if (sourceWidth != null) {
    arguments['source_width'] = sourceWidth;
  }
  if (sourceHeight != null) {
    arguments['source_height'] = sourceHeight;
  }
  return arguments;
}

Map<String, dynamic> _smokeDragArguments(Map<String, dynamic>? screenshot) {
  final sourceWidth = _intValue(screenshot?['width']);
  final sourceHeight = _intValue(screenshot?['height']);
  final fromX = sourceWidth == null ? 8.0 : (sourceWidth * 0.05).clamp(8, 48);
  final fromY = sourceHeight == null ? 8.0 : (sourceHeight * 0.05).clamp(8, 48);
  final toX = sourceWidth == null
      ? fromX + 1
      : (fromX + sourceWidth * 0.01).clamp(fromX + 1, sourceWidth - 1);
  final toY = sourceHeight == null
      ? fromY + 1
      : (fromY + sourceHeight * 0.01).clamp(fromY + 1, sourceHeight - 1);
  final arguments = <String, dynamic>{
    'from_x': fromX.toDouble(),
    'from_y': fromY.toDouble(),
    'to_x': toX.toDouble(),
    'to_y': toY.toDouble(),
    'duration_ms': 50,
    'reason': 'Live smoke was explicitly armed for input drag verification.',
  };
  if (sourceWidth != null) {
    arguments['source_width'] = sourceWidth;
  }
  if (sourceHeight != null) {
    arguments['source_height'] = sourceHeight;
  }
  return arguments;
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

bool _responseLooksSuccessful(Map<String, dynamic> response) {
  if (response['ok'] == false || response['code'] != null) {
    return false;
  }
  if (response['helperReachable'] == false) {
    return false;
  }
  if (response.containsKey('imageBase64')) {
    return response['imageBase64'] is String &&
        (response['imageBase64'] as String).isNotEmpty;
  }
  if (response.containsKey('windows')) {
    return response['windows'] is List;
  }
  return true;
}

bool _stepPassed(Map<String, dynamic>? response) {
  return response != null && _responseLooksSuccessful(response);
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value
      .map((item) => '$item')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<Map<String, dynamic>> _positiveSmokeGates(
  List<Map<String, dynamic>> steps, {
  required Map<String, dynamic>? permissions,
  required bool unsafeArmed,
}) {
  final screenGranted = permissions?['screenCaptureGranted'] == true;
  final accessibilityGranted = permissions?['accessibilityGranted'] == true;
  final audioSupported = permissions?['systemAudioRecordingSupported'] == true;
  return [
    _positiveSmokeGate(
      steps,
      id: 'display_screenshot',
      label: 'Display screenshot',
      required: screenGranted,
      blockedBy: screenGranted ? null : 'screen_capture',
    ),
    _positiveSmokeGate(
      steps,
      id: 'window_capture',
      label: 'Window screenshot',
      required: screenGranted,
      blockedBy: screenGranted ? null : 'screen_capture',
    ),
    _positiveSmokeGate(
      steps,
      id: 'input_move_pointer',
      label: 'Armed pointer movement',
      required: unsafeArmed && accessibilityGranted,
      blockedBy: unsafeArmed
          ? accessibilityGranted
                ? null
                : 'accessibility'
          : 'unsafe_smoke_not_armed',
    ),
    _positiveSmokeGate(
      steps,
      id: 'input_click',
      label: 'Armed pointer click',
      required:
          unsafeArmed &&
          _unsafeClickArmed &&
          accessibilityGranted &&
          screenGranted,
      blockedBy: unsafeArmed && _unsafeClickArmed
          ? accessibilityGranted && screenGranted
                ? null
                : 'accessibility_or_screen_capture'
          : 'unsafe_click_smoke_not_armed',
    ),
    _positiveSmokeGate(
      steps,
      id: 'input_drag_pointer',
      label: 'Armed pointer drag',
      required: unsafeArmed && accessibilityGranted,
      blockedBy: unsafeArmed
          ? accessibilityGranted
                ? null
                : 'accessibility'
          : 'unsafe_smoke_not_armed',
    ),
    _positiveSmokeGate(
      steps,
      id: 'input_scroll',
      label: 'Armed pointer scroll',
      required: unsafeArmed && accessibilityGranted,
      blockedBy: unsafeArmed
          ? accessibilityGranted
                ? null
                : 'accessibility'
          : 'unsafe_smoke_not_armed',
    ),
    _positiveSmokeGate(
      steps,
      id: 'input_press_key',
      label: 'Armed key press',
      required: unsafeArmed && accessibilityGranted,
      blockedBy: unsafeArmed
          ? accessibilityGranted
                ? null
                : 'accessibility'
          : 'unsafe_smoke_not_armed',
    ),
    _positiveSmokeGate(
      steps,
      id: 'input_type_text',
      label: 'Armed text input',
      required: unsafeArmed && _unsafeTextArmed && accessibilityGranted,
      blockedBy: unsafeArmed && _unsafeTextArmed
          ? accessibilityGranted
                ? null
                : 'accessibility'
          : _unsafeTextArmed
          ? 'unsafe_smoke_not_armed'
          : 'unsafe_text_smoke_not_armed',
    ),
    _positiveSmokeGate(
      steps,
      id: 'system_audio_recording',
      label: 'Armed system audio recording',
      required: unsafeArmed && screenGranted && audioSupported,
      blockedBy: unsafeArmed
          ? screenGranted && audioSupported
                ? null
                : 'screen_capture_or_audio_support'
          : 'unsafe_smoke_not_armed',
    ),
  ];
}

Map<String, dynamic> _positiveSmokeGate(
  List<Map<String, dynamic>> steps, {
  required String id,
  required String label,
  required bool required,
  required String? blockedBy,
}) {
  final step = steps.cast<Map<String, dynamic>?>().firstWhere(
    (step) => step?['id'] == id,
    orElse: () => null,
  );
  final passed = step?['ok'] == true && step?['skipped'] != true;
  final gate = <String, dynamic>{
    'id': id,
    'label': label,
    'required': required,
    'passed': passed,
    'skipped': step?['skipped'] == true,
    if (step?['reason'] != null) 'reason': step?['reason'],
  };
  if (blockedBy != null) {
    gate['blockedBy'] = blockedBy;
  }
  return gate;
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

int? _firstWindowId(Map<String, dynamic>? response) {
  final windows = response?['windows'];
  if (windows is! List || windows.isEmpty) {
    return null;
  }
  for (final window in windows) {
    if (window is! Map) {
      continue;
    }
    final id = window['windowId'] ?? window['window_id'];
    if (id is int) {
      return id;
    }
    if (id is num) {
      return id.toInt();
    }
  }
  return null;
}

void _printReport(Map<String, dynamic> report) {
  const encoder = JsonEncoder.withIndent('  ');
  if (_reportPath.isNotEmpty) {
    report['reportPath'] = _reportPath;
  }
  final encoded = encoder.convert(_compactReportValue(report));
  if (_reportPath.isNotEmpty) {
    final file = File(_reportPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encoded);
  }
  // The marker makes it easy to extract the report from compact test logs.
  // ignore: avoid_print
  print('CAVERNO_MACOS_COMPUTER_USE_SMOKE_JSON=$encoded');
}

Object? _compactReportValue(Object? value) {
  if (value is Map) {
    final compacted = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      if (key == 'imageBase64' && entry.value is String) {
        final imageBase64 = entry.value as String;
        compacted['imageBase64Omitted'] = true;
        compacted['imageBase64Length'] = imageBase64.length;
        continue;
      }
      compacted[key] = _compactReportValue(entry.value);
    }
    return compacted;
  }
  if (value is List) {
    return value.map(_compactReportValue).toList(growable: false);
  }
  return value;
}
