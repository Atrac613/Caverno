import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/pages/model_harness_config_settings_page.dart';
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
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('editing and saving persists a harness config for the model', (
    tester,
  ) async {
    final container = await _pumpHarnessPage(
      tester,
      AppSettings.defaults().copyWith(model: 'qwen-test'),
    );

    await tester.enterText(
      find.byKey(const ValueKey('harness-bootstrap')),
      'Create the answer file early.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('harness-tool-loop-cap')),
      '6',
    );
    await tester.tap(find.byKey(const ValueKey('harness-exploration-toggle')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('harness-save')));
    await tester.pumpAndSettle();

    final config = container
        .read(settingsNotifierProvider)
        .effectiveModelHarnessConfig;
    expect(config, isNotNull);
    expect(config!.bootstrapInstruction, 'Create the answer file early.');
    expect(config.toolLoopMaxIterations, 6);
    expect(config.explorationToEditNudgeEnabled, isTrue);
  });

  testWidgets('seeds fields from the stored config', (tester) async {
    final settings = AppSettings.defaults().copyWith(model: 'qwen-test');
    final stored = ModelHarnessConfig(
      id: '',
      provider: settings.llmProvider,
      baseUrl: settings.baseUrl,
      model: settings.effectiveModel,
      verificationInstruction: 'Run the tests before finishing.',
      recoveryMiddlewareEnabled: true,
    ).normalizedForPersistence();

    await _pumpHarnessPage(
      tester,
      settings.copyWith(modelHarnessConfigs: [stored]),
    );

    expect(find.text('Run the tests before finishing.'), findsOneWidget);
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('harness-recovery-toggle')),
    );
    expect(toggle.value, isTrue);
  });
}

Future<ProviderContainer> _pumpHarnessPage(
  WidgetTester tester,
  AppSettings settings,
) async {
  SharedPreferences.setMockInitialValues({
    'app_settings': jsonEncode(settings.toJson()),
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 2200);
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
          return UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const ModelHarnessConfigSettingsPage(),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}
