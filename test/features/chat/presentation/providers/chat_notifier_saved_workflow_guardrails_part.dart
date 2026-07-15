part of 'chat_notifier_test.dart';

// Saved workflow guardrail tests live in a part file so
// chat_notifier_test.dart stays under its F1 size ratchet.
void registerChatNotifierSavedWorkflowGuardrailTests() {
  test(
    'sendMessage continues behavioral evidence after saved validation succeeds',
    () async {
      final conversation = Conversation(
        id: 'conversation-post-validation-evidence',
        title: 'Plan thread',
        messages: const <Message>[],
        createdAt: DateTime(2026, 7, 15, 12),
        updatedAt: DateTime(2026, 7, 15, 12, 5),
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-cli',
              title: 'Implement the CLI behavior',
              targetFiles: ['bin/todo_cli.dart'],
              validationCommand: 'dart analyze bin/todo_cli.dart',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write',
            name: 'write_file',
            arguments: const {
              'path': 'bin/todo_cli.dart',
              'content': 'void main() {}\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'dart analyze bin/todo_cli.dart',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Static analysis passed. I will check an error case.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-behavior-check',
                name: 'local_execute_command',
                arguments: const {
                  'command':
                      'dart run bin/todo_cli.dart done 999; echo "exit=\$?"',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The error-case check exposed an unhandled exception.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-repair',
                name: 'edit_file',
                arguments: const {
                  'path': 'bin/todo_cli.dart',
                  'old_text': 'void main() {}',
                  'new_text': 'void main() { print("repaired"); }',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'I will rerun the saved validation after the repair.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-revalidate',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'dart analyze bin/todo_cli.dart',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The repaired CLI passed validation.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const [
          'The CLI task and its behavioral validation are complete.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file': '{"path":"/tmp/bin/todo_cli.dart","bytes_written":15}',
          'edit_file': '{"path":"/tmp/bin/todo_cli.dart","replacements":1}',
          'local_execute_command':
              '{"command":"check","exit_code":0,"stdout":"ok\\n","stderr":""}',
        },
        queuedResults: const {
          'local_execute_command': [
            '{"command":"analyze","exit_code":0,"stdout":"No issues found!\\n","stderr":""}',
            '{"command":"behavior","exit_code":0,"stdout":"Unhandled exception: Bad state\\n#0 main\\nexit=255\\n","stderr":""}',
            '{"command":"analyze","exit_code":0,"stdout":"No issues found!\\n","stderr":""}',
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
          conversationsNotifierProvider.overrideWith(
            () => _WorkflowTestConversationsNotifier(conversation),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final notifier = toolContainer.read(chatNotifierProvider.notifier);

        await notifier.sendMessage('Implement and verify the CLI task');

        expect(toolService.executedToolNames, [
          'write_file',
          'local_execute_command',
          'local_execute_command',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(4));
        expect(toolDataSource.toolResultBatches[3].single.name, 'edit_file');
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage repairs failed output from the saved validation batch',
    () async {
      final conversation = Conversation(
        id: 'conversation-saved-validation-output-repair',
        title: 'Plan thread',
        messages: const <Message>[],
        createdAt: DateTime(2026, 7, 15, 12),
        updatedAt: DateTime(2026, 7, 15, 12, 5),
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-cli-validation',
              title: 'Validate the CLI behavior',
              targetFiles: ['bin/todo_cli.dart'],
              validationCommand: 'dart run bin/todo_cli.dart done 999',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write',
            name: 'write_file',
            arguments: const {
              'path': 'bin/todo_cli.dart',
              'content': 'void main() {}\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'I will run the saved behavioral validation.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'dart run bin/todo_cli.dart done 999',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The saved validation exposed an unhandled exception.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-repair',
                name: 'edit_file',
                arguments: const {
                  'path': 'bin/todo_cli.dart',
                  'old_text': 'void main() {}',
                  'new_text': 'void main() { print("not found"); }',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'I will rerun the saved validation after the repair.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-revalidate',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'dart run bin/todo_cli.dart done 999',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The repaired saved validation passed.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['The CLI validation task is complete.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file': '{"path":"/tmp/bin/todo_cli.dart","bytes_written":15}',
          'edit_file': '{"path":"/tmp/bin/todo_cli.dart","replacements":1}',
        },
        queuedResults: const {
          'local_execute_command': [
            '{"command":"dart run bin/todo_cli.dart done 999","exit_code":0,"stdout":"Unhandled exception: Bad state\\n#0 main\\n","stderr":""}',
            '{"command":"dart run bin/todo_cli.dart done 999","exit_code":0,"stdout":"Error: Task 999 not found.\\n","stderr":""}',
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
          conversationsNotifierProvider.overrideWith(
            () => _WorkflowTestConversationsNotifier(conversation),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final notifier = toolContainer.read(chatNotifierProvider.notifier);

        await notifier.sendMessage('Implement and validate the CLI task');

        expect(
          toolDataSource.toolResultBatches.any(
            (batch) => batch.any((result) => result.name == 'edit_file'),
          ),
          isTrue,
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage blocks file writes outside the active saved task target',
    () async {
      final conversation = Conversation(
        id: 'conversation-tool-loop-target-scope',
        title: 'Plan thread',
        messages: const <Message>[],
        createdAt: DateTime(2026, 4, 24, 12),
        updatedAt: DateTime(2026, 4, 24, 12, 5),
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-requirements',
              title: 'Create requirements.txt for the host health CLI',
              targetFiles: ['requirements.txt'],
              validationCommand: 'test -f requirements.txt',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write-requirements',
            name: 'write_file',
            arguments: const {
              'path': 'requirements.txt',
              'content': 'requests>=2.32\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'I will add README notes next.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-write-readme',
                name: 'write_file',
                arguments: const {
                  'path': 'README.md',
                  'content': '# Host health CLI\n',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'I will stay on the active saved task and validate it.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate-requirements',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'test -f requirements.txt',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'The saved validation command passed, so the requirements task is complete.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Requirements task complete.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file': '{"path":"/tmp/requirements.txt","bytes_written":15}',
          'local_execute_command':
              '{"command":"test -f requirements.txt","exit_code":0,"stdout":"","stderr":""}',
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
            () => _WorkflowTestConversationsNotifier(conversation),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
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

        expect(
          toolNotifier.allowedSavedTaskTargetFilesForTest(
            const ConversationWorkflowTask(
              id: 'task-validation-entrypoint',
              title: 'Verify the CLI',
              targetFiles: ['lib/main.dart'],
              validationCommand:
                  'rm -f tasks.json && dart run bin/todo.dart list',
            ),
          ),
          containsAll(<String>['lib/main.dart', 'bin/todo.dart']),
        );
        expect(
          toolNotifier.allowedSavedTaskTargetFilesForTest(
            const ConversationWorkflowTask(
              id: 'task-validation-entrypoint',
              title: 'Verify the CLI',
              targetFiles: ['lib/main.dart'],
              validationCommand:
                  'rm -f tasks.json && dart run bin/todo.dart list',
            ),
          ),
          isNot(contains('tasks.json')),
        );

        await toolNotifier.sendMessage('Create requirements.txt first');

        expect(toolService.executedToolNames, [
          'write_file',
          'local_execute_command',
        ]);
        expect(
          toolService.executedToolArguments,
          isNot(contains(containsPair('path', 'README.md'))),
        );
        expect(toolDataSource.toolResultBatches, hasLength(3));
        final guardPayload =
            jsonDecode(toolDataSource.toolResultBatches[1].single.result)
                as Map<String, dynamic>;
        expect(
          guardPayload,
          containsPair('code', 'saved_task_target_scope_violation'),
        );
        expect(guardPayload, containsPair('attempted_path', 'README.md'));
        expect(
          guardPayload['allowed_target_files'],
          contains('requirements.txt'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Requirements task complete.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );
}
