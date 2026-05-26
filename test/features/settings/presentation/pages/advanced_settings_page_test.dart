import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/pages/advanced_settings_page.dart';
import 'package:caverno/features/settings/presentation/pages/debug_settings_page.dart';
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
    expect(find.text('Save LLM session logs'), findsOneWidget);
  });

  testWidgets('toggles LLM session logs from Debug settings', (tester) async {
    final prefs = await _setUpPreferences();
    await _pumpPage(
      tester,
      prefs,
      computerUseBuilder: (_) =>
          const Scaffold(body: Center(child: Text('Computer Use destination'))),
    );

    await tester.tap(find.byKey(const ValueKey('settings-menu-debug')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save LLM session logs'));
    await tester.pumpAndSettle();

    final rawSettings = prefs.getString('app_settings');
    expect(rawSettings, isNotNull);
    final decoded = AppSettings.fromJson(
      jsonDecode(rawSettings!) as Map<String, dynamic>,
    );
    expect(decoded.enableLlmSessionLogs, isTrue);
  });
}

Future<SharedPreferences> _setUpPreferences() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPreferences.getInstance();
}

Future<void> _pumpPage(
  WidgetTester tester,
  SharedPreferences prefs, {
  required WidgetBuilder computerUseBuilder,
}) async {
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
            overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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
