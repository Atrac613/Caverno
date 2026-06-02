import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/settings/data/settings_repository.dart';
import 'package:caverno/features/settings/presentation/pages/general_settings_page.dart';
import 'package:caverno/features/settings/presentation/pages/tools_settings_page.dart';
import 'package:caverno/features/settings/presentation/providers/model_list_provider.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno/features/settings/presentation/widgets/settings_modal.dart';
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

  testWidgets('switches categories and closes from the settings modal', (
    tester,
  ) async {
    await _pumpModal(tester);

    expect(find.byType(SettingsModal), findsOneWidget);
    // The sidebar lists every category. "Voice" and "Tools (MCP)" only appear
    // there until their page is selected, so they are unique on open.
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Tools (MCP)'), findsOneWidget);
    // General is the default category shown in the content panel.
    expect(find.byType(GeneralSettingsPage), findsOneWidget);

    await tester.tap(find.text('Tools (MCP)'));
    await tester.pumpAndSettle();

    expect(find.byType(ToolsSettingsPage), findsOneWidget);
    expect(find.byType(GeneralSettingsPage), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsModal), findsNothing);
  });
}

Future<void> _pumpModal(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsRepository(prefs).load();
  final modelConfig = (baseUrl: settings.baseUrl, apiKey: settings.apiKey);

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 1800);
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
              modelListProvider(
                modelConfig,
              ).overrideWith((ref) async => <String>[]),
            ],
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => showSettingsModal(context),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
