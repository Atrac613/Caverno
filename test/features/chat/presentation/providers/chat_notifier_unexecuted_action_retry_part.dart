part of 'chat_notifier_test.dart';

void registerChatNotifierUnexecutedActionRetryTests() {
  test(
    'an unexecuted command retry retains the code already inspected',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'retry-read-context-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/retry.py')
        ..writeAsStringSync('attempts = 3');
      final project = CodingProject(
        id: 'retry-read-context',
        name: 'retry-read-context',
        rootPath: directory.path,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'inspect-retry',
            name: 'read_file',
            arguments: {'path': file.path},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: '', finishReason: 'stop'),
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'run-retry-tests',
                name: 'local_execute_command',
                arguments: {
                  'command': 'python3 -m pytest',
                  'working_directory': directory.path,
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunkBatches: const [
          ['I successfully ran the local command python3 -m pytest.'],
          ['The tests passed.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'read_file': jsonEncode({
            'path': file.path,
            'content': 'attempts = 3',
          }),
          'local_execute_command': '{"exit_code":0,"stdout":"3 passed"}',
        },
      );
      final lifecycle = _MockAppLifecycleService();
      when(() => lifecycle.isInBackground).thenReturn(false);
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(lifecycle),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(container.dispose);
      standInForTheApprover(container);
      container
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final notifier = container.read(chatNotifierProvider.notifier);
      await notifier.sendMessage('Inspect retry.py and run its tests');

      final recovery = dataSource.toolResultBatches.singleWhere(
        (batch) => batch.any(
          (result) => result.result.contains(
            'unexecuted_command_action_retry_required',
          ),
        ),
      );
      expect(recovery.map((result) => result.name), [
        'read_file',
        'local_execute_command',
      ]);
      expect(recovery.first.result, contains('attempts = 3'));
      expect(recovery.first.fromEarlierLoop, isTrue);
      expect(recovery.first.changesSinceCapture, isEmpty);
      expect(toolService.executedToolNames, [
        'read_file',
        'local_execute_command',
      ]);
      expect(
        notifier.state.messages.last.content,
        contains('The tests passed.'),
      );
    },
  );

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
