import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:caverno/features/settings/presentation/pages/computer_use_debug_page.dart';
import 'package:caverno/features/settings/presentation/pages/settings_page.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final localeName = locale.countryCode == null || locale.countryCode!.isEmpty
        ? locale.languageCode
        : '${locale.languageCode}-${locale.countryCode}';
    final file = File('$path/$localeName.json');
    final fallbackFile = File('$path/${locale.languageCode}.json');
    final source = file.existsSync() ? file : fallbackFile;
    return jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('copies and exports diagnostics from the Settings card', (
    tester,
  ) async {
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
    await _tapByKey(tester, 'computer-use-settings-copy-diagnostics');

    final clipboardCall = platformCalls.singleWhere(
      (call) => call.method == 'Clipboard.setData',
    );
    final arguments = clipboardCall.arguments as Map<Object?, Object?>;
    final text = arguments['text'] as String;

    expect(text, contains('"schemaName": "macos_computer_use_onboarding"'));
    expect(text, contains('"onboardingVerification"'));
    expect(text, contains('"id": "display_screenshot"'));
    expect(text, contains('"lastStopResult"'));

    await _tapByKey(tester, 'computer-use-settings-export-diagnostics');

    expect(
      find.textContaining('Last export:', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('refreshes the Settings card when the app resumes', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    expect(service.helperStatusCallCount, 1);
    expect(service.pingHelperCallCount, 1);
    expect(service.getPermissionsCallCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(service.helperStatusCallCount, 2);
    expect(service.pingHelperCallCount, 2);
    expect(service.getPermissionsCallCount, 2);
  });

  testWidgets('refreshes the Settings card after returning from smoke tests', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Open Smoke Test');
    expect(find.byType(ComputerUseDebugPage), findsOneWidget);

    final helperStatusBeforeReturn = service.helperStatusCallCount;
    final pingBeforeReturn = service.pingHelperCallCount;
    final permissionsBeforeReturn = service.getPermissionsCallCount;

    Navigator.of(tester.element(find.byType(ComputerUseDebugPage))).pop();
    await tester.pumpAndSettle();

    expect(service.helperStatusCallCount, helperStatusBeforeReturn + 1);
    expect(service.pingHelperCallCount, pingBeforeReturn + 1);
    expect(service.getPermissionsCallCount, permissionsBeforeReturn + 1);
  });

  testWidgets('stops helper work from the Settings card', (tester) async {
    final service = _FakeMacosComputerUseService(helperWorkActive: true);
    await _pumpPage(tester, service);

    expect(find.text('Helper Work: Active'), findsOneWidget);

    await _tapByKey(tester, 'computer-use-settings-stop-helper-work');

    expect(service.stopHelperWorkCallCount, 1);
    expect(find.text('Helper Work: Idle'), findsOneWidget);
    expect(
      find.textContaining('Last stop: ok', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('opens targeted permission panes for missing permissions', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(
      accessibilityGranted: false,
      screenCaptureGranted: false,
    );
    await _pumpPage(tester, service);

    expect(find.text('Open Accessibility Settings'), findsOneWidget);
    expect(find.text('Open Screen Recording Settings'), findsOneWidget);

    await _tapByKey(
      tester,
      'computer-use-settings-open-accessibility',
      wait: const Duration(milliseconds: 700),
    );
    await _tapByKey(
      tester,
      'computer-use-settings-open-screen-recording',
      wait: const Duration(milliseconds: 700),
    );

    expect(service.openedSettingsSections, [
      'accessibility',
      'screen_recording',
    ]);
    expect(service.getPermissionsCallCount, greaterThanOrEqualTo(3));
    expect(
      find.textContaining('Last permission action:', skipOffstage: false),
      findsOneWidget,
    );
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeMacosComputerUseService service,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 2600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.runAsync(() async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        useOnlyLangCode: true,
        saveLocale: false,
        assetLoader: const _TestTranslationLoader(),
        child: Builder(
          builder: (context) {
            return ProviderScope(
              overrides: [
                macosComputerUseServiceProvider.overrideWithValue(service),
              ],
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: const SettingsPage(),
              ),
            );
          },
        ),
      ),
    );
  });
  await tester.pumpAndSettle();
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final finder = find.text(label);
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
  if (widget is OutlinedButton) {
    expect(widget.onPressed, isNotNull);
    await tester.runAsync(() async {
      widget.onPressed!();
      await Future<void>.delayed(wait);
    });
    await tester.pumpAndSettle();
    return;
  }
  await tester.tap(finder);
  await tester.pump(wait);
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
  _FakeMacosComputerUseService({
    bool helperWorkActive = false,
    bool accessibilityGranted = true,
    bool screenCaptureGranted = true,
  }) : _helperWorkActive = helperWorkActive,
       _accessibilityGranted = accessibilityGranted,
       _screenCaptureGranted = screenCaptureGranted;

  int helperStatusCallCount = 0;
  int launchHelperCallCount = 0;
  int pingHelperCallCount = 0;
  int stopHelperWorkCallCount = 0;
  int getPermissionsCallCount = 0;
  final List<String> openedSettingsSections = [];
  bool _helperWorkActive;
  final bool _accessibilityGranted;
  final bool _screenCaptureGranted;

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
      'accessibilityGranted': _accessibilityGranted,
      'screenCaptureGranted': _screenCaptureGranted,
      'systemAudioRecordingSupported': true,
      'onboardingVerification': _verification,
    });
  }

  @override
  Future<String> openSystemSettings({required String section}) async {
    openedSettingsSections.add(section);
    return _json({'ok': true, 'backend': 'helper', 'section': section});
  }

  @override
  Future<String> pingHelper() async {
    pingHelperCallCount += 1;
    return _json({
      'ok': true,
      'backend': 'helper',
      'helperReachable': true,
      'message': 'pong',
      'audioRecordingActive': _helperWorkActive,
      'activeWork': {'systemAudioRecording': _helperWorkActive},
      'onboardingVerification': _verification,
    });
  }

  @override
  Future<String> stopHelperWork() async {
    stopHelperWorkCallCount += 1;
    _helperWorkActive = false;
    return _json({
      'ok': true,
      'backend': 'helper',
      'stoppedAudioRecording': true,
      'cancelledInputEvents': true,
      'audioRecordingActive': false,
    });
  }

  static Map<String, dynamic> get _verification => {
    'ok': false,
    'generatedAt': '2026-04-25T12:00:00Z',
    'summary': 'Verification incomplete',
    'steps': [
      {
        'id': 'permissions',
        'label': 'Permissions',
        'ok': true,
        'status': 'done',
        'detail': 'Ready',
      },
      {
        'id': 'display_screenshot',
        'label': 'Display Screenshot',
        'ok': true,
        'status': 'done',
        'detail': '1 x 1 px',
      },
      {
        'id': 'window_capture',
        'label': 'Window Capture',
        'ok': false,
        'status': 'failed',
        'detail': 'No visible window',
      },
    ],
  };
}

String _json(Map<String, dynamic> value) => jsonEncode(value);
