part of 'chat_notifier_test.dart';

void registerChatNotifierAskUserQuestionTests() {
  test('ask-user-question response survives switching away and back', () async {
    final initialCompletion = Completer<ChatCompletionResult>();
    final dataSource = _DelayedAskQuestionToolChatDataSource(
      initialCompletion: initialCompletion,
    );
    final repository = _FakeConversationRepository();
    final toolService = _FakeMcpToolService(
      results: const {'ask_user_question': ''},
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(repository),
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

    final conversationsNotifier = threadContainer.read(
      conversationsNotifierProvider.notifier,
    );
    final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
    final firstConversationId = threadContainer
        .read(conversationsNotifierProvider)
        .currentConversationId!;

    final sendFuture = chatNotifier.sendMessage('Help choose a direction');
    await Future<void>.delayed(Duration.zero);
    conversationsNotifier.createNewConversation(
      workspaceMode: WorkspaceMode.chat,
    );
    final secondConversationId = threadContainer
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    expect(secondConversationId, isNot(firstConversationId));
    expect(chatNotifier.state.pendingAskUserQuestion, isNull);

    initialCompletion.complete(
      ChatCompletionResult(
        content: '',
        finishReason: 'tool_calls',
        toolCalls: [
          ToolCallInfo(
            id: 'tool-ask',
            name: 'ask_user_question',
            arguments: const {
              'question': 'Which direction should we use?',
              'help': 'Pick the implementation direction.',
              'options': [
                {'label': 'Small patch'},
                {'label': 'Refactor with tests'},
              ],
            },
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    conversationsNotifier.selectConversation(firstConversationId);
    await Future<void>.delayed(Duration.zero);

    final pending = chatNotifier.state.pendingAskUserQuestion;
    expect(pending, isNotNull);
    expect(pending!.question, 'Which direction should we use?');
    expect(chatNotifier.state.isLoading, isTrue);
    expect(chatNotifier.state.messages.map((message) => message.role), [
      MessageRole.user,
      MessageRole.assistant,
    ]);

    chatNotifier.resolveAskUserQuestion(
      id: pending.id,
      answer: AskUserQuestionAnswer(
        question: pending.question,
        selectedOptions: const [
          AskUserQuestionSelection(id: 'Small patch', label: 'Small patch'),
        ],
      ),
    );
    await sendFuture;

    final firstConversation = threadContainer
        .read(conversationsNotifierProvider)
        .conversations
        .firstWhere((conversation) => conversation.id == firstConversationId);
    expect(
      firstConversation.messages.map((message) => message.content).toList(),
      anyElement(contains('Proceeding with the selected option.')),
    );
    expect(chatNotifier.state.isLoading, isFalse);
    expect(
      chatNotifier.state.messages.last.content,
      contains('Proceeding with the selected option.'),
    );
    expect(
      dataSource.toolResultBatches.single.single.name,
      'ask_user_question',
    );
  });

  test(
    'ask-user-question reuses the first answer when the model asks again',
    () async {
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-ask-first',
            name: 'ask_user_question',
            arguments: const {
              'question': 'Which direction should we use first?',
              'options': [
                {'label': 'Minimal patch'},
                {'label': 'Refactor with tests'},
              ],
            },
          ),
        ],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'tool-ask-repeat',
            name: 'ask_user_question',
            arguments: const {
              'question': 'Which direction should we use now?',
              'options': [
                {'label': 'UI first'},
                {'label': 'Refactor with tests'},
              ],
            },
          ),
        ],
        finalAnswerChunks: const ['Continuing with the selected direction.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {'ask_user_question': ''},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
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
      final sendFuture = chatNotifier.sendMessage('Choose once');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final pending = chatNotifier.state.pendingAskUserQuestion;
      expect(pending, isNotNull);
      expect(pending!.question, 'Which direction should we use first?');
      chatNotifier.resolveAskUserQuestion(
        id: pending.id,
        answer: AskUserQuestionAnswer(
          question: pending.question,
          selectedOptions: const [
            AskUserQuestionSelection(
              id: 'minimal-patch',
              label: 'Minimal patch',
            ),
          ],
        ),
      );

      await sendFuture;

      expect(chatNotifier.state.pendingAskUserQuestion, isNull);
      expect(dataSource.toolResultBatches, hasLength(2));
      final repeatedAskResult =
          jsonDecode(dataSource.toolResultBatches.last.single.result)
              as Map<String, dynamic>;
      expect(repeatedAskResult['reused'], isTrue);
      expect(repeatedAskResult['answer'], 'Minimal patch');
      expect(
        repeatedAskResult['note'],
        contains('Continue using the existing answer'),
      );
      expect(
        chatNotifier.state.messages.last.content,
        contains('Continuing with the selected direction.'),
      );
    },
  );

  test(
    'ask-user-question answer is retained across later tool follow-ups',
    () async {
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-ask-version',
            name: 'ask_user_question',
            arguments: const {
              'question': 'How should the version be updated?',
              'options': [
                {'label': 'Minor version and build number'},
                {'label': 'Build number only'},
              ],
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Use the selected version update.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-read-pubspec',
                name: 'read_file',
                arguments: const {'path': 'pubspec.yaml'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunks: const ['Version update is still pending.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'ask_user_question': '',
          'read_file': '{"path":"pubspec.yaml","content":"version: 1.3.3+14"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
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
      final sendFuture = chatNotifier.sendMessage('Update version and build');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final pending = chatNotifier.state.pendingAskUserQuestion;
      expect(pending, isNotNull);
      chatNotifier.resolveAskUserQuestion(
        id: pending!.id,
        answer: AskUserQuestionAnswer(
          question: pending.question,
          selectedOptions: const [
            AskUserQuestionSelection(
              id: 'minor-and-build',
              label: 'Minor version and build number',
            ),
          ],
        ),
      );

      await sendFuture;

      expect(dataSource.toolResultBatches, hasLength(2));
      expect(dataSource.toolResultBatches.first.map((result) => result.name), [
        'ask_user_question',
      ]);
      expect(dataSource.toolResultBatches.last.map((result) => result.name), [
        'ask_user_question',
        'read_file',
      ]);
      final retainedAnswer =
          jsonDecode(dataSource.toolResultBatches.last.first.result)
              as Map<String, dynamic>;
      expect(retainedAnswer['answer'], 'Minor version and build number');
      expect(toolService.executedToolNames, ['read_file']);
    },
  );

  test(
    'parallel ask-user-question responses survive same prompt in a new thread',
    () async {
      final firstInitialCompletion = Completer<ChatCompletionResult>();
      final secondInitialCompletion = Completer<ChatCompletionResult>();
      final dataSource = _QueuedAskQuestionToolChatDataSource(
        initialCompletions: [firstInitialCompletion, secondInitialCompletion],
        finalAnswers: const [
          'Thread two final answer.',
          'Thread one final answer.',
        ],
      );
      final repository = _FakeConversationRepository();
      final toolService = _FakeMcpToolService(
        results: const {'ask_user_question': ''},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(repository),
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

      final conversationsNotifier = threadContainer.read(
        conversationsNotifierProvider.notifier,
      );
      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final firstConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;

      final firstSendFuture = chatNotifier.sendMessage('Repeat this prompt');
      await Future<void>.delayed(Duration.zero);
      conversationsNotifier.createNewConversation(
        workspaceMode: WorkspaceMode.chat,
      );
      final secondConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      expect(secondConversationId, isNot(firstConversationId));

      final secondSendFuture = chatNotifier.sendMessage('Repeat this prompt');
      await Future<void>.delayed(Duration.zero);
      expect(dataSource.initialRequests, hasLength(2));
      expect(dataSource.initialRequestContextConversationIds, [
        firstConversationId,
        secondConversationId,
      ]);

      firstInitialCompletion.complete(
        ChatCompletionResult(
          content: '',
          finishReason: 'tool_calls',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-ask-first',
              name: 'ask_user_question',
              arguments: const {
                'question': 'Which direction for thread one?',
                'options': [
                  {'label': 'Thread one option'},
                ],
              },
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(chatNotifier.state.pendingAskUserQuestion, isNull);

      secondInitialCompletion.complete(
        ChatCompletionResult(
          content: '',
          finishReason: 'tool_calls',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-ask-second',
              name: 'ask_user_question',
              arguments: const {
                'question': 'Which direction for thread two?',
                'options': [
                  {'label': 'Thread two option'},
                ],
              },
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final secondPending = chatNotifier.state.pendingAskUserQuestion;
      expect(secondPending, isNotNull);
      expect(secondPending!.question, 'Which direction for thread two?');
      chatNotifier.resolveAskUserQuestion(
        id: secondPending.id,
        answer: AskUserQuestionAnswer(
          question: secondPending.question,
          selectedOptions: const [
            AskUserQuestionSelection(
              id: 'thread-two-option',
              label: 'Thread two option',
            ),
          ],
        ),
      );
      await secondSendFuture;

      conversationsNotifier.selectConversation(firstConversationId);
      await Future<void>.delayed(Duration.zero);

      final firstPending = chatNotifier.state.pendingAskUserQuestion;
      expect(firstPending, isNotNull);
      expect(firstPending!.question, 'Which direction for thread one?');
      expect(chatNotifier.state.isLoading, isTrue);
      chatNotifier.resolveAskUserQuestion(
        id: firstPending.id,
        answer: AskUserQuestionAnswer(
          question: firstPending.question,
          selectedOptions: const [
            AskUserQuestionSelection(
              id: 'thread-one-option',
              label: 'Thread one option',
            ),
          ],
        ),
      );
      await firstSendFuture;

      final conversations = threadContainer
          .read(conversationsNotifierProvider)
          .conversations;
      final firstConversation = conversations.firstWhere(
        (conversation) => conversation.id == firstConversationId,
      );
      final secondConversation = conversations.firstWhere(
        (conversation) => conversation.id == secondConversationId,
      );
      expect(firstConversation.messages, hasLength(2));
      expect(secondConversation.messages, hasLength(2));
      expect(firstConversation.messages.first.content, 'Repeat this prompt');
      expect(secondConversation.messages.first.content, 'Repeat this prompt');
      expect(
        firstConversation.messages.last.content,
        contains('Thread one final answer.'),
      );
      expect(
        secondConversation.messages.last.content,
        contains('Thread two final answer.'),
      );
      expect(chatNotifier.state.isLoading, isFalse);
      expect(
        chatNotifier.state.messages.last.content,
        contains('Thread one final answer.'),
      );
      expect(dataSource.toolResultBatches, hasLength(2));
      expect(dataSource.toolResultContextConversationIds, [
        secondConversationId,
        firstConversationId,
      ]);
      expect(dataSource.finalAnswerContextConversationIds, [
        secondConversationId,
        firstConversationId,
      ]);
      expect(
        dataSource.toolResultBatches
            .expand((batch) => batch)
            .map((result) => result.name),
        everyElement('ask_user_question'),
      );
    },
  );

  test(
    'save_skill persists an approved skill and re-prompts on every save',
    () async {
      final firstCompletion = Completer<ChatCompletionResult>();
      final secondCompletion = Completer<ChatCompletionResult>();
      final dataSource = _QueuedAskQuestionToolChatDataSource(
        initialCompletions: [firstCompletion, secondCompletion],
        finalAnswers: const ['Saved the skill.', 'Updated the skill.'],
      );
      final repository = _FakeConversationRepository();
      // Offer save_skill so the tool loop does not drop the call as unknown;
      // the registry still routes it to ChatNotifier (never to this fallback).
      final toolService = _FakeMcpToolService(
        results: const {'save_skill': ''},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final skillContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(repository),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          skillsNotifierProvider.overrideWith(_RecordingSkillsNotifier.new),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(skillContainer.dispose);

      final chatNotifier = skillContainer.read(chatNotifierProvider.notifier);

      // First save authors a brand-new skill.
      final firstSend = chatNotifier.sendMessage('Save this as a skill');
      await Future<void>.delayed(Duration.zero);
      firstCompletion.complete(
        ChatCompletionResult(
          content: '',
          finishReason: 'tool_calls',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-save-1',
              name: 'save_skill',
              arguments: const {
                'name': 'iOS Release',
                'description': 'Ship an iOS build',
                'when_to_use': 'When cutting an iOS release',
                'content': '# Steps\n\n1. Bump version.\n2. Archive.',
              },
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final firstPending = chatNotifier.state.pendingFileOperation;
      expect(firstPending, isNotNull);
      expect(firstPending!.operation, 'Save Skill');
      expect(firstPending.path, 'iOS Release');
      expect(firstPending.preview, contains('1. Bump version.'));

      chatNotifier.resolveFileOperation(id: firstPending.id, approved: true);
      await firstSend;

      final afterCreate = skillContainer.read(skillsNotifierProvider).skills;
      expect(afterCreate, hasLength(1));
      expect(afterCreate.single.normalizedName, 'iOS Release');
      expect(afterCreate.single.content, contains('Bump version.'));

      // Saving the same name again must prompt again (non-cacheable) and update
      // the existing skill rather than create a duplicate.
      final secondSend = chatNotifier.sendMessage('Update that skill');
      await Future<void>.delayed(Duration.zero);
      secondCompletion.complete(
        ChatCompletionResult(
          content: '',
          finishReason: 'tool_calls',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-save-2',
              name: 'save_skill',
              arguments: const {
                'name': 'iOS Release',
                'content':
                    '# Steps\n\n1. Bump version.\n2. Archive.\n3. Upload.',
              },
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final secondPending = chatNotifier.state.pendingFileOperation;
      expect(
        secondPending,
        isNotNull,
        reason: 'save_skill must never resolve from the approval cache',
      );
      expect(secondPending!.operation, 'Update Skill');
      // SKILL2: updating an existing skill previews a diff against the stored
      // markdown rather than the full body.
      expect(secondPending.preview, contains('+++ skill: iOS Release'));
      expect(secondPending.preview, contains('Upload.'));

      chatNotifier.resolveFileOperation(id: secondPending.id, approved: true);
      await secondSend;

      final afterUpdate = skillContainer.read(skillsNotifierProvider).skills;
      expect(
        afterUpdate,
        hasLength(1),
        reason: 'saving an existing name updates instead of duplicating',
      );
      expect(afterUpdate.single.content, contains('Upload.'));
    },
  );

  test(
    'coding ask-user-question response survives switching away and back',
    () async {
      final project = CodingProject(
        id: 'project-question-switch',
        name: 'Question switch project',
        rootPath: '/tmp/question-switch-project',
        createdAt: DateTime(2026, 5, 29, 12),
        updatedAt: DateTime(2026, 5, 29, 12),
      );
      final initialCompletion = Completer<ChatCompletionResult>();
      final dataSource = _DelayedAskQuestionToolChatDataSource(
        initialCompletion: initialCompletion,
      );
      final repository = _FakeConversationRepository();
      final toolService = _FakeMcpToolService(
        results: const {'ask_user_question': ''},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(repository),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
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

      final conversationsNotifier = threadContainer.read(
        conversationsNotifierProvider.notifier,
      );
      conversationsNotifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
        createIfMissing: true,
      );
      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final firstConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;

      final sendFuture = chatNotifier.sendMessage('Choose the coding path');
      await Future<void>.delayed(Duration.zero);
      conversationsNotifier.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
      );
      final secondConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      expect(secondConversationId, isNot(firstConversationId));
      expect(chatNotifier.state.pendingAskUserQuestion, isNull);

      initialCompletion.complete(
        ChatCompletionResult(
          content: '',
          finishReason: 'tool_calls',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-ask-coding',
              name: 'ask_user_question',
              arguments: const {
                'question': 'Which coding direction should we use?',
                'help': 'Pick the implementation direction.',
                'options': [
                  {'label': 'Small patch'},
                  {'label': 'Refactor with tests'},
                ],
              },
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      conversationsNotifier.selectConversation(firstConversationId);
      await Future<void>.delayed(Duration.zero);

      final pending = chatNotifier.state.pendingAskUserQuestion;
      expect(pending, isNotNull);
      expect(pending!.question, 'Which coding direction should we use?');
      expect(chatNotifier.state.isLoading, isTrue);
      expect(chatNotifier.state.messages.map((message) => message.role), [
        MessageRole.user,
        MessageRole.assistant,
      ]);

      chatNotifier.resolveAskUserQuestion(
        id: pending.id,
        answer: AskUserQuestionAnswer(
          question: pending.question,
          selectedOptions: const [
            AskUserQuestionSelection(id: 'Small patch', label: 'Small patch'),
          ],
        ),
      );
      await sendFuture;

      final firstConversation = threadContainer
          .read(conversationsNotifierProvider)
          .conversations
          .firstWhere((conversation) => conversation.id == firstConversationId);
      expect(firstConversation.workspaceMode, WorkspaceMode.coding);
      expect(firstConversation.normalizedProjectId, project.id);
      expect(
        firstConversation.messages.map((message) => message.content).toList(),
        anyElement(contains('Proceeding with the selected option.')),
      );
      expect(chatNotifier.state.isLoading, isFalse);
      expect(
        chatNotifier.state.messages.last.content,
        contains('Proceeding with the selected option.'),
      );
      expect(
        dataSource.toolResultBatches.single.single.name,
        'ask_user_question',
      );
    },
  );
}
