import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _strict = bool.fromEnvironment('CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT');
const _strictXpc = bool.fromEnvironment(
  'CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT_XPC',
);
const _unsafeArmed = bool.fromEnvironment(
  'CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_ARMED',
);
const _unsafeClickArmed = bool.fromEnvironment(
  'CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_CLICK_ARMED',
);
const _unsafeTextArmed = bool.fromEnvironment(
  'CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_TEXT_ARMED',
);
const _requireCaptureReady = bool.fromEnvironment(
  'CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_CAPTURE_READY',
);
const _requireInputReady = bool.fromEnvironment(
  'CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_INPUT_READY',
);
const _requireAudioResolved = bool.fromEnvironment(
  'CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_AUDIO_RESOLVED',
);
const _runOverlaySmoke = bool.fromEnvironment(
  'CAVERNO_MACOS_COMPUTER_USE_SMOKE_RUN_OVERLAY',
);
const _requireOverlayReady = bool.fromEnvironment(
  'CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_OVERLAY_READY',
);
const _registerXpcAgent = bool.fromEnvironment(
  'CAVERNO_MACOS_COMPUTER_USE_SMOKE_REGISTER_XPC_AGENT',
);
const _cleanupXpcAgent = bool.fromEnvironment(
  'CAVERNO_MACOS_COMPUTER_USE_SMOKE_CLEANUP_XPC_AGENT',
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
      'strictXpc': _strictXpc,
      'unsafeArmed': _unsafeArmed,
      'unsafeClickArmed': _unsafeClickArmed,
      'unsafeTextArmed': _unsafeTextArmed,
      'requireCaptureReady': _requireCaptureReady,
      'requireInputReady': _requireInputReady,
      'requireAudioResolved': _requireAudioResolved,
      'runOverlaySmoke': _runOverlaySmoke,
      'requireOverlayReady': _requireOverlayReady,
      'registerXpcAgent': _registerXpcAgent,
      'cleanupXpcAgent': _cleanupXpcAgent,
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
    Map<String, dynamic>? xpcAgentRegistration;
    if (_registerXpcAgent) {
      xpcAgentRegistration = await _runStep(
        steps,
        'register_xpc_launch_agent',
        'Register the XPC LaunchAgent',
        service.registerXpcLaunchAgent,
      );
      await tester.pump(const Duration(milliseconds: 800));
    } else {
      _skipStep(
        steps,
        'register_xpc_launch_agent',
        'Register the XPC LaunchAgent',
        'XPC LaunchAgent registration is opt-in for live smoke.',
      );
    }
    Map<String, dynamic>? xpcAgentLaunchReset;
    if (_strictXpc && _registerXpcAgent) {
      xpcAgentLaunchReset = await _runStep(
        steps,
        'terminate_helper_for_xpc_launch_agent',
        'Terminate helper before LaunchAgent XPC probe',
        service.terminateHelperForXpcLaunchAgent,
      );
      await tester.pump(const Duration(milliseconds: 800));
    } else {
      _skipStep(
        steps,
        'terminate_helper_for_xpc_launch_agent',
        'Terminate helper before LaunchAgent XPC probe',
        'Strict XPC smoke is not enabled.',
      );
    }
    Map<String, dynamic>? launch;
    if (_strictXpc && _registerXpcAgent) {
      _skipStep(
        steps,
        'launch_helper',
        'Launch Caverno Computer Use',
        'LaunchAgent owns helper startup for strict XPC smoke.',
      );
    } else {
      launch = await _runStep(
        steps,
        'launch_helper',
        'Launch Caverno Computer Use',
        service.launchHelper,
      );
      await tester.pump(const Duration(milliseconds: 500));
    }
    Map<String, dynamic>? restart;
    if (_strictXpc && _registerXpcAgent) {
      _skipStep(
        steps,
        'restart_helper',
        'Restart Caverno Computer Use',
        'LaunchAgent owns helper startup for strict XPC smoke.',
      );
    } else {
      restart = await _runStep(
        steps,
        'restart_helper',
        'Restart Caverno Computer Use',
        service.restartHelper,
      );
      await tester.pump(const Duration(milliseconds: 800));
    }
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
    Map<String, dynamic>? xpcProductionProbe;
    if (_registerXpcAgent) {
      xpcProductionProbe = await _runStep(
        steps,
        'xpc_production_probe',
        'Probe named XPC after LaunchAgent registration',
        () => _waitForNamedXpc(service),
      );
    } else {
      _skipStep(
        steps,
        'xpc_production_probe',
        'Probe named XPC after LaunchAgent registration',
        'XPC LaunchAgent registration is opt-in for live smoke.',
      );
    }
    final permissions = await _runStep(
      steps,
      'permission_status',
      'Read helper-owned permission status',
      service.getPermissions,
    );
    Map<String, dynamic>? accessibilityOverlay;
    Map<String, dynamic>? screenRecordingOverlay;
    if (_runOverlaySmoke) {
      accessibilityOverlay = await _runStep(
        steps,
        'permission_overlay_accessibility',
        'Show Accessibility permission overlay',
        () => service.showPermissionOverlay(permission: 'accessibility'),
      );
      await tester.pump(const Duration(milliseconds: 300));
      screenRecordingOverlay = await _runStep(
        steps,
        'permission_overlay_screen_recording',
        'Show Screen & System Audio Recording permission overlay',
        () => service.showPermissionOverlay(permission: 'screenRecording'),
      );
      await tester.pump(const Duration(milliseconds: 300));
    } else {
      _skipStep(
        steps,
        'permission_overlay_accessibility',
        'Show Accessibility permission overlay',
        'Overlay smoke is opt-in. Rerun with --overlay-smoke or --require-overlay.',
      );
      _skipStep(
        steps,
        'permission_overlay_screen_recording',
        'Show Screen & System Audio Recording permission overlay',
        'Overlay smoke is opt-in. Rerun with --overlay-smoke or --require-overlay.',
      );
    }
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
    Map<String, dynamic>? xpcAgentCleanup;
    if (_cleanupXpcAgent) {
      xpcAgentCleanup = await _runStep(
        steps,
        'unregister_xpc_launch_agent',
        'Unregister the XPC LaunchAgent',
        service.unregisterXpcLaunchAgent,
      );
    } else {
      _skipStep(
        steps,
        'unregister_xpc_launch_agent',
        'Unregister the XPC LaunchAgent',
        'XPC LaunchAgent cleanup is opt-in for live smoke.',
      );
    }

    final coreOk =
        _stepPassed(helperStatus) &&
        (_strictXpc && _registerXpcAgent ? true : _stepPassed(launch)) &&
        (_strictXpc && _registerXpcAgent ? true : _stepPassed(restart)) &&
        (_strictXpc && _registerXpcAgent
            ? _stepPassed(xpcAgentLaunchReset)
            : true) &&
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
    final xpcProductionGate = _xpcProductionGate(steps);
    final xpcProductionOk =
        xpcProductionGate['productionReady'] == true &&
        (_registerXpcAgent ? _stepPassed(xpcAgentRegistration) : true) &&
        (_registerXpcAgent ? _namedXpcConnected(xpcProductionProbe) : true);
    report['ok'] = _strict ? coreOk && captureOk : coreOk;
    report['coreOk'] = coreOk;
    report['captureOk'] = captureOk;
    report['restartOk'] = _strictXpc && _registerXpcAgent
        ? null
        : _stepPassed(restart);
    report['xpcAgentLaunchResetOk'] = _strictXpc && _registerXpcAgent
        ? _stepPassed(xpcAgentLaunchReset)
        : null;
    report['ipcReadyOk'] = _stepPassed(readiness);
    report['xpcAgentRegistrationOk'] = _registerXpcAgent
        ? _stepPassed(xpcAgentRegistration)
        : null;
    report['xpcProductionProbeOk'] = _registerXpcAgent
        ? _namedXpcConnected(xpcProductionProbe)
        : null;
    report['xpcAgentCleanupOk'] = _cleanupXpcAgent
        ? _stepPassed(xpcAgentCleanup) &&
              _xpcLaunchAgentNotRegistered(xpcAgentCleanup)
        : null;
    report['xpcAgentCleanupVerified'] = _cleanupXpcAgent
        ? _xpcLaunchAgentNotRegistered(xpcAgentCleanup)
        : null;
    report['xpcProductionOk'] = xpcProductionOk;
    report['permissionSummary'] = {
      'accessibilityGranted': permissions?['accessibilityGranted'],
      'screenCaptureGranted': permissions?['screenCaptureGranted'],
      'systemAudioRecordingSupported':
          permissions?['systemAudioRecordingSupported'],
    };
    report['overlaySmoke'] = _overlaySmokeSummary(
      accessibilityOverlay: accessibilityOverlay,
      screenRecordingOverlay: screenRecordingOverlay,
      runOverlaySmoke: _runOverlaySmoke,
    );
    report['permissionGate'] = _permissionGate(permissions);
    report['captureGate'] = _captureGate(steps, permissions: permissions);
    report['inputGate'] = _inputGate(
      steps,
      permissions: permissions,
      unsafeArmed: _unsafeArmed,
    );
    report['audioGate'] = _audioGate(
      steps,
      permissions: permissions,
      unsafeArmed: _unsafeArmed,
    );
    report['unsafeActionGate'] = _unsafeActionGate(
      unsafeArmed: _unsafeArmed,
      unsafeClickArmed: _unsafeClickArmed,
      unsafeTextArmed: _unsafeTextArmed,
    );
    final signingDiagnostics = await _signingDiagnostics(helperStatus);
    report['signingDiagnostics'] = signingDiagnostics;
    report['xpcRuntimeDiagnostics'] = _xpcRuntimeDiagnostics(
      helperStatus: helperStatus,
      steps: steps,
      signingDiagnostics: signingDiagnostics,
      xpcProductionProbe: xpcProductionProbe,
      xpcProductionGate: xpcProductionGate,
    );
    report['xpcProductionGate'] = xpcProductionGate;
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
    report['positiveSmokeGateSummary'] = _positiveSmokeGateSummary(
      positiveSmokeGates,
    );
    report['requiredPositiveSmokeOk'] = requiredPositiveSmokeOk;
    final readinessExpectations = _readinessExpectations(report);
    report['readinessExpectations'] = readinessExpectations;
    if (_strict && !requiredPositiveSmokeOk) {
      report['ok'] = false;
    }
    if (readinessExpectations['ok'] == false) {
      report['ok'] = false;
    }
    if (_strict && _registerXpcAgent && !xpcProductionOk) {
      report['ok'] = false;
    }
    if (_strictXpc) {
      report['ok'] =
          report['ok'] == true &&
          _registerXpcAgent &&
          xpcProductionOk &&
          (!_cleanupXpcAgent || _xpcLaunchAgentNotRegistered(xpcAgentCleanup));
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
      if (_registerXpcAgent) {
        expect(
          xpcProductionOk,
          isTrue,
          reason:
              'Registered LaunchAgent smoke runs must reach production-ready named XPC.',
        );
      }
    }
    if (_requireCaptureReady) {
      expect(
        _gateReady(report['captureGate']),
        isTrue,
        reason:
            'Capture gate must be ready when capture readiness is required.',
      );
    }
    if (_requireInputReady) {
      expect(
        _gateReady(report['inputGate']),
        isTrue,
        reason: 'Input gate must be ready when input readiness is required.',
      );
    }
    if (_requireAudioResolved) {
      expect(
        _audioGateResolved(report['audioGate']),
        isTrue,
        reason:
            'Audio gate must be ready or unsupported when audio resolution is required.',
      );
    }
    if (_requireOverlayReady) {
      expect(
        _gateReady(report['overlaySmoke']),
        isTrue,
        reason:
            'Overlay smoke must show both permission overlays with a draggable helper tile.',
      );
    }
    if (_strictXpc) {
      expect(
        _registerXpcAgent,
        isTrue,
        reason: 'Strict XPC smoke requires LaunchAgent registration.',
      );
      expect(
        xpcProductionOk,
        isTrue,
        reason: 'Strict XPC smoke must reach production-ready named XPC.',
      );
      if (_cleanupXpcAgent) {
        expect(
          _xpcLaunchAgentNotRegistered(xpcAgentCleanup),
          isTrue,
          reason: 'Strict XPC cleanup must leave the LaunchAgent unregistered.',
        );
      }
    }
  });
}

