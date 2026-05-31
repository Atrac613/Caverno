import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
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

class _SlashSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      demoMode: false,
      mcpEnabled: false,
    );
  }
}

class _SlashChatNotifier extends ChatNotifier {
  _SlashChatNotifier({this.initialLoading = false});

  final bool initialLoading;
  int cancelCount = 0;
  int clearCount = 0;

  @override
  ChatState build() {
    return ChatState.initial().copyWith(isLoading: initialLoading);
  }

  @override
  void cancelStreaming() {
    cancelCount += 1;
    state = state.copyWith(isLoading: false);
  }

  @override
  void clearMessages() {
    clearCount += 1;
    state = ChatState.initial();
  }
}

class _SlashConversationsNotifier extends ConversationsNotifier {
  _SlashConversationsNotifier({required this.initialState});

  final ConversationsState initialState;
  int createCount = 0;
  int clearPersistCount = 0;
  int enterPlanCount = 0;

  @override
  ConversationsState build() => initialState;

  @override
  void createNewConversation({
    WorkspaceMode? workspaceMode,
    String? projectId,
  }) {
    createCount += 1;
    final resolvedWorkspace = workspaceMode ?? state.activeWorkspaceMode;
    final conversation = Conversation(
      id: 'created-$createCount',
      title: 'Created $createCount',
      messages: const <Message>[],
      createdAt: DateTime(2026, 5, 31, 10, createCount),
      updatedAt: DateTime(2026, 5, 31, 10, createCount),
      workspaceMode: resolvedWorkspace,
      projectId: projectId ?? '',
    );
    state = state.copyWith(
      conversations: [conversation, ...state.conversations],
      currentConversationId: conversation.id,
      activeWorkspaceMode: resolvedWorkspace,
      activeProjectId: projectId,
      clearActiveProject: projectId == null,
    );
  }

  @override
  Future<void> updateCurrentConversation(List<Message> messages) async {
    clearPersistCount += messages.isEmpty ? 1 : 0;
    final current = state.currentConversation;
    if (current == null) return;
    final updated = current.copyWith(messages: messages);
    state = state.copyWith(
      conversations: state.conversations
          .map(
            (conversation) =>
                conversation.id == updated.id ? updated : conversation,
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> enterPlanningSession() async {
    enterPlanCount += 1;
    final current = state.currentConversation;
    if (current == null) return;
    final updated = current.copyWith(
      executionMode: ConversationExecutionMode.planning,
    );
    state = state.copyWith(
      conversations: state.conversations
          .map(
            (conversation) =>
                conversation.id == updated.id ? updated : conversation,
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> ensureCurrentPlanArtifactBackfilled() async {}
}

class _SlashCodingProjectsNotifier extends CodingProjectsNotifier {
  _SlashCodingProjectsNotifier([this.project]);

  final CodingProject? project;

  @override
  CodingProjectsState build() {
    final project = this.project;
    if (project == null) return CodingProjectsState.initial();
    return CodingProjectsState(
      projects: [project],
      selectedProjectId: project.id,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  tearDown(() {
    debugRemoteCodingMobilePlatformOverride = null;
  });

  testWidgets('/new creates a new conversation', (tester) async {
    final conversation = _chatConversation(messages: const <Message>[]);
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.chat,
        activeProjectId: null,
      ),
    );
    final chatNotifier = _SlashChatNotifier();
    final container = await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
    );

    await _submitComposerText(tester, '/new');

    expect(conversationsNotifier.createCount, 1);
    expect(
      container.read(conversationsNotifierProvider).currentConversationId,
      'created-1',
    );
  });

  testWidgets('/clear clears and persists current messages', (tester) async {
    final conversation = _chatConversation(
      messages: [
        Message(
          id: 'message-1',
          content: 'Keep this until clear',
          role: MessageRole.user,
          timestamp: DateTime(2026, 5, 31, 10),
        ),
      ],
    );
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.chat,
        activeProjectId: null,
      ),
    );
    final chatNotifier = _SlashChatNotifier();
    final container = await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
    );

    await _submitComposerText(tester, '/clear');

    expect(chatNotifier.clearCount, 1);
    expect(conversationsNotifier.clearPersistCount, 1);
    expect(
      container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.messages,
      isEmpty,
    );
  });

  testWidgets('/plan enters planning for a coding thread', (tester) async {
    debugRemoteCodingMobilePlatformOverride = () => false;
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/tmp/project',
      createdAt: DateTime(2026, 5, 31, 10),
      updatedAt: DateTime(2026, 5, 31, 10),
    );
    final conversation = _chatConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
      messages: const <Message>[],
    );
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.coding,
        activeProjectId: project.id,
      ),
    );
    final chatNotifier = _SlashChatNotifier();
    final container = await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
      codingProjectsNotifier: _SlashCodingProjectsNotifier(project),
    );

    await _submitComposerText(tester, '/plan');

    expect(conversationsNotifier.enterPlanCount, 1);
    expect(
      container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.isPlanningSession,
      isTrue,
    );
  });

  testWidgets('/cancel cancels an active response', (tester) async {
    final conversation = _chatConversation(messages: const <Message>[]);
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.chat,
        activeProjectId: null,
      ),
    );
    final chatNotifier = _SlashChatNotifier(initialLoading: true);
    await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
    );

    await _submitComposerText(tester, '/cancel');

    expect(chatNotifier.cancelCount, 1);
  });
}

Conversation _chatConversation({
  WorkspaceMode workspaceMode = WorkspaceMode.chat,
  String? projectId,
  required List<Message> messages,
}) {
  return Conversation(
    id: 'conversation-1',
    title: 'Conversation',
    messages: messages,
    createdAt: DateTime(2026, 5, 31, 10),
    updatedAt: DateTime(2026, 5, 31, 10),
    workspaceMode: workspaceMode,
    projectId: projectId ?? '',
  );
}

Future<ProviderContainer> _pumpSlashChatPage(
  WidgetTester tester, {
  required _SlashConversationsNotifier conversationsNotifier,
  required _SlashChatNotifier chatNotifier,
  _SlashCodingProjectsNotifier? codingProjectsNotifier,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      settingsNotifierProvider.overrideWith(_SlashSettingsNotifier.new),
      conversationsNotifierProvider.overrideWith(() => conversationsNotifier),
      codingProjectsNotifierProvider.overrideWith(
        () => codingProjectsNotifier ?? _SlashCodingProjectsNotifier(),
      ),
      chatNotifierProvider.overrideWith(() => chatNotifier),
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
  return container;
}

Future<void> _submitComposerText(WidgetTester tester, String text) async {
  await tester.tap(find.byType(TextField));
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}
