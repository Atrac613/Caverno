part of 'chat_notifier_test.dart';

void registerChatNotifierExecutionRuntimeTests() {
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