Future<String> _waitForNamedXpc(MacosComputerUseService service) async {
  const maxAttempts = 5;
  const delay = Duration(milliseconds: 750);
  final startedAt = DateTime.now();
  final attempts = <Map<String, dynamic>>[];
  Map<String, dynamic>? lastResponse;
  Object? lastError;

  for (var index = 0; index < maxAttempts; index += 1) {
    try {
      final raw = await service.pingHelper();
      final decoded = _decodeMap(raw);
      lastResponse = decoded ?? {'raw': raw};
      final namedXpcConnected = _namedXpcConnected(decoded);
      attempts.add(_namedXpcAttempt(index + 1, decoded, namedXpcConnected));
      if (namedXpcConnected) {
        return jsonEncode({
          ...decoded!,
          'ok': decoded['ok'] != false,
          'xpcProbeReady': true,
          'xpcProbeAttemptCount': index + 1,
          'xpcProbeAttempts': attempts,
          'waitedMs': DateTime.now().difference(startedAt).inMilliseconds,
        });
      }
    } catch (error) {
      lastError = error;
      attempts.add({
        'attempt': index + 1,
        'ok': false,
        'error': error.toString(),
      });
    }
    if (index < maxAttempts - 1) {
      await Future<void>.delayed(delay);
    }
  }

  return jsonEncode({
    ...?lastResponse,
    'ok': false,
    'code': lastResponse?['code'] ?? 'named_xpc_probe_unavailable',
    'error': lastError?.toString() ?? 'Named XPC did not become ready.',
    'xpcProbeReady': false,
    'xpcProbeAttemptCount': attempts.length,
    'xpcProbeAttempts': attempts,
    'waitedMs': DateTime.now().difference(startedAt).inMilliseconds,
  });
}

