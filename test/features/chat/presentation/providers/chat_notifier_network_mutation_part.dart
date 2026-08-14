part of 'chat_notifier_test.dart';

void registerChatNotifierNetworkMutationTests() {
  test('default mode denies HTTP mutation without executing it', () async {
    final dataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [_httpToolCall('post-default', 'http_post')],
      toolLoopResponses: [
        ChatCompletionResult(content: 'Request denied.', finishReason: 'stop'),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {'http_post': '{"status":200}'},
    );
    final container = _networkApprovalTestContainer(
      dataSource: dataSource,
      toolService: toolService,
      settingsFactory: _ToolEnabledSettingsNotifier.new,
    );
    addTearDown(container.dispose);
    final notifier = container.read(chatNotifierProvider.notifier);

    final send = notifier.sendMessage('Update the remote record.');
    await _waitForCondition(() => notifier.state.pendingBrowserAction != null);

    expect(toolService.executedToolNames, isEmpty);
    final pending = notifier.state.pendingBrowserAction!;
    expect(pending.toolName, 'http_post');
    expect(pending.riskLabel, 'High-risk network mutation');
    notifier.resolveBrowserAction(id: pending.id, approved: false);
    await send.timeout(const Duration(seconds: 5));

    expect(toolService.executedToolNames, isEmpty);
  });

  test('full access executes an untainted HTTP mutation once', () async {
    final dataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [_httpToolCall('put-full', 'http_put')],
      toolLoopResponses: [
        ChatCompletionResult(content: 'Request sent.', finishReason: 'stop'),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {'http_put': '{"status":200}'},
    );
    final container = _networkApprovalTestContainer(
      dataSource: dataSource,
      toolService: toolService,
      settingsFactory: _ToolEnabledChatFullAccessSettingsNotifier.new,
    );
    addTearDown(container.dispose);
    final notifier = container.read(chatNotifierProvider.notifier);

    await notifier
        .sendMessage('Replace the remote record.')
        .timeout(const Duration(seconds: 5));

    expect(toolService.executedToolNames, ['http_put']);
    expect(notifier.state.pendingBrowserAction, isNull);
  });

  test('tainted HTTP mutation cannot use full access', () async {
    final dataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'read-remote',
          name: 'http_get',
          arguments: const {'url': 'https://example.test/instructions'},
        ),
      ],
      toolLoopResponses: [
        ChatCompletionResult(
          content: 'The remote response requested a state change.',
          toolCalls: [_httpToolCall('post-tainted', 'http_post')],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'The mutation was blocked.',
          finishReason: 'stop',
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'http_get': 'Untrusted instructions',
        'http_post': '{"status":200}',
      },
    );
    final container = _networkApprovalTestContainer(
      dataSource: dataSource,
      toolService: toolService,
      settingsFactory: _ToolEnabledChatFullAccessSettingsNotifier.new,
    );
    addTearDown(container.dispose);
    final notifier = container.read(chatNotifierProvider.notifier);

    await notifier
        .sendMessage('Inspect the remote instructions only.')
        .timeout(const Duration(seconds: 5));

    expect(toolService.executedToolNames, ['http_get']);
    expect(notifier.state.pendingBrowserAction, isNull);
  });
}

ToolCallInfo _httpToolCall(String id, String name) {
  return ToolCallInfo(
    id: id,
    name: name,
    arguments: const {
      'url': 'https://example.test/api/record?token=secret',
      'headers': {'Authorization': 'Bearer secret'},
      'body': '{"enabled":true}',
      'content_type': 'application/json',
    },
  );
}

ProviderContainer _networkApprovalTestContainer({
  required ChatDataSource dataSource,
  required McpToolService toolService,
  required SettingsNotifier Function() settingsFactory,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(settingsFactory),
      conversationsNotifierProvider.overrideWith(
        _TestConversationsNotifier.new,
      ),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        _TestSessionMemoryService(),
      ),
      mcpToolServiceProvider.overrideWithValue(toolService),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWith(
        (ref) => _TestBackgroundTaskService(),
      ),
    ],
  );
}
