part of 'chat_notifier_test.dart';

/// Tool-loop deduplication and pre-approval shell guards, extracted from
/// chat_notifier_test.dart to keep it within its size ratchet.
void registerChatNotifierCommandDedupTests() {
  test('duplicate read recovery preserves the path to editing', () async {
    final directory = Directory.systemTemp.createTempSync(
      'duplicate-recovery-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/retry.py')
      ..writeAsStringSync('attempts = 1');
    final sourceFiles = [
      for (final name in ['fetch.py', 'notify.py'])
        File('${directory.path}/$name')..writeAsStringSync('x' * 6000),
    ];
    final project = CodingProject(
      id: 'duplicate-recovery',
      name: 'duplicate-recovery',
      rootPath: directory.path,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    ToolCallInfo read(String id) => ToolCallInfo(
      id: id,
      name: 'read_file',
      arguments: const {'path': 'retry.py'},
    );
    final dataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        for (final source in sourceFiles)
          ToolCallInfo(
            id: source.path,
            name: 'read_file',
            arguments: {'path': source.path},
          ),
        read('read-1'),
      ],
      toolLoopResponses: [
        for (final id in ['read-2', 'read-3', 'read-4'])
          ChatCompletionResult(
            content: '',
            toolCalls: [read(id)],
            finishReason: 'tool_calls',
          ),
        ChatCompletionResult(
          content: '',
          toolCalls: [
            ToolCallInfo(
              id: 'edit-retry',
              name: 'edit_file',
              arguments: const {
                'path': 'retry.py',
                'old_text': 'attempts = 1',
                'new_text': 'attempts = 3',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'The retry edit is complete.',
          finishReason: 'stop',
        ),
      ],
      finalAnswerChunks: const ['The retry edit is complete.'],
    );
    final tools = _FakeMcpToolService(
      results: {
        'read_file': jsonEncode({'path': file.path, 'content': 'attempts = 1'}),
        'edit_file': jsonEncode({
          'path': file.path,
          'changed': true,
          'replacements': 1,
        }),
      },
      parameters: const {
        'read_file': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
            'offset': {'type': 'integer'},
            'limit': {'type': 'integer'},
          },
          'required': ['path'],
        },
      },
      queuedResults: {
        'read_file': [
          for (final source in sourceFiles)
            jsonEncode({'path': source.path, 'content': 'x' * 6000}),
          jsonEncode({'path': file.path, 'content': 'attempts = 1'}),
        ],
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
        mcpToolServiceProvider.overrideWithValue(tools),
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
    await notifier.sendMessage('Implement retry support in retry.py');

    Map parametersAt(int index) =>
        dataSource.toolResultDefinitions[index].singleWhere(
              (definition) => definition['function']['name'] == 'read_file',
            )['function']['parameters']
            as Map;
    expect(tools.executedToolNames, [
      'read_file',
      'read_file',
      'read_file',
      'edit_file',
    ]);
    // Both normal follow-ups and duplicate recovery need the implementation
    // files together. Session b82411f0 lost them under the 8 KiB carry cap.
    for (final batch in dataSource.toolResultBatches.skip(1)) {
      for (final source in sourceFiles) {
        expect(
          batch.any(
            (result) =>
                result.arguments['path'] == source.path &&
                result.result.contains('x' * 6000) &&
                result.fromEarlierLoop,
          ),
          isTrue,
        );
      }
    }
    // The two bounded recoveries use range reads, then the normal catalogue
    // returns after the edit. No shared definition was mutated.
    for (final index in [2, 3]) {
      expect(parametersAt(index)['required'], containsAll(['offset', 'limit']));
      expect(parametersAt(index)['properties']['limit']['maximum'], 120);
    }
    expect(parametersAt(4)['required'], ['path']);
    expect(
      notifier.state.messages.last.content,
      contains('The retry edit is complete.'),
    );
  });

  test(
    'duplicate-inspection recovery drops saved-task framing without a task',
    () {
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(chatNotifierProvider.notifier);
      final repeated = [
        ToolCallInfo(
          id: 'status',
          name: 'git_execute_command',
          arguments: const {'command': 'status --short'},
        ),
      ];

      final withTask = notifier.buildDuplicateInspectionRecoveryPromptForTest(
        repeated,
      );
      final withoutTask = notifier
          .buildDuplicateInspectionRecoveryPromptForTest(
            repeated,
            hasSavedTask: false,
          );

      // With no saved task the two-way demand has no reachable branch, and it
      // pushed toward editing a file during a turn that asked for a commit.
      expect(
        withTask,
        contains('modify a saved target file or run the saved validation'),
      );
      expect(withoutTask, isNot(contains('saved target file')));
      expect(withoutTask, isNot(contains('saved validation')));
      expect(withoutTask, isNot(contains('saved task')));
      // The part that does the work is kept either way.
      expect(
        withoutTask,
        contains('Do not repeat identical read-only inspection tools'),
      );
      expect(
        withoutTask,
        contains('Take the next concrete action the user asked for now.'),
      );
    },
  );

  test('duplicate follow-up recovery drops saved-task framing too', () {
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(chatNotifierProvider.notifier);

    final withoutTask = notifier.buildDuplicateFollowUpRecoveryPromptForTest([
      ToolCallInfo(
        id: 'search',
        name: 'search_web',
        arguments: const {'query': 'x'},
      ),
    ], hasSavedTask: false);

    expect(withoutTask, isNot(contains('saved task')));
    expect(withoutTask, isNot(contains('saved target file')));
    // The false-completion-claim guardrail is not task-specific and stays.
    expect(
      withoutTask,
      contains('Do not claim that files were created, edited, saved'),
    );
  });

  test(
    'sendMessage re-executes a read-only command only when reworded',
    () async {
      // Session 655e367f re-ran the same gh investigation across loop
      // iterations. This pins whether the loop's own dedup catches it.
      const command = 'gh pr checks 276 --repo Shiftall/gs1_flutter_app';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'checks-first',
            name: 'local_execute_command',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
              'reason': 'CIの状態を確認するため',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'checks-second',
                name: 'local_execute_command',
                arguments: const {
                  'command': command,
                  'working_directory': '/tmp/project',
                  // Only the narration differs, as in the real session.
                  'reason': 'PRの現在のCIチェック状態を確認するため',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunks: const ['CI checks are failing.'],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'command': command,
            'working_directory': '/tmp/project',
            'exit_code': 1,
            'stdout': 'flutter ci\tfail\t2m18s\n',
            'stderr': '',
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

        await toolNotifier.sendMessage('CIのエラーを調べて');

        // Characterization, not an endorsement: the execution key keeps
        // narration for non-file-mutation tools on purpose, so a re-narrated
        // read-only inspection can legitimately re-run (see
        // ToolCallExecutionPolicy.nonSemanticArgumentKeys). Byte-identical
        // arguments are still deduplicated. Session 655e367f shows the cost
        // when the model rewords out of amnesia rather than intent, which is
        // what the tool-loop context digest now addresses.
        expect(
          toolService.executedToolNames
              .where((name) => name == 'local_execute_command')
              .length,
          2,
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage re-runs a read-only git command whose output was dropped',
    () async {
      // Session 96e27118: the turn ran `git tag --list` at loop 5, the
      // follow-up request carried only the current batch's results so the tag
      // list was gone by loop 7, and the context digest told the model to run
      // the command again when it needed the output. It did -- the duplicate
      // guard discarded the identical call, the batch came back empty, and the
      // turn ended on its own Japanese preamble with no notice. The re-run has
      // to reach the shell.
      const command = 'tag --list --sort=-version:refname';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tags-first',
            name: 'git_execute_command',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tags-second',
                name: 'git_execute_command',
                // Byte-identical to the first call, narration included.
                arguments: const {
                  'command': command,
                  'working_directory': '/tmp/project',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunks: const ['Latest tag is 1.3.34+47.'],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'git_execute_command': jsonEncode({
            'command': 'git $command',
            'working_directory': '/tmp/project',
            'exit_code': 0,
            'stdout': '1.3.34+47\n1.3.33+46\n',
            'stderr': '',
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

        await toolNotifier.sendMessage('バージョンを上げてリリースして');

        expect(
          toolService.executedToolNames
              .where((name) => name == 'git_execute_command')
              .length,
          2,
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  // Session e3a9f3f0: a read-only `/review` re-issued a command whose output
  // the follow-up no longer carried, the duplicate was discarded, and the turn
  // answered with that command's raw stdout instead of the review.
  Future<String> answerAfterDiscardedDuplicate(
    ChatCompletionResult recovery,
  ) async {
    final repeated = {
      'command': './scripts/list_changes.sh',
      'working_directory': '/tmp/project',
      'reason': 'List untracked files',
    };
    final toolDataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'list-first',
          name: 'local_execute_command',
          arguments: repeated,
        ),
      ],
      toolLoopResponses: [
        ChatCompletionResult(
          content: '',
          toolCalls: [
            ToolCallInfo(
              id: 'list-second',
              name: 'local_execute_command',
              arguments: repeated,
            ),
          ],
          finishReason: 'tool_calls',
        ),
        recovery,
      ],
      finalAnswerChunks: const ['unexpected final answer'],
    );
    final toolService = _FakeMcpToolService(
      results: {
        'local_execute_command': jsonEncode({
          'command': './scripts/list_changes.sh',
          'working_directory': '/tmp/project',
          'exit_code': 0,
          'stdout': 'untracked.py\n',
          'stderr': '',
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
      await toolNotifier.sendMessage('Review the uncommitted changes');
      expect(toolService.executedToolNames, ['local_execute_command']);
      expect(
        toolDataSource.toolResultBatches,
        hasLength(2),
        reason: 'the discarded duplicate must reach one bounded recovery',
      );
      return toolNotifier.state.messages.last.content;
    } finally {
      toolContainer.dispose();
    }
  }

  test(
    'a discarded duplicate command lets the model write the answer first',
    () async {
      final answer = await answerAfterDiscardedDuplicate(
        ChatCompletionResult(
          content: 'Review: untracked.py has no tests yet.',
          finishReason: 'stop',
        ),
      );

      expect(answer, contains('Review: untracked.py has no tests yet.'));
    },
  );

  test(
    'a discarded duplicate command falls back to its earlier output',
    () async {
      // Session 96e27118's guarantee survives: when the recovery yields no
      // usable text, the output the model asked for is still delivered.
      final answer = await answerAfterDiscardedDuplicate(
        ChatCompletionResult(content: '', finishReason: 'stop'),
      );

      expect(answer, contains('untracked.py'));
    },
  );

  test(
    'sendMessage blocks an embedded git write before requesting approval',
    () async {
      const command = 'gh pr checkout 276 && git push --force-with-lease';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'chained-git-write',
            name: 'local_execute_command',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
              'reason': 'Push the rebased branch',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunks: const ['Pushed.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {'local_execute_command': ''},
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

        await toolNotifier.sendMessage('Push the branch');

        // The shell layer would reject this regardless, so the call never
        // reaches execution and never spends an approval round trip.
        expect(toolService.executedToolNames, isEmpty);
      } finally {
        toolContainer.dispose();
      }
    },
  );
}