Map<String, dynamic> _namedXpcAttempt(
  int attempt,
  Map<String, dynamic>? response,
  bool namedXpcConnected,
) {
  return {
    'attempt': attempt,
    'ok': namedXpcConnected,
    'selectedIpcTransport': response?['selectedIpcTransport'],
    'preferredAttemptStatus': response == null
        ? null
        : _preferredAttemptStatus(response),
    'code': response?['code'],
    'error': response?['error'],
    'helperRunning': response?['helperRunning'],
    'xpcLaunchAgentStatus': response?['xpcLaunchAgentStatus'],
  };
}

Future<Map<String, dynamic>> _signingDiagnostics(
  Map<String, dynamic>? helperStatus,
) async {
  final helperPath = helperStatus?['helperPath'];
  final appPath = helperPath is String
      ? _appPathFromHelperPath(helperPath)
      : null;
  final launchAgentPath = helperStatus?['xpcLaunchAgentPlistPath'];
  final app = await _codesignDiagnostics(appPath, role: 'app');
  final helper = await _codesignDiagnostics(
    helperPath is String ? helperPath : null,
    role: 'helper',
  );
  final blockers = <String>[
    for (final blocker in _stringList(app['launchConstraintBlockers']))
      'app:$blocker',
    for (final blocker in _stringList(helper['launchConstraintBlockers']))
      'helper:$blocker',
  ];
  return {
    'app': app,
    'helper': helper,
    'launchAgent': {
      'path': launchAgentPath,
      'exists': launchAgentPath is String
          ? File(launchAgentPath).existsSync()
          : false,
    },
    'launchConstraintLikelyAccepted': blockers.isEmpty,
    'launchConstraintBlockers': blockers,
  };
}

