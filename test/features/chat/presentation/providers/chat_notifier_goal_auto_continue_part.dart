part of 'chat_notifier_test.dart';

// Goal auto-continuation provider tests live in a part file so
// chat_notifier_test.dart stays under its F1 size ratchet.
void registerChatNotifierGoalAutoContinueTests() {
  registerChatNotifierTerminalSuccessTests();
  registerChatNotifierToolFailureClassificationTests();
  test(
    'goal auto-continue recovers an unexecuted short-prompt completion claim',
    () async {
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          const <ToolCallInfo>[],
          [
            ToolCallInfo(
              id: 'call-recover-unexecuted-work',
              name: 'local_execute_command',
              arguments: const {'command': 'dart test'},
            ),
          ],
        ],
        streamChunkBatches: const [
          [
            'Implementation complete. I created lib/todo_store.dart and '
                'bin/todo.dart. The dart test command completed successfully.',
          ],
          <String>[],
        ],
        finalAnswerChunkBatches: const [
          ['The requested implementation is now verified.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'local_execute_command': 'Run a local shell command.',
        },
        results: const {
          'local_execute_command':
              '{"exit_code":0,"stdout":"All tests passed.\\n","stderr":""}',
        },
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: toolService,
        projectId: 'goal-auto-unexecuted-short-prompt',
        settingsBuilder: _ToolEnabledNoConfirmSettingsNotifier.new,
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'goal-auto-unexecuted-short-prompt',
      );
      await conversations.saveCurrentGoal(
        objective: 'Implement and verify the TODO CLI',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 2,
      );

      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Implement the TODO CLI.', bypassPlanMode: true);

      await _waitForCondition(() {
        final state = container.read(chatNotifierProvider);
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        return !state.isLoading &&
            dataSource.initialRequestMessages.length == 2 &&
            goal?.turnsUsed == 2;
      });

      expect(toolService.executedToolNames, ['local_execute_command']);
      final continuationPrompt = dataSource.initialRequestMessages.last
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content)
          .join('\n');
      expect(continuationPrompt, contains('Automatic goal continuation 2/2.'));
      expect(
        continuationPrompt,
        contains('claimed file or command actions without tool evidence'),
      );
      final assistantContents = container
          .read(chatNotifierProvider)
          .messages
          .where((message) => message.role == MessageRole.assistant)
          .map((message) => message.content)
          .toList(growable: false);
      expect(assistantContents, everyElement(isNot(contains('I created'))));
      expect(
        assistantContents,
        anyElement(contains('The requested command was not executed')),
      );
    },
  );
  test(
    'goal auto-continue starts the active task before the first request ends',
    () async {
      final firstRequestGate = Completer<void>();
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: const [<ToolCallInfo>[]],
        streamChunkBatches: const [
          ['Execution is still running.'],
        ],
        toolCompletionGates: {1: firstRequestGate.future},
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: _FakeMcpToolService(
          descriptions: const {
            'local_execute_command': 'Execute a local command.',
          },
          results: const {'local_execute_command': 'unused'},
        ),
        projectId: 'goal-auto-live-progress',
        useRealConversationsNotifier: true,
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'goal-auto-live-progress',
        createIfMissing: true,
      );
      await conversations.saveCurrentGoal(
        objective: 'Implement and verify the TODO CLI',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 1,
      );

      final chatNotifier = container.read(chatNotifierProvider.notifier);
      final sendFuture = chatNotifier.sendMessage(
        'Implement the TODO CLI.',
        bypassPlanMode: true,
      );

      await _waitForCondition(
        () => dataSource.initialRequestMessages.length == 1,
      );
      final activeConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation!;
      final task = activeConversation.projectedExecutionTasks.single;
      final progress = activeConversation.executionProgressForTask(task.id);
      expect(task.status, ConversationWorkflowTaskStatus.inProgress);
      expect(progress?.lastRunAt, isNotNull);
      expect(progress?.recentEvents, hasLength(1));
      expect(
        progress?.recentEvents.single.type,
        ConversationExecutionTaskEventType.started,
      );
      final systemPrompt = dataSource.initialRequestMessages.single
          .firstWhere((message) => message.role == MessageRole.system)
          .content;
      expect(systemPrompt, contains('Active task status: inProgress'));

      firstRequestGate.complete();
      await sendFuture;
    },
  );
  test(
    'goal auto-continue retries a structured tool request from the final answer',
    () async {
      const finalToolRequest =
          '<tool_use>local_execute_command'
          '<arg_name>command</arg_name>'
          '<arg_value>dart run bin/todo_cli.dart show missing-id</arg_value>'
          '<arg_name>reason</arg_name>'
          '<arg_value>Verify unknown ID behavior</arg_value>'
          '</tool_use>';
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          [
            ToolCallInfo(
              id: 'call-list-initial',
              name: 'local_execute_command',
              arguments: const {'command': 'dart run bin/todo_cli.dart list'},
            ),
          ],
          [
            ToolCallInfo(
              id: 'call-verify-hidden',
              name: 'local_execute_command',
              arguments: const {
                'command': 'dart run bin/todo_cli.dart show missing-id',
              },
            ),
          ],
        ],
        finalAnswerChunkBatches: const [
          [finalToolRequest],
          ['Validation completed successfully.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'local_execute_command': 'unused fallback'},
        queuedResults: const {
          'local_execute_command': [
            '{"exit_code":0,"stdout":"No items.\\n","stderr":""}',
            '{"exit_code":0,"stdout":"Item not found.\\n","stderr":""}',
          ],
        },
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: toolService,
        projectId: 'goal-auto-final-tool-request',
        settingsBuilder: _ToolEnabledNoConfirmSettingsNotifier.new,
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'goal-auto-final-tool-request',
      );
      await conversations.saveCurrentGoal(
        objective: 'Implement and verify the TODO CLI',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 5,
      );

      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Implement the TODO CLI.', bypassPlanMode: true);

      await _waitForCondition(() {
        final state = container.read(chatNotifierProvider);
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        return !state.isLoading &&
            dataSource.initialRequestMessages.length == 2 &&
            goal?.turnsUsed == 2;
      });

      expect(toolService.executedToolNames, [
        'local_execute_command',
        'local_execute_command',
      ]);
      expect(dataSource.finalAnswerRequestMessages, hasLength(2));
      expect(
        dataSource.initialToolDefinitions[1]
            .map((definition) => definition['function'])
            .whereType<Map>()
            .map((function) => function['name']),
        contains('local_execute_command'),
      );
    },
  );
  test(
    'goal auto-continue dispatches one hidden continuation from current evidence',
    () async {
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          [
            ToolCallInfo(
              id: 'call-analyze-project',
              name: 'analyze_project',
              arguments: const {'command': 'dart analyze'},
            ),
          ],
          [_goalAutoContinueAnalyzeCall('call-analyze-continuation')],
        ],
        streamChunkBatches: const [
          <String>[],
          ['Continuation checked the goal and found no current errors.'],
        ],
        finalAnswerChunkBatches: const [
          ['Analyzer still reports unresolved errors.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'analyze_project': 'unused fallback'},
        queuedResults: {
          'analyze_project': [
            jsonEncode({
              'diagnostics': [
                {
                  'severity': 'Error',
                  'path': '/tmp/todo/bin/todo_cli.dart',
                  'relative_path': 'bin/todo_cli.dart',
                  'line': 12,
                  'column': 7,
                  'code': 'undefined_identifier',
                  'message': 'Undefined name store',
                },
              ],
            }),
            jsonEncode({
              'command': 'dart analyze',
              'exit_code': 0,
              'diagnostics': const <Object>[],
            }),
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final sessionLogRoot = await Directory.systemTemp.createTemp(
        'goal_auto_continue_session_log_',
      );
      addTearDown(() async {
        if (sessionLogRoot.existsSync()) {
          await sessionLogRoot.delete(recursive: true);
        }
      });
      final sessionLogStore = LlmSessionLogStore(
        rootDirectoryProvider: () async => sessionLogRoot,
      );
      final project = CodingProject(
        id: 'goal-auto-continue',
        name: 'Goal Auto Continue',
        rootPath: '/tmp/goal-auto-continue',
        createdAt: DateTime(2026, 5, 25, 10),
        updatedAt: DateTime(2026, 5, 25, 10),
      );
      final autoContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledLoggingSettingsNotifier.new,
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          conversationsNotifierProvider.overrideWith(
            _GoalAutoContinueConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
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
      addTearDown(autoContainer.dispose);

      final conversations = autoContainer.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'goal-auto-continue',
      );
      await conversations.saveCurrentGoal(
        objective: 'Fix the TODO CLI diagnostics',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 5,
      );

      final chatNotifier = autoContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Fix the TODO CLI.', bypassPlanMode: true);

      await _waitForCondition(() {
        final state = autoContainer.read(chatNotifierProvider);
        final goal = autoContainer
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        return !state.isLoading &&
            dataSource.initialRequestMessages.length == 2 &&
            goal?.turnsUsed == 2 &&
            state.goalAutoContinueCount == 0;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(dataSource.initialRequestMessages, hasLength(2));
      expect(toolService.executedToolNames, [
        'analyze_project',
        'analyze_project',
      ]);
      final continuationRequest = dataSource.initialRequestMessages.last;
      expect(
        continuationRequest
            .where((message) => message.role == MessageRole.user)
            .map((message) => message.content)
            .join('\n'),
        contains('Automatic goal continuation 2/5.'),
      );
      final visibleUserMessages = chatNotifier.state.messages.where(
        (message) => message.role == MessageRole.user,
      );
      expect(visibleUserMessages, hasLength(1));
      expect(visibleUserMessages.single.content, 'Fix the TODO CLI.');
      expect(
        chatNotifier.state.messages
            .where((message) => message.role == MessageRole.assistant)
            .map((message) => message.content),
        anyElement(
          contains(
            'Continuation checked the goal and found no current errors.',
          ),
        ),
      );

      final conversation = autoContainer
          .read(conversationsNotifierProvider)
          .currentConversation!;
      final sessionLogFile = await sessionLogStore.fileForContext(
        LlmSessionLogContext(
          workspaceMode: WorkspaceMode.coding,
          sessionId: conversation.id,
          conversationId: conversation.id,
        ),
        create: false,
      );
      final sessionLogEntries = (await sessionLogFile.readAsLines())
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList(growable: false);
      expect(
        sessionLogEntries.map((entry) => entry['operation']),
        containsAllInOrder([
          'turn_exit',
          'goal_auto_continue',
          'turn_exit',
          'goal_auto_continue',
        ]),
      );
      final goalAutoContinueEntries = sessionLogEntries
          .where((entry) => entry['operation'] == 'goal_auto_continue')
          .toList(growable: false);
      expect(goalAutoContinueEntries, hasLength(2));
      final continuationEntry = goalAutoContinueEntries.first;
      final marker =
          continuationEntry['goalAutoContinue'] as Map<String, dynamic>;
      expect(marker['decision'], 'continue');
      expect(marker['nextTurnNumber'], 2);
      expect(marker['effectiveTurnBudget'], 5);
      expect(marker['evidence']['hasBlockingEvidence'], isTrue);
      expect(marker['evidence']['noProgressStreak'], 0);
      expect(
        marker['evidence']['unresolvedErrorPaths'],
        contains('bin/todo_cli.dart'),
      );
      expect(marker['evidence']['safeBoundaryVeto'], isNull);
      final skipMarker =
          goalAutoContinueEntries.last['goalAutoContinue']
              as Map<String, dynamic>;
      expect(skipMarker['decision'], 'skip');
      expect(skipMarker['reason'], 'no incomplete evidence');
      expect(skipMarker['evidence']['hasIncompleteEvidence'], isFalse);
      expect(skipMarker['evidence']['safeBoundaryVeto'], isNull);
    },
  );

  test('goal auto-continue keeps mixed verifier failures blocking', () async {
    final dataSource = _GoalAutoContinueChatDataSource(
      toolCallBatches: [
        [
          ToolCallInfo(
            id: 'call-analyze-success',
            name: 'local_execute_command',
            arguments: const {'command': 'dart analyze'},
          ),
          ToolCallInfo(
            id: 'call-test-failure',
            name: 'local_execute_command',
            arguments: const {'command': 'dart test'},
          ),
        ],
        const <ToolCallInfo>[],
      ],
      streamChunkBatches: const [
        <String>[],
        ['The failed verification still requires repair.'],
      ],
      finalAnswerChunkBatches: const [
        ['Analysis passed, but the test command failed.'],
      ],
    );
    final toolService = _FakeMcpToolService(
      descriptions: const {
        'local_execute_command': 'Run a local shell command.',
      },
      results: const {'local_execute_command': 'unused'},
      queuedResults: {
        'local_execute_command': [
          jsonEncode({
            'command': 'dart analyze',
            'exit_code': 0,
            'stdout': 'No issues found!',
            'stderr': '',
          }),
          jsonEncode({
            'command': 'dart test',
            'exit_code': 65,
            'stdout': '',
            'stderr': 'No tests found.',
          }),
        ],
      },
    );
    final container = _goalAutoContinueContainer(
      dataSource: dataSource,
      toolService: toolService,
      projectId: 'goal-auto-mixed-verifier-failure',
      useRealConversationsNotifier: true,
      settingsBuilder: _ToolEnabledNoConfirmSettingsNotifier.new,
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.activateWorkspace(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'goal-auto-mixed-verifier-failure',
      createIfMissing: true,
    );
    await conversations.saveCurrentGoal(
      objective: 'Implement and verify the TODO CLI',
      enabled: true,
      autoContinue: true,
      status: ConversationGoalStatus.active,
      turnBudget: 2,
    );

    await container
        .read(chatNotifierProvider.notifier)
        .sendMessage('Implement the TODO CLI.', bypassPlanMode: true);

    await _waitForCondition(() {
      final state = container.read(chatNotifierProvider);
      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.goal;
      return !state.isLoading &&
          dataSource.initialRequestMessages.length == 2 &&
          goal?.turnsUsed == 2;
    });

    expect(toolService.executedToolNames, [
      'local_execute_command',
      'local_execute_command',
    ]);
    final continuationPrompt = dataSource.initialRequestMessages.last
        .where((message) => message.role == MessageRole.user)
        .map((message) => message.content)
        .join('\n');
    expect(continuationPrompt, contains('Automatic goal continuation 2/2.'));
    expect(continuationPrompt, contains('execution verification failed'));
    final conversation = container
        .read(conversationsNotifierProvider)
        .currentConversation!;
    expect(conversation.mutationGeneration, 0);
    expect(conversation.verificationGeneration, -1);
  });

  test(
    'saved workflow retains task tool results for its own continuation',
    () async {
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          [_goalAutoContinueAnalyzeCall('call-workflow-analyze')],
        ],
        finalAnswerChunkBatches: const [
          ['The current saved task still has unresolved diagnostics.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'analyze_project': jsonEncode({
            'diagnostics': [
              {
                'severity': 'Error',
                'path': '/tmp/workflow-owned/lib/main.dart',
                'relative_path': 'lib/main.dart',
                'line': 4,
                'column': 3,
                'code': 'undefined_identifier',
                'message': 'Undefined name store',
              },
            ],
          }),
        },
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: toolService,
        projectId: 'workflow-owned',
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'workflow-owned',
      );
      await conversations.updateCurrentWorkflow(
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Implement the saved workflow',
          tasks: [
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Implement the store',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
            ConversationWorkflowTask(id: 'task-2', title: 'Implement the CLI'),
          ],
        ),
      );
      await conversations.saveCurrentGoal(
        objective: 'Implement the saved workflow',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 5,
      );

      final chatNotifier = container.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage(
        'Run the first saved task.',
        bypassPlanMode: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(dataSource.initialRequestMessages, hasLength(1));
      expect(
        chatNotifier.takeLatestToolResults().map((result) => result.name),
        contains('analyze_project'),
      );
      expect(
        container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal
            ?.status,
        ConversationGoalStatus.active,
      );
    },
  );

  test(
    'goal auto-continue retains diagnostics across tool-free hidden turns',
    () async {
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          [
            ToolCallInfo(
              id: 'call-analyze-initial',
              name: 'analyze_project',
              arguments: {'command': 'dart analyze'},
            ),
          ],
          <ToolCallInfo>[],
          <ToolCallInfo>[],
        ],
        streamChunkBatches: const [
          <String>[],
          ['No new verification evidence was produced.'],
          ['Still no new verification evidence was produced.'],
        ],
        finalAnswerChunkBatches: const [
          ['Analyzer still reports unresolved errors.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'analyze_project': _goalAutoContinueDiagnosticPayload(
            count: 2,
            path: 'lib/main.dart',
          ),
        },
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: toolService,
        projectId: 'goal-auto-preserve-evidence',
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'goal-auto-preserve-evidence',
      );
      await conversations.saveCurrentGoal(
        objective: 'Fix analyzer diagnostics',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 5,
      );

      final chatNotifier = container.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage(
        'Fix analyzer diagnostics.',
        bypassPlanMode: true,
      );

      await _waitForCondition(() {
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        return !chatNotifier.state.isLoading &&
            goal?.status == ConversationGoalStatus.blocked;
      });

      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.goal;
      expect(dataSource.initialRequestMessages, hasLength(3));
      expect(goal?.blockedReason, contains('diagnostics remained'));
    },
  );

  test(
    'goal auto-continue grants one extension for decreasing diagnostics',
    () async {
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          [_goalAutoContinueAnalyzeCall('call-analyze-budget-initial')],
          [_goalAutoContinueAnalyzeCall('call-analyze-budget-first')],
          [_goalAutoContinueAnalyzeCall('call-analyze-budget-second')],
        ],
        streamChunkBatches: const [<String>[], <String>[], <String>[]],
        finalAnswerChunkBatches: const [
          ['Three diagnostics remain.'],
          ['Two diagnostics remain.'],
          ['One diagnostic remains.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'analyze_project': 'unused fallback'},
        queuedResults: {
          'analyze_project': [
            _goalAutoContinueDiagnosticPayload(
              count: 3,
              path: 'bin/todo_cli.dart',
            ),
            _goalAutoContinueDiagnosticPayload(
              count: 2,
              path: 'bin/todo_cli.dart',
            ),
            _goalAutoContinueDiagnosticPayload(
              count: 1,
              path: 'bin/todo_cli.dart',
            ),
          ],
        },
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: toolService,
        projectId: 'goal-auto-diagnostic-budget',
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'goal-auto-diagnostic-budget',
      );
      await conversations.saveCurrentGoal(
        objective: 'Fix analyzer diagnostics',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 5,
      );

      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Fix analyzer diagnostics.', bypassPlanMode: true);

      await _waitForCondition(() {
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        return !container.read(chatNotifierProvider).isLoading &&
            goal?.status == ConversationGoalStatus.blocked;
      });

      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.goal;
      expect(dataSource.initialRequestMessages, hasLength(4));
      expect(goal?.blockedReason, contains('one progress-based extension'));
    },
  );

  test('goal continuation recovery recognizes the automatic prompt', () {
    final dataSource = _GoalAutoContinueChatDataSource(
      toolCallBatches: const [],
    );
    final container = _goalAutoContinueContainer(
      dataSource: dataSource,
      toolService: _FakeMcpToolService(results: const {}),
      projectId: 'goal-auto-recovery-marker',
    );
    addTearDown(container.dispose);
    final notifier = container.read(chatNotifierProvider.notifier);
    final diagnosticContinuation = String.fromCharCodes(const [
      0x307e,
      0x305a,
      0x73fe,
      0x5728,
      0x306e,
      0x30a8,
      0x30e9,
      0x30fc,
      0x72b6,
      0x614b,
      0x3092,
      0x78ba,
      0x8a8d,
      0x3057,
      0x3001,
      0x4fee,
      0x6b63,
      0x3057,
      0x307e,
      0x3059,
      0x3002,
    ]);

    expect(
      notifier.looksLikeContinuationOnlyUserRequestForTest(
        'Automatic goal continuation 3/10. Continue the saved objective.',
      ),
      isTrue,
    );
    expect(
      notifier.looksLikeProseOnlyCodingContinuationForTest(
        diagnosticContinuation,
      ),
      isTrue,
    );
  });

  test(
    'coding continuation recovery recognizes a long fenced implementation',
    () {
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: const [],
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: _FakeMcpToolService(results: const {}),
        projectId: 'long-fenced-implementation-recovery',
      );
      addTearDown(container.dispose);
      final notifier = container.read(chatNotifierProvider.notifier);
      final response = StringBuffer(
        'Next I will implement the project file.\n```dart\n',
      );
      for (var index = 0; index < 180; index += 1) {
        response.writeln('void helper$index() {}');
      }
      response.write('```');

      expect(response.length, greaterThan(1600));
      expect(
        notifier.looksLikeProseOnlyCodingContinuationForTest(
          response.toString(),
        ),
        isTrue,
      );
      expect(
        notifier.looksLikeProseOnlyCodingContinuationForTest(
          'The project contains a long explanation. ${'details ' * 300}',
        ),
        isFalse,
      );
    },
  );

  test(
    'goal auto-continue clears approval result cache before hidden turns',
    () async {
      final commandArguments = {
        'command': 'dart test',
        'working_directory': '/tmp/goal-auto-approval-cache',
      };
      final commandCall = ToolCallInfo(
        id: 'call-risky-verifier',
        name: 'local_execute_command',
        arguments: commandArguments,
      );
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          [commandCall],
          [
            ToolCallInfo(
              id: 'call-risky-verifier-continuation',
              name: 'local_execute_command',
              arguments: commandArguments,
            ),
          ],
        ],
        finalAnswerChunkBatches: const [
          ['Verifier still reports unresolved errors.'],
          ['Verifier passed after the fix.'],
        ],
        autoReviewResponses: [
          ChatCompletionResult(
            content:
                '{"outcome":"allow","riskLevel":"medium","userAuthorization":"high","rationale":"The user requested this scoped verification command."}',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content:
                '{"outcome":"allow","riskLevel":"medium","userAuthorization":"high","rationale":"The continuation needs to re-run the same verification command."}',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'local_execute_command': 'Execute a local shell command.',
        },
        results: const {'local_execute_command': 'unexpected cached result'},
        queuedResults: {
          'local_execute_command': [
            _goalAutoContinueDiagnosticPayload(
              count: 1,
              path: 'bin/todo_cli.dart',
            ),
            jsonEncode({
              ...commandArguments,
              'exit_code': 0,
              'stdout': 'No issues found.',
              'stderr': '',
            }),
          ],
        },
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: toolService,
        projectId: 'goal-auto-approval-cache',
        settingsBuilder: _ToolEnabledAutoReviewSettingsNotifier.new,
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'goal-auto-approval-cache',
      );
      await conversations.saveCurrentGoal(
        objective: 'Fix the TODO CLI diagnostics',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 5,
      );

      final chatNotifier = container.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Fix the TODO CLI.', bypassPlanMode: true);

      await _waitForCondition(() {
        final state = container.read(chatNotifierProvider);
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        return !state.isLoading &&
            dataSource.initialRequestMessages.length == 2 &&
            goal?.turnsUsed == 2;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(dataSource.autoReviewRequestMessages, hasLength(2));
      expect(toolService.executedToolNames, [
        'local_execute_command',
        'local_execute_command',
      ]);
      expect(
        dataSource.toolResultBatches.last.single.result,
        contains('"exit_code":0'),
      );
      expect(chatNotifier.state.goalAutoContinueCount, 0);
      expect(chatNotifier.state.goalAutoContinueBudget, 0);
    },
  );

  test(
    'goal auto-continue derives evidence from content-embedded tool results',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final streamingDataSource = _QueuedStreamingChatDataSource([
        [
          '<tool_call>{"name":"local_execute_command","arguments":{"command":"python3 check.py --verify","working_directory":"/tmp/goal-auto-content-tool"}}</tool_call>',
        ],
        ['Verifier still reports unresolved errors.'],
        [
          '<tool_call>{"name":"local_execute_command","arguments":{"command":"python3 check.py","working_directory":"/tmp/goal-auto-content-tool"}}</tool_call>',
        ],
        ['Automatic continuation verified the clean result.'],
      ]);
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'local_execute_command': 'Execute a local shell command.',
        },
        results: const {'local_execute_command': 'unexpected fallback'},
        queuedResults: {
          'local_execute_command': [
            jsonEncode({
              'command': 'python3 check.py --verify',
              'working_directory': '/tmp/goal-auto-content-tool',
              'exit_code': 1,
              'stdout': '',
              'stderr': 'Undefined name store',
              'diagnostics': [
                {
                  'severity': 'Error',
                  'path': '/tmp/goal-auto-content-tool/bin/todo_cli.dart',
                  'relative_path': 'bin/todo_cli.dart',
                  'line': 12,
                  'column': 7,
                  'code': 'undefined_identifier',
                  'message': 'Undefined name store',
                },
              ],
            }),
            jsonEncode({
              'command': 'python3 check.py',
              'working_directory': '/tmp/goal-auto-content-tool',
              'exit_code': 0,
              'stdout': 'No issues found.',
              'stderr': '',
              'diagnostics': const <Object>[],
            }),
          ],
        },
      );
      final project = CodingProject(
        id: 'goal-auto-content-tool',
        name: 'Goal Auto Content Tool',
        rootPath: '/tmp/goal-auto-content-tool',
        createdAt: DateTime(2026, 5, 25, 10),
        updatedAt: DateTime(2026, 5, 25, 10),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ContentToolNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
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
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
        createIfMissing: true,
      );
      await conversations.saveCurrentGoal(
        objective: 'Fix the TODO CLI diagnostics',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 5,
      );

      final chatNotifier = container.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Fix the TODO CLI.', bypassPlanMode: true);

      await _waitForCondition(() {
        final state = container.read(chatNotifierProvider);
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        return !state.isLoading &&
            streamingDataSource.requests.length >= 4 &&
            goal?.turnsUsed == 2;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(toolService.executedToolNames, [
        'local_execute_command',
        'local_execute_command',
      ]);
      expect(streamingDataSource.requests, hasLength(4));
      expect(
        streamingDataSource.requests[2]
            .where((message) => message.role == MessageRole.user)
            .map((message) => message.content)
            .join('\n'),
        contains('Automatic goal continuation 2/5.'),
      );
      expect(chatNotifier.state.goalAutoContinueCount, 0);
      expect(chatNotifier.state.goalAutoContinueBudget, 0);
    },
  );

  test('goal auto-continue stays idle when the goal flag is off', () async {
    final dataSource = _GoalAutoContinueChatDataSource(
      toolCallBatches: [
        [
          ToolCallInfo(
            id: 'call-analyze-project',
            name: 'analyze_project',
            arguments: const {'command': 'dart analyze'},
          ),
        ],
      ],
      finalAnswerChunkBatches: const [
        ['Analyzer still reports unresolved errors.'],
      ],
    );
    final toolService = _FakeMcpToolService(
      results: {
        'analyze_project': jsonEncode({
          'diagnostics': [
            {
              'severity': 'Error',
              'path': '/tmp/todo/bin/todo_cli.dart',
              'relative_path': 'bin/todo_cli.dart',
              'line': 12,
              'column': 7,
              'code': 'undefined_identifier',
              'message': 'Undefined name store',
            },
          ],
        }),
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final project = CodingProject(
      id: 'goal-auto-continue-off',
      name: 'Goal Auto Continue Off',
      rootPath: '/tmp/goal-auto-continue-off',
      createdAt: DateTime(2026, 5, 25, 10),
      updatedAt: DateTime(2026, 5, 25, 10),
    );
    final autoOffContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        conversationsNotifierProvider.overrideWith(
          _GoalAutoContinueConversationsNotifier.new,
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
    addTearDown(autoOffContainer.dispose);

    final conversations = autoOffContainer.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.ensureCurrentConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'goal-auto-continue-off',
    );
    await conversations.saveCurrentGoal(
      objective: 'Fix the TODO CLI diagnostics',
      enabled: true,
      status: ConversationGoalStatus.active,
    );

    final chatNotifier = autoOffContainer.read(chatNotifierProvider.notifier);
    await chatNotifier.sendMessage('Fix the TODO CLI.', bypassPlanMode: true);

    await _waitForCondition(() {
      final state = autoOffContainer.read(chatNotifierProvider);
      final goal = autoOffContainer
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.goal;
      return !state.isLoading && goal?.turnsUsed == 1;
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(dataSource.initialRequestMessages, hasLength(1));
    expect(toolService.executedToolNames, ['analyze_project']);
    expect(chatNotifier.state.goalAutoContinueCount, 0);
    expect(chatNotifier.state.goalAutoContinueBudget, 0);
  });

  test(
    'goal auto-continue marks the goal blocked after stalled diagnostics',
    () async {
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          [_goalAutoContinueAnalyzeCall('call-analyze-initial')],
          [_goalAutoContinueAnalyzeCall('call-analyze-continue-1')],
          [_goalAutoContinueAnalyzeCall('call-analyze-continue-2')],
        ],
        finalAnswerChunkBatches: const [
          ['Analyzer still reports unresolved errors.'],
          ['Analyzer still reports the same unresolved errors.'],
          ['Analyzer still reports the same unresolved errors again.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'analyze_project': _goalAutoContinueDiagnosticPayload(
            count: 2,
            path: 'bin/todo_cli.dart',
          ),
        },
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: toolService,
        projectId: 'goal-auto-continue-stall',
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'goal-auto-continue-stall',
      );
      await conversations.saveCurrentGoal(
        objective: 'Fix the TODO CLI diagnostics',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 5,
      );

      final chatNotifier = container.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Fix the TODO CLI.', bypassPlanMode: true);

      await _waitForCondition(() {
        final state = container.read(chatNotifierProvider);
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        return !state.isLoading &&
            goal?.status == ConversationGoalStatus.blocked;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.goal;
      expect(dataSource.initialRequestMessages, hasLength(3));
      expect(toolService.executedToolNames, [
        'analyze_project',
        'analyze_project',
        'analyze_project',
      ]);
      expect(goal?.blockedReason, contains('diagnostics remained'));
      expect(chatNotifier.state.goalAutoContinueCount, 0);
      expect(chatNotifier.state.goalAutoContinueBudget, 0);
    },
  );

  test(
    'goal auto-continue blocks when a validation-only turn is ignored',
    () async {
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          [_goalAutoContinueWriteCall('call-write-initial')],
          <ToolCallInfo>[],
        ],
        streamChunkBatches: const [
          <String>[],
          ['Validation was not executed.'],
        ],
        finalAnswerChunkBatches: const [
          ['Updated the documentation.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file': 'unused',
          'local_execute_command': 'unused',
        },
        queuedResults: const {
          'write_file': [
            '{"path":"/tmp/goal-auto-unverified/README.md","bytes_written":18}',
            '{"path":"/tmp/goal-auto-unverified/README.md","bytes_written":18}',
          ],
        },
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: toolService,
        projectId: 'goal-auto-unverified',
        settingsBuilder: _ToolEnabledNoConfirmSettingsNotifier.new,
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'goal-auto-unverified',
      );
      await conversations.saveCurrentGoal(
        objective: 'Update the README docs',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 5,
      );

      final chatNotifier = container.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage(
        'Update the README.',
        bypassPlanMode: true,
      );

      await _waitForCondition(() {
        final state = container.read(chatNotifierProvider);
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        return !state.isLoading &&
            goal?.turnsUsed == 2 &&
            goal?.status == ConversationGoalStatus.blocked;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.goal;
      expect(dataSource.initialRequestMessages, hasLength(2));
      expect(toolService.executedToolNames, ['write_file']);
      expect(
        ToolDefinitionSearchService.toolNamesFromDefinitions(
          dataSource.initialToolDefinitions[1],
        ),
        {'local_execute_command'},
      );
      expect(
        dataSource.initialRequestMessages[1]
            .where((message) => message.role == MessageRole.user)
            .map((message) => message.content)
            .join('\n'),
        contains('This is a validation-only continuation.'),
      );
      expect(goal?.status, ConversationGoalStatus.blocked);
      expect(goal?.blockedReason, contains('dedicated validation turn'));
      expect(chatNotifier.state.goalAutoContinueNotice, isNull);
      expect(chatNotifier.state.goalAutoContinueCount, 0);
      expect(chatNotifier.state.goalAutoContinueBudget, 0);
    },
  );

  test(
    'goal auto-continue repairs exit-zero command output failures',
    () async {
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          [_goalAutoContinueWriteCall('call-write-initial')],
          [
            ToolCallInfo(
              id: 'call-runtime-validation',
              name: 'local_execute_command',
              arguments: const {
                'command': 'dart run bin/todo.dart done 999',
                'working_directory': '/tmp/goal-auto-output-feedback',
              },
            ),
          ],
          const <ToolCallInfo>[],
        ],
        streamChunkBatches: const [
          <String>[],
          <String>[],
          ['Concrete runtime failure recorded.'],
        ],
        finalAnswerChunkBatches: const [
          ['Initial implementation requires validation.'],
          ['Validation found a runtime failure.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file': 'unused',
          'local_execute_command': 'unused',
        },
        queuedResults: {
          'write_file': const [
            '{"path":"/tmp/goal-auto-output-feedback/README.md",'
                '"bytes_written":18}',
          ],
          'local_execute_command': [
            jsonEncode({
              'command': 'dart run bin/todo.dart done 999',
              'working_directory': '/tmp/goal-auto-output-feedback',
              'exit_code': 0,
              'stdout': '',
              'stderr':
                  'Unhandled exception: Bad state: task with id 999 not found.',
            }),
          ],
        },
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: toolService,
        projectId: 'goal-auto-output-feedback',
        settingsBuilder: _ToolEnabledNoConfirmSettingsNotifier.new,
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'goal-auto-output-feedback',
      );
      await conversations.saveCurrentGoal(
        objective: 'Implement and verify the TODO CLI',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 3,
      );

      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Implement the TODO CLI.', bypassPlanMode: true);

      await _waitForCondition(() {
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        return !container.read(chatNotifierProvider).isLoading &&
            dataSource.initialRequestMessages.length == 3 &&
            goal?.turnsUsed == 3;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(toolService.executedToolNames, [
        'write_file',
        'local_execute_command',
      ]);
      expect(
        dataSource.toolResultBatches[1].map((result) => result.name),
        containsAll([
          'local_execute_command',
          CodingCommandOutputGuardrailService.toolName,
        ]),
      );
      final offeredToolNames = dataSource.initialToolDefinitions
          .map(ToolDefinitionSearchService.toolNamesFromDefinitions)
          .toList(growable: false);
      expect(offeredToolNames[1], {'local_execute_command'});
      expect(offeredToolNames[2], {'write_file', 'local_execute_command'});
      final repairPrompt = dataSource.initialRequestMessages[2]
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content)
          .join('\n');
      expect(repairPrompt, contains('execution verification failed'));
      expect(repairPrompt, contains('unresolved Error diagnostic'));
      expect(
        repairPrompt,
        isNot(contains('This is a validation-only continuation.')),
      );
    },
  );

  test(
    'goal auto-continue rejects shell mutations during validation-only turns',
    () async {
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          [_goalAutoContinueWriteCall('call-write-before-validation')],
          [
            ToolCallInfo(
              id: 'call-shell-mutation-during-validation',
              name: 'local_execute_command',
              arguments: const {
                'command': "cat > README.md <<'EOF'\nchanged\nEOF",
                'working_directory': '/tmp/goal-auto-validation-shell-guard',
              },
            ),
          ],
        ],
        finalAnswerChunkBatches: const [
          ['Initial implementation requires validation.'],
          ['The validation-only command was rejected.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file': 'unused',
          'local_execute_command': '{"command":"unexpected","exit_code":0}',
        },
        queuedResults: const {
          'write_file': [
            '{"path":"/tmp/goal-auto-validation-shell-guard/README.md",'
                '"bytes_written":18}',
          ],
        },
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: toolService,
        projectId: 'goal-auto-validation-shell-guard',
        settingsBuilder: _ToolEnabledNoConfirmSettingsNotifier.new,
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'goal-auto-validation-shell-guard',
      );
      await conversations.saveCurrentGoal(
        objective: 'Implement and verify the fixture',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 5,
      );

      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Implement the fixture.', bypassPlanMode: true);

      await _waitForCondition(() {
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        return !container.read(chatNotifierProvider).isLoading &&
            dataSource.initialRequestMessages.length == 2 &&
            goal?.status == ConversationGoalStatus.blocked;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(toolService.executedToolNames, ['write_file']);
      expect(
        dataSource.toolResultBatches[1].single.result,
        contains('goal_validation_probe_requires_verifier'),
      );
      expect(
        dataSource.toolResultBatches[1].single.result,
        contains('workspaceMutation'),
      );
      final validationPrompt = dataSource.initialRequestMessages[1]
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content)
          .join('\n');
      expect(validationPrompt, contains('Only verification-effect commands'));
      expect(validationPrompt, contains('shell-based file mutation'));
      expect(validationPrompt, contains('next bounded continuation'));
    },
  );

  test(
    'goal validation accepts a scoped compound verification command',
    () async {
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          [_goalAutoContinueWriteCall('call-write-before-scoped-validation')],
          [
            ToolCallInfo(
              id: 'call-scoped-validation',
              name: 'local_execute_command',
              arguments: const {
                'command':
                    'cd /tmp/goal-auto-scoped-validation && dart analyze',
                'working_directory': '/tmp/goal-auto-scoped-validation',
              },
            ),
          ],
        ],
        finalAnswerChunkBatches: const [
          ['Initial implementation requires validation.'],
          ['The scoped analyzer command passed.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file': 'unused',
          'local_execute_command': 'unused',
        },
        queuedResults: const {
          'write_file': [
            '{"path":"/tmp/goal-auto-scoped-validation/README.md",'
                '"bytes_written":18}',
          ],
          'local_execute_command': [
            '{"command":"cd /tmp/goal-auto-scoped-validation && '
                'dart analyze","exit_code":0,"stdout":"No issues found."}',
          ],
        },
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: toolService,
        projectId: 'goal-auto-scoped-validation',
        useRealConversationsNotifier: true,
        settingsBuilder: _ToolEnabledNoConfirmSettingsNotifier.new,
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'goal-auto-scoped-validation',
        createIfMissing: true,
      );
      await conversations.saveCurrentGoal(
        objective: 'Implement and verify the fixture',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 2,
      );

      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Implement the fixture.', bypassPlanMode: true);

      await _waitForCondition(() {
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        return !container.read(chatNotifierProvider).isLoading &&
            dataSource.initialRequestMessages.length == 2 &&
            goal?.turnsUsed == 2;
      });

      expect(toolService.executedToolNames, [
        'write_file',
        'local_execute_command',
      ]);
      expect(
        dataSource.toolResultBatches[1].single.result,
        isNot(contains('goal_validation_probe_requires_verifier')),
      );
      expect(
        dataSource.toolResultBatches[1].single.result,
        contains('exit_code'),
      );
    },
  );

  test(
    'goal auto-continue extends once when repair replay advances diagnostics',
    () async {
      ToolCallInfo verifierCall(String id) => ToolCallInfo(
        id: id,
        name: 'local_execute_command',
        arguments: const {
          'command': 'dart run tool/verify.dart',
          'working_directory': '/tmp/goal-auto-capability-gate',
        },
      );

      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          [verifierCall('call-verify-failing')],
          [verifierCall('call-verify-plateau')],
          [_goalAutoContinueWriteCall('call-write-plateau-repair')],
          [verifierCall('call-verify-advanced-diagnostics')],
        ],
        finalAnswerChunkBatches: const [
          ['Verification found one concrete error.'],
          ['Verification found the same concrete error.'],
          ['Applied the plateau repair.'],
          ['Verified the concrete follow-up repair.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file': 'unused',
          'local_execute_command': 'unused',
        },
        queuedResults: {
          'write_file': const [
            '{"path":"/tmp/goal-auto-capability-gate/README.md","bytes_written":22}',
          ],
          'local_execute_command': [
            jsonEncode({
              'command': 'dart run tool/verify.dart',
              'exit_code': 1,
              'diagnostics': [
                {
                  'severity': 'Error',
                  'path': '/tmp/goal-auto-capability-gate/README.md',
                  'relative_path': 'README.md',
                  'line': 1,
                  'column': 1,
                  'code': 'fixture_failure',
                  'message': 'Expected repaired content.',
                },
              ],
            }),
            jsonEncode({
              'command': 'dart run tool/verify.dart',
              'exit_code': 1,
              'diagnostics': [
                {
                  'severity': 'Error',
                  'path': '/tmp/goal-auto-capability-gate/README.md',
                  'relative_path': 'README.md',
                  'line': 1,
                  'column': 1,
                  'code': 'fixture_failure',
                  'message': 'Expected repaired content.',
                },
              ],
            }),
            jsonEncode({
              'command': 'dart run tool/verify.dart',
              'exit_code': 1,
              'diagnostics': [
                {
                  'severity': 'Error',
                  'path': '/tmp/goal-auto-capability-gate/README.md',
                  'relative_path': 'README.md',
                  'line': 2,
                  'column': 1,
                  'code': 'concrete_failure_one',
                  'message': 'Apply the first concrete repair.',
                },
                {
                  'severity': 'Error',
                  'path': '/tmp/goal-auto-capability-gate/README.md',
                  'relative_path': 'README.md',
                  'line': 3,
                  'column': 1,
                  'code': 'concrete_failure_two',
                  'message': 'Apply the second concrete repair.',
                },
              ],
            }),
            jsonEncode({
              'command': 'dart run tool/verify.dart',
              'exit_code': 0,
              'diagnostics': const <Object>[],
            }),
          ],
        },
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: toolService,
        projectId: 'goal-auto-capability-gate',
        settingsBuilder: _ToolEnabledNoConfirmSettingsNotifier.new,
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'goal-auto-capability-gate',
      );
      await conversations.saveCurrentGoal(
        objective: 'Implement and verify the fixture',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 5,
      );

      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Implement the fixture.', bypassPlanMode: true);

      await _waitForCondition(() {
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        return !container.read(chatNotifierProvider).isLoading &&
            dataSource.initialRequestMessages.length == 4 &&
            goal?.turnsUsed == 4;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final offeredToolNames = dataSource.initialToolDefinitions
          .map(ToolDefinitionSearchService.toolNamesFromDefinitions)
          .toList(growable: false);
      expect(offeredToolNames, [
        {'write_file', 'local_execute_command'},
        {'write_file', 'local_execute_command'},
        {'write_file'},
        {'write_file', 'local_execute_command'},
      ]);
      final repairPrompt = dataSource.initialRequestMessages[2]
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content)
          .join('\n');
      expect(repairPrompt, contains('<repair_contract>'));
      expect(repairPrompt, contains('This is a repair-only continuation.'));
      expect(
        repairPrompt,
        contains('README.md: [fixture_failure] Expected repaired content.'),
      );
      expect(
        repairPrompt,
        contains('write_file when a required file is missing'),
      );
      expect(
        repairPrompt,
        isNot(contains('This is a validation-only continuation.')),
      );
      expect(toolService.executedToolNames, [
        'local_execute_command',
        'local_execute_command',
        'write_file',
        'local_execute_command',
        'local_execute_command',
      ]);
      expect(dataSource.toolResultToolDefinitions[2], isEmpty);
      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.goal;
      expect(goal?.status, isNot(ConversationGoalStatus.blocked));
    },
  );

  test(
    'goal auto-continue retries one repair turn that made no mutation',
    () async {
      ToolCallInfo verifierCall(String id) => ToolCallInfo(
        id: id,
        name: 'local_execute_command',
        arguments: const {
          'command': 'dart run tool/verify.dart',
          'working_directory': '/tmp/goal-auto-no-mutation-retry',
        },
      );

      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          [verifierCall('call-verify-failing')],
          [verifierCall('call-verify-plateau')],
          const <ToolCallInfo>[],
          [_goalAutoContinueWriteCall('call-write-retry-repair')],
        ],
        streamChunkBatches: const [
          <String>[],
          <String>[],
          ['Let me inspect the file before changing it.'],
          <String>[],
        ],
        finalAnswerChunkBatches: const [
          ['Verification found one concrete error.'],
          ['Verification found the same concrete error.'],
          ['Applied the retry repair.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file': 'unused',
          'local_execute_command': 'unused',
        },
        queuedResults: {
          'write_file': const [
            '{"path":"/tmp/goal-auto-no-mutation-retry/README.md",'
                '"bytes_written":22}',
          ],
          'local_execute_command': [
            for (var index = 0; index < 2; index += 1)
              jsonEncode({
                'command': 'dart run tool/verify.dart',
                'exit_code': 1,
                'diagnostics': [
                  {
                    'severity': 'Error',
                    'path': '/tmp/goal-auto-no-mutation-retry/README.md',
                    'relative_path': 'README.md',
                    'line': 1,
                    'column': 1,
                    'code': 'fixture_failure',
                    'message': 'Expected repaired content.',
                  },
                ],
              }),
            jsonEncode({
              'command': 'dart run tool/verify.dart',
              'exit_code': 0,
              'diagnostics': const <Object>[],
            }),
          ],
        },
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: toolService,
        projectId: 'goal-auto-no-mutation-retry',
        settingsBuilder: _ToolEnabledNoConfirmSettingsNotifier.new,
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'goal-auto-no-mutation-retry',
      );
      await conversations.saveCurrentGoal(
        objective: 'Implement and verify the fixture',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 5,
      );

      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Implement the fixture.', bypassPlanMode: true);

      await _waitForCondition(() {
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        return !container.read(chatNotifierProvider).isLoading &&
            dataSource.initialRequestMessages.length == 4 &&
            goal?.turnsUsed == 4;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final offeredToolNames = dataSource.initialToolDefinitions
          .map(ToolDefinitionSearchService.toolNamesFromDefinitions)
          .toList(growable: false);
      expect(offeredToolNames, [
        {'write_file', 'local_execute_command'},
        {'write_file', 'local_execute_command'},
        {'write_file'},
        {'write_file'},
      ]);
      expect(toolService.executedToolNames, [
        'local_execute_command',
        'local_execute_command',
        'write_file',
        'local_execute_command',
      ]);
      final retryPrompt = dataSource.initialRequestMessages[3]
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content)
          .join('\n');
      expect(retryPrompt, contains('This is the only retry.'));
      expect(retryPrompt, contains('call exactly one available'));
      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.goal;
      expect(goal?.status, isNot(ConversationGoalStatus.blocked));
    },
  );

  test('replays the last verifier once after a later mutation', () async {
    const verifierArguments = {
      'command': 'dart run tool/verify_fixture.dart',
      'working_directory': '/tmp/post-mutation-verifier-replay',
      'reason': 'Verify the fixture.',
    };
    final dataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'verify-before-repair',
          name: 'local_execute_command',
          arguments: verifierArguments,
        ),
      ],
      toolLoopResponses: [
        ChatCompletionResult(
          content: 'Checking the repaired source.',
          toolCalls: [
            ToolCallInfo(
              id: 'analyze-before-repair',
              name: 'local_execute_command',
              arguments: const {
                'command': 'dart analyze bin/main.dart',
                'working_directory': '/tmp/post-mutation-verifier-replay',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'Applying the final repair.',
          toolCalls: [_goalAutoContinueWriteCall('write-final-repair')],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'The repair is complete.',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content: 'The replayed verifier passed.',
          finishReason: 'stop',
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'write_file': 'unused',
        'local_execute_command': 'unused',
      },
      queuedResults: {
        'local_execute_command': [
          jsonEncode({...verifierArguments, 'exit_code': 0}),
          jsonEncode({'command': 'dart analyze bin/main.dart', 'exit_code': 1}),
          jsonEncode({...verifierArguments, 'exit_code': 0}),
        ],
        'write_file': const [
          '{"path":"/tmp/post-mutation-verifier-replay/README.md","bytes_written":18}',
        ],
      },
    );
    final container = _goalAutoContinueContainer(
      dataSource: dataSource,
      toolService: toolService,
      projectId: 'post-mutation-verifier-replay',
      settingsBuilder: _ToolEnabledNoConfirmSettingsNotifier.new,
    );
    addTearDown(container.dispose);
    container
        .read(conversationsNotifierProvider.notifier)
        .ensureCurrentConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'post-mutation-verifier-replay',
        );

    final chatNotifier = container.read(chatNotifierProvider.notifier);
    expect(
      chatNotifier.isVerifierReplayEligibleForTest(
        ToolCallInfo(
          id: 'compound-verifier',
          name: 'local_execute_command',
          arguments: const {'command': 'dart test && deploy production'},
        ),
      ),
      isFalse,
    );
    expect(
      chatNotifier.isVerifierReplayEligibleForTest(
        ToolCallInfo(
          id: 'scoped-verifier',
          name: 'local_execute_command',
          arguments: verifierArguments,
        ),
      ),
      isTrue,
    );

    await chatNotifier.sendMessage(
      'Implement and verify the fixture.',
      bypassPlanMode: true,
    );
    await _waitForCondition(
      () => !container.read(chatNotifierProvider).isLoading,
    );

    expect(toolService.executedToolNames, [
      'local_execute_command',
      'local_execute_command',
      'write_file',
      'local_execute_command',
    ]);
    expect(toolService.executedToolArguments.first, verifierArguments);
    expect(toolService.executedToolArguments.last, verifierArguments);
  });

  test(
    'does not carry a verifier replay candidate into the next task',
    () async {
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: const [],
      );
      final toolService = _FakeMcpToolService(results: const {});
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: toolService,
        projectId: 'task-scoped-verifier-replay',
      );
      addTearDown(container.dispose);
      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'task-scoped-verifier-replay',
      );
      await conversations.updateCurrentWorkflow(
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Build storage',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
            ConversationWorkflowTask(id: 'task-2', title: 'Build the CLI'),
          ],
        ),
      );

      final chatNotifier = container.read(chatNotifierProvider.notifier);
      chatNotifier.recordExecutedVerifierReplayCandidateForTest(
        ToolCallInfo(
          id: 'task-1-verifier',
          name: 'run_tests',
          arguments: {'test_path': 'test/storage_test.dart'},
        ),
      );
      expect(
        chatNotifier.hasVerifierReplayCandidateForCurrentTaskForTest(),
        isTrue,
      );

      await conversations.updateCurrentWorkflow(
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Build storage',
              status: ConversationWorkflowTaskStatus.completed,
            ),
            ConversationWorkflowTask(
              id: 'task-2',
              title: 'Build the CLI',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
      );

      expect(
        chatNotifier.hasVerifierReplayCandidateForCurrentTaskForTest(),
        isFalse,
      );
      chatNotifier.recordExecutedVerifierReplayCandidateForTest(
        ToolCallInfo(
          id: 'task-2-verifier',
          name: 'local_execute_command',
          arguments: {'command': 'dart analyze bin/todo_cli.dart'},
        ),
      );
      expect(
        chatNotifier.hasVerifierReplayCandidateForCurrentTaskForTest(),
        isTrue,
      );
    },
  );

  test('cancelStreaming clears the goal auto-continue indicator', () async {
    final hiddenPromptGate = Completer<void>();
    final dataSource = _GoalAutoContinueChatDataSource(
      toolCallBatches: [
        [_goalAutoContinueAnalyzeCall('call-analyze-initial')],
        [_goalAutoContinueAnalyzeCall('call-analyze-hidden')],
      ],
      toolCompletionGates: {2: hiddenPromptGate.future},
      finalAnswerChunkBatches: const [
        ['Analyzer still reports unresolved errors.'],
        ['Hidden continuation should be cancelled.'],
      ],
    );
    final toolService = _FakeMcpToolService(
      results: {
        'analyze_project': _goalAutoContinueDiagnosticPayload(
          count: 1,
          path: 'bin/todo_cli.dart',
        ),
      },
    );
    final container = _goalAutoContinueContainer(
      dataSource: dataSource,
      toolService: toolService,
      projectId: 'goal-auto-cancel',
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.ensureCurrentConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'goal-auto-cancel',
    );
    await conversations.saveCurrentGoal(
      objective: 'Fix the TODO CLI diagnostics',
      enabled: true,
      autoContinue: true,
      status: ConversationGoalStatus.active,
      turnBudget: 5,
    );

    final chatNotifier = container.read(chatNotifierProvider.notifier);
    final sendFuture = chatNotifier.sendMessage(
      'Fix the TODO CLI.',
      bypassPlanMode: true,
    );

    await _waitForCondition(() {
      final state = container.read(chatNotifierProvider);
      return dataSource.initialRequestMessages.length == 2 &&
          state.goalAutoContinueCount == 2 &&
          state.goalAutoContinueBudget == 5;
    });

    chatNotifier.cancelStreaming();
    expect(chatNotifier.state.goalAutoContinueCount, 0);
    expect(chatNotifier.state.goalAutoContinueBudget, 0);

    hiddenPromptGate.complete();
    await sendFuture;
    await _waitForCondition(() {
      final state = container.read(chatNotifierProvider);
      return !state.isLoading && state.goalAutoContinueCount == 0;
    });
  });

  test(
    'goal auto-continue stops at the turn budget without hiding the active goal',
    () async {
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          [_goalAutoContinueAnalyzeCall('call-analyze-budget')],
        ],
        finalAnswerChunkBatches: const [
          ['Analyzer still reports unresolved errors.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'analyze_project': _goalAutoContinueDiagnosticPayload(
            count: 1,
            path: 'bin/todo_cli.dart',
          ),
        },
      );
      final container = _goalAutoContinueContainer(
        dataSource: dataSource,
        toolService: toolService,
        projectId: 'goal-auto-continue-budget',
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'goal-auto-continue-budget',
      );
      await conversations.saveCurrentGoal(
        objective: 'Fix the TODO CLI diagnostics',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 1,
      );

      final chatNotifier = container.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Fix the TODO CLI.', bypassPlanMode: true);

      await _waitForCondition(() {
        final state = container.read(chatNotifierProvider);
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        return !state.isLoading && goal?.turnsUsed == 1;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.goal;
      expect(dataSource.initialRequestMessages, hasLength(1));
      expect(toolService.executedToolNames, ['analyze_project']);
      expect(goal?.status, ConversationGoalStatus.active);
      expect(goal?.turnBudgetExceeded, isTrue);
      expect(
        chatNotifier.state.goalAutoContinueNotice,
        'chat.goal_auto_continue_budget_reached',
      );
      expect(chatNotifier.state.goalAutoContinueCount, 0);
      expect(chatNotifier.state.goalAutoContinueBudget, 0);
    },
  );
}

