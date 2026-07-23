import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/apple_foundation_models_platform_client.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/pages/general_settings_page.dart';
import 'package:caverno/features/settings/presentation/providers/apple_foundation_models_availability_provider.dart';
import 'package:caverno/features/settings/presentation/providers/model_capability_auto_probe_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/model_list_provider.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The real auto-probe reaches into the chat stack (Hive boxes, MCP tools),
/// which this page-level test does not bootstrap.
class _StubModelCapabilityAutoProbeNotifier
    extends ModelCapabilityAutoProbeNotifier {
  @override
  Future<void> runForCurrentModel({
    bool force = false,
    String source = 'probe',
  }) async {}
}

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

  testWidgets('explains endpoint preflight failures with repair guidance', (
    tester,
  ) async {
    final settings = AppSettings.defaults().copyWith(
      baseUrl: 'http://localhost:65535/v1',
      model: 'missing-model',
      apiKey: 'test-key',
    );

    await _pumpGeneralSettingsPage(
      tester,
      settings: settings,
      loadModels: () async => throw Exception('Connection refused'),
    );

    expect(find.text('Endpoint preflight failed'), findsOneWidget);
    expect(
      find.text('Endpoint: http://localhost:65535/v1/models'),
      findsOneWidget,
    );
    expect(find.text('Model: missing-model'), findsOneWidget);
    expect(find.text('API key: configured'), findsOneWidget);
    expect(
      find.text(
        'Check the Base URL, API key, and that the server exposes an OpenAI-compatible /models route, then refresh the model list.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('warns when the selected model is absent from the endpoint', (
    tester,
  ) async {
    final settings = AppSettings.defaults().copyWith(
      baseUrl: 'http://localhost:1234/v1',
      model: 'selected-model',
      apiKey: 'no-key',
    );

    await _pumpGeneralSettingsPage(
      tester,
      settings: settings,
      loadModels: () async => ['other-model'],
    );

    expect(find.text('Selected model was not found'), findsOneWidget);
    expect(
      find.text('Endpoint: http://localhost:1234/v1/models'),
      findsOneWidget,
    );
    expect(find.text('Model: selected-model'), findsOneWidget);
    expect(find.text('API key: local placeholder'), findsOneWidget);
    expect(
      find.text(
        'Choose a fetched model or update the model name before starting Plan Mode.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('copies a redacted Plan Mode support snapshot', (tester) async {
    final settings = AppSettings.defaults().copyWith(
      baseUrl: 'http://localhost:1234/v1',
      model: 'selected-model',
      apiKey: 'super-secret-key',
      mcpEnabled: true,
    );
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

    await _pumpGeneralSettingsPage(
      tester,
      settings: settings,
      loadModels: () async => ['selected-model'],
    );

    await tester.tap(
      find.byKey(const ValueKey('plan-mode-copy-support-snapshot')),
    );
    await tester.pumpAndSettle();

    final clipboardCall = platformCalls.singleWhere(
      (call) => call.method == 'Clipboard.setData',
    );
    final arguments = clipboardCall.arguments as Map<Object?, Object?>;
    final text = arguments['text'] as String;
    final snapshot = jsonDecode(text) as Map<String, dynamic>;
    final settingsSnapshot = snapshot['settings'] as Map<String, dynamic>;
    final preflight = snapshot['preflight'] as Map<String, dynamic>;
    final artifactPaths = snapshot['artifactPaths'] as Map<String, dynamic>;

    expect(snapshot['schemaName'], 'plan_mode_support_snapshot');
    expect(settingsSnapshot['baseUrl'], 'http://localhost:1234/v1');
    expect(
      settingsSnapshot['modelsEndpoint'],
      'http://localhost:1234/v1/models',
    );
    expect(settingsSnapshot['model'], 'selected-model');
    expect(settingsSnapshot['apiKeyStatus'], 'configured');
    expect(preflight['failureClassification'], 'ready');
    expect(
      artifactPaths['deterministicSuiteReport'],
      contains('plan_mode_suite_macos_report.json'),
    );
    expect(text, isNot(contains('super-secret-key')));
    expect(find.text('Plan Mode support snapshot copied.'), findsOneWidget);
  });

  testWidgets('registers a second endpoint and switches the primary one', (
    tester,
  ) async {
    final settings = AppSettings.defaults().copyWith(
      baseUrl: 'http://localhost:1234/v1',
      model: 'selected-model',
      apiKey: 'no-key',
    );

    await _pumpGeneralSettingsPage(
      tester,
      settings: settings,
      loadModels: () async => ['selected-model'],
    );

    expect(find.text('http://localhost:1234/v1 · selected-model · local placeholder'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-add-endpoint')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('settings-endpoint-label-field')),
      'Workstation',
    );
    await tester.enterText(
      find.byKey(const ValueKey('settings-endpoint-base-url-field')),
      'http://192.168.100.241:8080/v1',
    );
    await tester.tap(find.byKey(const ValueKey('settings-endpoint-save')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(GeneralSettingsPage)),
    );
    final updated = container.read(settingsNotifierProvider);
    expect(updated.usableLlmEndpointProfiles, hasLength(2));
    expect(updated.baseUrl, 'http://192.168.100.241:8080/v1');
    expect(
      updated.activeLlmEndpointProfile?.normalizedLabel,
      'Workstation',
    );
    expect(find.text('Workstation'), findsOneWidget);
  });

  testWidgets('rejects an endpoint without a usable http(s) URL', (
    tester,
  ) async {
    await _pumpGeneralSettingsPage(
      tester,
      settings: AppSettings.defaults(),
      loadModels: () async => [AppSettings.defaults().model],
    );

    await tester.tap(find.byKey(const ValueKey('settings-add-endpoint')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settings-endpoint-base-url-field')),
      'localhost:1234',
    );
    await tester.tap(find.byKey(const ValueKey('settings-endpoint-save')));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter an http(s) URL, e.g. http://localhost:1234/v1'),
      findsOneWidget,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GeneralSettingsPage)),
    );
    expect(
      container.read(settingsNotifierProvider).usableLlmEndpointProfiles,
      hasLength(1),
    );
  });

  testWidgets('shows the full disabled Apple provider status below dropdown', (
    tester,
  ) async {
    await _pumpGeneralSettingsPage(
      tester,
      settings: AppSettings.defaults(),
      loadModels: () async => [AppSettings.defaults().model],
      appleAvailability: const AppleFoundationModelsAvailability(
        isAvailable: false,
        status: 'unavailable',
        reason: 'appleIntelligenceNotEnabled',
      ),
      physicalSize: const Size(720, 1400),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(DropdownButtonFormField<LlmProvider>), findsOneWidget);
    expect(
      find.text(
        'Apple Foundation Models status: Enable Apple Intelligence (appleIntelligenceNotEnabled)',
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pumpGeneralSettingsPage(
  WidgetTester tester, {
  required AppSettings settings,
  required Future<List<String>> Function() loadModels,
  AppleFoundationModelsAvailability? appleAvailability,
  Size physicalSize = const Size(1200, 1800),
}) async {
  SharedPreferences.setMockInitialValues({
    'app_settings': jsonEncode(settings.toJson()),
  });
  final prefs = await SharedPreferences.getInstance();
  final modelConfig = ModelListConfig(
    baseUrl: settings.baseUrl,
    apiKey: settings.apiKey,
  );

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = physicalSize;
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
              modelCapabilityAutoProbeNotifierProvider.overrideWith(
                _StubModelCapabilityAutoProbeNotifier.new,
              ),
              modelListProvider(
                modelConfig,
              ).overrideWith((ref) => loadModels()),
              appleFoundationModelsAvailabilityProvider.overrideWith(
                (ref) async =>
                    appleAvailability ??
                    const AppleFoundationModelsAvailability(
                      isAvailable: false,
                      status: 'unavailable',
                      reason: 'deviceNotEligible',
                    ),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const GeneralSettingsPage(),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
