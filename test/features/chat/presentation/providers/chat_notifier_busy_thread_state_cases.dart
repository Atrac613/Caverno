part of 'chat_presentation_providers_tiny_test.dart';

class _MockBoxChatNotifierBusyThreadState extends Mock implements Box<String> {}

class _MockAppLifecycleServiceChatNotifierBusyThreadState extends Mock
    implements AppLifecycleService {}

class _TestBackgroundTaskServiceChatNotifierBusyThreadState
    extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}

  @override
  void dispose() {}
}

class _TestSessionMemoryServiceChatNotifierBusyThreadState
    extends SessionMemoryService {
  _TestSessionMemoryServiceChatNotifierBusyThreadState()
    : super(
        ChatMemoryRepository.fromBox(_MockBoxChatNotifierBusyThreadState()),
      );

  @override
  String? buildPromptContext({
    required String currentUserInput,
    required String currentConversationId,
    DateTime? now,
  }) => null;

  @override
  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
  }) async => const MemoryUpdateResult.none();

  @override
  UserMemoryProfile loadProfile() => UserMemoryProfile.empty();
}

class _TestCodingProjectsNotifierChatNotifierBusyThreadState
    extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _TestSettingsNotifierChatNotifierBusyThreadState
    extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    enableLlmSessionLogs: false,
    assistantMode: AssistantMode.general,
    mcpEnabled: false,
    demoMode: false,
  );
}

/// Streams one short answer, so a turn starts and finishes normally.
class _StreamingDataSource implements ChatDataSource {
  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => StreamedChatCompletion.fromStream(
    Stream<String>.value('done'),
    finishReason: 'stop',
  );

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => ChatCompletionResult(content: '', finishReason: 'stop');

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => throw UnimplementedError();

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => throw UnimplementedError();

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => throw UnimplementedError();

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => throw UnimplementedError();
}

void _runChatNotifierBusyThreadState() {
  test('a detached response finishing clears the visible thread spinner', () {
    // Regression for the stall observed 2026-07-25: a turn finalized through
    // the detached path (run_completed with no turn_exit) left isLoading set
    // because the finished response belonged to another conversation, so both
    // the composer and the sidebar spinner ran forever.
    const visible = 'conversation-visible';
    final state = ChatState.initial().copyWith(
      isLoading: true,
      busyConversationIds: const <String>{},
    );

    expect(
      chatStateReportsConversationBusy(
        state: state,
        targetConversationId: visible,
        visibleConversationId: visible,
      ),
      isTrue,
      reason: 'this is the stuck state: nothing registered, isLoading stale',
    );
    expect(
      chatStateReportsConversationBusy(
        state: state.copyWith(isLoading: false),
        targetConversationId: visible,
        visibleConversationId: visible,
      ),
      isFalse,
      reason: 'clearing isLoading is what stops both spinners',
    );
  });

  test('a finished turn clears the thread busy state observably', () async {
    final conversationBox = _MockBoxChatNotifierBusyThreadState();
    final storage = <String, String>{};
    when(() => conversationBox.keys).thenAnswer((_) => storage.keys);
    when(
      () => conversationBox.get(any()),
    ).thenAnswer((call) => storage[call.positionalArguments[0]]);
    when(() => conversationBox.put(any(), any())).thenAnswer((call) async {
      storage[call.positionalArguments[0] as String] =
          call.positionalArguments[1] as String;
    });
    final appLifecycleService =
        _MockAppLifecycleServiceChatNotifierBusyThreadState();
    when(() => appLifecycleService.isInBackground).thenReturn(false);

    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _TestSettingsNotifierChatNotifierBusyThreadState.new,
        ),
        conversationBoxProvider.overrideWithValue(conversationBox),
        conversationsNotifierProvider.overrideWith(ConversationsNotifier.new),
        codingProjectsNotifierProvider.overrideWith(
          _TestCodingProjectsNotifierChatNotifierBusyThreadState.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(_StreamingDataSource()),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryServiceChatNotifierBusyThreadState(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskServiceChatNotifierBusyThreadState(),
        ),
      ],
    );
    addTearDown(container.dispose);

    // The thread list rebuilds from these emissions alone, so the busy flag
    // has to be visible in one of them — the registry is not observable.
    final busySnapshots = <Set<String>>[];
    container.listen(chatNotifierProvider, (previous, next) {
      busySnapshots.add(next.busyConversationIds);
    }, fireImmediately: true);

    final notifier = container.read(chatNotifierProvider.notifier);
    await notifier.sendMessage('hello');
    // Finalization continues past the send future (persistence, memory), so
    // give those continuations a bounded chance to run.
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (container
            .read(chatNotifierProvider)
            .busyConversationIds
            .isNotEmpty &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(
      busySnapshots.any((snapshot) => snapshot.isNotEmpty),
      isTrue,
      reason: 'the running turn must be observable as busy',
    );
    expect(
      busySnapshots.last,
      isEmpty,
      reason:
          'the last emission must report the thread idle, otherwise the '
          'sidebar spinner keeps animating after the turn finished',
    );
    expect(container.read(chatNotifierProvider).busyConversationIds, isEmpty);
  });
}
