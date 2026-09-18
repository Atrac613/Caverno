part of 'chat_presentation_pages_tiny_test.dart';

class _TestTranslationLoaderChatPageThreadOpenScroll extends AssetLoader {
  const _TestTranslationLoaderChatPageThreadOpenScroll();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final fallbackFile = File('$path/${locale.languageCode}.json');
    return jsonDecode(fallbackFile.readAsStringSync()) as Map<String, dynamic>;
  }
}

class _ChatSettingsNotifierChatPageThreadOpenScroll extends SettingsNotifier {
  _ChatSettingsNotifierChatPageThreadOpenScroll(this._settings);

  final AppSettings _settings;

  @override
  AppSettings build() => _settings;
}

class _SwitchableConversationsNotifier extends ConversationsNotifier {
  _SwitchableConversationsNotifier(this._conversations, this._initialId);

  final List<Conversation> _conversations;
  final String _initialId;

  @override
  ConversationsState build() {
    return ConversationsState(
      conversations: _conversations,
      currentConversationId: _initialId,
      activeWorkspaceMode: WorkspaceMode.chat,
      activeProjectId: null,
    );
  }

  void select(String id) {
    state = state.copyWith(currentConversationId: id);
  }
}

class _EmptyCodingProjectsNotifierChatPageThreadOpenScroll
    extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() {
    return const CodingProjectsState(projects: [], selectedProjectId: null);
  }
}

/// A [ChatNotifier] whose state the test drives directly, standing in for the
/// real notifier's `syncConversation` when a thread is switched.
class _ScriptedChatNotifierChatPageThreadOpenScroll extends ChatNotifier {
  _ScriptedChatNotifierChatPageThreadOpenScroll(this._initial);

  final ChatState _initial;

  @override
  ChatState build() => _initial;

  void emit(ChatState next) => state = next;
}

List<Message> _messagesChatPageThreadOpenScroll(String threadId, int count) {
  return List<Message>.generate(count, (index) {
    return Message(
      id: '$threadId-m$index',
      content: '$threadId message $index line one\nline two\nline three',
      role: index.isEven ? MessageRole.user : MessageRole.assistant,
      timestamp: DateTime(2026, 8, 22, 9, index % 60),
    );
  });
}

Conversation _conversation(String id, int messageCount) {
  final now = DateTime(2026, 8, 22, 9);
  return Conversation(
    id: id,
    title: 'Thread $id',
    messages: _messagesChatPageThreadOpenScroll(id, messageCount),
    createdAt: now,
    updatedAt: now,
    workspaceMode: WorkspaceMode.chat,
  );
}

