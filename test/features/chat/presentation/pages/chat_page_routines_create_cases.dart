part of 'chat_presentation_pages_tiny_test.dart';

class _TestTranslationLoaderChatPageRoutinesCreate extends AssetLoader {
  const _TestTranslationLoaderChatPageRoutinesCreate();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

class _TestSettingsNotifierChatPageRoutinesCreate extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      demoMode: false,
      mcpEnabled: false,
    );
  }
}

class _RoutinesWorkspaceConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() {
    return ConversationsState.initial().copyWith(
      activeWorkspaceMode: WorkspaceMode.routines,
    );
  }
}

class _TestCodingProjectsNotifierChatPageRoutinesCreate
    extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _TestChatNotifierChatPageRoutinesCreate extends ChatNotifier {
  @override
  ChatState build() => ChatState.initial();
}

void _runChatPageRoutinesCreate() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('mobile routines home FAB opens the editor without overflow', (
    tester,
  ) async {
    await _pumpRoutinesWorkspace(tester, size: const Size(400, 800));

    // The read-only home dashboard relies on this FAB for creation because the
    // temporary drawer closes after switching into the routines workspace,
    // hiding its create button until the user reopens the drawer.
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byTooltip('New routine'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // The editor must render cleanly at phone width; an unbounded dropdown would
    // surface a RenderFlex overflow here and fail the test.
    expect(find.byType(RoutineEditorSheet), findsOneWidget);
  });

  testWidgets(
    'desktop routines workspace omits the FAB and keeps the drawer create button',
    (tester) async {
      await _pumpRoutinesWorkspace(tester, size: const Size(1200, 900));

      // The persistent drawer is always visible on wide layouts and provides its
      // own create button, so the floating action button would be redundant.
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(ConversationDrawer), findsOneWidget);
      expect(find.byTooltip('New routine'), findsOneWidget);
    },
  );
}

Future<void> _pumpRoutinesWorkspace(
  WidgetTester tester, {
  required Size size,
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
      settingsNotifierProvider.overrideWith(
        _TestSettingsNotifierChatPageRoutinesCreate.new,
      ),
      conversationsNotifierProvider.overrideWith(
        _RoutinesWorkspaceConversationsNotifier.new,
      ),
      codingProjectsNotifierProvider.overrideWith(
        _TestCodingProjectsNotifierChatPageRoutinesCreate.new,
      ),
      chatNotifierProvider.overrideWith(
        _TestChatNotifierChatPageRoutinesCreate.new,
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
      assetLoader: const _TestTranslationLoaderChatPageRoutinesCreate(),
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
}
