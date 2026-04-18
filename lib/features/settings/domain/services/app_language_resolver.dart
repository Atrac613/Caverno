import 'package:flutter/material.dart';

const supportedAppLocales = <Locale>[
  Locale('ja'),
  Locale('en'),
];

const fallbackAppLocale = Locale('ja');

Locale resolveAppLocale({
  required String preference,
  Locale? systemLocale,
}) {
  switch (preference) {
    case 'en':
      return const Locale('en');
    case 'ja':
      return const Locale('ja');
    case 'system':
    default:
      return _resolveSystemLocale(systemLocale);
  }
}

String resolveAppLanguageCode({
  required String preference,
  Locale? systemLocale,
}) {
  return resolveAppLocale(
    preference: preference,
    systemLocale: systemLocale,
  ).languageCode;
}

Locale _resolveSystemLocale(Locale? systemLocale) {
  if (systemLocale != null) {
    for (final supportedLocale in supportedAppLocales) {
      if (supportedLocale.languageCode == systemLocale.languageCode) {
        return supportedLocale;
      }
    }
  }

  return fallbackAppLocale;
}
