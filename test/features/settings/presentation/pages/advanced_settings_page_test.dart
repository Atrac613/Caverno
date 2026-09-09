import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/macos_update_service.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/pages/advanced_settings_page.dart';
import 'package:caverno/features/settings/presentation/pages/debug_settings_page.dart';
import 'package:caverno/features/settings/presentation/pages/live_llm_diagnostic_page.dart';
import 'package:caverno/features/settings/data/log_file_cleanup_service.dart';
import 'package:caverno/features/settings/presentation/pages/logging_settings_page.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('opens Computer Use from Advanced settings', (tester) async {
    final prefs = await _setUpPreferences();
    await _pumpPage(
      tester,
      prefs,
      computerUseBuilder: (_) =>
          const Scaffold(body: Center(child: Text('Computer Use destination'))),
    );

    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Computer Use'), findsOneWidget);
    expect(find.text('Local Stack'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-menu-mesh')), findsNothing);
    expect(
      find.text('Helper permissions, smoke checks, and manual sign-off'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('settings-menu-computer-use')));
    await tester.pumpAndSettle();

    expect(find.text('Computer Use destination'), findsOneWidget);
  });

  testWidgets('opens Debug from Advanced settings', (tester) async {
    final prefs = await _setUpPreferences();
    await _pumpPage(
      tester,
      prefs,
      computerUseBuilder: (_) =>
          const Scaffold(body: Center(child: Text('Computer Use destination'))),
    );

    await tester.tap(find.byKey(const ValueKey('settings-menu-debug')));
    await tester.pumpAndSettle();

    expect(find.byType(DebugSettingsPage), findsOneWidget);
    expect(find.text('Debug'), findsAtLeastNWidgets(1));
    expect(find.text('Computer Use Smoke Sequence'), findsOneWidget);
    // File logging moved to the Logging page: nothing about log files here.
    expect(find.text('Save LLM session logs'), findsNothing);
    // Promoted out of Debug: macOS updates now live in General settings and
    // Live LLM Diagnostics in Advanced settings.
    expect(find.text('macOS Updates'), findsNothing);
    expect(find.text('Live LLM Diagnostics'), findsNothing);
  });

  testWidgets('opens Live LLM Diagnostics from Advanced settings', (
    tester,
  ) async {
    final prefs = await _setUpPreferences();
    await _pumpPage(
      tester,
      prefs,
      computerUseBuilder: (_) =>
          const Scaffold(body: Center(child: Text('Computer Use destination'))),
    );

    expect(find.text('Live LLM Diagnostics'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('settings-menu-live-llm-diagnostics')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LiveLlmDiagnosticPage), findsOneWidget);
  });

  testWidgets('opens Logging from Advanced settings', (tester) async {
    final prefs = await _setUpPreferences();
    await _pumpPage(
      tester,
      prefs,
      computerUseBuilder: (_) =>
          const Scaffold(body: Center(child: Text('Computer Use destination'))),
    );

    expect(find.text('Logging'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-menu-logging')));
    await tester.pumpAndSettle();

    expect(find.byType(LoggingSettingsPage), findsOneWidget);
    expect(find.text('Save LLM session logs'), findsOneWidget);
    expect(find.text('Save app log file'), findsOneWidget);
    // The audit trail is listed but has no opt-out: only a delete action.
    expect(find.text('Approval audit log'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(2));
  });

  testWidgets('toggles each file logging system from Logging settings', (
    tester,
  ) async {
    final prefs = await _setUpPreferences();
    await _pumpPage(
      tester,
      prefs,
      computerUseBuilder: (_) =>
          const Scaffold(body: Center(child: Text('Computer Use destination'))),
    );

    await tester.tap(find.byKey(const ValueKey('settings-menu-logging')));
    await tester.pumpAndSettle();

    // Both directions are asserted for every toggle because the switch is the
    // only way back and a one-way check would pass against a stuck control.
    // Widget tests run in debug, where every system defaults on, so each
    // first tap turns its toggle off.
    await tester.tap(find.text('Save LLM session logs'));
    await tester.pumpAndSettle();
    expect(_persistedSettings(prefs).enableLlmSessionLogs, isFalse);

    await tester.tap(find.text('Save LLM session logs'));
    await tester.pumpAndSettle();
    expect(_persistedSettings(prefs).enableLlmSessionLogs, isTrue);

    final appLogTile = find.text('Save app log file');
    await tester.ensureVisible(appLogTile);
    await tester.pumpAndSettle();
    await tester.tap(appLogTile);
    await tester.pumpAndSettle();
    expect(_persistedSettings(prefs).enableAppLogFile, isFalse);

    await tester.tap(appLogTile);
    await tester.pumpAndSettle();
    expect(_persistedSettings(prefs).enableAppLogFile, isTrue);
  });

  testWidgets('deletes one log system\'s files from Logging settings', (
    tester,
  ) async {
    final prefs = await _setUpPreferences();
    final cleanup = _RecordingLogFileCleanupService();
    await _pumpPage(
      tester,
      prefs,
      computerUseBuilder: (_) =>
          const Scaffold(body: Center(child: Text('Computer Use destination'))),
      logCleanupService: cleanup,
    );

    await tester.tap(find.byKey(const ValueKey('settings-menu-logging')));
    await tester.pumpAndSettle();

    // Each sink reports what it has on disk, so the user knows what a delete
    // would remove before confirming.
    expect(find.text('3 files, 2.0 KB'), findsNWidgets(3));

    await tester.tap(
      find.byKey(const ValueKey('logging-delete-approval-audit')),
    );
    await tester.pumpAndSettle();

    // Deletion is destructive and irreversible, so it is confirmed first.
    expect(find.text('Delete log files?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cleanup.deleted, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey('logging-delete-approval-audit')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    // Only the tapped sink is cleared; the other two keep their files.
    expect(cleanup.deleted, [LogFileTarget.approvalAudit]);
    expect(find.text('Deleted 3 files.'), findsOneWidget);
    expect(find.text('No files saved'), findsOneWidget);
    expect(find.text('3 files, 2.0 KB'), findsNWidgets(2));
  });

  testWidgets('configures feedback endpoint upload from Debug settings', (
    tester,
  ) async {
    final prefs = await _setUpPreferences();
    await _pumpPage(
      tester,
      prefs,
      computerUseBuilder: (_) =>
          const Scaffold(body: Center(child: Text('Computer Use destination'))),
    );

    await tester.tap(find.byKey(const ValueKey('settings-menu-debug')));
    await tester.pumpAndSettle();

    final endpointField = find.byKey(
      const ValueKey('feedback-endpoint-url-field'),
    );
    final authTokenField = find.byKey(
      const ValueKey('feedback-endpoint-auth-token-field'),
    );
    expect(endpointField, findsOneWidget);
    expect(authTokenField, findsOneWidget);
    expect(
      tester.widget<TextField>(endpointField).controller?.text,
      defaultFeedbackEndpointUrl,
    );
    expect(tester.widget<TextField>(authTokenField).obscureText, isTrue);

    await tester.enterText(
      endpointField,
      'https://feedback.example.com/caverno',
    );
    await tester.enterText(authTokenField, 'release-token');
    await tester.pumpAndSettle();

    final rawSettings = prefs.getString('app_settings');
    expect(rawSettings, isNotNull);
    final decoded = AppSettings.fromJson(
      jsonDecode(rawSettings!) as Map<String, dynamic>,
    );
    expect(decoded.feedbackUploadEnabled, isTrue);
    expect(decoded.feedbackEndpointUrl, 'https://feedback.example.com/caverno');
    // SEC4.6b moved credentials to the secure store, so the token entered here
    // must not reach shared preferences at all -- the same property
    // settings_repository_test asserts, checked at the screen that collects it.
    expect(rawSettings, isNot(contains('release-token')));
  });
}

AppSettings _persistedSettings(SharedPreferences prefs) {
  final raw = prefs.getString('app_settings');
  expect(raw, isNotNull);
  return AppSettings.fromJson(jsonDecode(raw!) as Map<String, dynamic>);
}

Future<SharedPreferences> _setUpPreferences() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPreferences.getInstance();
}


class _RecordingLogFileCleanupService implements LogFileCleanupService {
  _RecordingLogFileCleanupService();

  final List<LogFileTarget> deleted = <LogFileTarget>[];
  final Map<LogFileTarget, LogDirectoryUsage> usageByTarget = {
    for (final target in LogFileTarget.values)
      target: const LogDirectoryUsage(fileCount: 3, totalBytes: 2048),
  };

  @override
  Future<LogDirectoryUsage> usage(LogFileTarget target) async =>
      usageByTarget[target] ?? LogDirectoryUsage.empty;

  @override
  Future<int> deleteAll(LogFileTarget target) async {
    deleted.add(target);
    usageByTarget[target] = LogDirectoryUsage.empty;
    return 3;
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  SharedPreferences prefs, {
  required WidgetBuilder computerUseBuilder,
  LogFileCleanupService? logCleanupService,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

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
              sharedPreferencesProvider.overrideWithValue(prefs),
              macosUpdateServiceProvider.overrideWithValue(
                const _FakeMacosUpdateService(),
              ),
              if (logCleanupService != null)
                logFileCleanupServiceProvider.overrideWithValue(
                  logCleanupService,
                ),
            ],
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: AdvancedSettingsPage(
                computerUseBuilder: computerUseBuilder,
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeMacosUpdateService extends MacosUpdateService {
  const _FakeMacosUpdateService() : super();

  @override
  bool get isAvailable => true;

  @override
  Future<MacosUpdateStatus> getStatus() async {
    return const MacosUpdateStatus(
      available: true,
      configured: true,
      feedUrl:
          'https://d1ap7clvx8zf86.cloudfront.net/caverno/macos/appcast.xml',
      publicKeyConfigured: true,
      automaticallyChecksForUpdates: true,
      automaticallyDownloadsUpdates: false,
      scheduledCheckIntervalSeconds: 3600,
      updateCheckIntervalSeconds: 3600,
      bundleVersion: '13',
      bundleShortVersion: '1.3.2',
    );
  }

  @override
  Future<MacosUpdateStatus> checkForUpdates() async {
    return getStatus();
  }
}
