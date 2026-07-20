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
import 'package:caverno/features/dashboard/presentation/widgets/dashboard_view.dart';
import 'package:caverno/features/routines/presentation/providers/routine_scheduler.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _WorkspaceActivation {
  const _WorkspaceActivation({
    required this.workspaceMode,
    required this.projectId,
    required this.createFreshOnFirstOpen,
    required this.deferFreshConversationCreation,
  });

  final WorkspaceMode workspaceMode;
  final String? projectId;
  final bool createFreshOnFirstOpen;
  final bool deferFreshConversationCreation;
}

class _StateTransitionConversationsNotifier extends ConversationsNotifier {
  _StateTransitionConversationsNotifier(this.initialState);

  final ConversationsState initialState;
  final activationCalls = <_WorkspaceActivation>[];

  @override
  ConversationsState build() => initialState;

  @override
  void activateWorkspace({
    required WorkspaceMode workspaceMode,
    String? projectId,
    bool createIfMissing = true,
    bool createFreshOnFirstOpen = false,
    bool deferFreshConversationCreation = false,
  }) {
    final normalizedProjectId = _normalizeProjectId(workspaceMode, projectId);
    activationCalls.add(
      _WorkspaceActivation(
        workspaceMode: workspaceMode,
        projectId: normalizedProjectId,
        createFreshOnFirstOpen: createFreshOnFirstOpen,
        deferFreshConversationCreation: deferFreshConversationCreation,
      ),
    );
    final visibleConversations = state.conversations
        .where(
          (conversation) =>
              conversation.workspaceMode == workspaceMode &&
              (!workspaceMode.usesProjects ||
                  conversation.normalizedProjectId == normalizedProjectId),
        )
        .toList(growable: false);
    final currentConversationId = deferFreshConversationCreation
        ? null
        : visibleConversations.firstOrNull?.id;

    state = state.copyWith(
      currentConversationId: currentConversationId,
      activeWorkspaceMode: workspaceMode,
      activeProjectId: normalizedProjectId,
      clearCurrentConversation: currentConversationId == null,
      clearActiveProject:
          !workspaceMode.usesProjects || normalizedProjectId == null,
    );
  }

