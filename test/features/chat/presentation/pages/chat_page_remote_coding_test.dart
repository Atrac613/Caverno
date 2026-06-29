import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/widgets/conversation_drawer.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_repository.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_client_notifier.dart';
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

  @override
  Future<void> updateAssistantMode(AssistantMode assistantMode) async {
    state = state.copyWith(assistantMode: assistantMode);
  }
}

class _CodingWorkspaceConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() {
    return ConversationsState.initial().copyWith(
      activeWorkspaceMode: WorkspaceMode.coding,
    );
  }

  @override
  void activateWorkspace({
    required WorkspaceMode workspaceMode,
    String? projectId,
    bool createIfMissing = true,
    bool createFreshOnFirstOpen = false,
    bool deferFreshConversationCreation = false,
  }) {
    final normalizedProjectId = _normalizeProjectId(workspaceMode, projectId);
    var conversations = state.conversations;
    String? currentConversationId;

    final visibleConversations = conversations
        .where(
          (conversation) =>
              conversation.workspaceMode == workspaceMode &&
              (!workspaceMode.usesProjects ||
                  conversation.normalizedProjectId == normalizedProjectId),
        )
        .toList(growable: false);
    currentConversationId = visibleConversations.firstOrNull?.id;

    if (currentConversationId == null &&
        createIfMissing &&
        workspaceMode.usesConversations &&
        (!workspaceMode.usesProjects || normalizedProjectId != null)) {
      final conversation = Conversation(
        id: 'thread-${conversations.length + 1}',
        title: defaultConversationTitle,
        messages: const [],
        createdAt: DateTime(2026, 6, 3, 12),
        updatedAt: DateTime(2026, 6, 3, 12),
        workspaceMode: workspaceMode,
        projectId: normalizedProjectId ?? '',
      );
      conversations = [conversation, ...conversations];
      currentConversationId = conversation.id;
    }

    state = ConversationsState(
      conversations: conversations,
      currentConversationId: currentConversationId,
      activeWorkspaceMode: workspaceMode,
      activeProjectId: normalizedProjectId,
    );
  }

  String? _normalizeProjectId(WorkspaceMode workspaceMode, String? projectId) {
    if (!workspaceMode.usesProjects) {
      return null;
    }
    final trimmed = projectId?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _TestCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();

  @override
  void selectProject(String? id) {
    state = state.copyWith(
      selectedProjectId: id,
      clearSelectedProject: id == null,
    );
  }

  @override
  Future<CodingProject?> addProject(String rootPath) async {
    final normalizedPath = rootPath.trim();
    if (normalizedPath.isEmpty) return null;

    final project = CodingProject(
      id: 'project-${state.projects.length + 1}',
      name: normalizedPath
          .split(RegExp(r'[\\\/]+'))
          .where((segment) => segment.isNotEmpty)
          .last,
      rootPath: normalizedPath,
      createdAt: DateTime(2026, 6, 3, 12),
      updatedAt: DateTime(2026, 6, 3, 12),
    );
    state = CodingProjectsState(
      projects: [project, ...state.projects],
      selectedProjectId: project.id,
    );
    return project;
  }
}

class _TestChatNotifier extends ChatNotifier {
  @override
  ChatState build() => ChatState.initial();
}

class _ConnectedRemoteCodingClientNotifier extends RemoteCodingClientNotifier {
  static final _generatedAt = DateTime(2026, 6, 3, 12);

  @override
  RemoteCodingClientState build() {
    return RemoteCodingClientState(
      status: RemoteCodingConnectionStatus.connected,
      host: RemoteCodingHost(
        id: 'desktop-1',
        name: 'Desktop',
        host: '192.168.1.10',
        port: 8767,
        createdAt: _generatedAt,
        updatedAt: _generatedAt,
      ),
      projects: const [
        RemoteCodingProjectSummary(
          id: 'project-1',
          name: 'Caverno',
          rootPath: '/workspace/caverno',
        ),
        RemoteCodingProjectSummary(
          id: 'project-2',
          name: 'Universal BLE',
          rootPath: '/workspace/universal_ble',
        ),
      ],
      selectedProjectId: 'project-1',
      threads: [
        RemoteCodingThreadSummary(
          id: 'thread-1',
          title: 'Mobile drawer thread',
          projectId: 'project-1',
          updatedAt: _generatedAt,
        ),
      ],
      currentConversationId: 'thread-1',
      snapshotGeneratedAt: _generatedAt,
    );
  }

  @override
  Future<void> requestSnapshot() async {
    state = state.copyWith(snapshotSequence: state.snapshotSequence + 1);
  }

