part of 'chat_notifier_test.dart';

// Planning contract tests live in a part file so
// chat_notifier_test.dart stays under its F1 size ratchet.
void registerChatNotifierPlanningContractTests() {
  test(
    'initial planning proposal receives a sourced short-prompt contract',
    () async {
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_planning_contract_',
      );
      await File('${projectRoot.path}/todo_app.md').writeAsString('''
# Requirements

- Persist tasks between CLI invocations.

# Acceptance Criteria

- `dart test` passes.
''');
      final project = CodingProject(
        id: 'project-1',
        name: 'todo-app',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 7, 14),
        updatedAt: DateTime(2026, 7, 14),
      );
      final conversationRepository = _FakeConversationRepository();
      final proposalDataSource = _QueuedProposalDataSource([
        ChatCompletionResult(
          content:
              '{"kind":"proposal","workflowStage":"plan","goal":"Build the TODO MVP","constraints":["Persist tasks between CLI invocations."],"acceptanceCriteria":["dart test passes."],"openQuestions":[]}',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content:
              '{"tasks":[{"title":"Build the TODO MVP","targetFiles":["bin/todo_app.dart"],"validationCommand":"dart test","notes":"Follow todo_app.md."}]}',
          finishReason: 'stop',
        ),
      ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final planContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final conversations = planContainer.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
          createIfMissing: true,
        );
        await planContainer
            .read(chatNotifierProvider.notifier)
            .sendMessage('Build the MVP described in todo_app.md');

        final systemPrompt = proposalDataSource.requests.first
            .firstWhere((message) => message.role == MessageRole.system)
            .content;
        expect(systemPrompt, contains('<execution_snapshot>'));
        expect(
          systemPrompt,
          contains('Persist tasks between CLI invocations.'),
        );
        expect(
          systemPrompt,
          contains('Acceptance criteria: `dart test` passes.'),
        );
        expect(systemPrompt, contains('Contract sources: 2'));
        expect(systemPrompt, contains('Workflow stage: plan'));
        expect(systemPrompt, contains('Required next action: plan'));
        expect(systemPrompt, contains('Active task status: pending'));
      } finally {
        planContainer.dispose();
        await projectRoot.delete(recursive: true);
      }
    },
  );
}
