import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _strict = bool.fromEnvironment('CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT');

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
    final stop = await _runStep(
      steps,
      'stop_helper_work',
      'Stop helper work',
      service.stopHelperWork,
    );

    final coreOk =
        _stepPassed(helperStatus) &&
        _stepPassed(launch) &&
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
    report['permissionSummary'] = {
      'accessibilityGranted': permissions?['accessibilityGranted'],
      'screenCaptureGranted': permissions?['screenCaptureGranted'],
      'systemAudioRecordingSupported':
          permissions?['systemAudioRecordingSupported'],
    };
    _printReport(report);

    if (_strict) {
      expect(coreOk, isTrue, reason: 'Core helper smoke steps must pass.');
      expect(captureOk, isTrue, reason: 'Capture smoke steps must pass.');
    }
  });
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
      'result': decoded ?? raw,
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
  // The marker makes it easy to extract the report from compact test logs.
  // ignore: avoid_print
  print('CAVERNO_MACOS_COMPUTER_USE_SMOKE_JSON=${encoder.convert(report)}');
}