String? _appPathFromHelperPath(String helperPath) {
  const marker = '/Contents/Helpers/';
  final index = helperPath.indexOf(marker);
  if (index < 0) {
    return null;
  }
  return helperPath.substring(0, index);
}

Future<Map<String, dynamic>> _codesignDiagnostics(
  String? path, {
  required String role,
}) async {
  if (path == null || path.isEmpty) {
    return {
      'role': role,
      'path': path,
      'exists': false,
      'verifyExitCode': null,
      'launchConstraintLikelyAccepted': false,
      'launchConstraintBlockers': ['bundle_missing'],
    };
  }
  final exists =
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  final verify = exists
      ? await _runCommand('/usr/bin/codesign', ['--verify', '--strict', path])
      : null;
  final details = exists
      ? await _runCommand('/usr/bin/codesign', ['-dv', '--verbose=4', path])
      : null;
  final parsed = _parseCodesignDetails(details?['stderr'] as String? ?? '');
  final teamIdentifier = parsed['teamIdentifier'];
  final blockers = <String>[
    if (!exists) 'bundle_missing',
    if (verify == null || verify['exitCode'] != 0) 'codesign_verify_failed',
    if (parsed['adHoc'] == true) 'ad_hoc_signature',
    if (teamIdentifier == null ||
        teamIdentifier == '' ||
        teamIdentifier == 'not set')
      'team_identifier_missing',
  ];
  return {
    'role': role,
    'path': path,
    'exists': exists,
    'verifyExitCode': verify?['exitCode'],
    'verifyStderr': verify?['stderr'],
    'launchConstraintLikelyAccepted': blockers.isEmpty,
    'launchConstraintBlockers': blockers,
    ...parsed,
  };
}

Future<Map<String, dynamic>> _runCommand(
  String executable,
  List<String> arguments,
) async {
  try {
    final result = await Process.run(executable, arguments);
    return {
      'exitCode': result.exitCode,
      'stdout': '${result.stdout}'.trim(),
      'stderr': '${result.stderr}'.trim(),
    };
  } catch (error) {
    return {'exitCode': -1, 'stdout': '', 'stderr': error.toString()};
  }
}

Map<String, dynamic> _parseCodesignDetails(String output) {
  final values = <String, String>{};
  final authorities = <String>[];
  String? codeDirectoryFlags;
  for (final line in const LineSplitter().convert(output)) {
    final trimmed = line.trim();
    if (trimmed.startsWith('Authority=')) {
      authorities.add(trimmed.substring('Authority='.length));
      continue;
    }
    final separator = trimmed.indexOf('=');
    if (separator > 0) {
      values[trimmed.substring(0, separator)] = trimmed.substring(
        separator + 1,
      );
    }
    final flagsIndex = trimmed.indexOf(' flags=');
    if (flagsIndex >= 0) {
      codeDirectoryFlags = trimmed
          .substring(flagsIndex + ' flags='.length)
          .split(' ')
          .first;
    }
  }
  final teamIdentifier = values['TeamIdentifier'];
  final signature = values['Signature'];
  final adHoc =
      signature == 'adhoc' ||
      ((teamIdentifier == null ||
              teamIdentifier.isEmpty ||
              teamIdentifier == 'not set') &&
          authorities.isEmpty);
  return {
    'identifier': values['Identifier'],
    'format': values['Format'],
    'signature': signature,
    'teamIdentifier': teamIdentifier,
    'authorities': authorities,
    'codeDirectoryFlags': codeDirectoryFlags,
    'hardenedRuntime':
        values.containsKey('Runtime Version') ||
        (codeDirectoryFlags?.contains('runtime') ?? false),
    'adHoc': adHoc,
  };
}

