part of 'chat_notifier_test.dart';

void registerChatNotifierGitGuardrailTests() {
  test(
    'sendMessage marks Japanese commit completion claim without tool call as unexecuted',
    () async {
      // Reproduces the real session where the model answered a new "commit"
      // turn with "コミットが完了しました" and a change table, but issued no tool
      // call — the prior turn's commit had been blocked. The completion claim
      // must be replaced with the unexecuted-command notice.
      const finalContent =
          'コミットが完了しました。\n\n**今回の変更:**\n\n| ファイル | コミット |\n'
          '|---|---|\n| docs/releases/caverno-1.3.8.md | feat: Add release notes |\n'
          '| pubspec.yaml | chore: Bump version to 1.3.8+19 |';
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
          'The requested command was not executed because no matching successful command-execution tool result is available for that claimed action.',
        ),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('コミットが完了しました')),
      );
    },
  );

  test(
    'sendMessage neutralizes commit completion claim when a git commit fails '
    'before an unrelated command succeeds',
    () async {
      // Regression guard: a failed `git commit` (exit 2) followed by an
      // unrelated successful command (exit 0) must not let a streamed
      // "コミットが完了しました" claim survive. The completion-claim guards strip
      // the false claim and mark it unverified.
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-commit',
            name: 'git_execute_command',
            arguments: const {
              'command': 'commit -m "docs: add release notes"',
              'reason': 'Commit release notes',
            },
          ),
        ],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'tool-ls',
            name: 'local_execute_command',
            arguments: const {'command': 'ls'},
          ),
        ],
        finalAnswerChunks: const ['コミットが完了しました。'],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'git_execute_command': 'Execute a git command.',
          'local_execute_command': 'Execute a local command.',
        },
        results: const {
          'git_execute_command':
              '{"command":"git commit -m \\"docs: add release notes\\"",'
              '"exit_code":2,"code":"git_commit_unstaged_changes"}',
          'local_execute_command':
              '{"command":"ls","exit_code":0,"stdout":"a\\n"}',
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
      await chatNotifier.sendMessage('save and commit');

      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('コミットが完了しました')),
      );
      expect(chatNotifier.state.messages.last.content, contains('unverified'));
    },
  );

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
          'The requested command was not executed because no matching successful command-execution tool result is available for that claimed action.',
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

  test(
    'sendMessage accepts production release after ask-user-question approval',
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
            content: 'Dry run succeeded. I need production release approval.',
            toolCalls: [
              ToolCallInfo(
                id: 'release-approval',
                name: 'ask_user_question',
                arguments: const {
                  'question':
                      'Approve running the production release command now?',
                  'options': [
                    {'label': 'Approve production release'},
                    {'label': 'Do not release'},
                  ],
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'The user approved production release execution. I will run the production release command now.',
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
            content: 'Production release completed.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Production release completed.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'ask_user_question': '',
          'local_execute_command': 'unexpected fallback command result',
        },
        queuedResults: {
          'local_execute_command': [
            jsonEncode({
              'command': dryRunCommand,
              'working_directory': '/tmp/project',
              'exit_code': 0,
              'stdout': 'Dry run completed successfully.',
              'stderr': '',
            }),
            jsonEncode({
              'command': productionCommand,
              'working_directory': '/tmp/project',
              'exit_code': 0,
              'stdout': 'Production release completed successfully.',
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

        final sendFuture = toolNotifier.sendMessage('continue');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final pending = toolNotifier.state.pendingAskUserQuestion;
        expect(pending, isNotNull);
        toolNotifier.resolveAskUserQuestion(
          id: pending!.id,
          answer: AskUserQuestionAnswer(
            question: pending.question,
            selectedOptions: const [
              AskUserQuestionSelection(
                id: 'approve-production-release',
                label: 'Approve production release',
              ),
            ],
          ),
        );

        await sendFuture;

        expect(toolService.executedToolNames, [
          'local_execute_command',
          'local_execute_command',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(3));
        final productionResult =
            jsonDecode(toolDataSource.toolResultBatches.last.last.result)
                as Map<String, dynamic>;
        expect(productionResult, containsPair('command', productionCommand));
        expect(productionResult, containsPair('exit_code', 0));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage accepts production release after direct user approval reply',
    () async {
      const productionCommand =
          'bash tool/release_ios_macos.sh --macos-release-notes docs/releases/caverno-1.3.6.md';
      final now = DateTime(2026, 5, 25, 10);
      final conversation = Conversation(
        id: 'release-approval-reply',
        title: 'Release approval reply',
        messages: [
          Message(
            id: 'assistant-approval-request',
            role: MessageRole.assistant,
            content:
                'The production release command was blocked. Run this command '
                'only after explicit approval: `$productionCommand`. '
                'Do you approve executing the production release command now?',
            timestamp: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
        workspaceMode: WorkspaceMode.coding,
        projectId: '/tmp/project',
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'release-production',
            name: 'process_start',
            arguments: const {
              'command': productionCommand,
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Production release started.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Production release started.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {'process_start': ''},
        queuedResults: {
          'process_start': [
            jsonEncode({
              'ok': true,
              'job_id': 'release-job-1',
              'command': productionCommand,
              'working_directory': '/tmp/project',
              'started_at': now.toIso8601String(),
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

        await toolNotifier.sendMessage('承認します。続けてください。');

        expect(toolService.executedToolNames, ['process_start']);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        final productionResult =
            jsonDecode(toolDataSource.toolResultBatches.single.single.result)
                as Map<String, dynamic>;
        expect(productionResult, containsPair('command', productionCommand));
        expect(productionResult, containsPair('job_id', 'release-job-1'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage neutralizes production release success claim after direct approval when no tool call is issued',
    () async {
      const productionCommand =
          'bash tool/release_ios_macos.sh --macos-release-notes docs/releases/caverno-1.3.8.md';
      const finalContent =
          'iOS リリースを再実行します。\n\n'
          'iOS リリースが完了しました。結果は以下の通りです。\n\n'
          '## iOS 成功\n\n'
          '- **バージョン**: 1.3.8+20\n'
          '- **ビルド・署名**: 完了\n'
          '- **Export**: 完了（`build/ios/archive/Export/`）\n'
          '- **IPA**: `Caverno-1.3.8-20.ipa`\n'
          '- **S3 アップロード**: 完了\n'
          '- **公開検証**: 成功\n\n'
          '## macOS 成功\n\n'
          '- **ビルド・署名・Notarization**: 完了\n'
          '- **S3 アップロード**: 完了\n\n'
          '両プラットフォームのリリースが完了しました。';
      final now = DateTime(2026, 5, 25, 10);
      final conversation = Conversation(
        id: 'release-approval-no-tool',
        title: 'Release approval no tool',
        messages: [
          Message(
            id: 'assistant-approval-request',
            role: MessageRole.assistant,
            content:
                'The production release command was blocked. Run this command '
                'only after explicit approval: `$productionCommand`. '
                'Do you approve executing the production release command now?',
            timestamp: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
        workspaceMode: WorkspaceMode.coding,
        projectId: '/tmp/project',
      );
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialFinishReason: 'stop',
        initialCompletionContent: finalContent,
        initialStreamChunks: const [finalContent],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'process_start': 'Start a local process.',
          'local_execute_command': 'Execute a local shell command.',
        },
        results: const {
          'process_start': '',
          'local_execute_command': '{"exit_code":0}',
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
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
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

        await toolNotifier.sendMessage('承認します。');

        expect(toolService.executedToolNames, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains(
            'The requested command was not executed because no matching successful command-execution tool result is available for that claimed action.',
          ),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('iOS リリースが完了しました')),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('両プラットフォームのリリースが完了しました')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'ask_user_question prompts again for a different question in the same turn',
    () async {
      // Regression: the same-turn answer cache was keyed only by interaction
      // generation, so a DIFFERENT question reused the first answer and never
      // re-prompted. Two distinct questions in one turn must each prompt.
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'first-question',
            name: 'ask_user_question',
            arguments: const {
              'question': 'Approve the release?',
              'options': [
                {'label': 'Approve'},
                {'label': 'Cancel'},
              ],
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'I still need one detail.',
            toolCalls: [
              ToolCallInfo(
                id: 'second-question',
                name: 'ask_user_question',
                arguments: const {
                  'question': 'What is the notary profile name?',
                  'options': [
                    {'label': 'default'},
                  ],
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(content: 'All set.', finishReason: 'stop'),
        ],
        finalAnswerChunks: const ['All set.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {'ask_user_question': ''},
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
        final sendFuture = toolNotifier.sendMessage('continue');
        for (var i = 0; i < 4; i += 1) {
          await Future<void>.delayed(Duration.zero);
        }

        final firstPending = toolNotifier.state.pendingAskUserQuestion;
        expect(firstPending, isNotNull);
        expect(firstPending!.question, 'Approve the release?');
        toolNotifier.resolveAskUserQuestion(
          id: firstPending.id,
          answer: AskUserQuestionAnswer(
            question: firstPending.question,
            selectedOptions: const [
              AskUserQuestionSelection(id: 'approve', label: 'Approve'),
            ],
          ),
        );

        for (var i = 0; i < 4; i += 1) {
          await Future<void>.delayed(Duration.zero);
        }

        // The fix: a different question re-prompts instead of reusing the
        // earlier answer. Under the bug, no second pending question appears.
        final secondPending = toolNotifier.state.pendingAskUserQuestion;
        expect(secondPending, isNotNull);
        expect(secondPending!.question, 'What is the notary profile name?');
        toolNotifier.resolveAskUserQuestion(
          id: secondPending.id,
          answer: AskUserQuestionAnswer(
            question: secondPending.question,
            selectedOptions: const [
              AskUserQuestionSelection(id: 'default', label: 'default'),
            ],
          ),
        );

        await sendFuture;
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage blocks production release after ask-user-question rejection',
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
            content: 'Dry run succeeded. I need production release approval.',
            toolCalls: [
              ToolCallInfo(
                id: 'release-approval',
                name: 'ask_user_question',
                arguments: const {
                  'question':
                      'Approve running the production release command now?',
                  'options': [
                    {'label': 'Approve production release'},
                    {'label': 'Do not release'},
                  ],
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'The answer was not approval, but I will run the production release command now.',
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
            content: 'Production release remains blocked.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'ask_user_question': '',
          'local_execute_command': 'unexpected fallback command result',
        },
        queuedResults: {
          'local_execute_command': [
            jsonEncode({
              'command': dryRunCommand,
              'working_directory': '/tmp/project',
              'exit_code': 0,
              'stdout': 'Dry run completed successfully.',
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

        final sendFuture = toolNotifier.sendMessage('continue');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final pending = toolNotifier.state.pendingAskUserQuestion;
        expect(pending, isNotNull);
        toolNotifier.resolveAskUserQuestion(
          id: pending!.id,
          answer: AskUserQuestionAnswer(
            question: pending.question,
            selectedOptions: const [
              AskUserQuestionSelection(
                id: 'do-not-release',
                label: 'Do not release',
              ),
            ],
          ),
        );

        await sendFuture;

        expect(toolService.executedToolNames, ['local_execute_command']);
        expect(toolDataSource.toolResultBatches, hasLength(3));
        final releaseBlock =
            jsonDecode(toolDataSource.toolResultBatches.last.last.result)
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
