// Tests for auto-review denial escalation (②): a denied, user-directed coding
// command escalates to a manual approval prompt instead of dead-ending the
// turn. Lives in a part file to keep chat_notifier_test.dart under its F1
// line-count ratchet (test/quality/file_size_ratchet_test.dart).
part of 'chat_notifier_test.dart';

void registerChatNotifierAutoReviewEscalationTests() {
  test('auto-review denial escalates a user-directed command to manual '
      'approval', () async {
    final conversationRepository = _FakeConversationRepository();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'local_execute_command',
          arguments: const {
            'command': 'rm -rf build',
            'working_directory': '/tmp/project',
          },
        ),
      ],
      autoReviewResponses: [
        ChatCompletionResult(
          content:
              '{"outcome":"deny","riskLevel":"high","userAuthorization":"unknown","rationale":"The deletion is not clearly authorized."}',
          finishReason: 'stop',
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {'local_execute_command': 'unexpected command'},
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
          _ToolEnabledAutoReviewSettingsNotifier.new,
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

      final sendFuture = toolNotifier.sendMessage(
        'Clean build outputs',
        bypassPlanMode: true,
      );
      for (
        var i = 0;
        i < 20 && toolNotifier.state.pendingLocalCommand == null;
        i += 1
      ) {
        await Future<void>.delayed(Duration.zero);
      }

      // Auto-review denied, but the command is user-directed and untainted, so
      // the denial escalates to a manual approval prompt instead of dead-ending
      // the turn — and the reviewer's rationale is surfaced to the user.
      final pending = toolNotifier.state.pendingLocalCommand;
      expect(pending, isNotNull);
      expect(pending!.command, 'rm -rf build');
      expect(pending.warningTitle, 'Auto-review flagged this action');
      expect(pending.warningMessage, contains('not clearly authorized'));
      expect(toolService.executedToolNames, isEmpty);

      // Declining keeps the command unexecuted.
      toolNotifier.resolveLocalCommand(
        id: pending.id,
        approval: const LocalCommandApproval(approved: false),
      );
      await sendFuture;
      expect(toolService.executedToolNames, isEmpty);
    } finally {
      toolContainer.dispose();
    }
  });
}