Map<String, dynamic> _xpcRuntimeDiagnostics({
  required Map<String, dynamic>? helperStatus,
  required List<Map<String, dynamic>> steps,
  required Map<String, dynamic> signingDiagnostics,
  required Map<String, dynamic>? xpcProductionProbe,
  required Map<String, dynamic> xpcProductionGate,
}) {
  final latestDiagnostics = _latestHelperSharedDiagnostics(
    steps,
    fallback: helperStatus,
  );
  final helperSharedDiagnostics = _mapValue(latestDiagnostics['diagnostics']);
  final signingLooksAccepted =
      signingDiagnostics['launchConstraintLikelyAccepted'] == true;
  final launchAgentEnabled = xpcProductionGate['launchAgentEnabled'] == true;
  final namedServiceConnected =
      xpcProductionGate['namedServiceConnected'] == true ||
      _namedXpcConnected(xpcProductionProbe);
  final helperDiagnosticsObserved = helperSharedDiagnostics != null;
  final helperDiagnosticsStale = latestDiagnostics['stale'] == true;
  final xpcListenerStarted =
      helperSharedDiagnostics?['xpcListenerStarted'] == true;
  final xpcListenerStartAttempted =
      helperSharedDiagnostics?['xpcListenerStartAttempted'] == true;
  final helperRunning =
      helperStatus?['helperRunning'] == true ||
      (helperDiagnosticsObserved && !helperDiagnosticsStale);
  final blockers = <String>[
    if (launchAgentEnabled &&
        signingLooksAccepted &&
        (!helperDiagnosticsObserved || helperDiagnosticsStale))
      'launchd_helper_not_started',
    if (helperDiagnosticsObserved &&
        !helperDiagnosticsStale &&
        !xpcListenerStarted)
      'xpc_listener_not_started',
    if (launchAgentEnabled && signingLooksAccepted && !namedServiceConnected)
      'launchd_mach_service_not_responding',
  ];
  return {
    'launchAgentEnabled': launchAgentEnabled,
    'signingLooksAccepted': signingLooksAccepted,
    'helperRunning': helperRunning,
    'helperDiagnosticsObserved': helperDiagnosticsObserved,
    'helperDiagnosticsStale': helperDiagnosticsStale,
    'xpcListenerStarted': xpcListenerStarted,
    'xpcListenerStartAttempted': xpcListenerStartAttempted,
    'namedServiceConnected': namedServiceConnected,
    'blockers': blockers,
    'nextAction': blockers.isEmpty
        ? 'Named XPC runtime is ready or not enough launchd evidence was collected.'
        : 'Inspect helper startup diagnostics and launchd Mach service ownership.',
  };
}

Map<String, dynamic> _permissionGate(Map<String, dynamic>? permissions) {
  final accessibilityGranted = permissions?['accessibilityGranted'] == true;
  final screenCaptureGranted = permissions?['screenCaptureGranted'] == true;
  final systemAudioSupported =
      permissions?['systemAudioRecordingSupported'] == true;
  final gates = [
    _permissionGateEntry(
      id: 'accessibility',
      label: 'Accessibility',
      granted: accessibilityGranted,
      blocker: 'accessibility_permission_missing',
    ),
    _permissionGateEntry(
      id: 'screen_capture',
      label: 'Screen Recording',
      granted: screenCaptureGranted,
      blocker: 'screen_capture_permission_missing',
    ),
    {
      'id': 'system_audio_recording',
      'label': 'System Audio Recording',
      'supported': systemAudioSupported,
      'status': systemAudioSupported ? 'supported' : 'unsupported',
      if (!systemAudioSupported) 'blockedBy': 'system_audio_unsupported',
    },
  ];
  return {
    'captureExpected': screenCaptureGranted,
    'inputExpected': accessibilityGranted,
    'audioExpected': screenCaptureGranted && systemAudioSupported,
    'status': accessibilityGranted && screenCaptureGranted
        ? 'clear'
        : 'blocked',
    'blockedByPermissions': [
      if (!screenCaptureGranted) 'screen_capture',
      if (!accessibilityGranted) 'accessibility',
    ],
    'blockers': [
      if (!screenCaptureGranted) 'screen_capture_permission_missing',
      if (!accessibilityGranted) 'accessibility_permission_missing',
    ],
    'optionalBlockers': [if (!systemAudioSupported) 'system_audio_unsupported'],
    'gates': gates,
  };
}

Map<String, dynamic> _permissionGateEntry({
  required String id,
  required String label,
  required bool granted,
  required String blocker,
}) {
  return {
    'id': id,
    'label': label,
    'granted': granted,
    'status': granted ? 'granted' : 'expected_block',
    if (!granted) 'blockedBy': blocker,
  };
}

Map<String, dynamic> _overlaySmokeSummary({
  required Map<String, dynamic>? accessibilityOverlay,
  required Map<String, dynamic>? screenRecordingOverlay,
  required bool runOverlaySmoke,
}) {
  if (!runOverlaySmoke) {
    return {
      'status': 'not_run',
      'required': _requireOverlayReady,
      'blockers': [if (_requireOverlayReady) 'overlay_smoke_not_run'],
      'nextAction':
          'Rerun smoke with --overlay-smoke or --require-overlay to validate the permission overlay.',
    };
  }

  final accessibility = _overlaySmokeEntry(
    'accessibility',
    accessibilityOverlay,
  );
  final screenRecording = _overlaySmokeEntry(
    'screenRecording',
    screenRecordingOverlay,
  );
  final entries = [accessibility, screenRecording];
  final blockers = <String>[
    for (final entry in entries)
      for (final blocker in _stringList(entry['blockers'])) blocker,
  ];
  final ready = blockers.isEmpty;
  return {
    'status': ready ? 'ready' : 'failed',
    'required': _requireOverlayReady,
    'accessibility': accessibility,
    'screenRecording': screenRecording,
    'blockers': blockers,
    'nextAction': ready
        ? 'Permission overlays are ready for hands-on drag validation.'
        : 'Inspect overlay response diagnostics and confirm the helper can present its floating panel.',
  };
}

