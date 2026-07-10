part of 'chat_notifier_test.dart';

// Goal auto-continuation provider tests live in a part file so
// chat_notifier_test.dart stays under its F1 size ratchet.
void registerChatNotifierGoalAutoContinueTests() {
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
        containsAllInOrder(['turn_exit', 'goal_auto_continue', 'turn_exit']),
      );
      final continuationEntry = sessionLogEntries.singleWhere(
        (entry) => entry['operation'] == 'goal_auto_continue',
      );
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
      expect(goal?.blockedReason, contains('no diagnostic progress'));
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
    'goal auto-continue clears approval result cache before hidden turns',
    () async {
      final commandArguments = {
        'command': 'rm -rf build',
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
      expect(goal?.blockedReason, contains('no diagnostic progress'));
      expect(chatNotifier.state.goalAutoContinueCount, 0);
      expect(chatNotifier.state.goalAutoContinueBudget, 0);
    },
  );

  test(
    'goal auto-continue stops unverified no-progress loops without blocking',
    () async {
      final dataSource = _GoalAutoContinueChatDataSource(
        toolCallBatches: [
          [_goalAutoContinueWriteCall('call-write-initial')],
          [_goalAutoContinueWriteCall('call-write-continue-1')],
          [_goalAutoContinueWriteCall('call-write-continue-2')],
        ],
        finalAnswerChunkBatches: const [
          ['Updated the documentation.'],
          ['Updated the documentation again.'],
          ['Updated the documentation one more time.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': 'unused'},
        queuedResults: const {
          'write_file': [
            '{"path":"/tmp/goal-auto-unverified/README.md","bytes_written":18}',
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
            goal?.turnsUsed == 3 &&
            state.goalAutoContinueNotice != null;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.goal;
      expect(dataSource.initialRequestMessages, hasLength(3));
      expect(toolService.executedToolNames, [
        'write_file',
        'write_file',
        'write_file',
      ]);
      expect(goal?.status, ConversationGoalStatus.active);
      expect(goal?.blockedAt, isNull);
      expect(
        chatNotifier.state.goalAutoContinueNotice,
        'chat.goal_auto_continue_no_progress',
      );
      expect(chatNotifier.state.goalAutoContinueCount, 0);
      expect(chatNotifier.state.goalAutoContinueBudget, 0);
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
  required _GoalAutoContinueChatDataSource dataSource,
  required _FakeMcpToolService toolService,
  required String projectId,
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
