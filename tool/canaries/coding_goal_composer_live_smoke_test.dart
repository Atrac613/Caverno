import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/tool_result_artifact_store.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_suggestion_service.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/routines/presentation/providers/routine_scheduler.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

class _LiveSmokeEnv {
  const _LiveSmokeEnv({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  static bool get enabled =>
      Platform.environment['CAVERNO_CODING_GOAL_COMPOSER_LIVE_SMOKE'] == '1';

  static _LiveSmokeEnv fromEnvironment() {
    return _LiveSmokeEnv(
      baseUrl: _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: _requiredEnv('CAVERNO_LLM_MODEL'),
    );
  }

  static String _requiredEnv(String name) {
    final value = Platform.environment[name]?.trim();
    if (value == null || value.isEmpty) {
      throw StateError('$name is required for coding goal composer smoke.');
    }
    return value;
  }
}

class _LiveSmokeSettingsNotifier extends SettingsNotifier {
  _LiveSmokeSettingsNotifier({required this.env, this.baseUrlOverride});

  final _LiveSmokeEnv env;
  final String? baseUrlOverride;

  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      baseUrl: baseUrlOverride ?? env.baseUrl,
      apiKey: env.apiKey,
      model: env.model,
      assistantMode: AssistantMode.coding,
      demoMode: false,
      mcpEnabled: false,
    );
  }
}

class _LiveSmokeConversationsNotifier extends ConversationsNotifier {
  _LiveSmokeConversationsNotifier(this._conversation);

