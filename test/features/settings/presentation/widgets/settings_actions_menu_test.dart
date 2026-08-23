import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/settings/data/settings_file_service.dart';
import 'package:caverno/features/settings/data/settings_repository.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno/features/settings/presentation/widgets/settings_actions_menu.dart';
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

  testWidgets('resets settings and exits after confirmation', (tester) async {
    final initialSettings = AppSettings.defaults().copyWith(
      model: 'custom-model',
      onboardingCompleted: true,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_settings': jsonEncode(initialSettings.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    var exitCalled = false;

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
                home: Scaffold(
                  appBar: AppBar(
                    actions: [
                      SettingsActionsMenu(
                        onResetExit: () async {
                          exitCalled = true;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Reset all settings to default values? Caverno will quit after the reset.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(exitCalled, isTrue);
    expect(prefs.getString('app_settings'), isNull);
    expect(SettingsRepository(prefs).load().onboardingCompleted, isFalse);
  });

  testWidgets('requires confirmation before encrypted secret export', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final fileService = _RecordingSettingsFileService();

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
          builder: (context) => ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              settingsFileServiceProvider.overrideWithValue(fileService),
            ],
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: Scaffold(
                appBar: AppBar(actions: const [SettingsActionsMenu()]),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export Encrypted Backup with Secrets'));
    await tester.pumpAndSettle();

    expect(find.textContaining('contains API keys'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).at(0),
      'long-enough-passphrase',
    );
    await tester.enterText(
      find.byType(TextField).at(1),
      'different-passphrase',
    );
    await tester.tap(find.text('Export Encrypted Backup'));
    await tester.pumpAndSettle();
    expect(find.text('Passphrases do not match.'), findsOneWidget);
    expect(fileService.passphrase, isNull);

    await tester.enterText(
      find.byType(TextField).at(1),
      'long-enough-passphrase',
    );
    await tester.tap(find.text('Export Encrypted Backup'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fileService.passphrase, 'long-enough-passphrase');
    expect(find.text('Export Encrypted Backup with Secrets'), findsNothing);
  });
}

final class _RecordingSettingsFileService extends SettingsFileService {
  String? passphrase;

  @override
  Future<String?> exportSettingsWithSecrets(
    AppSettings settings,
    String passphrase,
  ) async {
    this.passphrase = passphrase;
    return '/tmp/encrypted-settings.json';
  }
}
