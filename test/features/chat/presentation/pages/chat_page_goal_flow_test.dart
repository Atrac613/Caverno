import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_suggestion_service.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/routines/presentation/providers/routine_scheduler.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final fallbackFile = File('$path/${locale.languageCode}.json');
    return jsonDecode(fallbackFile.readAsStringSync()) as Map<String, dynamic>;
  }
}

class _GoalFlowSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.coding,
      demoMode: false,
      mcpEnabled: false,
    );
  }
}

class _GoalFlowConversationsNotifier extends ConversationsNotifier {
  _GoalFlowConversationsNotifier(this._conversation);

  final Conversation _conversation;
  final savedObjectives = <String>[];

  @override
  ConversationsState build() {
    return ConversationsState(
      conversations: [_conversation],
      currentConversationId: _conversation.id,
      activeWorkspaceMode: WorkspaceMode.coding,
      activeProjectId: _conversation.projectId,
    );
  }

  @override
  Future<void> saveCurrentGoal({
    required String objective,
    required bool enabled,
    required ConversationGoalStatus status,
    int tokenBudget = 0,
    int turnBudget = 0,
    String? blockedReason,
    String? completionSummary,
  }) async {
    final conversation = state.currentConversation;
    if (conversation == null) {
      return;
    }
    final now = DateTime(2026, 5, 31, 12);
    final goal = ConversationGoal(
      id: 'goal-1',
      objective: objective.trim(),
      enabled: enabled,
      status: status,
      tokenBudget: tokenBudget,
      turnBudget: turnBudget,
      createdAt: now,
      updatedAt: now,
    );
    savedObjectives.add(goal.objective);
    final updated = conversation.copyWith(goal: goal, updatedAt: now);
    state = state.copyWith(
      conversations: [
        for (final item in state.conversations)
          if (item.id == updated.id) updated else item,
      ],
    );
  }
}

class _GoalFlowCodingProjectsNotifier extends CodingProjectsNotifier {
  _GoalFlowCodingProjectsNotifier(this._project);

  final CodingProject _project;

  @override
  CodingProjectsState build() {
    return CodingProjectsState(
      projects: [_project],
      selectedProjectId: _project.id,
    );
  }
}

class _GoalFlowChatNotifier extends ChatNotifier {
  _GoalFlowChatNotifier({
    List<ConversationGoalSuggestion> suggestions = const [
      ConversationGoalSuggestion.suggested('Ship implicit composer goals'),
    ],
    Object? suggestionError,
    Completer<void>? suggestionGate,
  }) : _suggestions = suggestions,
       _suggestionError = suggestionError,
       _suggestionGate = suggestionGate;

  final List<ConversationGoalSuggestion> _suggestions;
  final Object? _suggestionError;
  final Completer<void>? _suggestionGate;
  int _suggestionIndex = 0;
  int suggestionCallCount = 0;
  String? pendingUserMessageForSuggestion;
  String? clarificationQuestionForSuggestion;
  String? clarificationAnswerForSuggestion;
  final sentMessages = <String>[];
  String? goalObjectiveAtSend;

  @override
  ChatState build() => ChatState.initial();

  @override
  Future<ConversationGoalSuggestion> suggestCurrentGoal({
    String languageCode = 'en',
    String? pendingUserMessage,
    String? clarificationQuestion,
    String? clarificationAnswer,
  }) async {
    suggestionCallCount += 1;
    pendingUserMessageForSuggestion = pendingUserMessage;
    clarificationQuestionForSuggestion = clarificationQuestion;
    clarificationAnswerForSuggestion = clarificationAnswer;
    final suggestionGate = _suggestionGate;
    if (suggestionGate != null) {
      await suggestionGate.future;
    }
    final suggestionError = _suggestionError;
    if (suggestionError != null) {
      throw suggestionError;
    }
    final index = _suggestionIndex;
    if (_suggestionIndex < _suggestions.length - 1) {
      _suggestionIndex++;
    }
    final safeIndex = index >= _suggestions.length
        ? _suggestions.length - 1
        : index;
    return _suggestions[safeIndex];
  }

