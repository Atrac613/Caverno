import 'dart:async';
import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/services/attachment_storage_service.dart';
import 'core/services/login_shell_environment.dart';
import 'core/services/macos_app_menu_service.dart';
import 'core/services/window_manager_service.dart';
import 'core/services/window_settings_service.dart';
import 'core/utils/logger.dart';
import 'features/chat/data/repositories/chat_memory_repository.dart';
import 'features/chat/data/repositories/conversation_repository.dart';
import 'features/chat/data/repositories/skill_repository.dart';
import 'features/chat/data/repositories/tool_result_artifact_store.dart';
import 'features/chat/presentation/pages/chat_page.dart';
import 'features/settings/data/settings_repository.dart';
import 'features/settings/domain/services/app_language_resolver.dart';
import 'features/settings/presentation/providers/settings_notifier.dart';
import 'features/settings/presentation/widgets/onboarding_dialog.dart';
import 'features/settings/presentation/widgets/settings_modal.dart';
import 'features/remote_coding/presentation/remote_coding_server_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  final conversationBox = await Hive.openBox<String>('conversations');
  final memoryBox = await Hive.openBox<String>('chat_memory');
  final skillBox = await Hive.openBox<String>('skills');

  final prefs = await SharedPreferences.getInstance();
  final initialSettings = SettingsRepository(prefs).load();
  final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
  unawaited(_deleteExpiredToolResultArtifacts());
  unawaited(AttachmentStorageService.sweepOldAttachments());

  // Warm up the login-shell PATH so stdio MCP servers and shell/git tools can
  // resolve user-installed binaries (dart, npx, uvx, ...) even when launched
  // from Finder/Dock with launchd's minimal PATH.
  unawaited(LoginShellEnvironment.instance.ensureResolved());

  // Restore window size and position on desktop platforms
  WindowManagerService? windowService;
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    windowService = WindowManagerService(WindowSettingsService(prefs));
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
          skillBoxProvider.overrideWithValue(skillBox),
        ],
        child: MyApp(windowManagerService: windowService),
      ),
    ),
  );
}

Future<void> _deleteExpiredToolResultArtifacts() async {
  try {
    final deletedCount = await ToolResultArtifactStore()
        .deleteArtifactsOlderThan(ToolResultArtifactStore.defaultRetention);
    if (deletedCount > 0) {
      appLog('[Startup] Deleted $deletedCount expired tool result artifact(s)');
    }
  } catch (error) {
    appLog('[Startup] Failed to delete expired tool result artifacts: $error');
  }
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key, this.windowManagerService});

  final WindowManagerService? windowManagerService;

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  bool _localeSyncScheduled = false;
  bool _onboardingCheckScheduled = false;
  bool _onboardingChecked = false;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final MacosAppMenuService _appMenuService;
  bool _settingsModalOpen = false;
  bool _quitDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appMenuService = ref.read(macosAppMenuServiceProvider);
    _appMenuService.setHandlers(
      onOpenSettings: _handleOpenSettings,
      onQuit: _handleQuitShortcut,
    );
  }

  @override
  void dispose() {
    _appMenuService.clear();
    widget.windowManagerService?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Presents the settings modal in response to the native macOS application
  /// menu (Caverno > Settings…). Guards against stacking duplicate modals when
  /// the menu item is triggered repeatedly.
  Future<void> _handleOpenSettings() async {
    if (_settingsModalOpen) {
      return;
    }
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) {
      return;
    }
    _settingsModalOpen = true;
    try {
      await showSettingsModal(navigatorContext);
    } finally {
      _settingsModalOpen = false;
    }
  }

  Future<void> _handleQuitShortcut() async {
    if (_quitDialogOpen) {
      return;
    }

    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) {
      return;
    }

    _quitDialogOpen = true;
    try {
      final shouldQuit = await showDialog<bool>(
        context: navigatorContext,
        builder: (context) {
          return AlertDialog(
            title: const Text('Quit Caverno?'),
            content: const Text(
              'Caverno will stop background routines and active tasks.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Quit'),
              ),
            ],
          );
        },
      );

      if (shouldQuit != true) {
        return;
      }

      final windowManagerService = widget.windowManagerService;
      if (windowManagerService != null) {
        await windowManagerService.quitApplication();
        return;
      }

      await SystemNavigator.pop();
    } finally {
      _quitDialogOpen = false;
    }
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

  void _scheduleFirstLaunchOnboarding() {
    if (_onboardingChecked || _onboardingCheckScheduled) {
      return;
    }

    _onboardingCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _onboardingCheckScheduled = false;
      if (!mounted || _onboardingChecked) {
        return;
      }

      _onboardingChecked = true;
      if (ref.read(settingsNotifierProvider).onboardingCompleted) {
        return;
      }

      final navigatorContext = _navigatorKey.currentContext;
      if (navigatorContext == null) {
        _onboardingChecked = false;
        _scheduleFirstLaunchOnboarding();
        return;
      }

      await showOnboardingDialog(navigatorContext);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      ref.watch(remoteCodingServerProvider);
    }

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
    final onboardingCompleted = ref.watch(
      settingsNotifierProvider.select(
        (settings) => settings.onboardingCompleted,
      ),
    );
    if (!onboardingCompleted) {
      _scheduleFirstLaunchOnboarding();
    }

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyQ, control: true):
            QuitApplicationIntent(),
        SingleActivator(LogicalKeyboardKey.keyQ, meta: true):
            QuitApplicationIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          QuitApplicationIntent: CallbackAction<QuitApplicationIntent>(
            onInvoke: (_) {
              unawaited(_handleQuitShortcut());
              return null;
            },
          ),
        },
        child: MaterialApp(
          title: 'Caverno',
          navigatorKey: _navigatorKey,
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
          themeMode: ThemeMode.dark,
          home: const ChatPage(),
        ),
      ),
    );
  }
}

class QuitApplicationIntent extends Intent {
  const QuitApplicationIntent();
}
