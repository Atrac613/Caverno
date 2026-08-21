import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/lan_endpoint_discovery.dart';
import 'package:caverno/core/types/app_theme_preference.dart';
import 'package:caverno/features/onboarding/domain/services/local_llm_autodetect_service.dart';
import 'package:caverno/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:caverno/features/onboarding/presentation/providers/onboarding_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

String _modelsBody(List<String> ids) => jsonEncode({
  'object': 'list',
  'data': [
    for (final id in ids) {'id': id, 'object': 'model'},
  ],
});

/// Autodetect backed by a mock transport: [answering] decides whether the
/// simulated machine is running a local LLM.
LocalLlmAutodetectService _autodetect({required bool answering}) {
  return LocalLlmAutodetectService(
    LanEndpointDiscovery(
      client: MockClient((request) async {
        if (answering && request.url.port == 1234) {
          return http.Response(_modelsBody(['qwen3.6-35b', 'gemma3']), 200);
        }
        return http.Response('not found', 404);
      }),
    ),
  );
}

Future<ProviderContainer> _container({required bool answering}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      localLlmAutodetectServiceProvider.overrideWithValue(
        _autodetect(answering: answering),
      ),
    ],
  );
}

Future<void> _pumpPage(WidgetTester tester, ProviderContainer container) async {
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
        builder: (context) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: const OnboardingPage(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('onboarding-next')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('walks welcome -> language -> theme -> connect -> model -> done '
      'and persists the detected endpoint', (tester) async {
    final container = await _container(answering: true);
    addTearDown(container.dispose);
    await _pumpPage(tester, container);

    expect(find.text('Welcome to Caverno'), findsOneWidget);
    // First step has nowhere to go back to.
    expect(find.byKey(const ValueKey('onboarding-back')), findsNothing);

    await _tapNext(tester);
    expect(find.text('Choose your language'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-language-en')));
    await tester.pumpAndSettle();
    expect(container.read(settingsNotifierProvider).language, 'en');

    await _tapNext(tester);
    expect(find.text('Select Theme'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-theme-light')));
    await tester.pumpAndSettle();
    expect(
      container.read(settingsNotifierProvider).themePreference,
      AppThemePreference.light,
    );

    await _tapNext(tester);
    await tester.pumpAndSettle();
    // Loopback detection ran on its own and offered the endpoint it found.
    expect(find.textContaining('http://127.0.0.1:1234/v1'), findsOneWidget);

    await tester.tap(find.textContaining('http://127.0.0.1:1234/v1'));
    await tester.pumpAndSettle();
    await _tapNext(tester);
    await tester.pumpAndSettle();

    expect(find.text('Pick a default model'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-model-gemma3')));
    await tester.pumpAndSettle();

    await _tapNext(tester);
    expect(find.text("You're all set"), findsOneWidget);

    await _tapNext(tester);
    await tester.pumpAndSettle();

    final settings = container.read(settingsNotifierProvider);
    expect(settings.onboardingCompleted, isTrue);
    expect(settings.baseUrl, 'http://127.0.0.1:1234/v1');
    expect(settings.model, 'gemma3');
    expect(
      settings.llmEndpoints.map((e) => e.baseUrl),
      contains('http://127.0.0.1:1234/v1'),
    );
  });

  testWidgets('offers manual entry when nothing is detected, and blocks Next '
      'until the endpoint answers', (tester) async {
    final container = await _container(answering: false);
    addTearDown(container.dispose);
    await _pumpPage(tester, container);

    await _tapNext(tester); // language
    await _tapNext(tester); // theme
    await _tapNext(tester); // connect
    await tester.pumpAndSettle();

    expect(find.textContaining('No local LLM found'), findsOneWidget);
    // Nothing to connect to yet, so the wizard refuses to move on.
    final nextButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Next'),
    );
    expect(nextButton.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('onboarding-manual')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('onboarding-manual-base-url')),
      findsOneWidget,
    );
    expect(container.read(onboardingNotifierProvider).canAdvance, isFalse);
  });
}