void _runChatPageThreadOpenScroll() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets(
    'opening a thread jumps to its newest message, and reopening it within the '
    'session restores where it was left',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final threadA = _conversation('a', 40);
      final threadB = _conversation('b', 40);
      final settings = AppSettings.defaults().copyWith(
        demoMode: false,
        mcpEnabled: false,
      );
      final modelCatalogConfig = ModelListConfig(
        baseUrl: settings.baseUrl,
        apiKey: settings.apiKey,
        selectedModelId: settings.model,
      );

      final conversationsNotifier = _SwitchableConversationsNotifier([
        threadA,
        threadB,
      ], threadA.id);
      final chatNotifier = _ScriptedChatNotifierChatPageThreadOpenScroll(
        ChatState(messages: threadA.messages, isLoading: false),
      );

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          settingsNotifierProvider.overrideWith(
            () => _ChatSettingsNotifierChatPageThreadOpenScroll(settings),
          ),
          modelCatalogProvider(
            modelCatalogConfig,
          ).overrideWith((ref) async => const <ModelCatalogEntry>[]),
          conversationsNotifierProvider.overrideWith(
            () => conversationsNotifier,
          ),
          codingProjectsNotifierProvider.overrideWith(
            _EmptyCodingProjectsNotifierChatPageThreadOpenScroll.new,
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
          assetLoader: const _TestTranslationLoaderChatPageThreadOpenScroll(),
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

      final listFinder = find.byKey(const ValueKey('chat-message-list'));
      expect(listFinder, findsOneWidget);

      ScrollPosition position() {
        return tester.widget<ListView>(listFinder).controller!.position;
      }

      double distanceFromBottom() =>
          position().maxScrollExtent - position().pixels;

      void switchThread(Conversation conversation) {
        // The real notifiers move together on a switch: `ChatNotifier` listens
        // to `ConversationsNotifier`, so the page never builds a half-switched
        // pair. Emit both before pumping to reproduce that.
        conversationsNotifier.select(conversation.id);
        chatNotifier.emit(
          ChatState(messages: conversation.messages, isLoading: false),
        );
      }

      // The very first build already lands on the newest message, even though
      // no `ref.listen` fired: the list is long enough to scroll.
      expect(position().maxScrollExtent, greaterThan(300));
      expect(distanceFromBottom(), lessThan(1));

      // Scroll up to read history, then leave for another thread.
      await tester.drag(listFinder, const Offset(0, 600));
      await tester.pumpAndSettle();
      final offsetInThreadA = position().pixels;
      expect(distanceFromBottom(), greaterThan(80));

      switchThread(threadB);
      await tester.pumpAndSettle();
      // First open of thread B: newest message again.
      expect(distanceFromBottom(), lessThan(1));

      switchThread(threadA);
      await tester.pumpAndSettle();
      // Second open of thread A: back where the user left it, not the bottom.
      expect(position().pixels, closeTo(offsetInThreadA, 1));
      expect(distanceFromBottom(), greaterThan(80));
    },
  );

  testWidgets(
    'a thread left at the bottom reopens at the new bottom after it grew',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final threadA = _conversation('a', 40);
      final threadB = _conversation('b', 40);
      final grownThreadA = threadA.copyWith(
        messages: _messagesChatPageThreadOpenScroll('a', 80),
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

      final conversationsNotifier = _SwitchableConversationsNotifier([
        threadA,
        threadB,
      ], threadA.id);
      final chatNotifier = _ScriptedChatNotifierChatPageThreadOpenScroll(
        ChatState(messages: threadA.messages, isLoading: false),
      );

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          settingsNotifierProvider.overrideWith(
            () => _ChatSettingsNotifierChatPageThreadOpenScroll(settings),
          ),
          modelCatalogProvider(
            modelCatalogConfig,
          ).overrideWith((ref) async => const <ModelCatalogEntry>[]),
          conversationsNotifierProvider.overrideWith(
            () => conversationsNotifier,
          ),
          codingProjectsNotifierProvider.overrideWith(
            _EmptyCodingProjectsNotifierChatPageThreadOpenScroll.new,
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
          assetLoader: const _TestTranslationLoaderChatPageThreadOpenScroll(),
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

      final listFinder = find.byKey(const ValueKey('chat-message-list'));
      ScrollPosition position() =>
          tester.widget<ListView>(listFinder).controller!.position;
      double distanceFromBottom() =>
          position().maxScrollExtent - position().pixels;

      expect(distanceFromBottom(), lessThan(1));
      final bottomOfThreadA = position().pixels;

      conversationsNotifier.select(threadB.id);
      chatNotifier.emit(
        ChatState(messages: threadB.messages, isLoading: false),
      );
      await tester.pumpAndSettle();

      // Thread A kept streaming while it was off screen, so its old bottom
      // offset now points into the middle of the history.
      conversationsNotifier.select(grownThreadA.id);
      chatNotifier.emit(
        ChatState(messages: grownThreadA.messages, isLoading: false),
      );
      await tester.pumpAndSettle();

      expect(position().maxScrollExtent, greaterThan(bottomOfThreadA));
      expect(distanceFromBottom(), lessThan(1));
    },
  );
}
