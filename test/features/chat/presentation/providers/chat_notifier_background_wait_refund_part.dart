part of 'chat_notifier_test.dart';

void registerChatNotifierBackgroundWaitRefundTests() {
  test(
    'blocking waits on a running job do not exhaust the tool loop',
    () async {
      // Session 23d19ede: seven 120s polls on a release spent half the
      // 14-iteration budget, and the commit and tag announced right after the
      // release finished were cut off by finalization without tools. Here the
      // waits alone outnumber the 12-iteration cap plus every extension.
      const jobId = 'proc_release_long_wait_1';
      const waitArguments = {'job_id': jobId, 'wait_ms': 120000};
      const runningWaits = 16;
      String waitResult(String status) => jsonEncode({
        'ok': true,
        'status': status,
        if (status == 'exited') 'exit_code': 0,
        'job_id': jobId,
        'pid': 123,
        'command': 'bash tool/release_ios_macos.sh',
        'working_directory': '/tmp/project',
        'stdout_tail': status == 'exited' ? 'Release complete' : 'Uploading',
        'stderr_tail': '',
      });
      ChatCompletionResult call(
        String id,
        String name,
        Map<String, dynamic> args,
      ) => ChatCompletionResult(
        content: 'Continuing the release.',
        toolCalls: [ToolCallInfo(id: id, name: name, arguments: args)],
        finishReason: 'tool_calls',
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'process-start-long-release',
            name: 'process_start',
            arguments: const {
              'command': 'bash tool/release_ios_macos.sh',
              'working_directory': '/tmp/project',
              'label': 'release',
            },
          ),
        ],
        toolLoopResponses: [
          for (var i = 0; i <= runningWaits; i++)
            call('process-wait-long-$i', 'process_wait', waitArguments),
          call('git-status-after-release', 'git_execute_command', {
            'command': 'status',
          }),
          call('git-log-after-release', 'git_execute_command', {
            'command': 'log --oneline -1',
          }),
          ChatCompletionResult(
            content: 'Release finished and the tree is checked.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Release finished and the tree is checked.'],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'process_start': waitResult('running'),
          'process_wait': waitResult('exited'),
          'git_execute_command': jsonEncode({
            'exit_code': 0,
            'stdout': 'On branch main',
            'stderr': '',
          }),
        },
        queuedResults: {
          'process_wait': [
            for (var i = 0; i < runningWaits; i++) waitResult('running'),
            waitResult('exited'),
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

        await toolNotifier.sendMessage('Release the app, then check the tree');

        final batches = toolDataSource.toolResultBatches
            .map((batch) => batch.map((result) => result.name).join(','))
            .toList();
        expect(
          batches.where((names) => names == 'process_wait'),
          hasLength(runningWaits + 1),
        );
        expect(batches.sublist(batches.length - 2), [
          'git_execute_command',
          'git_execute_command',
        ], reason: 'the work after the wait must still get tool iterations');
        expect(
          toolDataSource.toolResultRequestMessages
              .expand((messages) => messages)
              .map((message) => message.content),
          everyElement(isNot(contains('bounded tool loop limit'))),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );
}
