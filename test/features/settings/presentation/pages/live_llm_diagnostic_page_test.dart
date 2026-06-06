import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/pages/live_llm_diagnostic_page.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
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

  testWidgets('shows Foundation Models live canary guidance on macOS', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
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

    try {
      await _pumpPage(
        tester,
        settings: AppSettings.defaults().copyWith(
          llmProvider: LlmProvider.appleFoundationModels,
        ),
      );

      expect(find.text('Foundation Models Live Canary'), findsOneWidget);
      expect(
        find.text('tool/run_foundation_models_live_canary.sh'),
        findsOneWidget,
      );
      expect(
        find.text(
          'build/integration_test_reports/foundation_models_live_canary_<timestamp>/canary_summary.json',
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey('foundation-models-live-canary-copy-command'),
        ),
      );
      await tester.pump();

      final clipboardCall = platformCalls.singleWhere(
        (call) => call.method == 'Clipboard.setData',
      );
      final arguments = clipboardCall.arguments as Map<Object?, Object?>;
      expect(arguments['text'], 'tool/run_foundation_models_live_canary.sh');
      expect(
        find.text('Foundation Models canary command copied.'),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('hides Foundation Models live canary guidance for OpenAI mode', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      await _pumpPage(tester, settings: AppSettings.defaults());

      expect(find.text('Foundation Models Live Canary'), findsNothing);
      expect(
        find.text('tool/run_foundation_models_live_canary.sh'),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required AppSettings settings,
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
            overrides: [
              settingsNotifierProvider.overrideWith(
                () => _FixedSettingsNotifier(settings),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const LiveLlmDiagnosticPage(),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FixedSettingsNotifier extends SettingsNotifier {
  _FixedSettingsNotifier(this.settings);

  final AppSettings settings;

  @override
  AppSettings build() => settings;
}
