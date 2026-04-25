import 'dart:convert';

import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:caverno/features/settings/presentation/pages/computer_use_debug_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows helper boundary while using helper IPC backend', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    expect(find.text('Computer Use App Boundary'), findsOneWidget);
    expect(find.text('Current executor'), findsOneWidget);
    expect(find.text('Permission owner now'), findsOneWidget);
    expect(find.text('Target helper'), findsOneWidget);
    expect(find.text('Caverno Computer Use (helper_ipc)'), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Reachable'), findsOneWidget);
    expect(
      find.text('Caverno Computer Use (com.noguwo.apps.caverno.computer-use)'),
      findsOneWidget,
    );
    expect(service.helperStatusCallCount, 1);
    expect(service.pingHelperCallCount, 1);
  });

  testWidgets('refreshes permission and audio recording state', (tester) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Refresh');

    expect(find.text('Granted'), findsNWidgets(2));
    expect(find.text('Reachable'), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget);
    expect(
      find.text('Action required: Screen & System Audio Recording'),
      findsOneWidget,
    );

    await _tapSwitch(tester, 'System Audio Armed');
    await _tapButton(tester, 'Start Recording');

    expect(find.text('Recording active'), findsOneWidget);
    expect(service.startAudioCallCount, 1);

    await _tapButton(tester, 'Stop Recording');

    expect(find.text('Not recording'), findsOneWidget);
    expect(service.stopAudioCallCount, 1);
  });

  testWidgets('pings and stops helper work from the permission panel', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Ping Helper');
    await _tapButton(tester, 'Stop Helper Work');

    expect(service.pingHelperCallCount, 2);
    expect(service.stopHelperWorkCallCount, 1);
  });

  testWidgets('launches helper and refreshes helper-owned permissions', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Launch Helper');

    expect(service.launchHelperCallCount, 1);
    expect(service.helperStatusCallCount, 2);
    expect(service.pingHelperCallCount, 2);
    expect(service.getPermissionsCallCount, 1);
  });

  testWidgets('opens macOS permission settings shortcuts', (tester) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Open Accessibility Settings');
    await _tapButton(tester, 'Open Screen Recording Settings');

    expect(service.openedSettingsSections, [
      'accessibility',
      'screen_recording',
    ]);
  });

  testWidgets('uses display preview taps for move pointer arguments', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Capture Display');
    await _tapPreview(tester, 'computer-use-display-preview-tap-area');
    await _tapSwitch(tester, 'Input Events Armed');
    await _tapButton(tester, 'Move Pointer');

    expect(service.lastMoveArguments, isNotNull);
    expect(service.lastMoveArguments, containsPair('x', 1.0));
    expect(service.lastMoveArguments, containsPair('y', 1.0));
    expect(service.lastMoveArguments, containsPair('source_width', 1));
    expect(service.lastMoveArguments, containsPair('source_height', 1));
    expect(service.lastMoveArguments!.containsKey('window_id'), isFalse);
  });

  testWidgets('uses selected window preview taps for click arguments', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'List Windows');
    expect(find.text('Terminal - Shell (#42)'), findsOneWidget);

    await _tapButton(tester, 'Capture Selected');
    await _tapPreview(tester, 'computer-use-window-preview-tap-area');
    await _tapSwitch(tester, 'Input Events Armed');
    await _tapButton(tester, 'Click Point');

    expect(
      service.lastWindowScreenshotArguments,
      containsPair('window_id', 42),
    );
    expect(service.lastClickArguments, isNotNull);
    expect(service.lastClickArguments, containsPair('window_id', 42));
    expect(service.lastClickArguments, containsPair('x', 1.0));
    expect(service.lastClickArguments, containsPair('y', 1.0));
    expect(service.lastClickArguments, containsPair('source_width', 1));
    expect(service.lastClickArguments, containsPair('source_height', 1));
    expect(service.lastClickArguments, containsPair('button', 'left'));
    expect(service.lastClickArguments, containsPair('click_count', 1));
  });

  testWidgets('runs smoke sequence without unsafe armed actions', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapByKey(tester, 'computer-use-run-smoke-sequence');

    expect(service.launchHelperCallCount, 1);
    expect(service.pingHelperCallCount, 2);
    expect(service.getPermissionsCallCount, 1);
    expect(service.screenshotCallCount, 1);
    expect(service.listWindowsCallCount, 1);
    expect(
      service.lastWindowScreenshotArguments,
      containsPair('window_id', 42),
    );
    expect(service.lastMoveArguments, isNull);
    expect(service.startAudioCallCount, 0);
    expect(service.stopAudioCallCount, 0);
  });

  testWidgets('runs armed input and audio during smoke sequence', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapSwitch(tester, 'Input Events Armed');
    await _tapSwitch(tester, 'System Audio Armed');
    await _tapByKey(
      tester,
      'computer-use-run-smoke-sequence',
      wait: const Duration(milliseconds: 500),
    );

    expect(service.lastMoveArguments, containsPair('window_id', 42));
    expect(service.lastMoveArguments, containsPair('source_width', 1));
    expect(service.lastMoveArguments, containsPair('source_height', 1));
    expect(service.startAudioCallCount, 1);
    expect(service.stopAudioCallCount, 1);
  });

  testWidgets('copies and exports redacted diagnostics', (tester) async {
    final service = _FakeMacosComputerUseService();
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpPage(tester, service);
    await _tapButton(tester, 'Capture Display');
    await _tapByKey(tester, 'computer-use-copy-diagnostics');

    final clipboardCall = platformCalls.singleWhere(
      (call) => call.method == 'Clipboard.setData',
    );
    final arguments = clipboardCall.arguments as Map<Object?, Object?>;
    final text = arguments['text'] as String;

    expect(text, contains('"coordinateTarget": "display"'));
    expect(text, contains('"setupChecklist"'));
    expect(text, contains('"onboardingSmokeChecklist"'));
    expect(text, contains('"id": "capture_display"'));
    expect(text, contains('"id": "run_smoke_sequence"'));
    expect(text, contains('"id": "run_input_smoke"'));
    expect(text, contains('"id": "run_audio_smoke"'));
    expect(text, contains('"manualSmokeSteps"'));
    expect(text, contains('"helperIpcProtocol"'));
    expect(text, contains('"preferredTransport": "xpc_service"'));
    expect(text, contains('"xpcReady": false'));
    expect(text, contains('"migratedCommands"'));
    expect(text, contains('"command": "startSystemAudioRecording"'));
    expect(text, contains('"helperStatus"'));
    expect(text, contains('"targetHelperName": "Caverno Computer Use"'));
    expect(text, contains('"displayScreenshot"'));
    expect(text, isNot(contains(_png1x1Base64)));

    await _pumpPage(tester, service);
    await _tapByKey(tester, 'computer-use-export-diagnostics');

    expect(
      find.textContaining('Last export:', skipOffstage: false),
      findsOneWidget,
    );
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeMacosComputerUseService service,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 3200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [macosComputerUseServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: ComputerUseDebugPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(FilledButton, label);
  await _scrollUntilVisible(tester, finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> _tapByKey(
  WidgetTester tester,
  String key, {
  Duration wait = const Duration(milliseconds: 100),
}) async {
  final finder = find.byKey(ValueKey(key));
  await _scrollUntilVisible(tester, finder);
  final widget = tester.widget(finder);
  if (widget is FilledButton) {
    expect(widget.onPressed, isNotNull);
    await tester.runAsync(() async {
      widget.onPressed!();
      await Future<void>.delayed(wait);
    });
    await tester.pumpAndSettle();
    return;
  }
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> _tapSwitch(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await _scrollUntilVisible(tester, finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> _tapPreview(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await _scrollUntilVisible(tester, finder);
  await tester.tapAt(tester.getCenter(finder));
  await tester.pumpAndSettle();
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  if (!tester.any(finder)) {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

class _FakeMacosComputerUseService extends MacosComputerUseService {
  int helperStatusCallCount = 0;
  int launchHelperCallCount = 0;
  int pingHelperCallCount = 0;
  int stopHelperWorkCallCount = 0;
  int getPermissionsCallCount = 0;
  int screenshotCallCount = 0;
  int listWindowsCallCount = 0;
  int startAudioCallCount = 0;
  int stopAudioCallCount = 0;
  final List<String> openedSettingsSections = [];
  Map<String, dynamic>? lastMoveArguments;
  Map<String, dynamic>? lastClickArguments;
  Map<String, dynamic>? lastWindowScreenshotArguments;

  @override
  bool get isAvailable => true;

  @override
  Future<String> getHelperStatus() async {
    helperStatusCallCount += 1;
    return _json({
      'ok': true,
      'backend': 'helper',
      'helperDisplayName': 'Caverno Computer Use',
      'helperBundleIdentifier': 'com.noguwo.apps.caverno.computer-use',
      'helperInstalled': true,
      'helperRunning': true,
      'helperPath':
          '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
    });
  }

  @override
  Future<String> launchHelper() async {
    launchHelperCallCount += 1;
    return _json({
      'ok': true,
      'backend': 'helper',
      'helperInstalled': true,
      'helperRunning': true,
      'launched': true,
    });
  }

  @override
  Future<String> getPermissions() async {
    getPermissionsCallCount += 1;
    return _json({
      'backend': 'helper',
      'helperReachable': true,
      'accessibilityGranted': true,
      'screenCaptureGranted': false,
      'systemAudioRecordingSupported': true,
    });
  }

  @override
  Future<String> pingHelper() async {
    pingHelperCallCount += 1;
    return _json({
      'ok': true,
      'backend': 'helper',
      'helperReachable': true,
      'message': 'pong',
    });
  }

  @override
  Future<String> openSystemSettings({required String section}) async {
    openedSettingsSections.add(section);
    return _json({'ok': true, 'section': section});
  }

  @override
  Future<String> stopHelperWork() async {
    stopHelperWorkCallCount += 1;
    return _json({'ok': true, 'backend': 'helper'});
  }

  @override
  Future<String> screenshot(Map<String, dynamic> arguments) async {
    screenshotCallCount += 1;
    return _imageResult(title: 'Display');
  }

  @override
  Future<String> listWindows(Map<String, dynamic> arguments) async {
    listWindowsCallCount += 1;
    return _json({
      'windows': [
        {
          'windowId': 42,
          'ownerPid': 100,
          'appName': 'Terminal',
          'title': 'Shell',
          'bounds': {'x': 10, 'y': 20, 'width': 800, 'height': 600},
          'layer': 0,
          'alpha': 1,
          'isOnScreen': true,
        },
      ],
      'count': 1,
      'coordinateSpace': 'window_pixels',
      'inputOrigin': 'top_left',
    });
  }

  @override
  Future<String> screenshotWindow(Map<String, dynamic> arguments) async {
    lastWindowScreenshotArguments = Map<String, dynamic>.from(arguments);
    return _imageResult(
      title: 'Shell',
      extra: {
        'windowId': 42,
        'ownerPid': 100,
        'appName': 'Terminal',
        'windowBounds': {'x': 10, 'y': 20, 'width': 800, 'height': 600},
      },
    );
  }

  @override
  Future<String> moveMouse(Map<String, dynamic> arguments) async {
    lastMoveArguments = Map<String, dynamic>.from(arguments);
    return _json({'ok': true});
  }

  @override
  Future<String> click(Map<String, dynamic> arguments) async {
    lastClickArguments = Map<String, dynamic>.from(arguments);
    return _json({'ok': true});
  }

  @override
  Future<String> startSystemAudioRecording(
    Map<String, dynamic> arguments,
  ) async {
    startAudioCallCount += 1;
    return _json({'ok': true, 'path': '/tmp/system-audio.caf'});
  }

  @override
  Future<String> stopSystemAudioRecording() async {
    stopAudioCallCount += 1;
    return _json({'ok': true, 'path': '/tmp/system-audio.caf'});
  }

  String _imageResult({
    required String title,
    Map<String, dynamic> extra = const {},
  }) {
    return _json({
      'imageBase64': _png1x1Base64,
      'imageMimeType': 'image/png',
      'width': 1,
      'height': 1,
      'title': title,
      'coordinateSpace': 'screenshot_pixels',
      'inputOrigin': 'top_left',
      ...extra,
    });
  }
}

String _json(Map<String, dynamic> value) => jsonEncode(value);

const _png1x1Base64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR42mP8z8BQDwAFgwJ/l1vNswAAAABJRU5ErkJggg==';