  @override
  Future<void> selectProject(String projectId) async {
    final thread = RemoteCodingThreadSummary(
      id: projectId == 'project-2' ? 'thread-2' : 'thread-1',
      title: projectId == 'project-2'
          ? 'Other remote thread'
          : 'Mobile drawer thread',
      projectId: projectId,
      updatedAt: _generatedAt,
    );
    state = state.copyWith(
      selectedProjectId: projectId,
      threads: [thread],
      currentConversationId: thread.id,
    );
  }

  @override
  Future<void> selectConversation(String conversationId) async {
    state = state.copyWith(currentConversationId: conversationId);
  }

  @override
  Future<void> createThread({String? projectId}) async {
    final targetProjectId = projectId ?? state.selectedProjectId;
    if (targetProjectId == null) {
      return;
    }
    const threadId = 'created-thread';
    final thread = RemoteCodingThreadSummary(
      id: threadId,
      title: 'Created remote thread',
      projectId: targetProjectId,
      updatedAt: _generatedAt,
    );
    state = state.copyWith(
      selectedProjectId: targetProjectId,
      threads: [thread, ...state.threads],
      currentConversationId: threadId,
    );
  }
}

class _ConnectedRemoteCodingQuestionClientNotifier
    extends RemoteCodingClientNotifier {
  static final _generatedAt = DateTime(2026, 6, 3, 12);
  final List<String> resolvedQuestionIds = <String>[];

  @override
  RemoteCodingClientState build() {
    return RemoteCodingClientState(
      status: RemoteCodingConnectionStatus.connected,
      host: RemoteCodingHost(
        id: 'desktop-1',
        name: 'Desktop',
        host: '192.168.1.10',
        port: 8767,
        createdAt: _generatedAt,
        updatedAt: _generatedAt,
      ),
      projects: const [
        RemoteCodingProjectSummary(
          id: 'project-1',
          name: 'Caverno',
          rootPath: '/workspace/caverno',
        ),
      ],
      selectedProjectId: 'project-1',
      threads: [
        RemoteCodingThreadSummary(
          id: 'thread-1',
          title: 'Mobile question thread',
          projectId: 'project-1',
          updatedAt: _generatedAt,
        ),
      ],
      currentConversationId: 'thread-1',
      pendingQuestion: const RemoteCodingQuestion(
        id: 'question-1',
        question: 'Which fruit?',
        help: 'Pick one for the smoke test.',
        options: [
          RemoteCodingQuestionOption(id: 'apple', label: 'Apple'),
          RemoteCodingQuestionOption(id: 'banana', label: 'Banana'),
          RemoteCodingQuestionOption(id: 'cherry', label: 'Cherry'),
          RemoteCodingQuestionOption(id: 'date', label: 'Date'),
          RemoteCodingQuestionOption(id: 'elderberry', label: 'Elderberry'),
          RemoteCodingQuestionOption(id: 'fig', label: 'Fig'),
          RemoteCodingQuestionOption(id: 'grape', label: 'Grape'),
          RemoteCodingQuestionOption(id: 'honeydew', label: 'Honeydew'),
        ],
        allowOther: false,
      ),
      snapshotGeneratedAt: _generatedAt,
    );
  }

  @override
  Future<void> resolveQuestion({
    required String questionId,
    List<String> selectedOptionIds = const <String>[],
    String otherText = '',
    bool cancelled = false,
  }) async {
    resolvedQuestionIds.add(questionId);
    state = state.copyWith(clearPendingQuestion: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  tearDown(() {
    debugRemoteCodingMobilePlatformOverride = null;
  });

  test('desktop prompt UI is only used for local-origin requests', () {
    expect(shouldPresentDesktopApproval(ChatInteractionOrigin.local), isTrue);
    expect(shouldPresentDesktopApproval(ChatInteractionOrigin.remote), isFalse);
    expect(shouldPresentDesktopQuestion(ChatInteractionOrigin.local), isTrue);
    expect(shouldPresentDesktopQuestion(ChatInteractionOrigin.remote), isFalse);
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

  testWidgets('mobile remote coding keeps the navigation drawer accessible', (
    tester,
  ) async {
    debugRemoteCodingMobilePlatformOverride = () => true;

    await _pumpCodingWorkspace(tester);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.byType(ConversationDrawer), findsOneWidget);
    expect(find.byKey(const ValueKey('drawer-workspace-chat')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('drawer-workspace-coding')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('drawer-workspace-routines')),
      findsOneWidget,
    );
  });

  testWidgets('mobile coding shows the navigation menu button at phone size', (
    tester,
  ) async {
    debugRemoteCodingMobilePlatformOverride = () => true;

    // iPhone 12 Pro logical resolution: the regression hid the hamburger button
    // entirely on coding because the drawer was null, so assert it is present at
    // a real phone width rather than only on the wide default canvas.
    await _pumpCodingWorkspace(tester, size: const Size(390, 844));

    expect(find.byTooltip('Open navigation menu'), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.byType(ConversationDrawer), findsOneWidget);
  });

  testWidgets('mobile remote coding lists projects and threads in the drawer', (
    tester,
  ) async {
    debugRemoteCodingMobilePlatformOverride = () => true;

    final container = await _pumpCodingWorkspace(
      tester,
      size: const Size(390, 844),
      connectRemoteClient: true,
    );

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('remote-drawer-project-project-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('remote-drawer-project-project-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('remote-drawer-thread-thread-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('drawer-project-project-1')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('remote-drawer-project-project-2')),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(remoteCodingClientProvider).selectedProjectId,
      'project-2',
    );
    expect(
      find.byKey(const ValueKey('remote-drawer-thread-thread-2')),
      findsOneWidget,
    );
  });

  testWidgets('mobile remote coding presents an already pending question', (
    tester,
  ) async {
    debugRemoteCodingMobilePlatformOverride = () => true;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        remoteCodingClientProvider.overrideWith(
          _ConnectedRemoteCodingQuestionClientNotifier.new,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: RemoteCodingPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Which fruit?'), findsOneWidget);
    expect(find.text('Pick one for the smoke test.'), findsOneWidget);
    expect(find.text('Apple'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final notifier =
        container.read(remoteCodingClientProvider.notifier)
            as _ConnectedRemoteCodingQuestionClientNotifier;
    expect(notifier.resolvedQuestionIds, ['question-1']);
  });

  testWidgets('desktop coding tab keeps local project controls', (
    tester,
  ) async {
    debugRemoteCodingMobilePlatformOverride = () => false;

    await _pumpCodingWorkspace(tester);

    expect(find.byType(RemoteCodingPage), findsNothing);
    expect(find.byTooltip('Add Project'), findsOneWidget);
  });

  testWidgets('desktop coding left pane adds and activates a project', (
    tester,
  ) async {
    debugRemoteCodingMobilePlatformOverride = () => false;
    final projectRoot = Directory.systemTemp.createTempSync(
      'chat_page_left_pane_project_',
    );
    addTearDown(() {
      if (projectRoot.existsSync()) {
        projectRoot.deleteSync(recursive: true);
      }
    });
    var directoryPickerCalls = 0;
    const filePickerChannel = MethodChannel(
      'miguelruivo.flutter.plugins.filepicker',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      filePickerChannel,
      (call) async {
        expect(call.method, 'dir');
        directoryPickerCalls += 1;
        return projectRoot.path;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        filePickerChannel,
        null,
      );
    });

    final container = await _pumpCodingWorkspace(tester);

    await tester.tap(find.byTooltip('Add Project'));
    await tester.pumpAndSettle();
    expect(directoryPickerCalls, 1);

    final projectsState = container.read(codingProjectsNotifierProvider);
    expect(projectsState.projects.single.rootPath, projectRoot.path);
    expect(projectsState.selectedProjectId, 'project-1');

    final conversationsState = container.read(conversationsNotifierProvider);
    expect(conversationsState.activeWorkspaceMode, WorkspaceMode.coding);
    expect(conversationsState.activeProjectId, 'project-1');
    expect(
      conversationsState.currentConversation?.normalizedProjectId,
      'project-1',
    );
    expect(
      find.text(projectRoot.path.split(Platform.pathSeparator).last),
      findsWidgets,
    );
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

  testWidgets('mobile connection view copies redacted support packet', (
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

    await tester.tap(find.text('Copy Support Packet'));
    await tester.pump();

    expect(clipboardText, contains('remote_coding_p1_support_packet'));
    expect(clipboardText, contains('remote_coding_mobile_diagnostics'));
    expect(clipboardText, contains('"mobileDiagnosticsCopied": true'));
    expect(
      clipboardText,
      contains('"diagnosticsContainNoTokenMaterial": true'),
    );
    expect(clipboardText, isNot(contains('token')));
  });
}

Future<ProviderContainer> _pumpCodingWorkspace(
  WidgetTester tester, {
  Size size = const Size(1200, 900),
  bool connectRemoteClient = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

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
      if (connectRemoteClient)
        remoteCodingClientProvider.overrideWith(
          _ConnectedRemoteCodingClientNotifier.new,
        ),
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
              home: const ChatPage(showDashboardOnStartup: false),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
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