ProviderContainer _goalAutoContinueContainer({
  required ChatDataSource dataSource,
  required _FakeMcpToolService toolService,
  required String projectId,
  bool useRealConversationsNotifier = false,
  SettingsNotifier Function() settingsBuilder =
      _ToolEnabledSettingsNotifier.new,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  final project = CodingProject(
    id: projectId,
    name: projectId,
    rootPath: '/tmp/$projectId',
    createdAt: DateTime(2026, 5, 25, 10),
    updatedAt: DateTime(2026, 5, 25, 10),
  );
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(settingsBuilder),
      codingProjectsNotifierProvider.overrideWith(
        () => _FixedCodingProjectsNotifier(project),
      ),
      if (!useRealConversationsNotifier)
        conversationsNotifierProvider.overrideWith(
          _GoalAutoContinueConversationsNotifier.new,
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
}

ToolCallInfo _goalAutoContinueAnalyzeCall(String id) {
  return ToolCallInfo(
    id: id,
    name: 'analyze_project',
    arguments: const {'command': 'dart analyze'},
  );
}

ToolCallInfo _goalAutoContinueWriteCall(String id) {
  return ToolCallInfo(
    id: id,
    name: 'write_file',
    arguments: const {'path': 'README.md', 'content': 'Updated docs.\n'},
  );
}

String _goalAutoContinueDiagnosticPayload({
  required int count,
  required String path,
}) {
  return jsonEncode({
    'diagnostics': [
      for (var index = 0; index < count; index += 1)
        {
          'severity': 'Error',
          'path': '/tmp/todo/$path',
          'relative_path': path,
          'line': 12 + index,
          'column': 7,
          'code': 'undefined_identifier_$index',
          'message': 'Undefined name value$index',
        },
    ],
  });
}
