part of 'chat_notifier_test.dart';

void registerChatNotifierParticipantTurnTests() {
  test('sendMessage streams attributed participant turns in order', () async {
    final dataSource = _ParticipantStreamingChatDataSource(
      chunkBatches: const [
        ['<think>Hidden planning.</think>\nPrimary answer.'],
        ['Reviewer answer.'],
      ],
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final participantContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(participantContainer.dispose);
    final chatNotifier = participantContainer.read(
      chatNotifierProvider.notifier,
    );
    final conversationsNotifier = participantContainer.read(
      conversationsNotifierProvider.notifier,
    );
    final conversation = conversationsNotifier.ensureCurrentConversation()!;
    await conversationsNotifier.updateConversationParticipants(
      conversation.id,
      participants: const [
        ConversationParticipant(
          id: 'primary',
          displayName: 'Primary',
          roleLabel: 'Coordinator',
          roleSystemPrompt: 'Coordinate the discussion.',
          model: 'primary-model',
          colorValue: 0xFF6750A4,
          order: 0,
        ),
        ConversationParticipant(
          id: 'reviewer',
          displayName: 'Reviewer',
          roleLabel: 'Critic',
          roleSystemPrompt: 'Critique the proposal.',
          model: 'review-model',
          colorValue: 0xFF006A6A,
          order: 1,
        ),
      ],
    );

    await chatNotifier.sendMessage('Discuss the proposal');

    final assistantMessages = chatNotifier.state.messages
        .where((message) => message.role == MessageRole.assistant)
        .toList(growable: false);
    expect(assistantMessages, hasLength(2));
    expect(
      assistantMessages[0].content,
      '<think>Hidden planning.</think>\nPrimary answer.',
    );
    expect(assistantMessages[0].participantId, 'primary');
    expect(assistantMessages[0].participantDisplayName, 'Primary');
    expect(assistantMessages[0].participantRoleLabel, 'Coordinator');
    expect(assistantMessages[1].content, 'Reviewer answer.');
    expect(assistantMessages[1].participantId, 'reviewer');
    expect(assistantMessages[1].participantColorValue, 0xFF006A6A);
    expect(dataSource.requestedModels, ['primary-model', 'review-model']);
    expect(dataSource.streamRequests, hasLength(2));
    expect(dataSource.streamRequests.first.first.role, MessageRole.system);
    expect(
      dataSource.streamRequests.first.first.content,
      contains('Participant role instructions for this response:'),
    );
    expect(
      dataSource.streamRequests.first.first.content,
      contains('Coordinate the discussion.'),
    );
    expect(
      dataSource.streamRequests.first.first.content,
      contains('- Name: Primary'),
    );
    expect(
      dataSource.streamRequests.first.first.content,
      contains('- Role: Coordinator'),
    );
    expect(
      dataSource.streamRequests.first.first.content,
      contains('- Reviewer · Critic'),
    );
    expect(
      dataSource.streamRequests.first.first.content,
      contains('Handoff: <participant name or role>'),
    );
    expect(
      dataSource.streamRequests.last.first.content,
      contains('Critique the proposal.'),
    );
    expect(
      dataSource.streamRequests.last.first.content,
      contains('- Name: Reviewer'),
    );
    expect(
      dataSource.streamRequests.last.first.content,
      contains('- Role: Critic'),
    );
    expect(
      dataSource.streamRequests.last.first.content,
      contains('- Primary · Coordinator'),
    );
    expect(
      dataSource.streamRequests.last.first.content,
      contains('yield the floor'),
    );
    expect(
      dataSource.streamRequests.first.where(
        (message) => message.id.startsWith('participant_role_prompt_'),
      ),
      isEmpty,
    );
    expect(
      dataSource.streamRequests.last
          .map((message) => message.content)
          .join('\n'),
      contains('Primary'),
    );
    expect(
      dataSource.streamRequests.last
          .map((message) => message.content)
          .join('\n'),
      isNot(contains('Hidden planning')),
    );
    expect(chatNotifier.state.participantTurnRuntime, isNull);
  });

  test(
    'facilitator without handoff returns the floor before specialists speak',
    () async {
      final dataSource = _ParticipantStreamingChatDataSource(
        chunkBatches: const [
          ['This can be answered without specialist input.'],
          ['Unexpected engineer answer.'],
        ],
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final participantContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(participantContainer.dispose);
      final chatNotifier = participantContainer.read(
        chatNotifierProvider.notifier,
      );
      final conversationsNotifier = participantContainer.read(
        conversationsNotifierProvider.notifier,
      );
      final conversation = conversationsNotifier.ensureCurrentConversation()!;
      await conversationsNotifier.updateConversationParticipants(
        conversation.id,
        participants: const [
          ConversationParticipant(
            id: 'primary',
            displayName: 'Primary',
            roleLabel: 'Facilitator',
            roleSystemPrompt: 'Facilitate the discussion.',
            model: 'primary-model',
            colorValue: 0xFF6750A4,
            order: 0,
          ),
          ConversationParticipant(
            id: 'engineer',
            displayName: 'Engineer',
            roleLabel: 'Senior Engineer',
            roleSystemPrompt: 'Cover implementation details.',
            model: 'engineer-model',
            colorValue: 0xFF006A6A,
            order: 1,
          ),
        ],
      );

      await chatNotifier.sendMessage('Discuss the proposal');

      final assistantMessages = chatNotifier.state.messages
          .where((message) => message.role == MessageRole.assistant)
          .toList(growable: false);
      expect(assistantMessages.map((message) => message.participantId), [
        'primary',
      ]);
      expect(
        assistantMessages.single.content,
        'This can be answered without specialist input.',
      );
      expect(dataSource.requestedModels, ['primary-model']);
      expect(dataSource.streamRequests, hasLength(1));
      expect(
        dataSource.streamRequests.single.first.content,
        contains('the floor returns to the user'),
      );
    },
  );
}
