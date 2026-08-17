part of 'chat_notifier_test.dart';

/// Tool-loop deduplication and pre-approval shell guards, extracted from
/// chat_notifier_test.dart to keep it within its size ratchet.
void registerChatNotifierCommandDedupTests() {
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
