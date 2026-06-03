import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/widgets/conversation_drawer.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/model_list_provider.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno/features/settings/presentation/widgets/settings_modal.dart';
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

const _collapsedProjectIdsPrefsKey =
    'conversationDrawer.collapsedCodingProjectIds';

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(demoMode: false, mcpEnabled: false);
  }
}

class _DrawerConversationsNotifier extends ConversationsNotifier {
  _DrawerConversationsNotifier(this.initialState);

  final ConversationsState initialState;

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
    final visibleConversations = state.conversations
        .where(
          (conversation) =>
              conversation.workspaceMode == workspaceMode &&
              (!workspaceMode.usesProjects ||
                  conversation.normalizedProjectId == normalizedProjectId),
        )
        .toList(growable: false);
    final currentConversationId = visibleConversations.firstOrNull?.id;

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
    if (conversation == null) return;

    state = state.copyWith(
      currentConversationId: conversation.id,
      activeWorkspaceMode: conversation.workspaceMode,
      activeProjectId: conversation.normalizedProjectId,
      clearActiveProject: !conversation.workspaceMode.usesProjects,
    );
  }

  @override
  void createNewConversation({
    WorkspaceMode? workspaceMode,
    String? projectId,
  }) {
    final resolvedWorkspaceMode = workspaceMode ?? state.activeWorkspaceMode;
    final resolvedProjectId = _normalizeProjectId(
      resolvedWorkspaceMode,
      projectId ?? state.activeProjectId,
    );
    final now = DateTime(2026, 5, 28, 12);
    final conversation = Conversation(
      id: 'new-${state.conversations.length + 1}',
      title: defaultConversationTitle,
      messages: const [],
      createdAt: now,
      updatedAt: now,
      workspaceMode: resolvedWorkspaceMode,
      projectId: resolvedProjectId ?? '',
    );

    state = state.copyWith(
      conversations: [conversation, ...state.conversations],
      currentConversationId: conversation.id,
      activeWorkspaceMode: resolvedWorkspaceMode,
      activeProjectId: resolvedProjectId,
      clearActiveProject:
          !resolvedWorkspaceMode.usesProjects || resolvedProjectId == null,
    );
  }

  @override
  Future<void> deleteConversation(String id) async {
    state = state.copyWith(
      conversations: state.conversations
          .where((conversation) => conversation.id != id)
          .toList(growable: false),
      clearCurrentConversation: state.currentConversationId == id,
    );
  }

  @override
  Future<void> deleteScopedConversations() async {
    final scopedIds = state.visibleConversations
        .map((conversation) => conversation.id)
        .toSet();
    state = state.copyWith(
      conversations: state.conversations
          .where((conversation) => !scopedIds.contains(conversation.id))
          .toList(growable: false),
      clearCurrentConversation: scopedIds.contains(state.currentConversationId),
    );
  }

  @override
  Future<void> deleteConversationsForProject(String projectId) async {
    state = state.copyWith(
      conversations: state.conversations
          .where(
            (conversation) =>
                conversation.workspaceMode != WorkspaceMode.coding ||
                conversation.normalizedProjectId != projectId,
          )
          .toList(growable: false),
      clearCurrentConversation: state.conversations.any(
        (conversation) =>
            conversation.id == state.currentConversationId &&
            conversation.workspaceMode == WorkspaceMode.coding &&
            conversation.normalizedProjectId == projectId,
      ),
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

class _DrawerCodingProjectsNotifier extends CodingProjectsNotifier {
  _DrawerCodingProjectsNotifier(this.initialState);

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

  @override
  Future<void> removeProject(String id) async {
    final projects = state.projects
        .where((project) => project.id != id)
        .toList(growable: false);
    final selectedProjectId = state.selectedProjectId == id
        ? projects.firstOrNull?.id
        : state.selectedProjectId;
    state = state.copyWith(
      projects: projects,
      selectedProjectId: selectedProjectId,
      clearSelectedProject: selectedProjectId == null,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('drawer shows workspace navigation and opens settings', (
    tester,
  ) async {
    await _pumpDrawerApp(
      tester,
      conversationsState: ConversationsState(
        conversations: [
          _conversation(
            id: 'chat-1',
            title: 'General question',
            workspaceMode: WorkspaceMode.chat,
          ),
        ],
        currentConversationId: 'chat-1',
        activeWorkspaceMode: WorkspaceMode.chat,
        activeProjectId: null,
      ),
      projectsState: CodingProjectsState.initial(),
    );

    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Coding'), findsOneWidget);
    expect(find.text('Routines'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('drawer-settings')));
    await tester.pumpAndSettle();

    // On desktop (the test host is macOS) the drawer opens the settings modal.
    expect(find.byType(SettingsModal), findsOneWidget);
  });

  testWidgets('workspace entries switch the active workspace', (tester) async {
    final project = _project(id: 'project-1', name: 'sample_app');
    final container = await _pumpDrawerApp(
      tester,
      conversationsState: ConversationsState(
        conversations: [
          _conversation(
            id: 'chat-1',
            title: 'General question',
            workspaceMode: WorkspaceMode.chat,
          ),
          _conversation(
            id: 'thread-1',
            title: 'Fix parser',
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
          ),
        ],
        currentConversationId: 'chat-1',
        activeWorkspaceMode: WorkspaceMode.chat,
        activeProjectId: null,
      ),
      projectsState: CodingProjectsState(
        projects: [project],
        selectedProjectId: project.id,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('drawer-workspace-coding')));
    await tester.pumpAndSettle();

    final conversationsState = container.read(conversationsNotifierProvider);
    expect(conversationsState.activeWorkspaceMode, WorkspaceMode.coding);
    expect(conversationsState.activeProjectId, project.id);
  });

  testWidgets(
    'coding drawer groups project threads and expands older threads',
    (tester) async {
      final firstProject = _project(id: 'project-1', name: 'caverno');
      final secondProject = _project(id: 'project-2', name: 'universal_ble');
      final conversations = [
        for (var index = 1; index <= 6; index++)
          _conversation(
            id: 'thread-$index',
            title: 'Thread $index',
            workspaceMode: WorkspaceMode.coding,
            projectId: firstProject.id,
            minutesAgo: index,
          ),
        _conversation(
          id: 'thread-other',
          title: 'Other project thread',
          workspaceMode: WorkspaceMode.coding,
          projectId: secondProject.id,
          minutesAgo: 20,
        ),
      ];

      await _pumpDrawerApp(
        tester,
        conversationsState: ConversationsState(
          conversations: conversations,
          currentConversationId: 'thread-1',
          activeWorkspaceMode: WorkspaceMode.coding,
          activeProjectId: firstProject.id,
        ),
        projectsState: CodingProjectsState(
          projects: [firstProject, secondProject],
          selectedProjectId: firstProject.id,
        ),
      );

      expect(find.text('caverno'), findsOneWidget);
      expect(find.text('universal_ble'), findsOneWidget);
      expect(find.text('Thread 1'), findsOneWidget);
      expect(find.text('Thread 5'), findsOneWidget);
      expect(find.text('Thread 6'), findsNothing);
      expect(find.text('Show more'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('drawer-project-project-1-show-more')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thread 6'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);
    },
  );

  testWidgets('coding drawer collapses and reopens project threads', (
    tester,
  ) async {
    final project = _project(id: 'project-1', name: 'caverno');
    final conversations = [
      _conversation(
        id: 'thread-1',
        title: 'Thread 1',
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
      ),
      _conversation(
        id: 'thread-2',
        title: 'Thread 2',
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
        minutesAgo: 1,
      ),
    ];

    final container = await _pumpDrawerApp(
      tester,
      conversationsState: ConversationsState(
        conversations: conversations,
        currentConversationId: 'thread-1',
        activeWorkspaceMode: WorkspaceMode.coding,
        activeProjectId: project.id,
      ),
      projectsState: CodingProjectsState(
        projects: [project],
        selectedProjectId: project.id,
      ),
    );

    expect(find.text('caverno'), findsOneWidget);
    expect(find.text('Thread 1'), findsOneWidget);
    expect(find.text('Thread 2'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('drawer-project-project-1-toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.text('caverno'), findsOneWidget);
    expect(find.text('Thread 1'), findsNothing);
    expect(find.text('Thread 2'), findsNothing);
    expect(
      container
          .read(sharedPreferencesProvider)
          .getStringList(_collapsedProjectIdsPrefsKey),
      ['project-1'],
    );

    await tester.tap(
      find.byKey(const ValueKey('drawer-project-project-1-toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Thread 1'), findsOneWidget);
    expect(find.text('Thread 2'), findsOneWidget);
    expect(
      container
          .read(sharedPreferencesProvider)
          .getStringList(_collapsedProjectIdsPrefsKey),
      isEmpty,
    );
  });

  testWidgets('coding drawer restores collapsed project state', (tester) async {
    final project = _project(id: 'project-1', name: 'caverno');
    final conversations = [
      _conversation(
        id: 'thread-1',
        title: 'Thread 1',
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
      ),
    ];

    await _pumpDrawerApp(
      tester,
      conversationsState: ConversationsState(
        conversations: conversations,
        currentConversationId: 'thread-1',
        activeWorkspaceMode: WorkspaceMode.coding,
        activeProjectId: project.id,
      ),
      projectsState: CodingProjectsState(
        projects: [project],
        selectedProjectId: project.id,
      ),
      initialPreferences: const {
        _collapsedProjectIdsPrefsKey: ['project-1'],
      },
    );

    expect(find.text('caverno'), findsOneWidget);
    expect(find.text('Thread 1'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('drawer-project-project-1-toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Thread 1'), findsOneWidget);
  });
}

Future<ProviderContainer> _pumpDrawerApp(
  WidgetTester tester, {
  required ConversationsState conversationsState,
  required CodingProjectsState projectsState,
  Map<String, Object> initialPreferences = const <String, Object>{},
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1400);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  SharedPreferences.setMockInitialValues(initialPreferences);
  final preferences = await SharedPreferences.getInstance();
  late final ProviderContainer container;
  container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
      // The desktop drawer opens the settings modal, whose default General page
      // watches the model list; stub it so the modal settles offline.
      modelListProvider((
        baseUrl: AppSettings.defaults().baseUrl,
        apiKey: AppSettings.defaults().apiKey,
      )).overrideWith((ref) async => <String>[]),
      conversationsNotifierProvider.overrideWith(
        () => _DrawerConversationsNotifier(conversationsState),
      ),
      codingProjectsNotifierProvider.overrideWith(
        () => _DrawerCodingProjectsNotifier(projectsState),
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
              home: Scaffold(
                drawer: ConversationDrawer(
                  onWorkspaceModeSelected: (workspaceMode) async {
                    final selectedProjectId = container
                        .read(codingProjectsNotifierProvider)
                        .selectedProjectId;
                    container
                        .read(conversationsNotifierProvider.notifier)
                        .activateWorkspace(
                          workspaceMode: workspaceMode,
                          projectId: workspaceMode == WorkspaceMode.coding
                              ? selectedProjectId
                              : null,
                          createIfMissing: false,
                        );
                  },
                  onCodingProjectSelected: (projectId) async {
                    container
                        .read(codingProjectsNotifierProvider.notifier)
                        .selectProject(projectId);
                    container
                        .read(conversationsNotifierProvider.notifier)
                        .activateWorkspace(
                          workspaceMode: WorkspaceMode.coding,
                          projectId: projectId,
                          createIfMissing: true,
                        );
                  },
                  onConversationSelected: (conversationId) async {
                    final conversation = container
                        .read(conversationsNotifierProvider)
                        .conversations
                        .firstWhere((item) => item.id == conversationId);
                    if (conversation.workspaceMode == WorkspaceMode.coding &&
                        conversation.normalizedProjectId != null) {
                      container
                          .read(codingProjectsNotifierProvider.notifier)
                          .selectProject(conversation.normalizedProjectId);
                    }
                    container
                        .read(conversationsNotifierProvider.notifier)
                        .selectConversation(conversationId);
                  },
                  onAddCodingProject: () async {},
                ),
                body: Builder(
                  builder: (context) {
                    return TextButton(
                      key: const ValueKey('open-drawer'),
                      onPressed: Scaffold.of(context).openDrawer,
                      child: const Text('Open drawer'),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open-drawer')));
  await tester.pumpAndSettle();
  return container;
}

CodingProject _project({required String id, required String name}) {
  final now = DateTime(2026, 5, 28, 12);
  return CodingProject(
    id: id,
    name: name,
    rootPath: '/tmp/$name',
    createdAt: now,
    updatedAt: now,
  );
}

Conversation _conversation({
  required String id,
  required String title,
  required WorkspaceMode workspaceMode,
  String projectId = '',
  int minutesAgo = 0,
}) {
  final now = DateTime(2026, 5, 28, 12).subtract(Duration(minutes: minutesAgo));
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
