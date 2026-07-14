part of 'chat_notifier_test.dart';

// Coding-mode continuation-recovery test group, extracted from
// chat_notifier_test.dart to keep that file under its F1 size ratchet
// (docs/large_file_refactor_plan.md). These tests share the library's
// private test doubles via the part-of relationship.
void registerChatNotifierContinuationRecoveryTests() {
  test(
    'sendMessage skips continuation recovery for completed tool-role command response',
    () async {
      const toolRoleCompletion =
          'The Dart script completed successfully after running the local command. '
          'It printed 168 prime numbers and the ported implementation is complete.';
      const streamedFinalAnswer =
          'The Dart script was ported and verified successfully.';
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'run-dart-script',
            name: 'local_execute_command',
            arguments: const {
              'command': 'dart run prime_numbers.dart',
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: toolRoleCompletion,
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Recovery should not run.',
            toolCalls: [
              ToolCallInfo(
                id: 'unexpected-read',
                name: 'read_file',
                arguments: const {'path': '/tmp/project/prime_numbers.dart'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const [streamedFinalAnswer],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'local_execute_command': 'Execute a local shell command.',
          'read_file': 'Read a local file.',
        },
        results: const {
          'local_execute_command': 'unexpected fallback',
          'read_file': 'unexpected fallback',
        },
        queuedResults: {
          'local_execute_command': [
            jsonEncode({
              'command': 'dart run prime_numbers.dart',
              'working_directory': '/tmp/project',
              'exit_code': 0,
              'stdout': '168 primes\n',
              'stderr': '',
            }),
          ],
          'read_file': [
            '{"path":"/tmp/project/prime_numbers.dart","content":"void main() {}"}',
          ],
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
      await chatNotifier.sendMessage('Port the script to Dart and verify it');

      expect(toolService.executedToolNames, ['local_execute_command']);
      expect(dataSource.toolResultBatches, hasLength(1));
      expect(
        dataSource.toolResultBatches
            .expand((batch) => batch)
            .map((result) => result.name),
        isNot(contains('coding_continuation_recovery')),
      );
      expect(
        chatNotifier.state.messages.last.content,
        contains(streamedFinalAnswer),
      );
    },
  );

  test(
    'sendMessage recovers prose-only coding continuation after continue',
    () async {
      final continuationText = String.fromCharCodes(const [
        0x65e2,
        0x5b58,
        0x306e,
        0x0044,
        0x0061,
        0x0072,
        0x0074,
        0x30b3,
        0x30fc,
        0x30c9,
        0x3092,
        0x78ba,
        0x8a8d,
        0x3057,
        0x3001,
        0x0050,
        0x0079,
        0x0074,
        0x0068,
        0x006f,
        0x006e,
        0x30b9,
        0x30af,
        0x30ea,
        0x30d7,
        0x30c8,
        0x306e,
        0x30ed,
        0x30b8,
        0x30c3,
        0x30af,
        0x3092,
        0x0044,
        0x0061,
        0x0072,
        0x0074,
        0x306b,
        0x30dd,
        0x30fc,
        0x30c6,
        0x30a3,
        0x30f3,
        0x30b0,
        0x3057,
        0x307e,
        0x3059,
        0x3002,
      ]);
      final conversationRepository = _FakeConversationRepository();
      final project = CodingProject(
        id: 'project-prose-continuation',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 6, 18),
        updatedAt: DateTime(2026, 6, 18),
      );
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialFinishReason: 'stop',
        initialCompletionContent: continuationText,
        initialStreamChunks: [continuationText],
        intermediateToolRoleResponseContent:
            'Recovering by inspecting the Dart entrypoint.',
        followUpToolCalls: [
          ToolCallInfo(
            id: 'read-dart-entrypoint',
            name: 'read_file',
            arguments: const {
              'path': '/tmp/project/prime_numbers/bin/prime_numbers.dart',
            },
          ),
        ],
        toolRoleResponseContent: 'Dart entrypoint was inspected.',
        finalAnswerChunks: const [
          'Dart porting can continue after inspection.',
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {'read_file': 'Read a local file.'},
        results: const {
          'read_file':
              '{"path":"/tmp/project/prime_numbers/bin/prime_numbers.dart","content":"void main() {}"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(toolContainer.dispose);

      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final chatNotifier = toolContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('continue', bypassPlanMode: true);

      expect(toolService.executedToolNames, ['read_file']);
      expect(dataSource.toolResultBatches, hasLength(2));
      expect(
        dataSource.toolResultBatches.first.single.result,
        contains('prose_only_coding_continuation'),
      );
      expect(
        dataSource.toolResultRequestMessages.first.last.content,
        contains('The previous assistant response was a coding continuation'),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains(continuationText)),
      );
      expect(
        chatNotifier.state.messages.last.content,
        contains('Dart porting can continue after inspection.'),
      );
    },
  );

  test(
    'sendMessage recovers a Japanese structured deferral for an active goal',
    () async {
      const structuredDeferral = '''
## \u5b9f\u884c\u8a08\u753b

### 1. todo_app.md \u3092\u8aad\u3080
\u307e\u305a\u3001MVP\u306e\u8981\u4ef6\u3092\u628a\u63e1\u3057\u307e\u3059\u3002

### 2. Dart\u30d7\u30ed\u30b8\u30a7\u30af\u30c8\u3092\u521d\u671f\u5316
`dart create` \u3067CLI\u30d7\u30ed\u30b8\u30a7\u30af\u30c8\u3092\u4f5c\u6210\u3057\u307e\u3059\u3002

### 3. main.dart \u3092\u5b9f\u88c5

### 4. \u691c\u8a3c

\u307e\u305a\u3001todo_app.md\u306e\u5185\u5bb9\u3092\u78ba\u8a8d\u3057\u307e\u3059\u3002
''';
      final project = CodingProject(
        id: 'project-structured-execution-deferral',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 7, 14),
        updatedAt: DateTime(2026, 7, 14),
      );
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialCompletionContent: structuredDeferral,
        initialFinishReason: 'stop',
        initialStreamChunks: const [structuredDeferral],
        intermediateToolRoleResponseContent:
            'Recovering by reading the referenced specification.',
        followUpToolCalls: [
          ToolCallInfo(
            id: 'read-structured-deferral-spec',
            name: 'read_file',
            arguments: const {'path': '/tmp/project/todo_app.md'},
          ),
        ],
        toolRoleResponseContent: 'The specification was inspected.',
        finalAnswerChunks: const ['The implementation can now proceed.'],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {'read_file': 'Read a local file.'},
        results: const {
          'read_file':
              '{"path":"/tmp/project/todo_app.md","content":"Build a TODO CLI."}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
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
        objective: 'Implement the TODO MVP from todo_app.md.',
        enabled: true,
        autoContinue: true,
        status: ConversationGoalStatus.active,
        turnBudget: 5,
      );
      await conversations.updateCurrentWorkflow(
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Implement the TODO MVP from todo_app.md.',
          tasks: [
            ConversationWorkflowTask(
              id: 'implement-todo-mvp',
              title: 'Implement the TODO MVP',
            ),
          ],
        ),
      );

      final notifier = container.read(chatNotifierProvider.notifier);
      await notifier.sendMessage(
        'Implement the TODO MVP from todo_app.md.',
        bypassPlanMode: true,
      );

      expect(toolService.executedToolNames, ['read_file']);
      expect(dataSource.toolResultBatches, hasLength(2));
      expect(
        dataSource.toolResultBatches.first.single.result,
        contains('prose_only_coding_continuation'),
      );
      expect(
        notifier.state.messages.last.content,
        isNot(contains(structuredDeferral)),
      );
    },
  );

  test(
    'sendMessage preserves a Japanese plan without an active execution goal',
    () async {
      const structuredPlan = '''
## \u5b9f\u884c\u8a08\u753b

todo_app.md \u3092\u8aad\u3093\u3067Dart\u30d7\u30ed\u30b8\u30a7\u30af\u30c8\u3092\u78ba\u8a8d\u3057\u307e\u3059\u3002
''';
      final project = CodingProject(
        id: 'project-structured-plan-no-goal',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 7, 14),
        updatedAt: DateTime(2026, 7, 14),
      );
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialCompletionContent: structuredPlan,
        initialFinishReason: 'stop',
        initialStreamChunks: const [structuredPlan],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {'read_file': 'Read a local file.'},
        results: const {'read_file': 'unused'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final notifier = container.read(chatNotifierProvider.notifier);

      await notifier.sendMessage(
        'Describe an implementation plan.',
        bypassPlanMode: true,
      );

      expect(toolService.executedToolNames, isEmpty);
      expect(dataSource.toolResultBatches, isEmpty);
      expect(
        notifier.state.messages.last.content,
        contains(structuredPlan.trim()),
      );
    },
  );

  test(
    'sendMessage recovers prose-only coding continuation after tool results',
    () async {
      final continuationText = String.fromCharCodes(const [
        0x30d7,
        0x30ed,
        0x30b8,
        0x30a7,
        0x30af,
        0x30c8,
        0x304c,
        0x4f5c,
        0x6210,
        0x3055,
        0x308c,
        0x307e,
        0x3057,
        0x305f,
        0x3002,
        0x65e2,
        0x5b58,
        0x306e,
        0x30b3,
        0x30fc,
        0x30c9,
        0x3092,
        0x78ba,
        0x8a8d,
        0x3057,
        0x3001,
        0x0050,
        0x0079,
        0x0074,
        0x0068,
        0x006f,
        0x006e,
        0x30b9,
        0x30af,
        0x30ea,
        0x30d7,
        0x30c8,
        0x306e,
        0x30ed,
        0x30b8,
        0x30c3,
        0x30af,
        0x3092,
        0x0044,
        0x0061,
        0x0072,
        0x0074,
        0x306b,
        0x30dd,
        0x30fc,
        0x30c6,
        0x30a3,
        0x30f3,
        0x30b0,
        0x3057,
        0x307e,
        0x3059,
        0x3002,
      ]);
      final conversationRepository = _FakeConversationRepository();
      final project = CodingProject(
        id: 'project-tool-result-prose-continuation',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 6, 18),
        updatedAt: DateTime(2026, 6, 18),
      );
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'create-dart-project',
            name: 'local_execute_command',
            arguments: const {
              'command': 'dart create --template console-simple prime_numbers',
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: continuationText, finishReason: 'stop'),
          ChatCompletionResult(
            content: 'Recovering by inspecting the generated Dart entrypoint.',
            toolCalls: [
              ToolCallInfo(
                id: 'read-generated-entrypoint',
                name: 'read_file',
                arguments: const {
                  'path': '/tmp/project/prime_numbers/bin/prime_numbers.dart',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Generated Dart entrypoint was inspected.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const [
          'Dart porting can continue after inspection.',
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'local_execute_command': 'Execute a local command.',
          'read_file': 'Read a local file.',
        },
        results: const {
          'local_execute_command': 'unexpected fallback',
          'read_file': 'unexpected fallback',
        },
        queuedResults: {
          'local_execute_command': [
            jsonEncode({
              'command': 'dart create --template console-simple prime_numbers',
              'working_directory': '/tmp/project',
              'exit_code': 0,
              'stdout': 'Creating prime_numbers...',
              'stderr': '',
            }),
          ],
          'read_file': [
            '{"path":"/tmp/project/prime_numbers/bin/prime_numbers.dart","content":"void main() {}"}',
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(toolContainer.dispose);

      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final chatNotifier = toolContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage(
        'Port the script to Dart',
        bypassPlanMode: true,
      );

      expect(toolService.executedToolNames, [
        'local_execute_command',
        'read_file',
      ]);
      expect(dataSource.toolResultBatches, hasLength(3));
      expect(
        dataSource.toolResultBatches[1].single.result,
        contains('prose_only_coding_continuation'),
      );
      expect(dataSource.assistantContents[1], continuationText);
      expect(
        chatNotifier.state.messages.last.content,
        contains('Dart porting can continue after inspection.'),
      );
    },
  );

  test(
    'continuation recovery after a failed command does not tell the model to restart',
    () async {
      // Repro of the "chat restarted" report: a command runs and fails this
      // turn, then the model emits a prose-only continuation that trips the
      // recovery heuristic. The blanket "treat that response as unexecuted"
      // re-prompt used to make the model re-run already-completed steps. The
      // re-prompt must instead preserve progress and point at the failure.
      const continuationText =
          'Next I will read the project Dart file to continue the work.';
      final conversationRepository = _FakeConversationRepository();
      final project = CodingProject(
        id: 'project-failed-command-continuation',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 6, 18),
        updatedAt: DateTime(2026, 6, 18),
      );
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'run-analyze',
            name: 'local_execute_command',
            arguments: const {
              'command': 'flutter analyze',
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: continuationText, finishReason: 'stop'),
          ChatCompletionResult(
            content: 'Investigating the analyzer failure.',
            toolCalls: [
              ToolCallInfo(
                id: 'read-entrypoint',
                name: 'read_file',
                arguments: const {'path': '/tmp/project/lib/main.dart'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Resolved the analyzer failure.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['The analyzer failure is resolved.'],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'local_execute_command': 'Execute a local command.',
          'read_file': 'Read a local file.',
        },
        results: const {
          'local_execute_command': 'unexpected fallback',
          'read_file': 'unexpected fallback',
        },
        queuedResults: {
          'local_execute_command': [
            jsonEncode({
              'command': 'flutter analyze',
              'working_directory': '/tmp/project',
              'exit_code': 1,
              'stdout': '50614 issues found.',
              'stderr': '',
            }),
          ],
          'read_file': [
            '{"path":"/tmp/project/lib/main.dart","content":"void main() {}"}',
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(toolContainer.dispose);

      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final chatNotifier = toolContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Run analyze', bypassPlanMode: true);

      // Recovery still fires (the failed command is a real open problem).
      expect(dataSource.toolResultBatches, hasLength(3));
      expect(
        dataSource.toolResultBatches[1].single.result,
        contains('prose_only_coding_continuation'),
      );
      // The re-prompt for the recovery turn must use the non-destructive,
      // progress-preserving framing instead of "treat as unexecuted".
      final recoveryPrompt =
          dataSource.toolResultRequestMessages[1].last.content;
      expect(
        recoveryPrompt,
        contains('Do not restart the task or re-run commands'),
      );
      expect(
        recoveryPrompt,
        contains('a command exited with a non-zero status'),
      );
      expect(
        recoveryPrompt,
        isNot(contains('Treat that response as unexecuted')),
      );
    },
  );

  test(
    'sendMessage skips continuation recovery after a save_skill completes the turn',
    () async {
      // A prose-only "skill created, next I will…" summary that, on its own,
      // trips the coding continuation-recovery heuristic (target + action). The
      // guard must suppress recovery because save_skill already executed the
      // task this turn — otherwise the loop forces a redundant second save.
      const continuationText =
          'Skill saved. Next I will update the project file.';
      final conversationRepository = _FakeConversationRepository();
      final project = CodingProject(
        id: 'project-save-skill-no-recovery',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 6, 23),
        updatedAt: DateTime(2026, 6, 23),
      );
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'author-release-skill',
            name: 'save_skill',
            arguments: const {
              'name': 'iOS Release',
              'description': 'Ship an iOS build',
              'when_to_use': 'When cutting an iOS release',
              'content': '# Steps\n\n1. Bump version.\n2. Archive.',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: continuationText, finishReason: 'stop'),
        ],
        finalAnswerChunks: const ['Skill creation finished.'],
      );
      // read_file is offered so the recovery's tool-availability gate passes;
      // without the save_skill guard, recovery would otherwise fire here.
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'save_skill': 'Save a reusable skill.',
          'read_file': 'Read a local file.',
        },
        results: const {'save_skill': '', 'read_file': 'unexpected fallback'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          skillsNotifierProvider.overrideWith(_RecordingSkillsNotifier.new),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final chatNotifier = container.read(chatNotifierProvider.notifier);

      final send = chatNotifier.sendMessage(
        'Turn this conversation into a release skill',
        bypassPlanMode: true,
      );
      // save_skill is non-cacheable: approve the pending write so the turn
      // completes, then let the prose-only "stop" response settle.
      for (var i = 0; i < 8; i++) {
        final pending = chatNotifier.state.pendingFileOperation;
        if (pending != null) {
          chatNotifier.resolveFileOperation(id: pending.id, approved: true);
          break;
        }
        await Future<void>.delayed(Duration.zero);
      }
      await send;

      // The skill was authored exactly once.
      expect(container.read(skillsNotifierProvider).skills, hasLength(1));
      expect(toolService.executedToolNames, isNot(contains('read_file')));
      // Only the save_skill tool-result batch was sent — no recovery batch.
      expect(dataSource.toolResultBatches, hasLength(1));
      for (final batch in dataSource.toolResultBatches) {
        for (final result in batch) {
          expect(result.name, isNot('coding_continuation_recovery'));
          expect(
            result.result,
            isNot(contains('prose_only_coding_continuation')),
          );
        }
      }
    },
  );
}
