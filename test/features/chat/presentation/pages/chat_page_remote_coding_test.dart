import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_repository.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_page.dart';
import 'package:caverno/features/routines/presentation/providers/routine_scheduler.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      demoMode: false,
      mcpEnabled: false,
    );
  }
}

class _CodingWorkspaceConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() {
    return ConversationsState.initial().copyWith(
      activeWorkspaceMode: WorkspaceMode.coding,
    );
  }
}

class _TestCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _TestChatNotifier extends ChatNotifier {
  @override
  ChatState build() => ChatState.initial();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  tearDown(() {
    debugRemoteCodingMobilePlatformOverride = null;
  });

  test('desktop approval UI is only used for local-origin requests', () {
    expect(shouldPresentDesktopApproval(ChatInteractionOrigin.local), isTrue);
    expect(shouldPresentDesktopApproval(ChatInteractionOrigin.remote), isFalse);
  });

  test('mobile remote coding platform decision can be tested explicitly', () {
    debugRemoteCodingMobilePlatformOverride = () => true;
    expect(isRemoteCodingMobilePlatform(), isTrue);

    debugRemoteCodingMobilePlatformOverride = () => false;
    expect(isRemoteCodingMobilePlatform(), isFalse);
  });

  testWidgets('coding tab is remote-only on mobile platforms', (tester) async {
    debugRemoteCodingMobilePlatformOverride = () => true;

    await _pumpCodingWorkspace(tester);

    expect(find.byType(RemoteCodingPage), findsOneWidget);
    expect(find.text('Remote Coding'), findsOneWidget);
    expect(find.byIcon(Icons.create_new_folder_outlined), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('desktop coding tab keeps local project controls', (
    tester,
  ) async {
    debugRemoteCodingMobilePlatformOverride = () => false;

    await _pumpCodingWorkspace(tester);

    expect(find.byType(RemoteCodingPage), findsNothing);
    expect(find.byTooltip('Add Project'), findsOneWidget);
  });

  testWidgets('mobile connection errors show recovery guidance', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final repository = _RemoteCodingHostWithoutTokenRepository(preferences);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        remoteCodingRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: RemoteCodingPage())),
      ),
    );

    expect(find.text('Desktop (192.168.1.10:8767)'), findsOneWidget);
    await tester.tap(find.text('Reconnect'));
    await tester.pump();

    expect(find.text('Connection checks'), findsOneWidget);
    expect(find.textContaining('fresh device token'), findsOneWidget);
    expect(find.textContaining('same Wi-Fi or LAN'), findsOneWidget);
    expect(find.textContaining('Forget Host'), findsAtLeastNWidgets(1));
  });

  testWidgets('mobile connection view copies redacted diagnostics', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final data = Map<String, dynamic>.from(
            call.arguments as Map<dynamic, dynamic>,
          );
          clipboardText = data['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final repository = _RemoteCodingHostWithoutTokenRepository(preferences);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        remoteCodingRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: RemoteCodingPage())),
      ),
    );

    await tester.tap(find.text('Copy Diagnostics'));
    await tester.pump();

    expect(clipboardText, contains('remote_coding_mobile_diagnostics'));
    expect(clipboardText, contains('"mobileDeviceTokenIncluded": false'));
    expect(clipboardText, isNot(contains('token')));
  });
}

Future<void> _pumpCodingWorkspace(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
      conversationsNotifierProvider.overrideWith(
        _CodingWorkspaceConversationsNotifier.new,
      ),
      codingProjectsNotifierProvider.overrideWith(
        _TestCodingProjectsNotifier.new,
      ),
      chatNotifierProvider.overrideWith(_TestChatNotifier.new),
      routineSchedulerProvider.overrideWith(RoutineSchedulerController.new),
    ],
  );
  addTearDown(container.dispose);

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
              home: const ChatPage(),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _RemoteCodingHostWithoutTokenRepository extends RemoteCodingRepository {
  _RemoteCodingHostWithoutTokenRepository(super.prefs);

  final _host = RemoteCodingHost(
    id: 'device-1',
    name: 'Desktop',
    host: '192.168.1.10',
    port: 8767,
    createdAt: DateTime(2026, 5, 26, 12),
    updatedAt: DateTime(2026, 5, 26, 12),
  );

  @override
  RemoteCodingHost? loadMobileHost() => _host;

  @override
  Future<String?> loadMobileHostToken(String hostId) async => null;
}
