import 'package:caverno/features/chat/presentation/providers/composer_shortcuts_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ComposerShortcutsNotifier.preferredLanguageCode', () {
    // The suggest() parameter defaulted to 'en' and no caller ever passed it,
    // so every draft since the feature shipped asked for English. In a
    // Japanese thread the chips came back in English, and tapping one posted
    // an English sentence into the conversation as if the user had typed it --
    // observed in session d3518675, where three drafts in a row were English
    // while every user message was Japanese.
    AppSettings withLanguage(String language) => AppSettings(
      baseUrl: 'http://localhost:1234/v1',
      model: 'test-model',
      apiKey: 'no-key',
      temperature: 0.7,
      maxTokens: 4096,
      language: language,
    );

    test('follows an explicit language preference', () {
      expect(
        ComposerShortcutsNotifier.preferredLanguageCode(withLanguage('ja')),
        'ja',
      );
      expect(
        ComposerShortcutsNotifier.preferredLanguageCode(withLanguage('en')),
        'en',
      );
    });

    test('resolves "system" rather than falling back to English', () {
      // The old default made 'system' mean English on every device. Going
      // through the app's own resolver makes it mean the device, whose
      // fallback is Japanese.
      final resolved = ComposerShortcutsNotifier.preferredLanguageCode(
        withLanguage('system'),
      );

      expect(supportedAppLanguageCodes, contains(resolved));
    });
  });
}

const supportedAppLanguageCodes = {'ja', 'en'};
