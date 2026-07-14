part of 'chat_notifier_test.dart';

void registerChatNotifierToolFailureClassificationTests() {
  test(
    'sendMessage blocks unchanged path-backed verifier replay until repair',
    () async {
      const command = 'dart run tool/verify_todo_app.dart';
      final conversation = Conversation(
        id: 'command-diagnostic-focus',
        title: 'Repair TODO CLI',
        messages: const <Message>[],
        createdAt: DateTime(2026, 7, 13, 20),
        updatedAt: DateTime(2026, 7, 13, 20),
        workspaceMode: WorkspaceMode.coding,
        projectId: 'todo-project',
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Build the TODO CLI',
          tasks: [
            ConversationWorkflowTask(
              id: 'todo-task',
              title: 'Implement the TODO CLI',
              validationCommand: command,
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'verify-1',
            name: 'local_execute_command',
            arguments: const {'command': command, 'working_directory': '/tmp'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'I will inspect the same verifier result once more.',
            toolCalls: [
              ToolCallInfo(
                id: 'verify-2',
                name: 'local_execute_command',
                arguments: const {
                  'command': command,
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'I found the required repair and will apply it.',
            toolCalls: [
              ToolCallInfo(
                id: 'repair-1',
                name: 'write_cli',
                arguments: const {'path': 'bin/todo_cli.dart'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The repair is ready for another verification pass.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Repair feedback remained actionable.'],
      );
      const verifierFailure = McpToolResult(
        toolName: 'local_execute_command',
        result:
            '{"exit_code":1,"stdout":"","stderr":"TODO fixture acceptance criteria failed.","diagnostics":[{"severity":"Error","path":"/tmp/run/bin/todo_cli.dart","relative_path":"bin/todo_cli.dart","code":"todo_cli_missing","message":"bin/todo_cli.dart does not exist."}]}',
        isSuccess: false,
        errorMessage: 'TODO verifier found one issue.',
      );
      final toolService = _QueuedMcpToolResultService({
        'local_execute_command': [verifierFailure, verifierFailure],
        'write_cli': const [
          McpToolResult(
            toolName: 'write_cli',
            result: '{"path":"/tmp/bin/todo_cli.dart","bytes_written":64}',
            isSuccess: true,
          ),
        ],
      });
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledCodingNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            () => _WorkflowTestConversationsNotifier(conversation),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
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

        await toolNotifier.sendMessage('Repair the TODO CLI');

        expect(toolService.executedToolNames, [
          'local_execute_command',
          'write_cli',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(3));
        final firstRepairRequestSystemPrompt = toolDataSource
            .toolResultRequestMessages[0]
            .where((message) => message.role == MessageRole.system)
            .map((message) => message.content)
            .firstWhere(
              (content) => content.contains('Command diagnostic streak: 1'),
            );
        expect(
          firstRepairRequestSystemPrompt,
          contains('Required next action: repair'),
        );
        expect(
          firstRepairRequestSystemPrompt,
          contains('inspect the diagnostic context only as needed'),
        );
        expect(
          firstRepairRequestSystemPrompt,
          contains(
            'Do not rerun unchanged validation before corrective action.',
          ),
        );
        final guardPayload =
            jsonDecode(toolDataSource.toolResultBatches[1].single.result)
                as Map<String, dynamic>;
        expect(
          guardPayload,
          containsPair(
            'code',
            'unchanged_verifier_replay_before_repair_blocked',
          ),
        );
        expect(
          guardPayload['diagnostic'],
          contains('bin/todo_cli.dart: [todo_cli_missing]'),
        );
        expect(guardPayload['diagnostic'], isNot(contains('/tmp/run/')));
        expect(
          guardPayload['required_action'],
          contains('Make one concrete mutation'),
        );
        final guardedRepairRequestSystemPrompts = toolDataSource
            .toolResultRequestMessages[1]
            .where((message) => message.role == MessageRole.system)
            .map((message) => message.content)
            .toList();
        final guardedRepairRequestSystemPrompt =
            guardedRepairRequestSystemPrompts.firstWhere(
              (content) => content.contains('Command diagnostic streak: 1'),
            );
        expect(
          guardedRepairRequestSystemPrompt,
          contains('Required next action: repair'),
        );
        expect(
          guardedRepairRequestSystemPrompt,
          isNot(contains('Repeated command diagnostic streak: 2')),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Repair feedback remained actionable.'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('check your server configuration')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage allows a verifier after a preceding batch mutation',
    () async {
      final result = await _runOrderedVerifierBatch(mutationFirst: true);

      expect(result.executedToolNames, [
        'local_execute_command',
        'write_file',
        'local_execute_command',
      ]);
      expect(
        result.secondBatchCodes,
        isNot(contains('unchanged_verifier_replay_before_repair_blocked')),
      );
    },
  );

  test('sendMessage blocks a verifier before a later batch mutation', () async {
    final result = await _runOrderedVerifierBatch(mutationFirst: false);

    expect(result.executedToolNames, [
      'local_execute_command',
      'write_file',
      'local_execute_command',
    ]);
    expect(
      result.secondBatchCodes,
      contains('unchanged_verifier_replay_before_repair_blocked'),
    );
  });
}

Future<({List<String> executedToolNames, Set<String> secondBatchCodes})>
_runOrderedVerifierBatch({required bool mutationFirst}) async {
  const command = 'dart run tool/verify_todo_app.dart';
  final conversation = Conversation(
    id: mutationFirst
        ? 'mutation-first-command-diagnostic-focus'
        : 'verifier-first-command-diagnostic-focus',
    title: 'Repair TODO CLI in order',
    messages: const <Message>[],
    createdAt: DateTime(2026, 7, 14, 3),
    updatedAt: DateTime(2026, 7, 14, 3),
    workspaceMode: WorkspaceMode.coding,
    projectId: 'todo-project',
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: const ConversationWorkflowSpec(
      goal: 'Build the TODO CLI',
      tasks: [
        ConversationWorkflowTask(
          id: 'todo-task',
          title: 'Implement the TODO CLI',
          validationCommand: command,
          status: ConversationWorkflowTaskStatus.inProgress,
        ),
      ],
    ),
  );
  final mutationCall = ToolCallInfo(
    id: 'repair-1',
    name: 'write_file',
    arguments: const {'path': 'bin/todo_cli.dart'},
  );
  final verifierCall = ToolCallInfo(
    id: 'verify-2',
    name: 'local_execute_command',
    arguments: const {'command': command, 'working_directory': '/tmp'},
  );
  final toolDataSource = _QueuedToolLoopChatDataSource(
    initialToolCalls: [
      ToolCallInfo(
        id: 'verify-1',
        name: 'local_execute_command',
        arguments: const {'command': command, 'working_directory': '/tmp'},
      ),
    ],
    toolLoopResponses: [
      ChatCompletionResult(
        content: 'I will apply the queued repair and verifier calls.',
        toolCalls: mutationFirst
            ? [mutationCall, verifierCall]
            : [verifierCall, mutationCall],
        finishReason: 'tool_calls',
      ),
      ChatCompletionResult(
        content: 'The ordered repair attempt is complete.',
        finishReason: 'stop',
      ),
      ChatCompletionResult(
        content: 'The post-mutation verifier remains actionable.',
        finishReason: 'stop',
      ),
    ],
    finalAnswerChunks: const ['Ordered repair feedback remained actionable.'],
  );
  const verifierFailure = McpToolResult(
    toolName: 'local_execute_command',
    result:
        '{"exit_code":1,"stdout":"","stderr":"TODO fixture acceptance criteria failed.","diagnostics":[{"severity":"Error","path":"/tmp/run/bin/todo_cli.dart","relative_path":"bin/todo_cli.dart","code":"todo_cli_missing","message":"bin/todo_cli.dart does not exist."}]}',
    isSuccess: false,
    errorMessage: 'TODO verifier found one issue.',
  );
  final toolService = _QueuedMcpToolResultService({
    'local_execute_command': [verifierFailure, verifierFailure],
    'write_file': const [
      McpToolResult(
        toolName: 'write_file',
        result: '{"path":"/tmp/bin/todo_cli.dart","bytes_written":64}',
        isSuccess: true,
      ),
    ],
  });
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  final toolContainer = ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(
        _ToolEnabledCodingNoConfirmSettingsNotifier.new,
      ),
      conversationsNotifierProvider.overrideWith(
        () => _WorkflowTestConversationsNotifier(conversation),
      ),
      codingProjectsNotifierProvider.overrideWith(
        _TestCodingProjectsNotifier.new,
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
    await toolContainer
        .read(chatNotifierProvider.notifier)
        .sendMessage('Repair the TODO CLI in order');
    final secondBatchCodes = toolDataSource.toolResultBatches[1]
        .map((result) {
          final decoded = jsonDecode(result.result);
          return decoded is Map ? decoded['code'] : null;
        })
        .whereType<String>()
        .toSet();
    return (
      executedToolNames: List<String>.from(toolService.executedToolNames),
      secondBatchCodes: secondBatchCodes,
    );
  } finally {
    toolContainer.dispose();
  }
}

class _ToolEnabledCodingNoConfirmSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => _baseTestSettings().copyWith(
    assistantMode: AssistantMode.coding,
    mcpEnabled: true,
    demoMode: false,
    codingApprovalMode: ToolApprovalMode.fullAccess,
    confirmFileMutations: false,
    confirmLocalCommands: false,
    confirmGitWrites: false,
  );
}
