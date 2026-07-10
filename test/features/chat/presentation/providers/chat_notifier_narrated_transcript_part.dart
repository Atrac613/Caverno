part of 'chat_notifier_test.dart';

// Narrated-transcript claim guard tests: a final answer that presents a
// terminal transcript for commands that never executed (fabricated
// verification evidence, observed live in coding session 87f29602) must be
// repaired by actually running the commands or annotated as unverified.
void registerChatNotifierNarratedTranscriptTests() {
  const executedCompound =
      'dart run lib/main.dart add "buy milk" && dart run lib/main.dart list';
  const fabricatedAnswer = '''
The TODO CLI is implemented and verified:

```bash
\$ dart run lib/main.dart add "buy milk"
#1 [ ] buy milk
\$ dart run lib/main.dart done 4
Todo #4 marked as done.
```

The MVP is complete.''';
  const loopCompletion =
      'The command completed successfully after running the local command. '
      'The implementation is complete.';

  Future<Directory> createProjectRoot() async {
    final projectRoot = await Directory.systemTemp.createTemp(
      'narrated_transcript_project_',
    );
    addTearDown(() async {
      if (projectRoot.existsSync()) {
        await projectRoot.delete(recursive: true);
      }
    });
    return projectRoot;
  }

  _QueuedToolLoopChatDataSource buildDataSource({
    required String workingDirectory,
    required List<ChatCompletionResult> toolLoopResponses,
    required List<List<String>> finalAnswerChunkBatches,
  }) {
    return _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'run-compound',
          name: 'local_execute_command',
          arguments: {
            'command': executedCompound,
            'working_directory': workingDirectory,
          },
        ),
      ],
      toolLoopResponses: toolLoopResponses,
      finalAnswerChunkBatches: finalAnswerChunkBatches,
      finalAnswerChunks: const [fabricatedAnswer],
    );
  }

  _FakeMcpToolService buildToolService({
    required String workingDirectory,
    List<String> extraCommandResults = const [],
  }) {
    return _FakeMcpToolService(
      descriptions: const {
        'local_execute_command': 'Execute a local shell command.',
      },
      results: const {'local_execute_command': 'unexpected fallback'},
      queuedResults: {
        'local_execute_command': [
          jsonEncode({
            'command': executedCompound,
            'working_directory': workingDirectory,
            'exit_code': 0,
            'stdout': '#1 [ ] buy milk\n',
            'stderr': '',
          }),
          ...extraCommandResults,
        ],
      },
    );
  }

  ProviderContainer buildContainer({
    required String projectRoot,
    required _QueuedToolLoopChatDataSource dataSource,
    required _FakeMcpToolService toolService,
    SettingsNotifier Function() settingsNotifierBuilder =
        _ToolEnabledNoConfirmSettingsNotifier.new,
  }) {
    final project = CodingProject(
      id: 'narrated-transcript',
      name: 'Narrated Transcript',
      rootPath: projectRoot,
      createdAt: DateTime(2026, 7, 10),
      updatedAt: DateTime(2026, 7, 10),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(settingsNotifierBuilder),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
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
        codingDiagnosticFeedbackServiceProvider.overrideWithValue(
          _FakeCodingDiagnosticFeedbackService(null),
        ),
        codingVerificationFeedbackServiceProvider.overrideWithValue(
          _FakeCodingVerificationFeedbackService.runs([]),
        ),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    container
        .read(conversationsNotifierProvider.notifier)
        .ensureCurrentConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
        );
    return container;
  }

  test(
    'sendMessage replaces a fabricated transcript when the repair declines '
    'to execute the narrated commands',
    () async {
      const repairProse =
          'The done command was not actually executed; treat that '
          'check as not run.';
      final projectRoot = await createProjectRoot();
      final dataSource = buildDataSource(
        workingDirectory: projectRoot.path,
        toolLoopResponses: [
          ChatCompletionResult(content: loopCompletion, finishReason: 'stop'),
          // Narrated-transcript repair follow-up answers with prose instead
          // of executing the narrated command.
          ChatCompletionResult(content: repairProse, finishReason: 'stop'),
        ],
        finalAnswerChunkBatches: const [],
      );
      final toolService = buildToolService(
        workingDirectory: projectRoot.path,
      );
      final container = buildContainer(
        projectRoot: projectRoot.path,
        dataSource: dataSource,
        toolService: toolService,
      );
      addTearDown(container.dispose);

      final chatNotifier = container.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Implement the TODO CLI and verify it.');
      await _waitForCondition(
        () => !container.read(chatNotifierProvider).isLoading,
      );

      final answer = container.read(chatNotifierProvider).messages.last.content;
      // The blocking feedback removed the streamed fabricated answer and the
      // repair prose replaced it, so no fake output reaches the user.
      expect(answer, contains(repairProse));
      expect(answer, isNot(contains('Todo #4 marked as done.')));
      expect(
        dataSource.toolResultBatches
            .expand((batch) => batch)
            .map((result) => result.name),
        contains('narrated_transcript_check'),
      );
      // Only the compound command ran; the narrated done never executed.
      expect(
        toolService.executedToolArguments.map(
          (arguments) => arguments['command'],
        ),
        isNot(contains('dart run lib/main.dart done 4')),
      );
    },
  );

  test(
    'sendMessage annotates a fabricated transcript when the repair is '
    'disabled',
    () async {
      final projectRoot = await createProjectRoot();
      final dataSource = buildDataSource(
        workingDirectory: projectRoot.path,
        toolLoopResponses: [
          ChatCompletionResult(content: loopCompletion, finishReason: 'stop'),
        ],
        finalAnswerChunkBatches: const [],
      );
      final toolService = buildToolService(
        workingDirectory: projectRoot.path,
      );
      final container = buildContainer(
        projectRoot: projectRoot.path,
        dataSource: dataSource,
        toolService: toolService,
        settingsNotifierBuilder: _ToolEnabledNoVerificationSettingsNotifier.new,
      );
      addTearDown(container.dispose);

      final chatNotifier = container.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Implement the TODO CLI and verify it.');
      await _waitForCondition(
        () => !container.read(chatNotifierProvider).isLoading,
      );

      final answer = container.read(chatNotifierProvider).messages.last.content;
      expect(answer, contains('Transcript claim check:'));
      expect(answer, contains('`dart run lib/main.dart done 4`'));
      // The executed add/list compound must not be flagged.
      expect(
        answer,
        isNot(contains('`dart run lib/main.dart add "buy milk"`')),
      );
      expect(
        dataSource.toolResultBatches
            .expand((batch) => batch)
            .map((result) => result.name),
        isNot(contains('narrated_transcript_check')),
      );
    },
  );

  test(
    'sendMessage revives the tool loop to execute narrated transcript '
    'commands for real',
    () async {
      final projectRoot = await createProjectRoot();
      final dataSource = buildDataSource(
        workingDirectory: projectRoot.path,
        toolLoopResponses: [
          ChatCompletionResult(content: loopCompletion, finishReason: 'stop'),
          // Narrated-transcript repair follow-up executes the narrated
          // command instead of restating completion.
          ChatCompletionResult(
            content: 'Executing the narrated command now.',
            toolCalls: [
              ToolCallInfo(
                id: 'repair-done-4',
                name: 'local_execute_command',
                arguments: {
                  'command': 'dart run lib/main.dart done 4',
                  'working_directory': projectRoot.path,
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'The command completed successfully after running the local '
                'command. The implementation is complete.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunkBatches: const [
          [fabricatedAnswer],
          [
            'done 4 executed with exit code 0; all acceptance checks pass '
                'against real output.',
          ],
        ],
      );
      final toolService = buildToolService(
        workingDirectory: projectRoot.path,
        extraCommandResults: [
          jsonEncode({
            'command': 'dart run lib/main.dart done 4',
            'working_directory': projectRoot.path,
            'exit_code': 0,
            'stdout': 'Todo #4 marked as done.\n',
            'stderr': '',
          }),
        ],
      );
      final container = buildContainer(
        projectRoot: projectRoot.path,
        dataSource: dataSource,
        toolService: toolService,
      );
      addTearDown(container.dispose);

      final chatNotifier = container.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Implement the TODO CLI and verify it.');
      await _waitForCondition(
        () => !container.read(chatNotifierProvider).isLoading,
      );

      expect(
        toolService.executedToolArguments.map(
          (arguments) => arguments['command'],
        ),
        contains('dart run lib/main.dart done 4'),
      );
      expect(
        dataSource.toolResultBatches
            .expand((batch) => batch)
            .map((result) => result.name),
        contains('narrated_transcript_check'),
      );
      final answer = container.read(chatNotifierProvider).messages.last.content;
      expect(answer, contains('all acceptance checks pass'));
      expect(answer, isNot(contains('Transcript claim check:')));
    },
  );

  test(
    'sendMessage answers a length-truncated empty-arguments tool call with '
    'a truncation diagnostic instead of executing it',
    () async {
      final projectRoot = await createProjectRoot();
      final dataSource = buildDataSource(
        workingDirectory: projectRoot.path,
        toolLoopResponses: [
          // The follow-up hit the output token limit while generating the
          // tool call arguments, so they parsed empty (session 87f29602
          // entry 18: 8192 completion tokens, finish_reason=length, {}).
          ChatCompletionResult(
            content: 'Now running the full verification chain.',
            toolCalls: [
              ToolCallInfo(
                id: 'truncated-verification',
                name: 'local_execute_command',
                arguments: const {},
              ),
            ],
            finishReason: 'length',
          ),
          ChatCompletionResult(content: loopCompletion, finishReason: 'stop'),
        ],
        finalAnswerChunkBatches: const [
          ['The add and list commands were verified against real output.'],
        ],
      );
      final toolService = buildToolService(
        workingDirectory: projectRoot.path,
      );
      final container = buildContainer(
        projectRoot: projectRoot.path,
        dataSource: dataSource,
        toolService: toolService,
      );
      addTearDown(container.dispose);

      final chatNotifier = container.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Implement the TODO CLI and verify it.');
      await _waitForCondition(
        () => !container.read(chatNotifierProvider).isLoading,
      );

      // Only the initial compound command was dispatched; the truncated call
      // never reached the tool service.
      expect(toolService.executedToolNames, ['local_execute_command']);
      expect(
        toolService.executedToolArguments.single['command'],
        executedCompound,
      );
      final truncationResults = dataSource.toolResultBatches
          .expand((batch) => batch)
          .where(
            (result) =>
                result.result.contains('tool_call_arguments_truncated'),
          );
      expect(truncationResults, hasLength(1));
      expect(
        truncationResults.single.result,
        contains('finish_reason=length'),
      );
    },
  );
}
