import 'dart:convert';
import 'dart:io';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/pages/built_in_tools_settings_page.dart';
import 'package:caverno/features/settings/presentation/pages/tools_settings_page.dart';
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

  testWidgets('updates coding approval mode from Tools settings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

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
                sharedPreferencesProvider.overrideWithValue(preferences),
              ],
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: const ToolsSettingsPage(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Code & local execution approvals'), findsOneWidget);
    expect(
      find.text(
        'Ask before file edits, Python scripts, local write commands, and git writes.',
      ),
      findsOneWidget,
    );

    // The page now shows two approval selectors (coding + chat tools) that share
    // the "Auto-review"/"Full access" labels, so scope to the coding card —
    // identified by its unique "Default permissions" option.
    final codingCard = find.ancestor(
      of: find.text('Default permissions'),
      matching: find.byType(Card),
    );
    expect(codingCard, findsOneWidget);
    expect(
      find.descendant(of: codingCard, matching: find.text('Auto-review')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: codingCard, matching: find.text('Full access')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: codingCard, matching: find.text('Full access')),
    );
    await tester.pumpAndSettle();

    final storedJson = preferences.getString('app_settings');
    expect(storedJson, isNotNull);
    final storedSettings = AppSettings.fromJson(
      jsonDecode(storedJson!) as Map<String, dynamic>,
    );

    expect(storedSettings.codingApprovalMode, ToolApprovalMode.fullAccess);
    expect(storedSettings.confirmFileMutations, isFalse);
    expect(storedSettings.confirmLocalCommands, isFalse);
    expect(storedSettings.confirmGitWrites, isFalse);
  });

  testWidgets('built-in tools groups code and script execution together', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

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
                sharedPreferencesProvider.overrideWithValue(preferences),
              ],
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: const BuiltInToolsSettingsPage(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Code & Scripts'), 400);
    await tester.pumpAndSettle();
    expect(find.text('Code & Scripts'), findsOneWidget);

    await tester.tap(find.text('Code & Scripts'));
    await tester.pumpAndSettle();

    expect(find.text('resolve_installed_dependency'), findsOneWidget);
    expect(find.textContaining('local lockfiles'), findsOneWidget);
    expect(find.text('run_python_script'), findsOneWidget);
    expect(find.textContaining('analyze an attached image'), findsOneWidget);
  });

  testWidgets('toggles coding verification feedback from Tools settings', (
    tester,
  ) async {
    _useLargeTestSurface(tester);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

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
                sharedPreferencesProvider.overrideWithValue(preferences),
              ],
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: const ToolsSettingsPage(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Verify coding completion with tests'),
      120,
    );

    expect(find.text('Verify coding completion with tests'), findsOneWidget);

    // scrollUntilVisible may stop with the target at the bottom edge of the
    // 800x600 test viewport on Linux font metrics. ensureVisible centers the
    // tile enough for the tap hit test to remain stable across runners.
    await tester.ensureVisible(
      find.text('Verify coding completion with tests'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Verify coding completion with tests'));
    await tester.pumpAndSettle();

    final storedJson = preferences.getString('app_settings');
    expect(storedJson, isNotNull);
    final storedSettings = AppSettings.fromJson(
      jsonDecode(storedJson!) as Map<String, dynamic>,
    );

    expect(storedSettings.enableCodingVerificationFeedback, isFalse);
  });

  testWidgets(
    'updates coding verification trigger policy from Tools settings',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();

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
                  sharedPreferencesProvider.overrideWithValue(preferences),
                ],
                child: MaterialApp(
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  home: const ToolsSettingsPage(),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(find.text('On completion claims'), findsOneWidget);
      expect(find.text('On request only'), findsOneWidget);

      await tester.tap(find.text('On request only'));
      await tester.pumpAndSettle();

      final storedJson = preferences.getString('app_settings');
      expect(storedJson, isNotNull);
      final storedSettings = AppSettings.fromJson(
        jsonDecode(storedJson!) as Map<String, dynamic>,
      );

      expect(
        storedSettings.codingVerificationTriggerPolicy,
        CodingVerificationTriggerPolicy.onRequestOnly,
      );
      expect(storedSettings.runsCodingVerificationOnCompletionClaim, isFalse);
    },
  );
}

void _useLargeTestSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
