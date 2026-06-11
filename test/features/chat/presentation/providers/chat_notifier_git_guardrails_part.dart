part of 'chat_notifier_test.dart';

void registerChatNotifierGitGuardrailTests() {
  test(
    'sendMessage marks Japanese git commit claim without tool call as unexecuted',
    () async {
      const finalContent = 'pubspec.yaml をステージしてコミットします。';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialFinishReason: 'stop',
        initialCompletionContent: finalContent,
        initialStreamChunks: const [finalContent],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {'git_execute_command': 'Execute a git command.'},
        results: const {'git_execute_command': '{"exit_code":0}'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
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
      await chatNotifier.sendMessage('commit');

      expect(toolService.executedToolNames, isEmpty);
      expect(
        chatNotifier.state.messages.last.content,
        contains(
          'The requested command was not executed because no successful command-execution tool result is available.',
        ),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains(finalContent)),
      );
    },
  );

  test(
    'sendMessage does not execute git write when asking for commit confirmation',
    () async {
      const confirmationContent =
          '更新しました。\n\n- 旧: `1.3.5+17`\n- 新: `1.3.6+18`\n\nコミットしますか？';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-stage-version',
            name: 'git_execute_command',
            arguments: const {
              'command': 'add pubspec.yaml',
              'reason': 'Stage version bump',
            },
          ),
        ],
        initialCompletionContent: confirmationContent,
        initialStreamChunks: const [confirmationContent],
        toolRoleResponseContent: 'This should not be reached.',
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {'git_execute_command': 'Execute a git command.'},
        results: const {
          'git_execute_command':
              '{"command":"git add pubspec.yaml","exit_code":0}',
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
      await chatNotifier.sendMessage('バージョン番号とビルドナンバーを更新');

      expect(toolService.executedToolNames, isEmpty);
      expect(dataSource.toolResultBatches, isEmpty);
      expect(chatNotifier.state.messages.last.content, contains('コミットしますか？'));
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('This should not be reached')),
      );
    },
  );

  test(
    'sendMessage does not replace pending git write command at tool loop limit',
    () async {
      final toolLoopResponses = <ChatCompletionResult>[
        for (var index = 0; index < 11; index += 1)
          ChatCompletionResult(
            content: 'Continue inspecting pubspec.yaml before committing.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-${index + 2}',
                name: 'read_file',
                arguments: const {'path': 'pubspec.yaml'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ChatCompletionResult(
          content: 'Commit the selected version bump now.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-correct-commit',
              name: 'git_execute_command',
              arguments: const {
                'command': 'commit -m "chore: bump version to 1.3.6+17"',
                'reason': 'Commit version bump to 1.3.6+17',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'Regenerated the pending command incorrectly.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-wrong-commit',
              name: 'git_execute_command',
              arguments: const {
                'command': 'commit -m "chore: bump version to 1.2.0+1200"',
                'reason': 'Commit version bump',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'The wrong commit should never run.',
          finishReason: 'stop',
        ),
      ];
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'read_file',
            arguments: const {'path': 'pubspec.yaml'},
          ),
        ],
        toolLoopResponses: toolLoopResponses,
        finalAnswerChunks: const [
          'Final answer acknowledges the pending commit was not executed.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'read_file': '{"content":"version: 1.3.6+17"}',
          'git_execute_command':
              '{"command":"git commit","exit_code":0,"stdout":"committed\\n","stderr":""}',
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
          backgroundTaskServiceProvider.overrideWith(
            (ref) => _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Commit the selected version bump');

        expect(toolService.executedToolNames, List.filled(12, 'read_file'));
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        final finalPrompt = toolDataSource.finalAnswerMessages
            .map((message) => message.content)
            .join('\n');
        expect(finalPrompt, contains('chore: bump version to 1.3.6+17'));
        expect(finalPrompt, isNot(contains('1.2.0+1200')));
        expect(
          toolNotifier.state.messages.last.content,
          contains('pending commit was not executed'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage blocks duplicate side-effect command after timeout',
    () async {
      const command =
          'bash tool/release_ios_macos.sh --macos-release-notes docs/releases/caverno-1.3.4.md';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'release-command-1',
            name: 'local_execute_command',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The release timed out; I will retry it.',
            toolCalls: [
              ToolCallInfo(
                id: 'release-command-2',
                name: 'local_execute_command',
                arguments: const {
                  'command': command,
                  'working_directory': '/tmp/project',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The retry was blocked until the user confirms.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'command': command,
            'working_directory': '/tmp/project',
            'error': 'Command timed out after 60 seconds.',
            'timed_out': true,
            'timeout_ms': 60000,
            'process_terminated': true,
          }),
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

        await toolNotifier.sendMessage('Release Caverno');

        expect(toolService.executedToolNames, ['local_execute_command']);
        expect(toolDataSource.toolResultBatches, hasLength(2));
        expect(
          jsonDecode(toolDataSource.toolResultBatches.first.single.result),
          containsPair('timed_out', true),
        );
        final retryBlock =
            jsonDecode(toolDataSource.toolResultBatches.last.single.result)
                as Map<String, dynamic>;
        expect(
          retryBlock,
          containsPair('code', 'command_retry_after_timeout_blocked'),
        );
        expect(retryBlock['command'], command);
        expect(
          retryBlock['required_action'],
          contains('read-only inspection command'),
        );
        final finalPrompt = toolDataSource.finalAnswerMessages
            .map((message) => message.content)
            .join('\n');
        expect(finalPrompt, contains('command_retry_after_timeout_blocked'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage blocks process_start retry after command timeout',
    () async {
      const command = 'bash tool/deploy_production.sh --target app-store';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'deploy-command-1',
            name: 'local_execute_command',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                'The command timed out; I will start it in the background.',
            toolCalls: [
              ToolCallInfo(
                id: 'deploy-command-2',
                name: 'process_start',
                arguments: const {
                  'command': command,
                  'working_directory': '/tmp/project',
                  'label': 'deployment',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The background retry was blocked until inspection.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'command': command,
            'working_directory': '/tmp/project',
            'error': 'Command timed out after 60 seconds.',
            'timed_out': true,
            'timeout_ms': 60000,
            'process_terminated': true,
          }),
          'process_start': 'unexpected background retry',
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

        await toolNotifier.sendMessage('Deploy Caverno');

        expect(toolService.executedToolNames, ['local_execute_command']);
        expect(toolDataSource.toolResultBatches, hasLength(2));
        final retryBlock =
            jsonDecode(toolDataSource.toolResultBatches.last.single.result)
                as Map<String, dynamic>;
        expect(
          retryBlock,
          containsPair('code', 'command_retry_after_timeout_blocked'),
        );
        expect(retryBlock['command'], command);
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage blocks production release after dry run without approval',
    () async {
      const dryRunCommand =
          'bash tool/release_ios_macos.sh --dry-run --macos-release-notes docs/releases/caverno-1.3.6.md';
      const productionCommand =
          'bash tool/release_ios_macos.sh --macos-release-notes docs/releases/caverno-1.3.6.md';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'release-dry-run',
            name: 'local_execute_command',
            arguments: const {
              'command': dryRunCommand,
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                'Dry run succeeded. I will run the production release now.',
            toolCalls: [
              ToolCallInfo(
                id: 'release-production',
                name: 'local_execute_command',
                arguments: const {
                  'command': productionCommand,
                  'working_directory': '/tmp/project',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Production release is blocked until explicit approval.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'local_execute_command': 'unexpected production run'},
        queuedResults: {
          'local_execute_command': [
            jsonEncode({
              'command': dryRunCommand,
              'working_directory': '/tmp/project',
              'exit_code': 0,
              'stdout': 'Release workflow completed successfully.',
              'stderr': '',
            }),
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

        await toolNotifier.sendMessage('continue');

        expect(toolService.executedToolNames, ['local_execute_command']);
        expect(toolDataSource.toolResultBatches, hasLength(2));
        final releaseBlock =
            jsonDecode(toolDataSource.toolResultBatches.last.single.result)
                as Map<String, dynamic>;
        expect(
          releaseBlock,
          containsPair('code', 'production_release_explicit_approval_required'),
        );
        expect(releaseBlock['command'], productionCommand);
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('git tag creation requires prior tag format inspection', () async {
    final conversationRepository = _FakeConversationRepository();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'git_execute_command',
          arguments: const {
            'command': 'tag -a v1.3.4 -m "Release v1.3.4"',
            'reason': 'Create release tag',
          },
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {'git_execute_command': '{"exit_code":0}'},
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/tmp/project',
      createdAt: DateTime(2026, 5, 26),
      updatedAt: DateTime(2026, 5, 26),
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
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
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

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage(
        'Create a release tag',
        bypassPlanMode: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(toolNotifier.state.pendingGitCommand, isNull);
      expect(toolService.executedToolNames, isEmpty);
      expect(toolDataSource.toolResultBatches, hasLength(1));
      final result = toolDataSource.toolResultBatches.single.single;
      expect(result.name, 'git_execute_command');
      expect(result.result, contains('git_tag_format_inspection_required'));
      expect(result.result, contains('tag --list'));
    } finally {
      toolContainer.dispose();
    }
  });

  test('piped git tag list is not blocked by tag creation guard', () async {
    final conversationRepository = _FakeConversationRepository();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'git_execute_command',
          arguments: const {
            'command': 'tag --list --sort=-v:refname | head -10',
          },
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'git_execute_command':
            '{"command":"git tag --list --sort=-v:refname | head -10","working_directory":"/tmp/project","exit_code":2,"error":"git_execute_command accepts one git subcommand per tool call. Shell control operator \\"|\\" is not supported."}',
      },
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/tmp/project',
      createdAt: DateTime(2026, 5, 26),
      updatedAt: DateTime(2026, 5, 26),
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
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
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

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage(
        'Inspect recent release tags',
        bypassPlanMode: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(toolService.executedToolNames, ['git_execute_command']);
      expect(toolDataSource.toolResultBatches, hasLength(1));
      final result = toolDataSource.toolResultBatches.single.single;
      expect(result.result, contains('one git subcommand'));
      expect(
        result.result,
        isNot(contains('git_tag_format_inspection_required')),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test('git tag pattern list is not blocked by tag creation guard', () async {
    final conversationRepository = _FakeConversationRepository();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'git_execute_command',
          arguments: const {
            'command': "tag -l '1.3.4*' --sort=-version:refname",
          },
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'git_execute_command':
            '{"command":"git tag -l \'1.3.4*\' --sort=-version:refname","working_directory":"/tmp/project","exit_code":0,"stdout":"1.3.4+15\\n","stderr":""}',
      },
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/tmp/project',
      createdAt: DateTime(2026, 5, 26),
      updatedAt: DateTime(2026, 5, 26),
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
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
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

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage(
        'Inspect release tags',
        bypassPlanMode: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(toolService.executedToolNames, ['git_execute_command']);
      expect(toolDataSource.toolResultBatches, hasLength(1));
      final result = toolDataSource.toolResultBatches.single.single;
      expect(result.result, contains('1.3.4+15'));
      expect(
        result.result,
        isNot(contains('git_tag_format_inspection_required')),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'repeated successful git command can continue to next tool call',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'git_execute_command',
            arguments: const {'command': 'tag --list'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-2',
                name: 'git_execute_command',
                arguments: const {'command': 'tag --list'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-3',
                name: 'write_file',
                arguments: const {
                  'path': 'docs/releases/caverno-1.3.4.md',
                  'content': '# Caverno 1.3.4\n',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Release notes were created.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Release notes were created.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'git_execute_command':
              '{"command":"git tag --list","working_directory":"/tmp/project","exit_code":0,"stdout":"1.3.3+14\\n1.3.4+15\\n","stderr":""}',
          'write_file': '{"ok":true,"created":true}',
        },
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
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
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
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

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage(
          'Create release notes',
          bypassPlanMode: true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(toolService.executedToolNames, [
          'git_execute_command',
          'write_file',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches[1].single.result,
          contains('1.3.4+15'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Release notes were created.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('git tag creation runs after tag format inspection', () async {
    final conversationRepository = _FakeConversationRepository();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'git_execute_command',
          arguments: const {'command': 'tag --list'},
        ),
      ],
      followUpToolCalls: [
        ToolCallInfo(
          id: 'tool-2',
          name: 'git_execute_command',
          arguments: const {
            'command': 'tag 1.3.4+15',
            'reason': 'Create release tag matching existing format',
          },
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {'git_execute_command': '{"exit_code":0}'},
      queuedResults: const {
        'git_execute_command': [
          '{"command":"git tag --list","working_directory":"/tmp/project","exit_code":0,"stdout":"1.3.3+14\\n","stderr":""}',
          '{"command":"git tag 1.3.4+15","working_directory":"/tmp/project","exit_code":0,"stdout":"","stderr":""}',
        ],
      },
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/tmp/project',
      createdAt: DateTime(2026, 5, 26),
      updatedAt: DateTime(2026, 5, 26),
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
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
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

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage(
        'Create a release tag',
        bypassPlanMode: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(toolNotifier.state.pendingGitCommand, isNull);
      expect(toolService.executedToolNames, [
        'git_execute_command',
        'git_execute_command',
      ]);
      expect(
        toolService.executedToolArguments.map((arguments) {
          return arguments['command'];
        }),
        ['tag --list', 'tag 1.3.4+15'],
      );
      expect(toolDataSource.toolResultBatches, hasLength(2));
      expect(
        toolDataSource.toolResultBatches.last.single.result,
        isNot(contains('git_tag_format_inspection_required')),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test('full access runs git writes without a pending approval', () async {
    final conversationRepository = _FakeConversationRepository();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'git_execute_command',
          arguments: const {
            'command': 'checkout -b full-access-branch',
            'working_directory': '/tmp/project',
          },
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {'git_execute_command': '{"exit_code":0}'},
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/tmp/project',
      createdAt: DateTime(2026, 5, 26),
      updatedAt: DateTime(2026, 5, 26),
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
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
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

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Create a branch', bypassPlanMode: true);
      await Future<void>.delayed(Duration.zero);

      expect(toolNotifier.state.pendingGitCommand, isNull);
      expect(toolDataSource.autoReviewRequestMessages, isEmpty);
      expect(toolService.executedToolNames, ['git_execute_command']);
    } finally {
      toolContainer.dispose();
    }
  });
}
