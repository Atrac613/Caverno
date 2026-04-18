import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/services/app_language_resolver.dart';

void main() {
  group('resolveAppLocale', () {
    test('returns explicit English locale when selected', () {
      expect(
        resolveAppLocale(
          preference: 'en',
          systemLocale: const Locale('ja', 'JP'),
        ),
        const Locale('en'),
      );
    });

    test('returns explicit Japanese locale when selected', () {
      expect(
        resolveAppLocale(
          preference: 'ja',
          systemLocale: const Locale('en', 'US'),
        ),
        const Locale('ja'),
      );
    });

    test('uses supported system locale when system default is selected', () {
      expect(
        resolveAppLocale(
          preference: 'system',
          systemLocale: const Locale('en', 'US'),
        ),
        const Locale('en'),
      );
    });

    test('falls back when system locale is unsupported', () {
      expect(
        resolveAppLocale(
          preference: 'system',
          systemLocale: const Locale('fr', 'FR'),
        ),
        fallbackAppLocale,
      );
    });
  });

  test('resolveAppLanguageCode matches the resolved locale', () {
    expect(
      resolveAppLanguageCode(
        preference: 'system',
        systemLocale: const Locale('en', 'GB'),
      ),
      'en',
    );
  });
}
