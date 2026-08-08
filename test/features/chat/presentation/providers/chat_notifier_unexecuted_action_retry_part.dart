part of 'chat_notifier_test.dart';

void registerChatNotifierUnexecutedActionRetryTests() {
  test('sendMessage dispatches the retry call for a command an answer only '
      'described', () async {
    final describedRun =
        'iOS IPA ${String.fromCharCodes(const [0x30d3, 0x30eb, 0x30c9, 0x6210, 0x529f])}\n'
        'App Store Connect ${String.fromCharCodes(const [0x30a2, 0x30c3, 0x30d7, 0x30ed, 0x30fc, 0x30c9, 0x6210, 0x529f])}\n'
        'iOS ${String.fromCharCodes(const [0x30ea, 0x30ea, 0x30fc, 0x30b9, 0x5b8c, 0x4e86])}';
    final dataSource = _NoToolStreamingWithToolsDataSource(
      streamChunks: [describedRun],
      completionContent: describedRun,
      toolResultResponse: ChatCompletionResult(
        content: '',
        finishReason: 'tool_calls',
        toolCalls: [
          ToolCallInfo(
            id: 'retry-run-1',
            name: 'mcp_release_check',
            arguments: const {'target': 'ios'},
          ),
        ],
      ),
    );
    final toolService = _FakeMcpToolService(
      descriptions: const {
        'local_execute_command': 'Run a local shell command.',
        'mcp_release_check': 'Check a release target.',
      },
      results: const {
        'local_execute_command': '{"exit_code":0,"stdout":"ok"}',
        'mcp_release_check': '{"exit_code":0,"stdout":"checked"}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(
          _FakeConversationRepository(),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(threadContainer.dispose);

    final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
    await chatNotifier.sendMessage('はい');

    expect(dataSource.toolResultRequestCount, greaterThanOrEqualTo(1));
    expect(toolService.executedToolNames, contains('mcp_release_check'));
  });
}