  final Conversation _conversation;
  final savedObjectives = <String>[];
  int saveCount = 0;

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
    bool? autoContinue,
    int tokenBudget = 0,
    int turnBudget = 0,
    String? blockedReason,
    String? completionSummary,
  }) async {
    final conversation = state.currentConversation;
    if (conversation == null) {
      return;
    }

    saveCount += 1;
    final now = DateTime.now();
    final goal = ConversationGoal(
      id: 'live-goal-$saveCount',
      objective: objective.trim(),
      enabled: enabled,
      autoContinue: autoContinue ?? false,
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

class _LiveSmokeCodingProjectsNotifier extends CodingProjectsNotifier {
  _LiveSmokeCodingProjectsNotifier(this._project);

  final CodingProject _project;

  @override
  CodingProjectsState build() {
    return CodingProjectsState(
      projects: [_project],
      selectedProjectId: _project.id,
    );
  }
}

class _LiveSmokeChatNotifier extends ChatNotifier {
  _LiveSmokeChatNotifier({this.suggestionDelay = Duration.zero});

  final Duration suggestionDelay;
  final sentMessages = <String>[];
  final pendingMessagesForSuggestion = <String?>[];
  final clarificationQuestionsForSuggestion = <String?>[];
  final clarificationAnswersForSuggestion = <String?>[];
  int suggestionCallCount = 0;
  String? goalObjectiveAtSend;

  @override
  Future<ConversationGoalSuggestion> suggestCurrentGoal({
    String languageCode = 'en',
    String? pendingUserMessage,
    String? clarificationQuestion,
    String? clarificationAnswer,
  }) async {
    suggestionCallCount += 1;
    pendingMessagesForSuggestion.add(pendingUserMessage);
    clarificationQuestionsForSuggestion.add(clarificationQuestion);
    clarificationAnswersForSuggestion.add(clarificationAnswer);
    if (suggestionDelay > Duration.zero) {
      await Future<void>.delayed(suggestionDelay);
    }
    return super.suggestCurrentGoal(
      languageCode: languageCode,
      pendingUserMessage: pendingUserMessage,
      clarificationQuestion: clarificationQuestion,
      clarificationAnswer: clarificationAnswer,
    );
  }

  @override
  Future<void> sendMessage(
    String content, {
    String? imageBase64,
    String? imageMimeType,
    String? originalImagePath,
    String? originalImageMimeType,
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

class _LiveSmokeHarness {
  _LiveSmokeHarness({
    required this.container,
    required this.tempDir,
    required this.memoryBox,
    required this.conversations,
    required this.chat,
  });

  final ProviderContainer container;
  final Directory tempDir;
  final Box<String> memoryBox;
  final _LiveSmokeConversationsNotifier conversations;
  final _LiveSmokeChatNotifier chat;

  Future<void> dispose() async {
    container.dispose();
    if (memoryBox.isOpen) {
      await memoryBox.close();
    }
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  }
}

bool _hiveInitialized = false;

Future<_LiveSmokeHarness> _pumpLiveSmokeHarness(
  WidgetTester tester,
  _LiveSmokeEnv env, {
  String? baseUrlOverride,
  Duration suggestionDelay = Duration.zero,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1150, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final tempDir = await Directory.systemTemp.createTemp(
    'caverno_goal_composer_live_smoke_',
  );
  if (!_hiveInitialized) {
    Hive.init(tempDir.path);
    _hiveInitialized = true;
  }
  final memoryBox = await Hive.openBox<String>(
    'memory_${DateTime.now().microsecondsSinceEpoch}',
  );

  final now = DateTime.now();
  final project = CodingProject(
    id: 'project-1',
    name: 'caverno',
    rootPath: tempDir.path,
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

  final conversations = _LiveSmokeConversationsNotifier(conversation);
  final chat = _LiveSmokeChatNotifier(suggestionDelay: suggestionDelay);

  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      chatMemoryBoxProvider.overrideWithValue(memoryBox),
      toolResultArtifactStoreProvider.overrideWithValue(
        ToolResultArtifactStore(baseDirectory: tempDir),
      ),
      settingsNotifierProvider.overrideWith(
        () => _LiveSmokeSettingsNotifier(
          env: env,
          baseUrlOverride: baseUrlOverride,
        ),
      ),
      conversationsNotifierProvider.overrideWith(() => conversations),
      codingProjectsNotifierProvider.overrideWith(
        () => _LiveSmokeCodingProjectsNotifier(project),
      ),
      mcpToolServiceProvider.overrideWithValue(null),
      chatNotifierProvider.overrideWith(() => chat),
      routineSchedulerProvider.overrideWith(RoutineSchedulerController.new),
    ],
  );

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
  await tester.pump();

  final harness = _LiveSmokeHarness(
    container: container,
    tempDir: tempDir,
    memoryBox: memoryBox,
    conversations: conversations,
    chat: chat,
  );
  addTearDown(harness.dispose);
  return harness;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 45),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump();
    if (predicate()) {
      return;
    }
    await tester.runAsync(() => Future<void>.delayed(step));
  }
  await tester.pump();
  if (predicate()) {
    return;
  }
  fail('Timed out waiting for live smoke condition.');
}

TextField _composerTextField(WidgetTester tester) {
  return tester.widget<TextField>(find.byType(TextField).last);
}

Finder _sendButton() {
  return find.widgetWithIcon(IconButton, Icons.send);
}

Future<void> _pressSend(WidgetTester tester) async {
  final button = tester.widget<IconButton>(_sendButton());
  expect(button.onPressed, isNotNull);
  button.onPressed!();
  await tester.pump();
}

Future<void> _tryPressSend(WidgetTester tester) async {
  final matches = _sendButton().evaluate();
  if (matches.isEmpty) {
    return;
  }
  tester.widget<IconButton>(_sendButton()).onPressed?.call();
  await tester.pump();
}

Future<void> _pressUseAnswer(WidgetTester tester) async {
  final buttonFinder = find.ancestor(
    of: find.text('Use answer'),
    matching: find.byType(FilledButton),
  );
  final button = tester.widget<FilledButton>(buttonFinder);
  expect(button.onPressed, isNotNull);
  button.onPressed!();
  await tester.pump();
}

void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  final skipLiveSmoke = !_LiveSmokeEnv.enabled;

  testWidgets(
    'empty composer defers goal setup until the next non-empty send',
    skip: skipLiveSmoke,
    (tester) async {
      final env = _LiveSmokeEnv.fromEnvironment();
      final harness = await _pumpLiveSmokeHarness(tester, env);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(find.text('Goal setup pending'), findsOneWidget);
      expect(harness.chat.suggestionCallCount, 0);

      const message =
          'Add a concise release checklist section for the coding goal composer.';
      await tester.enterText(find.byType(TextField).last, message);
      await tester.pump();
      await _pressSend(tester);

      await _pumpUntil(
        tester,
        () =>
            harness.conversations.saveCount == 1 &&
            harness.chat.sentMessages.length == 1,
      );

      expect(harness.chat.suggestionCallCount, 1);
      expect(harness.chat.pendingMessagesForSuggestion.single, message);
      expect(harness.chat.sentMessages, [message]);
      expect(harness.chat.goalObjectiveAtSend, isNotNull);
      expect(harness.conversations.savedObjectives.single, isNotEmpty);
    },
  );

  testWidgets(
    'draft switch saves a live suggested goal without sending the message',
    skip: skipLiveSmoke,
    (tester) async {
      final env = _LiveSmokeEnv.fromEnvironment();
      final harness = await _pumpLiveSmokeHarness(tester, env);

      const draft =
          'Add a concise release checklist section for the coding goal composer.';
      await tester.enterText(find.byType(TextField).last, draft);
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();

      await _pumpUntil(tester, () => harness.conversations.saveCount == 1);

      expect(harness.chat.suggestionCallCount, 1);
      expect(harness.chat.pendingMessagesForSuggestion.single, draft);
      expect(harness.chat.sentMessages, isEmpty);
      expect(harness.conversations.savedObjectives.single, isNotEmpty);
      expect(find.text('Goal setup pending'), findsNothing);
    },
  );

  testWidgets(
    'ambiguous request opens clarification and applies the clarified goal',
    skip: skipLiveSmoke,
    (tester) async {
      final env = _LiveSmokeEnv.fromEnvironment();
      final harness = await _pumpLiveSmokeHarness(tester, env);

      const draft = 'Help me improve this project.';
      await tester.enterText(find.byType(TextField).last, draft);
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();

      await _pumpUntil(
        tester,
        () => find.text('Clarify goal').evaluate().isNotEmpty,
      );

      const clarification =
          'In Caverno, add a concise release checklist section to '
          'docs/coding_goal_composer_release_checklist.md for the composer '
          'goal switch.';
      await tester.enterText(find.byType(TextField).last, clarification);
      await tester.pump();
      await _pressUseAnswer(tester);

      await _pumpUntil(tester, () => harness.conversations.saveCount == 1);

      expect(harness.chat.suggestionCallCount, 2);
      expect(harness.chat.pendingMessagesForSuggestion, [draft, draft]);
      expect(
        harness.chat.clarificationAnswersForSuggestion.last,
        clarification,
      );
      expect(harness.chat.sentMessages, isEmpty);
      expect(harness.conversations.savedObjectives.single, isNotEmpty);
    },
  );

  testWidgets(
    'repeated ambiguity asks twice and then falls back to the snackbar',
    skip: skipLiveSmoke,
    (tester) async {
      final env = _LiveSmokeEnv.fromEnvironment();
      final harness = await _pumpLiveSmokeHarness(tester, env);

      const draft = 'Help me improve this project.';
      await tester.enterText(find.byType(TextField).last, draft);
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();

      await _pumpUntil(
        tester,
        () => find.text('Clarify goal').evaluate().isNotEmpty,
      );

      const firstClarification = 'I am still not sure what outcome I want.';
      await tester.enterText(find.byType(TextField).last, firstClarification);
      await tester.pump();
      await _pressUseAnswer(tester);

      await _pumpUntil(
        tester,
        () =>
            harness.chat.suggestionCallCount >= 2 &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty &&
            find.text('Clarify goal').evaluate().isNotEmpty,
      );

      const secondClarification =
          'I still cannot choose a concrete coding outcome.';
      await tester.enterText(find.byType(TextField).last, secondClarification);
      await tester.pump();
      await _pressUseAnswer(tester);

      await _pumpUntil(
        tester,
        () => find.textContaining('Goal needs clarity').evaluate().isNotEmpty,
      );

      expect(harness.chat.suggestionCallCount, 3);
      expect(harness.conversations.savedObjectives, isEmpty);
      expect(harness.chat.sentMessages, isEmpty);
    },
  );

  testWidgets(
    'offline endpoint preserves the pending message draft without duplicates',
    skip: skipLiveSmoke,
    (tester) async {
      final env = _LiveSmokeEnv.fromEnvironment();
      final harness = await _pumpLiveSmokeHarness(
        tester,
        env,
        baseUrlOverride: 'http://127.0.0.1:9/v1',
      );

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(find.text('Goal setup pending'), findsOneWidget);

      const message =
          'Add a concise release checklist section for the coding goal composer.';
      await tester.enterText(find.byType(TextField).last, message);
      await tester.pump();
      await _pressSend(tester);

      await _pumpUntil(
        tester,
        () => find.text('Clarify goal').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      await _pumpUntil(
        tester,
        () => _composerTextField(tester).controller?.text == message,
      );

      expect(harness.chat.suggestionCallCount, 1);
      expect(harness.conversations.savedObjectives, isEmpty);
      expect(harness.chat.sentMessages, isEmpty);
      expect(find.text('Goal setup pending'), findsOneWidget);
    },
  );

  testWidgets(
    'rapid switch and send taps during suggestion do not duplicate work',
    skip: skipLiveSmoke,
    (tester) async {
      final env = _LiveSmokeEnv.fromEnvironment();
      final harness = await _pumpLiveSmokeHarness(
        tester,
        env,
        suggestionDelay: const Duration(seconds: 2),
      );

      await tester.tap(find.byType(Switch));
      await tester.pump();

      const message =
          'Add a concise release checklist section for the coding goal composer.';
      await tester.enterText(find.byType(TextField).last, message);
      await tester.pump();
      await _pressSend(tester);

      expect(harness.chat.suggestionCallCount, 1);

      await tester.tap(find.byType(Switch), warnIfMissed: false);
      await _tryPressSend(tester);
      await _tryPressSend(tester);
      await tester.pump();

      expect(harness.chat.suggestionCallCount, 1);
      expect(harness.conversations.saveCount, 0);
      expect(harness.chat.sentMessages, isEmpty);

      await _pumpUntil(
        tester,
        () =>
            harness.conversations.saveCount == 1 &&
            harness.chat.sentMessages.length == 1,
      );

      expect(harness.chat.suggestionCallCount, 1);
      expect(harness.conversations.saveCount, 1);
      expect(harness.chat.sentMessages, [message]);
    },
  );
}
