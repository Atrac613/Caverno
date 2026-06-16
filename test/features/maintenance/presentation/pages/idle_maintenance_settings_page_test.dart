import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/maintenance/presentation/pages/idle_maintenance_settings_page.dart';
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

  Future<ProviderContainer> pumpPage(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

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
                home: const IdleMaintenanceSettingsPage(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('enabling maintenance persists to settings', (tester) async {
    final container = await pumpPage(tester);
    expect(
      container.read(settingsNotifierProvider).idleMaintenanceEnabled,
      isFalse,
    );

    await tester.tap(find.byKey(const ValueKey('idle-maintenance-enabled')));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsNotifierProvider).idleMaintenanceEnabled,
      isTrue,
    );
  });

  testWidgets('AC-power toggle updates settings once enabled', (tester) async {
    final container = await pumpPage(tester);
    // Enable maintenance first; the AC toggle is disabled while off.
    await container
        .read(settingsNotifierProvider.notifier)
        .updateIdleMaintenance(enabled: true);
    await tester.pumpAndSettle();

    expect(
      container.read(settingsNotifierProvider).idleMaintenanceRequireAcPower,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('idle-maintenance-require-ac')));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsNotifierProvider).idleMaintenanceRequireAcPower,
      isFalse,
    );
  });
}
