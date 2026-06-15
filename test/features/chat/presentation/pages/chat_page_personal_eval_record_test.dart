import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/personal_eval/presentation/pages/personal_eval_record_page.dart';
import 'package:caverno/features/routines/presentation/providers/routine_scheduler.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/model_catalog_entry.dart';
import 'package:caverno/features/settings/presentation/providers/model_list_provider.dart';
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
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

class _RecordSettingsNotifier extends SettingsNotifier {
  _RecordSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  AppSettings build() => _settings;
}

class _RecordConversationsNotifier extends ConversationsNotifier {
  _RecordConversationsNotifier(this._conversation);

  final Conversation _conversation;

  @override
  ConversationsState build() {
    return ConversationsState(
      conversations: [_conversation],
      currentConversationId: _conversation.id,
      activeWorkspaceMode: _conversation.workspaceMode,
      activeProjectId: null,
    );
  }
}

class _RecordCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _RecordChatNotifier extends ChatNotifier {
  _RecordChatNotifier(this._state);

  final ChatState _state;

  @override
  ChatState build() => _state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('opens the personal eval recorder for the current session', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final now = DateTime(2026, 6, 15, 10);
    final messages = [
      Message(
        id: 'u1',
        content: 'Fix the login crash',
        role: MessageRole.user,
        timestamp: now,
      ),
      Message(
        id: 'a1',
        content: 'I will inspect the failure.',
        role: MessageRole.assistant,
        timestamp: now.add(const Duration(minutes: 1)),
      ),
    ];
    final conversation = Conversation(
      id: 'session-42',
      title: 'Login crash investigation',
      messages: messages,
      createdAt: now,
      updatedAt: now,
      workspaceMode: WorkspaceMode.chat,
    );
    final settings = AppSettings.defaults().copyWith(
      demoMode: false,
      enableLlmSessionLogs: true,
      mcpEnabled: false,
    );
    final modelCatalogConfig = ModelListConfig(
      baseUrl: settings.baseUrl,
      apiKey: settings.apiKey,
      selectedModelId: settings.model,
    );

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        settingsNotifierProvider.overrideWith(
          () => _RecordSettingsNotifier(settings),
        ),
        modelCatalogProvider(
          modelCatalogConfig,
        ).overrideWith((ref) async => const <ModelCatalogEntry>[]),
        conversationsNotifierProvider.overrideWith(
          () => _RecordConversationsNotifier(conversation),
        ),
        codingProjectsNotifierProvider.overrideWith(
          _RecordCodingProjectsNotifier.new,
        ),
        chatNotifierProvider.overrideWith(
          () => _RecordChatNotifier(
            ChatState.initial().copyWith(messages: messages),
          ),
        ),
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

    await tester.tap(
      find.byKey(const ValueKey('record-personal-eval-case-action')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PersonalEvalRecordPage), findsOneWidget);
    final promptField = tester.widget<TextField>(
      find.byKey(const ValueKey('personal-eval-record-prompt')),
    );
    final titleField = tester.widget<TextField>(
      find.byKey(const ValueKey('personal-eval-record-title')),
    );
    expect(promptField.controller?.text, 'Fix the login crash');
    expect(titleField.controller?.text, 'Login crash investigation');
  });
}
