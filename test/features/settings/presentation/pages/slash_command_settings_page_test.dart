import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/presentation/providers/custom_slash_commands_notifier.dart';
import 'package:caverno/features/settings/presentation/pages/slash_command_settings_page.dart';
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

  testWidgets('creates custom slash command templates', (tester) async {
    final container = await _pumpPage(tester);

    expect(find.text('No custom slash commands yet.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slash-command-add')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('slash-command-name-field')),
      'summarize',
    );
    await tester.enterText(
      find.byKey(const ValueKey('slash-command-description-field')),
      'Summarize a target',
    );
    await tester.enterText(
      find.byKey(const ValueKey('slash-command-aliases-field')),
      'sum',
    );
    await tester.enterText(
      find.byKey(const ValueKey('slash-command-template-field')),
      'Summarize this:\n{input}',
    );
    await tester.tap(find.byKey(const ValueKey('slash-command-save')));
    await tester.pumpAndSettle();

    expect(find.text('/summarize'), findsOneWidget);
    expect(find.text('Summarize a target'), findsOneWidget);
    expect(container.read(customSlashCommandsNotifierProvider).single.aliases, [
      'sum',
    ]);
  });
}

Future<ProviderContainer> _pumpPage(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
  );
  addTearDown(container.dispose);

  await tester.runAsync(() async {
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
                home: const SlashCommandSettingsPage(),
              ),
            );
          },
        ),
      ),
    );
  });
  await tester.pumpAndSettle();
  return container;
}