Map<String, dynamic> _overlaySmokeEntry(
  String expectedPermission,
  Map<String, dynamic>? response,
) {
  final shown = response?['overlayShown'] == true;
  final tileReady = response?['draggableTileReady'] == true;
  final settingsOpened = response?['settingsOpened'] == true;
  final permission = response?['permission'];
  final permissionMatches = permission == expectedPermission;
  final blockers = <String>[
    if (response == null) 'overlay_response_missing',
    if (response != null && !settingsOpened) 'overlay_settings_not_opened',
    if (response != null && !shown) 'overlay_window_not_shown',
    if (response != null && !tileReady) 'overlay_tile_not_ready',
    if (response != null && !permissionMatches) 'overlay_permission_mismatch',
  ];
  return {
    'permission': expectedPermission,
    'status': blockers.isEmpty ? 'ready' : 'failed',
    'settingsOpened': settingsOpened,
    'overlayShown': shown,
    'draggableTileReady': tileReady,
    'reportedPermission': permission,
    'overlayPlacement': response?['overlayPlacement'],
    'overlayMode': response?['overlayMode'],
    'helperBundlePath': response?['helperBundlePath'],
    'dragPasteboardTypes': _stringList(response?['dragPasteboardTypes']),
    'blockers': blockers,
  };
}

Map<String, dynamic> _captureGate(
  List<Map<String, dynamic>> steps, {
  required Map<String, dynamic>? permissions,
}) {
  final screenCaptureGranted = permissions?['screenCaptureGranted'] == true;
  final displayPassed = _stepPassedById(steps, 'display_screenshot');
  final windowPassed = _stepPassedById(steps, 'window_capture');
  final blockers = <String>[
    if (!screenCaptureGranted) 'screen_capture_permission_missing',
    if (screenCaptureGranted && !displayPassed)
      'display_capture_runtime_failed',
    if (screenCaptureGranted && !windowPassed) 'window_capture_runtime_failed',
  ];
  return {
    'status': !screenCaptureGranted
        ? 'blocked'
        : blockers.isEmpty
        ? 'ready'
        : 'failed',
    'screenCaptureGranted': screenCaptureGranted,
    'displayScreenshotPassed': displayPassed,
    'windowCapturePassed': windowPassed,
    'blockers': blockers,
    'nextAction': blockers.isEmpty
        ? 'Capture smoke is ready.'
        : !screenCaptureGranted
        ? 'Grant Screen Recording to Caverno Computer Use, then rerun smoke.'
        : 'Inspect capture runtime failures after permissions are granted.',
  };
}

Map<String, dynamic> _inputGate(
  List<Map<String, dynamic>> steps, {
  required Map<String, dynamic>? permissions,
  required bool unsafeArmed,
}) {
  final accessibilityGranted = permissions?['accessibilityGranted'] == true;
  const actionIds = [
    'input_move_pointer',
    'input_drag_pointer',
    'input_scroll',
    'input_press_key',
  ];
  final actionResults = {
    for (final id in actionIds) id: _stepPassedById(steps, id),
  };
  final actions = {for (final id in actionIds) id: _stepStatusById(steps, id)};
  final allActionsPassed = actionResults.values.every((passed) => passed);
  final blockers = <String>[
    if (!unsafeArmed) 'unsafe_smoke_not_armed',
    if (unsafeArmed && !accessibilityGranted)
      'accessibility_permission_missing',
    if (unsafeArmed && accessibilityGranted && !allActionsPassed)
      'input_runtime_failed',
  ];
  return {
    'status': !unsafeArmed
        ? 'not_armed'
        : !accessibilityGranted
        ? 'blocked'
        : allActionsPassed
        ? 'ready'
        : 'failed',
    'unsafeArmed': unsafeArmed,
    'accessibilityGranted': accessibilityGranted,
    'nonDestructiveActions': actionResults,
    'nonDestructiveActionStatus': actions,
    'blockers': blockers,
    'nextAction': blockers.isEmpty
        ? 'Input smoke is ready.'
        : !unsafeArmed
        ? 'Rerun smoke with unsafe arming for non-destructive input checks.'
        : !accessibilityGranted
        ? 'Grant Accessibility to Caverno Computer Use, then rerun smoke.'
        : 'Inspect input runtime failures after Accessibility is granted.',
  };
}

