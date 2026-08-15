part of 'chat_notifier_test.dart';

// Recovery of tool calls a model prints as a raw object instead of emitting
// through the tool-call channel (grok-4.6 does this for some requests).
// Extracted from chat_notifier_test.dart to keep that file under its F1 size
// ratchet (docs/large_file_refactor_plan.md); these tests share the library's
// private test doubles via the part-of relationship.
void registerChatNotifierPrintedToolCallTests() {
  test('a printed call object runs when the turn advertised that tool', () async {
    // grok-4.6 answers some tool requests by printing the call in a fenced
    // block instead of emitting it. The non-streaming path recovers this shape
    // through the response normalizer; without the same recovery here the chat
    // UI would show the user a JSON blob where an action belongs, and the same
    // model would behave differently depending on whether it streamed.
    const printedCall =
        'Checking clients.\n'
        '```json\n'
        '{"name":"arp","arguments":{"ip_version":"all"}}\n'
        '```';
    final dataSource = _ToolBatchChatDataSource(
      initialToolCalls: const [],
      initialFinishReason: 'stop',
      initialStreamChunks: const [printedCall],
      initialCompletionContent: printedCall,
      finalAnswerChunks: const ['Client analysis complete.'],
    );
    final toolService = _FakeMcpToolService(
      results: const {'arp': '{"entries":15}'},
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
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

    try {
      final notifier = container.read(chatNotifierProvider.notifier);

      await notifier.sendMessage('Deep dive clients');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(toolService.executedToolNames, contains('arp'));
      expect(toolService.executedToolArguments.first['ip_version'], 'all');
    } finally {
      container.dispose();
    }
  });

  test('a printed call object for an unoffered tool stays text', () async {
    // The advertised-name check is the whole safety story for a shape that
    // carries no marker of intent, unlike a <tool_call> tag.
    const printedCall =
        'Here is what a delete would look like:\n'
        '```json\n'
        '{"name":"delete_file","arguments":{"path":"lib/main.dart"}}\n'
        '```';
    final dataSource = _ToolBatchChatDataSource(
      initialToolCalls: const [],
      initialFinishReason: 'stop',
      initialStreamChunks: const [printedCall],
      initialCompletionContent: printedCall,
      finalAnswerChunks: const ['Nothing was deleted.'],
    );
    final toolService = _FakeMcpToolService(
      results: const {'arp': '{"entries":15}'},
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
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

    try {
      final notifier = container.read(chatNotifierProvider.notifier);

      await notifier.sendMessage('Show me a delete call');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(toolService.executedToolNames, isEmpty);
    } finally {
      container.dispose();
    }
  });
}
