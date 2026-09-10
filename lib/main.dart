import 'dart:async';
import 'dart:io' show Directory, File, Platform, exit;
import 'dart:ui' show AppExitResponse;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/services/attachment_storage_service.dart';
import 'core/services/caverno_app_exit_handler.dart';
import 'core/services/crashlytics_service.dart';
import 'core/services/login_shell_environment.dart';
import 'core/services/macos_app_menu_service.dart';
import 'core/services/window_manager_service.dart';
import 'core/services/window_settings_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_log_file.dart';
import 'core/utils/logger.dart';
import 'core/widgets/quit_confirmation_dialog.dart';
import 'features/chat/application/persistence/caverno_chat_memory_mutation_coordinator.dart';
import 'features/chat/application/persistence/caverno_legacy_hive_boxes.dart';
import 'features/chat/application/persistence/caverno_persistence_bootstrap.dart';
import 'features/chat/data/datasources/app_database_open.dart';
import 'features/chat/data/repositories/chat_memory_repository.dart';
import 'features/chat/data/repositories/conversation_repository.dart';
import 'features/chat/data/repositories/skill_repository.dart';
import 'features/chat/data/repositories/tool_result_artifact_store.dart';
import 'features/chat/domain/entities/conversation.dart';
import 'features/chat/presentation/providers/approval_notification_actions.dart';
import 'features/chat/presentation/providers/caverno_execution_runtime_provider.dart';
import 'features/chat/presentation/providers/semantic_search_provider.dart';
import 'features/maintenance/presentation/providers/maintenance_scheduler_provider.dart';
import 'features/onboarding/presentation/pages/onboarding_page.dart';
import 'features/remote_coding/presentation/remote_coding_notification_navigation_shell.dart';
import 'features/remote_coding/presentation/remote_coding_server_notifier.dart';
import 'features/settings/data/settings_repository.dart';
import 'features/settings/domain/services/app_language_resolver.dart';
import 'features/settings/presentation/providers/settings_notifier.dart';
import 'features/settings/presentation/widgets/settings_modal.dart';
import 'features/terminal/application/caverno_cli_arguments.dart';
import 'features/terminal/presentation/caverno_cli_process.dart';
import 'features/watch/presentation/watch_session_notifier.dart';


/// Gives the file log sink a writable directory on iOS and Android.
///
/// Its own fallback is `$HOME/.caverno/app_logs`, which is a desktop path. On
/// mobile `HOME` is the sandbox root, the first write throws, and the sink
/// latches disabled — so a device produced no log at all, which is where one
/// is needed most: there is no attached `flutter run`, and a profile build
/// prints nothing. Desktop is left alone so the tooling that reads its path
/// keeps working.
Future<void> _bindMobileAppLogDirectory() async {
  if (!Platform.isIOS && !Platform.isAndroid) return;
  try {
    final support = await getApplicationSupportDirectory();
    AppLogFile.instance.bindDirectory(
      Directory('${support.path}/app_logs'),
    );
  } on Object {
    // Logging must never be the reason the app fails to start.
  }
}

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (CavernoCliInvocation.looksLikeCliInvocation(arguments)) {
    exit(await runCavernoCliProcess(arguments));
  }
  await EasyLocalization.ensureInitialized();
  await _bindMobileAppLogDirectory();

  final prefs = await SharedPreferences.getInstance();
  WindowManagerService? windowService;
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    windowService = WindowManagerService(WindowSettingsService(prefs));
    await windowService.initialize();
  }

  final settingsRepository = await SettingsRepository.create(prefs);
  final initialSettings = settingsRepository.load();
  final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;

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
      child: CavernoGuiBootstrap(
        prefs: prefs,
        settingsRepository: settingsRepository,
        windowManagerService: windowService,
      ),
    ),
  );
}

Future<void> _installCrashlyticsWithoutBlockingLaunch() async {
  try {
    await installCavernoCrashlytics().timeout(
      const Duration(seconds: 3),
      onTimeout: () => false,
    );
  } catch (_) {
    // Fail closed so the GUI can still paint its first frame.
  }
}