Map<String, dynamic> _audioGate(
  List<Map<String, dynamic>> steps, {
  required Map<String, dynamic>? permissions,
  required bool unsafeArmed,
}) {
  final screenCaptureGranted = permissions?['screenCaptureGranted'] == true;
  final audioSupported = permissions?['systemAudioRecordingSupported'] == true;
  final audioStatus = _stepStatusById(steps, 'system_audio_recording');
  final audioPassed = audioStatus['passed'] == true;
  final blockers = <String>[
    if (!audioSupported) 'system_audio_unsupported',
    if (audioSupported && !unsafeArmed) 'unsafe_smoke_not_armed',
    if (audioSupported && unsafeArmed && !screenCaptureGranted)
      'screen_capture_permission_missing',
    if (audioSupported && unsafeArmed && screenCaptureGranted && !audioPassed)
      'system_audio_runtime_failed',
  ];
  return {
    'status': !audioSupported
        ? 'unsupported'
        : !unsafeArmed
        ? 'not_armed'
        : !screenCaptureGranted
        ? 'blocked'
        : audioPassed
        ? 'ready'
        : 'failed',
    'optional': true,
    'unsafeArmed': unsafeArmed,
    'screenCaptureGranted': screenCaptureGranted,
    'systemAudioRecordingSupported': audioSupported,
    'systemAudioRecording': audioStatus,
    'blockers': blockers,
    'nextAction': blockers.isEmpty
        ? 'System audio smoke is ready.'
        : !audioSupported
        ? 'System audio recording is unsupported on this macOS runtime.'
        : !unsafeArmed
        ? 'Rerun smoke with unsafe arming for system audio checks.'
        : !screenCaptureGranted
        ? 'Grant Screen & System Audio Recording to Caverno Computer Use, then rerun smoke.'
        : 'Inspect system audio runtime failures after permissions are granted.',
  };
}

Map<String, dynamic> _unsafeActionGate({
  required bool unsafeArmed,
  required bool unsafeClickArmed,
  required bool unsafeTextArmed,
}) {
  final arming = [
    {
      'id': 'non_destructive_input',
      'label': 'Non-destructive input smoke',
      'requiredArm': 'unsafe',
      'status': unsafeArmed ? 'armed' : 'not_armed',
    },
    {
      'id': 'click',
      'label': 'Click smoke',
      'requiredArm': 'unsafe_click',
      'status': unsafeClickArmed ? 'armed' : 'not_armed',
    },
    {
      'id': 'text',
      'label': 'Text input smoke',
      'requiredArm': 'unsafe_text',
      'status': unsafeTextArmed ? 'armed' : 'not_armed',
    },
  ];
  final blockers = [
    if (!unsafeArmed) 'unsafe_smoke_not_armed',
    if (!unsafeClickArmed) 'unsafe_click_smoke_not_armed',
    if (!unsafeTextArmed) 'unsafe_text_smoke_not_armed',
  ];
  return {
    'status': unsafeArmed ? 'armed' : 'not_armed',
    'unsafeArmed': unsafeArmed,
    'unsafeClickArmed': unsafeClickArmed,
    'unsafeTextArmed': unsafeTextArmed,
    'nonDestructiveInputArmed': unsafeArmed,
    'clickRequiresExtraArm': true,
    'textRequiresExtraArm': true,
    'arming': arming,
    'blockers': blockers,
    'nextAction': blockers.isEmpty
        ? 'All unsafe smoke arms are enabled for this run.'
        : 'Rerun smoke with only the explicit unsafe arms needed for the next check.',
  };
}

bool _stepPassedById(List<Map<String, dynamic>> steps, String id) {
  final step = steps.cast<Map<String, dynamic>?>().firstWhere(
    (step) => step?['id'] == id,
    orElse: () => null,
  );
  return step?['ok'] == true && step?['skipped'] != true;
}

Map<String, dynamic> _stepStatusById(
  List<Map<String, dynamic>> steps,
  String id,
) {
  final step = steps.cast<Map<String, dynamic>?>().firstWhere(
    (step) => step?['id'] == id,
    orElse: () => null,
  );
  if (step == null) {
    return {'status': 'missing'};
  }
  final skipped = step['skipped'] == true;
  final passed = step['ok'] == true && !skipped;
  return {
    'status': skipped
        ? 'skipped'
        : passed
        ? 'passed'
        : 'failed',
    'passed': passed,
    'skipped': skipped,
    if (step['reason'] != null) 'reason': step['reason'],
    if (step['error'] != null) 'error': step['error'],
  };
}