  @override
  void selectConversation(String id) {
    final conversation = state.conversations
        .where((item) => item.id == id)
        .firstOrNull;
    if (conversation == null) {
      return;
    }

    state = state.copyWith(
      currentConversationId: conversation.id,
      activeWorkspaceMode: conversation.workspaceMode,
      activeProjectId: conversation.normalizedProjectId,
      clearActiveProject: !conversation.workspaceMode.usesProjects,
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

class _StateTransitionCodingProjectsNotifier extends CodingProjectsNotifier {
  _StateTransitionCodingProjectsNotifier(this.initialState);

  final CodingProjectsState initialState;

  @override
  CodingProjectsState build() => initialState;

  @override
  void selectProject(String? id) {
    state = state.copyWith(
      selectedProjectId: id,
      clearSelectedProject: id == null,
    );
  }
}

class _TestChatNotifier extends ChatNotifier {
  @override
  ChatState build() => ChatState.initial();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets(
    'dashboard exit synchronizes workspace project and assistant mode',
    (tester) async {
      final harness = await _pumpStateTransitionPage(
        tester,
        showDashboardOnStartup: true,
      );

      expect(find.byType(DashboardView), findsOneWidget);
      expect(
        harness.container
            .read(conversationsNotifierProvider)
            .currentConversationId,
        'chat-1',
      );

      await tester.tap(find.byKey(const ValueKey('drawer-workspace-coding')));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardView), findsNothing);
      final codingState = harness.container.read(conversationsNotifierProvider);
      expect(codingState.activeWorkspaceMode, WorkspaceMode.coding);
      expect(codingState.activeProjectId, 'project-1');
      expect(codingState.currentConversationId, isNull);
      expect(
        harness.container
            .read(codingProjectsNotifierProvider)
            .selectedProjectId,
        'project-1',
      );
      expect(
        harness.container.read(settingsNotifierProvider).assistantMode,
        AssistantMode.coding,
      );
      final codingActivation = harness.conversations.activationCalls.single;
      expect(codingActivation.workspaceMode, WorkspaceMode.coding);
      expect(codingActivation.projectId, 'project-1');
      expect(codingActivation.createFreshOnFirstOpen, isTrue);
      expect(codingActivation.deferFreshConversationCreation, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('drawer-workspace-dashboard')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DashboardView), findsOneWidget);
      expect(
        harness.container.read(conversationsNotifierProvider),
        same(codingState),
      );

      await tester.tap(find.byKey(const ValueKey('drawer-workspace-chat')));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardView), findsNothing);
      final chatState = harness.container.read(conversationsNotifierProvider);
      expect(chatState.activeWorkspaceMode, WorkspaceMode.chat);
      expect(chatState.activeProjectId, isNull);
      expect(chatState.currentConversationId, 'chat-1');
      expect(
        harness.container.read(settingsNotifierProvider).assistantMode,
        AssistantMode.general,
      );
    },
  );

  testWidgets('drawer conversation selection keeps scoped state synchronized', (
    tester,
  ) async {
    final harness = await _pumpStateTransitionPage(
      tester,
      showDashboardOnStartup: false,
    );

    await tester.tap(find.byKey(const ValueKey('drawer-workspace-coding')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drawer-thread-coding-2')));
    await tester.pumpAndSettle();

    final codingState = harness.container.read(conversationsNotifierProvider);
    expect(codingState.currentConversationId, 'coding-2');
    expect(codingState.activeWorkspaceMode, WorkspaceMode.coding);
    expect(codingState.activeProjectId, 'project-2');
    expect(
      harness.container.read(codingProjectsNotifierProvider).selectedProjectId,
      'project-2',
    );
    expect(
      harness.container.read(settingsNotifierProvider).assistantMode,
      AssistantMode.coding,
    );

    await tester.tap(find.byKey(const ValueKey('drawer-workspace-chat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drawer-conversation-chat-2')));
    await tester.pumpAndSettle();

    final chatState = harness.container.read(conversationsNotifierProvider);
    expect(chatState.currentConversationId, 'chat-2');
    expect(chatState.activeWorkspaceMode, WorkspaceMode.chat);
    expect(chatState.activeProjectId, isNull);
    expect(
      harness.container.read(codingProjectsNotifierProvider).selectedProjectId,
      'project-2',
    );
    expect(
      harness.container.read(settingsNotifierProvider).assistantMode,
      AssistantMode.general,
    );
  });
}

class _StateTransitionHarness {
  const _StateTransitionHarness({
    required this.container,
    required this.conversations,
  });

  final ProviderContainer container;
  final _StateTransitionConversationsNotifier conversations;
}

Future<_StateTransitionHarness> _pumpStateTransitionPage(
  WidgetTester tester, {
  required bool showDashboardOnStartup,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final now = DateTime(2026, 7, 19, 9);
  final projects = [
    CodingProject(
      id: 'project-1',
      name: 'first_app',
      rootPath: '/tmp/first_app',
      createdAt: now,
      updatedAt: now,
    ),
    CodingProject(
      id: 'project-2',
      name: 'second_app',
      rootPath: '/tmp/second_app',
      createdAt: now,
      updatedAt: now,
    ),
  ];
  Conversation conversation({
    required String id,
    required String title,
    required WorkspaceMode workspaceMode,
    String projectId = '',
  }) {
    return Conversation(
      id: id,
      title: title,
      messages: const [],
      createdAt: now,
      updatedAt: now,
      workspaceMode: workspaceMode,
      projectId: projectId,
    );
  }

  final conversationsState = ConversationsState(
    conversations: [
      conversation(
        id: 'chat-1',
        title: 'First chat',
        workspaceMode: WorkspaceMode.chat,
      ),
      conversation(
        id: 'chat-2',
        title: 'Second chat',
        workspaceMode: WorkspaceMode.chat,
      ),
      conversation(
        id: 'coding-1',
        title: 'First coding thread',
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
      ),
      conversation(
        id: 'coding-2',
        title: 'Second coding thread',
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-2',
      ),
    ],
    currentConversationId: 'chat-1',
    activeWorkspaceMode: WorkspaceMode.chat,
    activeProjectId: null,
  );
  final conversations = _StateTransitionConversationsNotifier(
    conversationsState,
  );
  final codingProjects = _StateTransitionCodingProjectsNotifier(
    CodingProjectsState(projects: projects, selectedProjectId: 'project-1'),
  );

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
      conversationsNotifierProvider.overrideWith(() => conversations),
      codingProjectsNotifierProvider.overrideWith(() => codingProjects),
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
              home: ChatPage(showDashboardOnStartup: showDashboardOnStartup),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _StateTransitionHarness(
    container: container,
    conversations: conversations,
  );
}
