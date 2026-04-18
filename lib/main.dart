import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/services/window_manager_service.dart';
import 'core/services/window_settings_service.dart';
import 'features/chat/data/repositories/chat_memory_repository.dart';
import 'features/chat/data/repositories/conversation_repository.dart';
import 'features/chat/presentation/pages/chat_page.dart';
import 'features/settings/data/settings_repository.dart';
import 'features/settings/domain/services/app_language_resolver.dart';
import 'features/settings/presentation/providers/settings_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  final conversationBox = await Hive.openBox<String>('conversations');
  final memoryBox = await Hive.openBox<String>('chat_memory');

  final prefs = await SharedPreferences.getInstance();
  final initialSettings = SettingsRepository(prefs).load();
  final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;

  // Restore window size and position on desktop platforms
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    final windowService = WindowManagerService(WindowSettingsService(prefs));
    await windowService.initialize();
  }

  runApp(
    EasyLocalization(
      supportedLocales: supportedAppLocales,
      path: 'assets/translations',
      fallbackLocale: fallbackAppLocale,
      startLocale: resolveAppLocale(
        preference: initialSettings.language,
        systemLocale: systemLocale,
      ),
      saveLocale: false,
      useOnlyLangCode: true,
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          conversationBoxProvider.overrideWithValue(conversationBox),
          chatMemoryBoxProvider.overrideWithValue(memoryBox),
        ],
        child: const MyApp(),
      ),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  bool _localeSyncScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (ref.read(settingsNotifierProvider).language != 'system') {
      return;
    }
    _scheduleLocaleSync(locales?.first);
  }

  void _scheduleLocaleSync([Locale? systemLocale]) {
    final targetLocale = resolveAppLocale(
      preference: ref.read(settingsNotifierProvider).language,
      systemLocale:
          systemLocale ?? WidgetsBinding.instance.platformDispatcher.locale,
    );
    if (context.locale == targetLocale || _localeSyncScheduled) {
      return;
    }

    _localeSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _localeSyncScheduled = false;
      if (!mounted) {
        return;
      }

      final latestTargetLocale = resolveAppLocale(
        preference: ref.read(settingsNotifierProvider).language,
        systemLocale: WidgetsBinding.instance.platformDispatcher.locale,
      );
      if (context.locale == latestTargetLocale) {
        return;
      }

      await context.setLocale(latestTargetLocale);
    });
  }

  @override
  Widget build(BuildContext context) {
    final languagePreference = ref.watch(
      settingsNotifierProvider.select((settings) => settings.language),
    );
    final targetLocale = resolveAppLocale(
      preference: languagePreference,
      systemLocale: WidgetsBinding.instance.platformDispatcher.locale,
    );
    if (context.locale != targetLocale) {
      _scheduleLocaleSync();
    }

    return MaterialApp(
      title: 'Caverno',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const ChatPage(),
    );
  }
}