Map<String, dynamic> _latestHelperSharedDiagnostics(
  List<Map<String, dynamic>> steps, {
  required Map<String, dynamic>? fallback,
}) {
  Map<String, dynamic>? diagnostics = _mapValue(
    fallback?['helperSharedDiagnostics'],
  );
  var stale = fallback?['helperSharedDiagnosticsStale'] == true;
  for (final step in steps) {
    final result = _mapValue(step['result']);
    final direct = _mapValue(result?['helperSharedDiagnostics']);
    final details = _mapValue(result?['details']);
    final nested = _mapValue(details?['helperSharedDiagnostics']);
    final candidate = nested ?? direct;
    if (candidate != null) {
      diagnostics = candidate;
      stale =
          result?['helperSharedDiagnosticsStale'] == true ||
          details?['helperSharedDiagnosticsStale'] == true;
    }
  }
  return {'diagnostics': diagnostics, 'stale': stale};
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

Map<String, dynamic> _xpcProductionGate(List<Map<String, dynamic>> steps) {
  final results = steps
      .where((step) => step['id'] != 'unregister_xpc_launch_agent')
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

bool _namedXpcConnected(Map<String, dynamic>? response) {
  return response != null &&
      response['selectedIpcTransport'] == 'xpc_service' &&
      response['ok'] != false;
}

bool _xpcLaunchAgentNotRegistered(Map<String, dynamic>? response) {
  return response != null &&
      response['xpcLaunchAgentRegistered'] != true &&
      response['xpcLaunchAgentEnabled'] != true &&
      response['xpcLaunchAgentStatus'] == 'not_registered';
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

Map<String, dynamic> _positiveSmokeGateSummary(
  List<Map<String, dynamic>> gates,
) {
  final requiredGates = gates
      .where((gate) => gate['required'] == true)
      .toList(growable: false);
  final failedRequired = requiredGates
      .where((gate) => gate['passed'] != true)
      .toList(growable: false);
  final failedRequiredBlockers = failedRequired
      .map((gate) => gate['blockedBy'])
      .whereType<String>()
      .toSet()
      .toList(growable: false);
  final readinessBlockers = gates
      .map((gate) => gate['blockedBy'])
      .whereType<String>()
      .where(_positiveSmokeReadinessBlocker)
      .toSet()
      .toList(growable: false);
  final blockedBy = {
    ...failedRequiredBlockers,
    if (requiredGates.isEmpty) ...readinessBlockers,
  }.toList(growable: false);
  final failedGateIds = failedRequired
      .map((gate) => gate['id'])
      .whereType<String>()
      .toList(growable: false);
  final blocked = failedRequired.isNotEmpty || blockedBy.isNotEmpty;
  return {
    'status': blocked ? 'blocked' : 'ready',
    'requiredCount': requiredGates.length,
    'passedRequiredCount': requiredGates.length - failedRequired.length,
    'failedRequiredCount': failedRequired.length,
    'failedRequiredGateIds': failedGateIds,
    'blockedBy': blockedBy,
    'nextAction': !blocked
        ? 'Positive smoke gates are ready.'
        : blockedBy.isNotEmpty
        ? 'Resolve positive smoke blockers, then rerun live smoke.'
        : 'Inspect failed required live smoke steps.',
  };
}

bool _positiveSmokeReadinessBlocker(String blockedBy) {
  return blockedBy == 'screen_capture' ||
      blockedBy == 'accessibility' ||
      blockedBy == 'accessibility_or_screen_capture';
}

Map<String, dynamic> _readinessExpectations(Map<String, dynamic> report) {
  final captureReady = _gateReady(report['captureGate']);
  final inputReady = _gateReady(report['inputGate']);
  final audioResolved = _audioGateResolved(report['audioGate']);
  final overlayReady = _gateReady(report['overlaySmoke']);
  final checks = [
    {
      'id': 'capture_ready',
      'required': _requireCaptureReady,
      'ok': !_requireCaptureReady || captureReady,
      'status': _gateStatus(report['captureGate']),
      'nextAction': _gateNextAction(report['captureGate']),
    },
    {
      'id': 'input_ready',
      'required': _requireInputReady,
      'ok': !_requireInputReady || inputReady,
      'status': _gateStatus(report['inputGate']),
      'nextAction': _gateNextAction(report['inputGate']),
    },
    {
      'id': 'audio_resolved',
      'required': _requireAudioResolved,
      'ok': !_requireAudioResolved || audioResolved,
      'status': _gateStatus(report['audioGate']),
      'nextAction': _gateNextAction(report['audioGate']),
    },
    {
      'id': 'overlay_ready',
      'required': _requireOverlayReady,
      'ok': !_requireOverlayReady || overlayReady,
      'status': _gateStatus(report['overlaySmoke']),
      'nextAction': _gateNextAction(report['overlaySmoke']),
    },
  ];
  final failed = checks
      .where((check) => check['required'] == true && check['ok'] != true)
      .map((check) => check['id'])
      .whereType<String>()
      .toList(growable: false);
  return {'ok': failed.isEmpty, 'failed': failed, 'checks': checks};
}

bool _gateReady(Object? gate) {
  return gate is Map && gate['status'] == 'ready';
}

bool _audioGateResolved(Object? gate) {
  return gate is Map &&
      (gate['status'] == 'ready' || gate['status'] == 'unsupported');
}

String _gateStatus(Object? gate) {
  if (gate is Map && gate['status'] is String) {
    return gate['status'] as String;
  }
  return 'missing';
}

String? _gateNextAction(Object? gate) {
  if (gate is Map && gate['nextAction'] is String) {
    return gate['nextAction'] as String;
  }
  return null;
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