  @override
  Future<void> sendMessage(
    String content, {
    String? imageBase64,
    String? imageMimeType,
    String languageCode = 'en',
    bool isVoiceMode = false,
    bool bypassPlanMode = false,
    ChatInteractionOrigin origin = ChatInteractionOrigin.local,
  }) async {
    sentMessages.add(content);
    goalObjectiveAtSend = ref
        .read(conversationsNotifierProvider)
        .currentConversation
        ?.goal
        ?.normalizedObjective;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('applies a pending suggested goal before sending the message', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1150, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final now = DateTime(2026, 5, 31, 10);
    final project = CodingProject(
      id: 'project-1',
      name: 'example_app',
      rootPath: Directory.systemTemp.path,
      createdAt: now,
      updatedAt: now,
    );
    final conversation = Conversation(
      id: 'thread-1',
      title: 'Goal flow thread',
      messages: const [],
      createdAt: now,
      updatedAt: now,
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
    );
    final conversationsNotifier = _GoalFlowConversationsNotifier(conversation);
    final chatNotifier = _GoalFlowChatNotifier();

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        settingsNotifierProvider.overrideWith(_GoalFlowSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(() => conversationsNotifier),
        codingProjectsNotifierProvider.overrideWith(
          () => _GoalFlowCodingProjectsNotifier(project),
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

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.text('Goal setup pending'), findsOneWidget);

    const message = 'Build the implicit goal flow';
    await tester.enterText(find.byType(TextField).last, message);
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(chatNotifier.pendingUserMessageForSuggestion, message);
    expect(conversationsNotifier.savedObjectives, [
      'Ship implicit composer goals',
    ]);
    expect(chatNotifier.sentMessages, [message]);
    expect(chatNotifier.goalObjectiveAtSend, 'Ship implicit composer goals');
    expect(find.text('Edit goal'), findsNothing);
    expect(find.textContaining('Ship implicit composer goals'), findsWidgets);
  });

  testWidgets('uses the current draft when enabling goal setup immediately', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1150, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final now = DateTime(2026, 5, 31, 10);
    final project = CodingProject(
      id: 'project-1',
      name: 'example_app',
      rootPath: Directory.systemTemp.path,
      createdAt: now,
      updatedAt: now,
    );
    final conversation = Conversation(
      id: 'thread-1',
      title: 'Goal flow thread',
      messages: const [],
      createdAt: now,
      updatedAt: now,
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
    );
    final conversationsNotifier = _GoalFlowConversationsNotifier(conversation);
    final chatNotifier = _GoalFlowChatNotifier();

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        settingsNotifierProvider.overrideWith(_GoalFlowSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(() => conversationsNotifier),
        codingProjectsNotifierProvider.overrideWith(
          () => _GoalFlowCodingProjectsNotifier(project),
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

    const message = 'Build the implicit goal flow';
    await tester.enterText(find.byType(TextField).last, message);
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(chatNotifier.pendingUserMessageForSuggestion, message);
    expect(conversationsNotifier.savedObjectives, [
      'Ship implicit composer goals',
    ]);
    expect(chatNotifier.sentMessages, isEmpty);
    expect(find.text('Goal setup pending'), findsNothing);
    expect(find.textContaining('Ship implicit composer goals'), findsWidgets);
  });

  testWidgets('blocks duplicate goal setup while suggestion is in progress', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1150, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final now = DateTime(2026, 5, 31, 10);
    final project = CodingProject(
      id: 'project-1',
      name: 'example_app',
      rootPath: Directory.systemTemp.path,
      createdAt: now,
      updatedAt: now,
    );
    final conversation = Conversation(
      id: 'thread-1',
      title: 'Goal flow thread',
      messages: const [],
      createdAt: now,
      updatedAt: now,
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
    );
    final conversationsNotifier = _GoalFlowConversationsNotifier(conversation);
    final suggestionGate = Completer<void>();
    final chatNotifier = _GoalFlowChatNotifier(suggestionGate: suggestionGate);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        settingsNotifierProvider.overrideWith(_GoalFlowSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(() => conversationsNotifier),
        codingProjectsNotifierProvider.overrideWith(
          () => _GoalFlowCodingProjectsNotifier(project),
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

    const message = 'Build the duplicate goal setup guard';
    await tester.enterText(find.byType(TextField).last, message);
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(chatNotifier.suggestionCallCount, 1);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byType(Switch), warnIfMissed: false);
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.send),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(chatNotifier.suggestionCallCount, 1);
    expect(chatNotifier.sentMessages, isEmpty);
    expect(conversationsNotifier.savedObjectives, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller?.text,
      message,
    );

    suggestionGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(chatNotifier.suggestionCallCount, 1);
    expect(conversationsNotifier.savedObjectives, [
      'Ship implicit composer goals',
    ]);
    expect(chatNotifier.sentMessages, isEmpty);
    expect(find.textContaining('Ship implicit composer goals'), findsWidgets);
  });

  testWidgets('asks for clarification before applying an ambiguous goal', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1150, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final now = DateTime(2026, 5, 31, 10);
    final project = CodingProject(
      id: 'project-1',
      name: 'example_app',
      rootPath: Directory.systemTemp.path,
      createdAt: now,
      updatedAt: now,
    );
    final conversation = Conversation(
      id: 'thread-1',
      title: 'Goal flow thread',
      messages: const [],
      createdAt: now,
      updatedAt: now,
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
    );
    final conversationsNotifier = _GoalFlowConversationsNotifier(conversation);
    final chatNotifier = _GoalFlowChatNotifier(
      suggestions: const [
        ConversationGoalSuggestion.needsClarification(
          'Should this create a Markdown report file?',
        ),
        ConversationGoalSuggestion.suggested('Save Tokyo weather as Markdown'),
      ],
    );

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        settingsNotifierProvider.overrideWith(_GoalFlowSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(() => conversationsNotifier),
        codingProjectsNotifierProvider.overrideWith(
          () => _GoalFlowCodingProjectsNotifier(project),
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

    await tester.tap(find.byType(Switch));
    await tester.pump();

    const message = 'Check Tokyo weather tomorrow and save Markdown';
    await tester.enterText(find.byType(TextField).last, message);
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(find.text('Clarify goal'), findsOneWidget);
    expect(
      find.text('Should this create a Markdown report file?'),
      findsOneWidget,
    );

    const clarification = 'Yes, save the result as a Markdown report file.';
    await tester.enterText(find.byType(TextField).last, clarification);
    await tester.pump();
    await tester.tap(find.text('Use answer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(chatNotifier.pendingUserMessageForSuggestion, message);
    expect(
      chatNotifier.clarificationQuestionForSuggestion,
      'Should this create a Markdown report file?',
    );
    expect(chatNotifier.clarificationAnswerForSuggestion, clarification);
    expect(conversationsNotifier.savedObjectives, [
      'Save Tokyo weather as Markdown',
    ]);
    expect(chatNotifier.sentMessages, [message]);
    expect(chatNotifier.goalObjectiveAtSend, 'Save Tokyo weather as Markdown');
    expect(find.textContaining('Save Tokyo weather as Markdown'), findsWidgets);
  });

  testWidgets(
    'asks a second clarification when the first answer is ambiguous',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1150, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime(2026, 5, 31, 10);
      final project = CodingProject(
        id: 'project-1',
        name: 'example_app',
        rootPath: Directory.systemTemp.path,
        createdAt: now,
        updatedAt: now,
      );
      final conversation = Conversation(
        id: 'thread-1',
        title: 'Goal flow thread',
        messages: const [],
        createdAt: now,
        updatedAt: now,
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
      );
      final conversationsNotifier = _GoalFlowConversationsNotifier(
        conversation,
      );
      final chatNotifier = _GoalFlowChatNotifier(
        suggestions: const [
          ConversationGoalSuggestion.needsClarification(
            'Should this create a saved report?',
          ),
          ConversationGoalSuggestion.needsClarification(
            'Which report format should be saved?',
          ),
          ConversationGoalSuggestion.suggested(
            'Save Tokyo weather as a Markdown report',
          ),
        ],
      );

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          settingsNotifierProvider.overrideWith(_GoalFlowSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            () => conversationsNotifier,
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _GoalFlowCodingProjectsNotifier(project),
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

      await tester.tap(find.byType(Switch));
      await tester.pump();

      const message = 'Check Tokyo weather tomorrow and save a report';
      await tester.enterText(find.byType(TextField).last, message);
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      expect(find.text('Should this create a saved report?'), findsOneWidget);

      const firstClarification = 'Yes, save a report.';
      await tester.enterText(find.byType(TextField).last, firstClarification);
      await tester.pump();
      await tester.tap(find.text('Use answer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Which report format should be saved?'), findsOneWidget);

      const secondClarification = 'Use Markdown.';
      await tester.enterText(find.byType(TextField).last, secondClarification);
      await tester.pump();
      await tester.tap(find.text('Use answer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(chatNotifier.pendingUserMessageForSuggestion, message);
      expect(
        chatNotifier.clarificationQuestionForSuggestion,
        'Which report format should be saved?',
      );
      expect(
        chatNotifier.clarificationAnswerForSuggestion,
        secondClarification,
      );
      expect(conversationsNotifier.savedObjectives, [
        'Save Tokyo weather as a Markdown report',
      ]);
      expect(chatNotifier.sentMessages, [message]);
      expect(
        chatNotifier.goalObjectiveAtSend,
        'Save Tokyo weather as a Markdown report',
      );
    },
  );

  testWidgets('keeps a pending goal draft when clarification is cancelled', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1150, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final now = DateTime(2026, 5, 31, 10);
    final project = CodingProject(
      id: 'project-1',
      name: 'example_app',
      rootPath: Directory.systemTemp.path,
      createdAt: now,
      updatedAt: now,
    );
    final conversation = Conversation(
      id: 'thread-1',
      title: 'Goal flow thread',
      messages: const [],
      createdAt: now,
      updatedAt: now,
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
    );
    final conversationsNotifier = _GoalFlowConversationsNotifier(conversation);
    final chatNotifier = _GoalFlowChatNotifier(
      suggestions: const [
        ConversationGoalSuggestion.needsClarification(
          'Should this create a Markdown report file?',
        ),
      ],
    );

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        settingsNotifierProvider.overrideWith(_GoalFlowSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(() => conversationsNotifier),
        codingProjectsNotifierProvider.overrideWith(
          () => _GoalFlowCodingProjectsNotifier(project),
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

    await tester.tap(find.byType(Switch));
    await tester.pump();

    const message = 'Check Tokyo weather tomorrow and save Markdown';
    await tester.enterText(find.byType(TextField).last, message);
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(find.text('Clarify goal'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(conversationsNotifier.savedObjectives, isEmpty);
    expect(chatNotifier.sentMessages, isEmpty);
    expect(find.text('Goal setup pending'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller?.text,
      message,
    );
  });

  testWidgets('keeps a pending goal draft when suggestion fails', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1150, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final now = DateTime(2026, 5, 31, 10);
    final project = CodingProject(
      id: 'project-1',
      name: 'example_app',
      rootPath: Directory.systemTemp.path,
      createdAt: now,
      updatedAt: now,
    );
    final conversation = Conversation(
      id: 'thread-1',
      title: 'Goal flow thread',
      messages: const [],
      createdAt: now,
      updatedAt: now,
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
    );
    final conversationsNotifier = _GoalFlowConversationsNotifier(conversation);
    final chatNotifier = _GoalFlowChatNotifier(
      suggestionError: Exception('LLM unavailable'),
    );

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        settingsNotifierProvider.overrideWith(_GoalFlowSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(() => conversationsNotifier),
        codingProjectsNotifierProvider.overrideWith(
          () => _GoalFlowCodingProjectsNotifier(project),
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

    await tester.tap(find.byType(Switch));
    await tester.pump();

    const message = 'Check Tokyo weather tomorrow and save Markdown';
    await tester.enterText(find.byType(TextField).last, message);
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text(
        'Could not draft a goal. Your message was kept so you can retry or set the goal manually.',
      ),
      findsOneWidget,
    );
    expect(chatNotifier.pendingUserMessageForSuggestion, message);
    expect(conversationsNotifier.savedObjectives, isEmpty);
    expect(chatNotifier.sentMessages, isEmpty);
    expect(find.text('Goal setup pending'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller?.text,
      message,
    );
  });
}
