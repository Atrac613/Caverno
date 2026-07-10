part of 'chat_notifier_test.dart';

void registerChatNotifierFinalAnswerRecoveryTests() {
  test(
    'length-truncated tool final answer gets one bounded concise replacement',
    () async {
      const firstAnswer =
          'This original truncated answer must be replaced completely.';
      const recoveryAnswer = 'Concise replacement answer.';
      final fixture = await _createFinalAnswerRecoveryFixture(
        firstAnswer: firstAnswer,
        recoveryAnswer: recoveryAnswer,
        recoveryFinishReason: 'stop',
      );
      addTearDown(fixture.dispose);
      final notifier = fixture.container.read(chatNotifierProvider.notifier);

      await notifier.sendMessage('Inspect the file');

      expect(fixture.toolService.executedToolNames, ['read_file']);
      expect(fixture.dataSource.toolResultCompletionCount, 1);
      expect(fixture.dataSource.finalAnswerStreamCount, 1);
      expect(fixture.dataSource.recoveryRequestMessages, hasLength(1));
      expect(fixture.dataSource.recoveryToolBatches.single, isEmpty);
      expect(
        fixture.dataSource.recoveryMaxTokens.single,
        lessThanOrEqualTo(2048),
      );
      expect(fixture.dataSource.recoveryTemperatures.single, 0.1);

      final recoveryPrompt = fixture.dataSource.recoveryRequestMessages.single
          .singleWhere((message) => message.id == 'final_answer_recovery');
      expect(
        recoveryPrompt.content,
        contains('cut off at the output-token limit'),
      );
      expect(
        recoveryPrompt.content,
        contains('Do not include internal reasoning'),
      );

      final visibleAnswer = notifier.state.messages.last.content;
      expect(visibleAnswer, contains(recoveryAnswer));
      expect(visibleAnswer, isNot(contains(firstAnswer)));
      expect(visibleAnswer, isNot(contains(TruncationNotice.maxTokenNotice)));

      final conversation = fixture.container
          .read(conversationsNotifierProvider)
          .currentConversation!;
      final sessionLogFile = await fixture.sessionLogStore.fileForContext(
        LlmSessionLogContext(
          workspaceMode: WorkspaceMode.chat,
          sessionId: conversation.id,
          conversationId: conversation.id,
        ),
        create: false,
      );
      final entries = (await sessionLogFile.readAsLines())
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList(growable: false);
      final turnExit = entries.lastWhere(
        (entry) => entry['operation'] == 'turn_exit',
      );
      final turnExitPayload = turnExit['turnExit'] as Map<String, dynamic>;
      expect(turnExitPayload['reason'], 'text_response');
      expect(
        turnExitPayload['transforms'],
        contains('final_answer_concise_retry'),
      );
    },
  );

  test(
    'second length finish does not trigger a third final-answer attempt',
    () async {
      final fixture = await _createFinalAnswerRecoveryFixture(
        firstAnswer: 'First answer was truncated.',
        recoveryAnswer: 'Second answer also reached its output limit.',
        recoveryFinishReason: 'length',
      );
      addTearDown(fixture.dispose);
      final notifier = fixture.container.read(chatNotifierProvider.notifier);

      await notifier.sendMessage('Inspect the file');

      expect(fixture.toolService.executedToolNames, ['read_file']);
      expect(fixture.dataSource.toolResultCompletionCount, 1);
      expect(fixture.dataSource.finalAnswerStreamCount, 1);
      expect(fixture.dataSource.recoveryRequestMessages, hasLength(1));
      expect(
        notifier.state.messages.last.content,
        contains(TruncationNotice.maxTokenNotice),
      );
    },
  );

  test(
    'repetitive stopped final answer gets one concise replacement',
    () async {
      const repeatedLine = 'Then `lib/src/todo_storage.dart` will be written.';
      final firstAnswer = [
        List.filled(4, repeatedLine).join('\n'),
        List.filled(1000, 'x').join(),
      ].join('\n');
      final fixture = await _createFinalAnswerRecoveryFixture(
        firstAnswer: firstAnswer,
        firstFinishReason: 'stop',
        recoveryAnswer: 'Verified concise replacement.',
        recoveryFinishReason: 'stop',
      );
      addTearDown(fixture.dispose);
      final notifier = fixture.container.read(chatNotifierProvider.notifier);

      await notifier.sendMessage('Inspect the file');

      expect(fixture.dataSource.recoveryRequestMessages, hasLength(1));
      final recoveryPrompt = fixture.dataSource.recoveryRequestMessages.single
          .singleWhere((message) => message.id == 'final_answer_recovery');
      expect(recoveryPrompt.content, contains('excessive repeated content'));
      final visibleAnswer = notifier.state.messages.last.content;
      expect(visibleAnswer, contains('Verified concise replacement.'));
      expect(visibleAnswer, isNot(contains(repeatedLine)));
    },
  );
}

Future<_FinalAnswerRecoveryFixture> _createFinalAnswerRecoveryFixture({
  required String firstAnswer,
  String firstFinishReason = 'length',
  required String recoveryAnswer,
  required String recoveryFinishReason,
}) async {
  final sessionLogRoot = await Directory.systemTemp.createTemp(
    'final_answer_recovery_logs_',
  );
  final sessionLogStore = LlmSessionLogStore(
    rootDirectoryProvider: () async => sessionLogRoot,
  );
  final dataSource = _FinalAnswerRecoveryChatDataSource(
    initialToolCall: ToolCallInfo(
      id: 'tool-1',
      name: 'read_file',
      arguments: const {'path': 'lib/main.dart'},
    ),
    firstAnswer: firstAnswer,
    firstFinishReason: firstFinishReason,
    recoveryResult: ChatCompletionResult(
      content: recoveryAnswer,
      finishReason: recoveryFinishReason,
    ),
  );
  final toolService = _FakeMcpToolService(
    results: const {'read_file': '{"content":"void main() {}"}'},
  );
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  final container = ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(
        _ToolEnabledLoggingSettingsNotifier.new,
      ),
      conversationsNotifierProvider.overrideWith(
        _TestConversationsNotifier.new,
      ),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        _TestSessionMemoryService(),
      ),
      mcpToolServiceProvider.overrideWithValue(toolService),
      llmSessionLogStoreProvider.overrideWithValue(sessionLogStore),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _TestBackgroundTaskService(),
      ),
    ],
  );
  return _FinalAnswerRecoveryFixture(
    container: container,
    dataSource: dataSource,
    toolService: toolService,
    sessionLogStore: sessionLogStore,
    sessionLogRoot: sessionLogRoot,
  );
}

class _FinalAnswerRecoveryFixture {
  const _FinalAnswerRecoveryFixture({
    required this.container,
    required this.dataSource,
    required this.toolService,
    required this.sessionLogStore,
    required this.sessionLogRoot,
  });

  final ProviderContainer container;
  final _FinalAnswerRecoveryChatDataSource dataSource;
  final _FakeMcpToolService toolService;
  final LlmSessionLogStore sessionLogStore;
  final Directory sessionLogRoot;

  Future<void> dispose() async {
    container.dispose();
    if (sessionLogRoot.existsSync()) {
      await sessionLogRoot.delete(recursive: true);
    }
  }
}
