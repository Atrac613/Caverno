// Tests for auto-review denial escalation (②): a denied, user-directed coding
// command escalates to a manual approval prompt instead of dead-ending the
// turn. Lives in a part file to keep chat_notifier_test.dart under its F1
// line-count ratchet (test/quality/file_size_ratchet_test.dart).
part of 'chat_notifier_test.dart';

void registerChatNotifierAutoReviewEscalationTests() {
  test('auto-review denial escalates a user-directed command to manual '
      'approval', () async {
    final projectRoot = await Directory.systemTemp.createTemp(
      'review-escalation-',
    );
    addTearDown(() => projectRoot.delete(recursive: true));
    final conversationRepository = _FakeConversationRepository();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'local_execute_command',
          arguments: {
            'command': 'rm -rf build',
            'working_directory': projectRoot.path,
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
      rootPath: projectRoot.path,
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
      await _waitForCondition(
        () => toolNotifier.state.pendingLocalCommand != null,
      );

      // Containment restores auto-review; its denial still asks the user.
      final pending = toolNotifier.state.pendingLocalCommand;
      expect(pending, isNotNull);
      expect(pending!.command, 'rm -rf build');
      if (_supportsForegroundCommandContainment()) {
        expect(pending.warningTitle, 'Auto-review flagged this action');
        expect(
          pending.warningMessage,
          contains('The deletion is not clearly authorized.'),
        );
        expect(
          pending.warningMessage,
          contains('permanently remove files or directories'),
        );
        expect(pending.canRememberAllow, isTrue);
        expect(toolDataSource.autoReviewRequestMessages, hasLength(1));
      } else {
        expect(pending.warningTitle, 'Recursive file deletion');
        expect(
          pending.warningMessage,
          startsWith('It runs through the native'),
        );
        expect(pending.canRememberAllow, isFalse);
        expect(toolDataSource.autoReviewRequestMessages, isEmpty);
      }
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
