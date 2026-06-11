part of 'chat_notifier_test.dart';

class _DelayedFirstMessageSaveConversationsNotifier
    extends _TestConversationsNotifier {
  final Completer<void> firstMessageSaveStarted = Completer<void>();
  final Completer<void> releaseFirstMessageSave = Completer<void>();
  bool _delayedFirstMessageSave = false;

  @override
  Future<void> updateConversationMessages(
    String conversationId,
    List<Message> messages,
  ) async {
    if (!_delayedFirstMessageSave && messages.length == 1) {
      _delayedFirstMessageSave = true;
      if (!firstMessageSaveStarted.isCompleted) {
        firstMessageSaveStarted.complete();
      }
      await releaseFirstMessageSave.future;
    }
    await super.updateConversationMessages(conversationId, messages);
  }
}

void registerChatNotifierPersistenceTests() {
  test(
    'sendMessage keeps final assistant response when initial save completes late',
    () async {
      final delayedController = StreamController<String>();
      final conversationsNotifier =
          _DelayedFirstMessageSaveConversationsNotifier();
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final delayedContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            () => conversationsNotifier,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(
            _StreamingChatDataSource(delayedController),
          ),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(() async {
        delayedContainer.dispose();
        if (!delayedController.isClosed) {
          await delayedController.close();
        }
      });

      final delayedNotifier = delayedContainer.read(
        chatNotifierProvider.notifier,
      );
      final sendFuture = delayedNotifier.sendMessage('Hello');
      await conversationsNotifier.firstMessageSaveStarted.future;

      delayedController.add('Final answer');
      await delayedController.close();
      await _waitForCondition(() => !delayedNotifier.state.isLoading);
      await Future<void>.delayed(Duration.zero);

      conversationsNotifier.releaseFirstMessageSave.complete();
      await sendFuture;
      await Future<void>.delayed(Duration.zero);

      expect(delayedNotifier.state.messages.map((message) => message.content), [
        'Hello',
        'Final answer',
      ]);
      expect(
        delayedContainer
            .read(conversationsNotifierProvider)
            .currentConversation!
            .messages
            .map((message) => message.content),
        ['Hello', 'Final answer'],
      );
    },
  );
}
