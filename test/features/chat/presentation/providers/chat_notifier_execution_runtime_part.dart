part of 'chat_notifier_test.dart';

void registerChatNotifierExecutionRuntimeTests() {
  test(
    'sendMessage bounds repeated read_file result replay and requests recovery',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'read-1',
            name: 'read_file',
            arguments: const {'path': 'bin/todo_app.dart'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Read the file again before validating it.',
            toolCalls: [
              ToolCallInfo(
                id: 'read-2',
                name: 'read_file',
                arguments: const {'path': 'bin/todo_app.dart'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Read the file one more time before validating it.',
            toolCalls: [
              ToolCallInfo(
                id: 'read-3',
                name: 'read_file',
                arguments: const {'path': 'bin/todo_app.dart'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Apply the required repair now.',
            toolCalls: [
              ToolCallInfo(
                id: 'write-1',
                name: 'write_file',
                arguments: const {
                  'path': 'bin/todo_app.dart',
                  'content': 'void main() {}',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The validation completed successfully.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'read_file': 'void main() {}',
          'write_file': '{"path":"/tmp/bin/todo_app.dart","bytes_written":14}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
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

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Validate the existing Dart CLI');

        expect(toolService.executedToolNames, ['read_file', 'write_file']);
        expect(
          toolDataSource.toolResultBatches
              .map((batch) => batch.map((item) => item.name).toList())
              .toList(),
          [
            ['read_file'],
            ['read_file'],
            ['read_file'],
            ['write_file'],
          ],
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Recovered final answer'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('one-shot chat publishes the shared runtime lifecycle', () async {
    final streamController = StreamController<String>();
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final runtimeContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(
          _StreamingChatDataSource(streamController),
        ),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
        cavernoRuntimeSurfaceProvider.overrideWithValue(
          CavernoRuntimeSurface.headless,
        ),
      ],
    );
    final runtime = runtimeContainer.read(cavernoExecutionRuntimeProvider);
    final events = <CavernoRuntimeEvent>[];
    final terminalEvent = Completer<CavernoRuntimeTerminalEvent>();
    final subscription = runtime.events.listen((event) {
      events.add(event);
      if (event is CavernoRuntimeTerminalEvent && !terminalEvent.isCompleted) {
        terminalEvent.complete(event);
      }
    });
    addTearDown(() async {
      await subscription.cancel();
      runtimeContainer.dispose();
      if (!streamController.isClosed) {
        await streamController.close();
      }
    });

    final chatNotifier = runtimeContainer.read(chatNotifierProvider.notifier);
    final sendFuture = chatNotifier.sendMessage('Say hello');
    streamController
      ..add('Hello ')
      ..add('there!');
    await streamController.close();
    await sendFuture;
    await terminalEvent.future.timeout(const Duration(seconds: 5));

    expect(events.map((event) => event.type), [
      'run_started',
      'assistant_delta',
      'assistant_delta',
      'run_completed',
    ]);
    final started = events.first as CavernoRuntimeRunStarted;
    expect(started.surface, CavernoRuntimeSurface.headless);
    expect(started.mode, AssistantMode.general.name);
    expect(started.conversationId, 'test-conversation-1');
    expect(started.hidden, isFalse);
    expect(
      events.whereType<CavernoRuntimeAssistantDelta>().map(
        (event) => event.delta,
      ),
      ['Hello ', 'there!'],
    );
    final completed = events.last as CavernoRuntimeRunCompleted;
    expect(completed.content, 'Hello there!');
    expect(chatNotifier.state.messages.last.content, completed.content);
    expect(events.map((event) => event.sequence), orderedEquals([1, 2, 3, 4]));
  });

  test('stream cancellation terminalizes the shared runtime turn', () async {
    final streamController = StreamController<String>();
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final runtimeContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(
          _StreamingChatDataSource(streamController),
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
    final runtime = runtimeContainer.read(cavernoExecutionRuntimeProvider);
    final terminalEvent = Completer<CavernoRuntimeTerminalEvent>();
    final subscription = runtime.events.listen((event) {
      if (event is CavernoRuntimeTerminalEvent && !terminalEvent.isCompleted) {
        terminalEvent.complete(event);
      }
    });
    addTearDown(() async {
      await subscription.cancel();
      runtimeContainer.dispose();
      if (!streamController.isClosed) {
        await streamController.close();
      }
    });

    final chatNotifier = runtimeContainer.read(chatNotifierProvider.notifier);
    final sendFuture = chatNotifier.sendMessage('Start a long response');
    await Future<void>.delayed(Duration.zero);
    streamController.add('Partial response');
    await Future<void>.delayed(Duration.zero);

    chatNotifier.cancelStreaming();

    final terminal = await terminalEvent.future.timeout(
      const Duration(seconds: 5),
    );
    expect(terminal, isA<CavernoRuntimeRunFailed>());
    expect((terminal as CavernoRuntimeRunFailed).code, 'cancelled');
    expect(terminal.exitCode, 130);
    await streamController.close();
    await sendFuture;
  });

  test('runtime output excludes embedded reasoning and tool markers', () async {
    final streamController = StreamController<String>();
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final runtimeContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(
          _StreamingChatDataSource(streamController),
        ),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
        cavernoRuntimeSurfaceProvider.overrideWithValue(
          CavernoRuntimeSurface.terminal,
        ),
      ],
    );
    final runtime = runtimeContainer.read(cavernoExecutionRuntimeProvider);
    final events = <CavernoRuntimeEvent>[];
    final terminalEvent = Completer<CavernoRuntimeTerminalEvent>();
    final subscription = runtime.events.listen((event) {
      events.add(event);
      if (event is CavernoRuntimeTerminalEvent && !terminalEvent.isCompleted) {
        terminalEvent.complete(event);
      }
    });
    addTearDown(() async {
      await subscription.cancel();
      runtimeContainer.dispose();
      if (!streamController.isClosed) {
        await streamController.close();
      }
    });

    final chatNotifier = runtimeContainer.read(chatNotifierProvider.notifier);
    final sendFuture = chatNotifier.sendMessage('Show the visible response');
    streamController
      ..add('<think>private reasoning</think>')
      ..add('<tool_')
      ..add('use>{"name":"memory_update","arguments":{}}</tool_use>')
      ..add('Visible response.');
    await streamController.close();
    await sendFuture;
    await terminalEvent.future.timeout(const Duration(seconds: 5));

    final deltas = events.whereType<CavernoRuntimeAssistantDelta>().toList();
    expect(deltas.map((event) => event.delta), ['Visible response.']);
    final completed = events.whereType<CavernoRuntimeRunCompleted>().single;
    expect(completed.content, 'Visible response.');
    expect(
      events.map((event) => event.toJson().toString()).join(),
      isNot(contains('private reasoning')),
    );
    expect(
      events.map((event) => event.toJson().toString()).join(),
      isNot(contains('<tool_use>')),
    );
  });

  test('plan proposal completes the runtime with draft markdown', () async {
    final conversationRepository = _FakeConversationRepository();
    final proposalDataSource = _QueuedProposalDataSource([
      ChatCompletionResult(
        content:
            '{"kind":"proposal","workflowStage":"plan","goal":"Add a greeting feature","constraints":["Keep the change small"],"acceptanceCriteria":["The greeting returns hello"],"openQuestions":[]}',
        finishReason: 'stop',
      ),
      ChatCompletionResult(
        content:
            '{"tasks":[{"title":"Implement the greeting","targetFiles":["lib/greeting.dart"],"validationCommand":"dart test","notes":"Return hello from a focused library API."},{"title":"Validate the greeting","targetFiles":["test/greeting_test.dart"],"validationCommand":"dart test","notes":"Cover the expected greeting value."}]}',
        finishReason: 'stop',
      ),
    ]);
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final runtimeContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          _TestCodingProjectsNotifier.new,
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
        cavernoRuntimeSurfaceProvider.overrideWithValue(
          CavernoRuntimeSurface.terminal,
        ),
      ],
    );
    final runtime = runtimeContainer.read(cavernoExecutionRuntimeProvider);
    final events = <CavernoRuntimeEvent>[];
    final subscription = runtime.events.listen(events.add);
    addTearDown(() async {
      await subscription.cancel();
      runtimeContainer.dispose();
    });

    runtimeContainer
        .read(conversationsNotifierProvider.notifier)
        .activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-1',
          createIfMissing: true,
        );
    await runtimeContainer
        .read(chatNotifierProvider.notifier)
        .generatePlanProposal();

    final completed = events.whereType<CavernoRuntimeRunCompleted>().single;
    expect(completed.content, startsWith('# Plan'));
    expect(completed.content, contains('Add a greeting feature'));
    expect(completed.content, contains('Implement the greeting'));
  });

  test('pending decisions publish typed runtime events', () async {
    final streamController = StreamController<String>();
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final runtimeContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(
          _StreamingChatDataSource(streamController),
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
    final runtime = runtimeContainer.read(cavernoExecutionRuntimeProvider);
    final events = <CavernoRuntimeEvent>[];
    final terminalEvent = Completer<CavernoRuntimeTerminalEvent>();
    final subscription = runtime.events.listen((event) {
      events.add(event);
      if (event is CavernoRuntimeTerminalEvent && !terminalEvent.isCompleted) {
        terminalEvent.complete(event);
      }
    });
    addTearDown(() async {
      await subscription.cancel();
      runtimeContainer.dispose();
      if (!streamController.isClosed) {
        await streamController.close();
      }
    });

    final chatNotifier = runtimeContainer.read(chatNotifierProvider.notifier);
    final sendFuture = chatNotifier.sendMessage('Prepare the change');
    await Future<void>.delayed(Duration.zero);

    final approvalFuture = chatNotifier.requestLocalCommand(
      command: 'dart test',
      workingDirectory: '/workspace',
      reason: 'Verify the implementation',
    );
    final pendingApproval = chatNotifier.state.pendingLocalCommand!;
    chatNotifier.resolveLocalCommand(
      id: pendingApproval.id,
      approval: const LocalCommandApproval(approved: false),
    );
    await approvalFuture;

    final questionFuture = chatNotifier.requestAskUserQuestion(
      question: 'Which target should be used?',
      help: 'Choose one target.',
      options: const [
        AskUserQuestionOption(id: 'local', label: 'Local'),
        AskUserQuestionOption(id: 'remote', label: 'Remote'),
      ],
      allowMultiple: false,
      allowOther: false,
      otherPlaceholder: '',
    );
    final pendingQuestion = chatNotifier.state.pendingAskUserQuestion!;
    chatNotifier.resolveAskUserQuestion(id: pendingQuestion.id);
    await questionFuture;

    streamController.add('Stopped before execution.');
    await streamController.close();
    await sendFuture;
    await terminalEvent.future.timeout(const Duration(seconds: 5));

    final approval = events.whereType<CavernoRuntimeApprovalRequired>().single;
    expect(approval.request.id, pendingApproval.id);
    expect(approval.request.capability, 'command_execution');
    expect(approval.request.summary, 'Verify the implementation');
    expect(approval.request.target, '/workspace');
    expect(approval.request.rememberAllowed, isTrue);

    final question = events.whereType<CavernoRuntimeQuestionRequired>().single;
    expect(question.request.id, pendingQuestion.id);
    expect(question.request.prompt, 'Which target should be used?');
    expect(question.request.options, ['Local', 'Remote']);
    expect(question.request.multiple, isFalse);
    expect(events.last, isA<CavernoRuntimeRunCompleted>());
  });
}
