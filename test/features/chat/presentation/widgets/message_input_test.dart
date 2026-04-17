import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/presentation/widgets/message_input.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      demoMode: false,
    );
  }
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

Future<void> _pumpMessageInput(
  WidgetTester tester, {
  required ValueNotifier<bool> isLoading,
  required VoidCallback onCancel,
}) async {
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
            return ProviderScope(
              overrides: [
                settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
              ],
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: Scaffold(
                  body: ValueListenableBuilder<bool>(
                    valueListenable: isLoading,
                    builder: (context, loading, child) {
                      return MessageInput(
                        onSend: (_, _, _) {},
                        onCancel: onCancel,
                        isLoading: loading,
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  });
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('disables the composer and shows cancel while loading', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    var cancelCount = 0;
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {
        cancelCount += 1;
      },
    );

    expect(find.byIcon(Icons.record_voice_over), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);

    isLoading.value = true;
    await tester.pump();

    expect(find.byIcon(Icons.record_voice_over), findsNothing);
    expect(find.byIcon(Icons.stop_circle), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    await tester.tap(find.byIcon(Icons.stop_circle));
    await tester.pump();

    expect(cancelCount, 1);
  });
}
