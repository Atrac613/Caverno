part of 'chat_notifier_test.dart';

// Terminal-success provider tests live in a part file so
// chat_notifier_test.dart stays under its F1 size ratchet.
void registerChatNotifierTerminalSuccessTests() {
  test(
    'sendMessage records explicit terminal success as the goal summary',
    () async {
      const terminalMessage =
          'Verification succeeded. The requested work is complete.';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'read-before-verification',
            name: 'read_file',
            arguments: const {'path': '/tmp/project/lib/main.dart'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                'Let me inspect the project before finishing. Next I will '
                'implement the remaining changes.',
            toolCalls: [
              ToolCallInfo(
                id: 'verify-terminal-success',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'dart run tool/verify.dart',
                  'working_directory': '/tmp/project',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Recovery should not run.',
            toolCalls: [
              ToolCallInfo(
                id: 'unexpected-post-success-write',
                name: 'write_file',
                arguments: const {
                  'path': '/tmp/project/lib/main.dart',
                  'content': 'void main() {}',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'read_file': jsonEncode({
            'path': '/tmp/project/lib/main.dart',
            'content': 'void main() {}',
          }),
          'local_execute_command': jsonEncode({
            'command': 'dart run tool/verify.dart',
            'exit_code': 0,
            'terminal_success': true,
            'terminal_message': terminalMessage,
          }),
          'write_file': jsonEncode({
            'path': '/tmp/project/lib/main.dart',
            'bytes_written': 14,
          }),
        },
      );
      final conversationsNotifier = _TerminalSuccessGoalConversationsNotifier();
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            () => conversationsNotifier,
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
        final conversations = toolContainer.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.ensureCurrentConversation();
        await conversations.saveCurrentGoal(
          objective: 'Implement and verify the fixture',
          enabled: true,
          autoContinue: true,
          status: ConversationGoalStatus.active,
        );

        await toolContainer
            .read(chatNotifierProvider.notifier)
            .sendMessage('Implement the fixture');

        final finalContent = toolContainer
            .read(chatNotifierProvider)
            .messages
            .last
            .content;
        expect(
          finalContent,
          contains('Next I will implement the remaining changes.'),
        );
        expect(finalContent, contains(terminalMessage));
        expect(toolService.executedToolNames, [
          'read_file',
          'local_execute_command',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        expect(
          conversationsNotifier.recordedAssistantResponse,
          terminalMessage,
        );
        expect(
          conversationsNotifier
              .state
              .currentConversation
              ?.goal
              ?.completionSummary,
          terminalMessage,
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );
}
