// Preview entrypoint for the onboarding wizard.
//
// Runs the wizard against mocked SharedPreferences so a visual check never
// touches the real settings blob. Not wired into any build: run it explicitly
// with `flutter run -d macos -t tool/preview/onboarding_preview_main.dart`.
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/theme/app_theme.dart';
import 'package:caverno/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  // Deliberate: an in-memory prefs store is exactly what makes this preview
  // safe to run next to a real install.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ja')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('ja'),
      useOnlyLangCode: true,
      child: ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const _PreviewApp(),
      ),
    ),
  );
}

class _PreviewApp extends ConsumerWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(
      settingsNotifierProvider.select((settings) => settings.themePreference),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: preference.themeMode,
      home: const OnboardingPage(),
    );
  }
}
