import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/pages/model_routing_settings_page.dart';
import 'package:caverno/features/settings/presentation/providers/model_list_provider.dart';
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

  testWidgets('assigning a role model persists it in settings', (tester) async {
    final settings = AppSettings.defaults().copyWith(model: 'main-model');

    await _pumpModelRoutingPage(
      tester,
      settings: settings,
      loadModels: () async => ['main-model', 'small-model'],
    );

    expect(
      find.text('Default (main model)'),
      findsNWidgets(4),
      reason: 'all four roles start on the main-model fallback',
    );

    await tester.tap(
      find.byKey(const ValueKey('model-routing-memory-extraction')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('small-model').last);
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(ModelRoutingSettingsPage));
    final container = ProviderScope.containerOf(element);
    final updated = container.read(settingsNotifierProvider);
    expect(updated.memoryExtractionModel, 'small-model');
    expect(updated.effectiveMemoryExtractionModel, 'small-model');
    expect(updated.effectiveSubagentModel, 'main-model');
  });

  testWidgets('a configured model stays selectable when not in the catalog', (
    tester,
  ) async {
    final settings = AppSettings.defaults().copyWith(
      model: 'main-model',
      subagentModel: 'offline-model',
    );

    await _pumpModelRoutingPage(
      tester,
      settings: settings,
      loadModels: () async => ['main-model'],
    );

    expect(find.text('offline-model'), findsOneWidget);
  });
}

Future<void> _pumpModelRoutingPage(
  WidgetTester tester, {
  required AppSettings settings,
  required Future<List<String>> Function() loadModels,
}) async {
  SharedPreferences.setMockInitialValues({
    'app_settings': jsonEncode(settings.toJson()),
  });
  final prefs = await SharedPreferences.getInstance();
  final modelConfig = ModelListConfig(
    baseUrl: settings.baseUrl,
    apiKey: settings.apiKey,
    selectedModelId: settings.model,
  );

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1800);
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
              ).overrideWith((ref) => loadModels()),
            ],
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const ModelRoutingSettingsPage(),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
