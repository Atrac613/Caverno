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
    final fallbackFile = File('$path/${locale.languageCode}.json');
    return jsonDecode(fallbackFile.readAsStringSync()) as Map<String, dynamic>;
  }
}

class _ChatSettingsNotifier extends SettingsNotifier {
  _ChatSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  AppSettings build() {
    return _settings;
  }
}

class _ChatConversationsNotifier extends ConversationsNotifier {
  _ChatConversationsNotifier(this._conversation);

  final Conversation _conversation;

  @override
  ConversationsState build() {
    return ConversationsState(
      conversations: [_conversation],
      currentConversationId: _conversation.id,
      activeWorkspaceMode: WorkspaceMode.chat,
      activeProjectId: null,
    );
  }
}

class _EmptyCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() {
    return const CodingProjectsState(projects: [], selectedProjectId: null);
  }
}

/// A [ChatNotifier] whose state the test drives directly to simulate the
/// streaming chat loop without a real LLM.
class _ScriptedChatNotifier extends ChatNotifier {
  _ScriptedChatNotifier(this._initial);

  final ChatState _initial;

  @override
  ChatState build() => _initial;

  void emit(ChatState next) => state = next;
}

List<Message> _messages(int count, {required String lastContent}) {
  return List<Message>.generate(count, (index) {
    final isLast = index == count - 1;
    return Message(
      id: 'm$index',
      content: isLast
          ? lastContent
          : 'Message $index line one\nline two\nline three',
      role: index.isEven ? MessageRole.user : MessageRole.assistant,
      timestamp: DateTime(2026, 5, 28, 9, index % 60),
      isStreaming: isLast && !lastContent.endsWith('done'),
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets(
    'auto-follows streaming, backs off after the user scrolls up, and '
    're-engages on a new message',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime(2026, 5, 28, 9);
      final conversation = Conversation(
        id: 'thread-1',
        title: 'Scroll thread',
        messages: const [],
        createdAt: now,
        updatedAt: now,
        workspaceMode: WorkspaceMode.chat,
      );
      final settings = AppSettings.defaults().copyWith(
        demoMode: false,
        mcpEnabled: false,
      );
      final modelCatalogConfig = ModelListConfig(
        baseUrl: settings.baseUrl,
        apiKey: settings.apiKey,
        selectedModelId: settings.model,
      );

      // Start with a short, non-scrollable list. `ref.listen` does not fire on
      // the first build, so the auto-scroll behavior is exercised by emitting
      // new states afterwards — exactly how the real chat loop drives it.
      final chatNotifier = _ScriptedChatNotifier(
        ChatState(
          messages: _messages(3, lastContent: 'Hello done'),
          isLoading: false,
        ),
      );

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          settingsNotifierProvider.overrideWith(
            () => _ChatSettingsNotifier(settings),
          ),
          modelCatalogProvider(
            modelCatalogConfig,
          ).overrideWith((ref) async => const <ModelCatalogEntry>[]),
          conversationsNotifierProvider.overrideWith(
            () => _ChatConversationsNotifier(conversation),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _EmptyCodingProjectsNotifier.new,
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

      final listFinder = find.byKey(const ValueKey('chat-message-list'));
      expect(listFinder, findsOneWidget);

      ScrollPosition position() {
        return tester.widget<ListView>(listFinder).controller!.position;
      }

      double distanceFromBottom() =>
          position().maxScrollExtent - position().pixels;

      // `pumpAndSettle` cannot be used while `isLoading` is true: the chat
      // loading indicator animates indefinitely. Advance several frames
      // explicitly so the listen -> post-frame -> scroll chain and the 220ms
      // scroll animation all complete.
      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      // Streaming a long answer grows the message list past the viewport; the
      // view follows the new content down to the bottom.
      chatNotifier.emit(
        ChatState(
          messages: _messages(20, lastContent: 'Streaming answer'),
          isLoading: true,
        ),
      );
      await settle();
      expect(position().maxScrollExtent, greaterThan(300));
      expect(distanceFromBottom(), lessThan(80));

      // A further streaming chunk keeps the view pinned to the bottom.
      chatNotifier.emit(
        ChatState(
          messages: _messages(
            20,
            lastContent: 'Streaming answer that keeps going\n' * 6,
          ),
          isLoading: true,
        ),
      );
      await settle();
      expect(distanceFromBottom(), lessThan(80));

      // The user scrolls up to read history; auto-follow must back off.
      await tester.drag(listFinder, const Offset(0, 400));
      await settle();
      expect(distanceFromBottom(), greaterThan(80));
      final afterDrag = position().pixels;

      // Further streaming must NOT yank the user back to the bottom.
      chatNotifier.emit(
        ChatState(
          messages: _messages(
            20,
            lastContent: 'Streaming answer that keeps going\n' * 12,
          ),
          isLoading: true,
        ),
      );
      await settle();
      expect(distanceFromBottom(), greaterThan(80));
      expect(position().pixels, closeTo(afterDrag, 1));

      // A brand-new message re-engages following and snaps to the bottom.
      chatNotifier.emit(
        ChatState(
          messages: _messages(21, lastContent: 'Second answer done'),
          isLoading: false,
        ),
      );
      await settle();
      expect(distanceFromBottom(), lessThan(80));
    },
  );
}