/// F4: open the drift database, run the one-time Hive->drift migrations, and
/// return the drift-backed repositories to serve conversations and chat memory.
/// Before either migration marker exists, a failure returns null so the app can
/// temporarily keep using Hive and retry next launch. An authoritative drift
/// failure is rethrown so stale Hive data cannot become mutable again.
Future<CavernoPersistenceStorage?> _initDriftStorage({
  required SharedPreferences prefs,
  required Box<String>? conversationBox,
  required Box<String>? memoryBox,
  required Directory dataRoot,
}) async {
  try {
    return await const CavernoPersistenceBootstrap().open(
      openDatabase: () => openAppDatabase(
        databaseFile: File('${dataRoot.path}/caverno.sqlite'),
      ),
      conversationsMigrated:
          prefs.getBool(cavernoConversationsMigrationKey) ?? false,
      chatMemoryMigrated: prefs.getBool(cavernoChatMemoryMigrationKey) ?? false,
      readLegacyConversations: () async {
        final box = conversationBox;
        if (box == null) {
          return const <Conversation>[];
        }
        return ConversationRepository(box).getAll();
      },
      readLegacyChatMemory: () async {
        final box = memoryBox;
        if (box == null) {
          return const <String, String>{};
        }
        return {for (final key in box.keys) key.toString(): ?box.get(key)};
      },
      markConversationsMigrated: () async {
        await prefs.setBool(cavernoConversationsMigrationKey, true);
      },
      markChatMemoryMigrated: () async {
        await prefs.setBool(cavernoChatMemoryMigrationKey, true);
      },
      mutationCoordinator: CavernoChatMemoryMutationCoordinator(
        dataRoot: dataRoot,
        frontend: 'flutterGui',
      ),
    );
  } catch (error, stackTrace) {
    if (error is CavernoAuthoritativePersistenceException) {
      appLog(
        '[F4] authoritative drift storage failed; refusing Hive fallback: '
        '${error.cause}',
      );
      appLog('[F4] ${error.causeStackTrace}');
      rethrow;
    }
    appLog('[F4] drift storage init failed; falling back to Hive: $error');
    appLog('[F4] $stackTrace');
    return null;
  }
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

class CavernoGuiBootstrap extends StatefulWidget {
  const CavernoGuiBootstrap({
    super.key,
    required this.prefs,
    required this.settingsRepository,
    this.windowManagerService,
  });

  final SharedPreferences prefs;
  final SettingsRepository settingsRepository;
  final WindowManagerService? windowManagerService;

  @override
  State<CavernoGuiBootstrap> createState() => _CavernoGuiBootstrapState();
}

class _CavernoGuiBootstrapState extends State<CavernoGuiBootstrap> {
  Widget? _app;
  Object? _error;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startOnce();
    });
    // A hidden macOS FlutterView may not vsync, so don't wait forever
    // for the first frame before allowing the native window to appear.
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) {
        return;
      }
      _startOnce();
    });
  }

  void _startOnce() {
    if (_started) {
      return;
    }
    _started = true;
    widget.windowManagerService?.showAfterFirstFrame();
    unawaited(_installCrashlyticsWithoutBlockingLaunch());
    unawaited(_hydrate());
  }

  Future<void> _hydrate() async {
    try {
      final prefs = widget.prefs;
      final dataRoot = await resolveCavernoDataRoot();
      await Hive.initFlutter();
      final hiveBoxes = await CavernoLegacyHiveBoxes.open(
        conversationsMigrated:
            prefs.getBool(cavernoConversationsMigrationKey) ?? false,
        chatMemoryMigrated:
            prefs.getBool(cavernoChatMemoryMigrationKey) ?? false,
      );
      final conversationBox = hiveBoxes.conversations;
      final memoryBox = hiveBoxes.memory;
      final skillBox = hiveBoxes.skills;
      final driftStorage = await _initDriftStorage(
        prefs: prefs,
        conversationBox: conversationBox,
        memoryBox: memoryBox,
        dataRoot: dataRoot,
      );
      unawaited(_deleteExpiredToolResultArtifacts());
      unawaited(AttachmentStorageService.sweepOldAttachments());
      unawaited(LoginShellEnvironment.instance.ensureResolved());
      if (!mounted) {
        await driftStorage?.close();
        return;
      }
      setState(() {
        _app = ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            settingsRepositoryProvider.overrideWithValue(
              widget.settingsRepository,
            ),
            if (conversationBox != null)
              conversationBoxProvider.overrideWithValue(conversationBox),
            if (memoryBox != null)
              chatMemoryBoxProvider.overrideWithValue(memoryBox),
            skillBoxProvider.overrideWithValue(skillBox),
            cavernoRuntimeDataRootProvider.overrideWithValue(dataRoot),
            if (driftStorage != null) ...[
              conversationRepositoryProvider.overrideWithValue(
                driftStorage.conversationRepository,
              ),
              chatMemoryRepositoryProvider.overrideWithValue(
                driftStorage.chatMemoryRepository,
              ),
              appDatabaseProvider.overrideWithValue(driftStorage.database),
            ],
          ],
          child: MyApp(
            windowManagerService: widget.windowManagerService,
            exitHandler: CavernoAppExitHandler(
              closePersistence: driftStorage?.close,
            ),
          ),
        );
      });
    } catch (error, stackTrace) {
      appLog('[Startup] GUI persistence hydrate failed: $error');
      appLog('[Startup] $stackTrace');
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _app;
    if (ready != null) {
      return ready;
    }
    final themePreference = widget.settingsRepository.load().themePreference;
    return MaterialApp(
      title: 'Caverno',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themePreference.themeMode,
      home: Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Caverno could not finish starting.\n$_error',
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
      ),
    );
  }
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key, this.windowManagerService, this.exitHandler});

  final WindowManagerService? windowManagerService;
  final CavernoAppExitHandler? exitHandler;

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  bool _localeSyncScheduled = false;
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

    // LL18: poll the idle/overnight maintenance gate on desktop. The gate
    // (disabled by default) decides whether anything actually runs; the
    // scheduler is disposed with the provider container on app shutdown.
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      ref.read(idleMaintenanceSchedulerProvider).start();
    }
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
      final shouldQuit = await QuitConfirmationDialog.show(navigatorContext);

      if (!shouldQuit) {
        return;
      }

      final exitResponse = await _handleAppExit();
      if (exitResponse == AppExitResponse.cancel) {
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
  Future<AppExitResponse> didRequestAppExit() => _handleAppExit();

  Future<AppExitResponse> _handleAppExit() async {
    Future<AppExitResponse> requestExit() {
      return widget.exitHandler?.handleExitRequest() ??
          Future<AppExitResponse>.value(AppExitResponse.exit);
    }

    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      return requestExit();
    }
    final scheduler = ref.read(idleMaintenanceSchedulerProvider);
    return withMaintenancePausedForExit(
      stopMaintenance: scheduler.stop,
      startMaintenance: scheduler.start,
      requestExit: requestExit,
    );
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
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      ref.watch(remoteCodingServerProvider);
    }
    // Approve/Deny straight from a notification, on every platform that shows
    // one. On iOS this is also what puts the buttons on a paired Apple Watch
    // when the companion app is not running.
    ref.watch(approvalNotificationActionsProvider);
    if (Platform.isIOS) {
      // Keeps the Apple Watch bridge alive for the app's lifetime. The notifier
      // mirrors chat state to the watch and applies the commands that come
      // back, so it has to be listening before the watch first asks — not only
      // while some watch-related screen happens to be on top.
      ref.watch(watchSessionProvider);
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
    final themePreference = ref.watch(
      settingsNotifierProvider.select((settings) => settings.themePreference),
    );
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
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themePreference.themeMode,
          home: onboardingCompleted
              ? const RemoteCodingNotificationNavigationShell()
              : const OnboardingPage(),
        ),
      ),
    );
  }
}

class QuitApplicationIntent extends Intent {
  const QuitApplicationIntent();
}
