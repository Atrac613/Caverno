part of 'chat_notifier_test.dart';

void registerChatNotifierUnwrittenFileClaimTests() {
  test(
    'sendMessage annotates an unbacked file claim and logs the transform',
    () async {
      final projectRoot = await Directory.systemTemp.createTemp(
        'unwritten_file_claim_project_',
      );
      final sessionLogRoot = await Directory.systemTemp.createTemp(
        'unwritten_file_claim_logs_',
      );
      addTearDown(() async {
        if (projectRoot.existsSync()) {
          await projectRoot.delete(recursive: true);
        }
        if (sessionLogRoot.existsSync()) {
          await sessionLogRoot.delete(recursive: true);
        }
      });
      final project = CodingProject(
        id: 'unwritten-file-claim',
        name: 'Unwritten File Claim',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 7, 10),
        updatedAt: DateTime(2026, 7, 10),
      );
      final writtenPath = '${projectRoot.path}/lib/a.dart';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'write-a',
            name: 'write_file',
            arguments: const {
              'path': 'lib/a.dart',
              'content': 'void main() {}',
            },
          ),
        ],
        finalAnswerChunks: const [
          '- `lib/a.dart` was created.\n'
              '- `lib/b.dart` was created.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'write_file': jsonEncode({'path': writtenPath, 'bytes_written': 14}),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final sessionLogStore = LlmSessionLogStore(
        rootDirectoryProvider: () async => sessionLogRoot,
      );
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _UnwrittenClaimLoggingSettingsNotifier.new,
          ),
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
          llmSessionLogStoreProvider.overrideWithValue(sessionLogStore),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final conversation = conversations.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
      )!;
      final notifier = container.read(chatNotifierProvider.notifier);

      await notifier.sendMessage('Create the two Dart files.');
      await _waitForCondition(
        () => !container.read(chatNotifierProvider).isLoading,
      );

      final answer = container.read(chatNotifierProvider).messages.last.content;
      expect(answer, contains('`lib/a.dart` was created.'));
      expect(answer, contains('`lib/b.dart` was created.'));
      expect(answer, contains('`lib/b.dart`'));
      expect(answer, contains('does not exist'));
      expect(
        answer.substring(answer.indexOf('Deliverable claim check:')),
        isNot(contains('lib/a.dart')),
      );

      final sessionLogFile = await sessionLogStore.fileForContext(
        LlmSessionLogContext(
          workspaceMode: WorkspaceMode.coding,
          sessionId: conversation.id,
          conversationId: conversation.id,
        ),
        create: false,
      );
      final entries = (await sessionLogFile.readAsLines())
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList(growable: false);
      final turnExit = entries.lastWhere(
        (entry) => entry['operation'] == 'turn_exit',
      );
      expect(
        (turnExit['turnExit'] as Map<String, dynamic>)['transforms'],
        contains('unwritten_file_claim_notice'),
      );
    },
  );

  test(
    'sendMessage does not apply the guard outside coding workspace',
    () async {
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
      initialCompletionContent: '`lib/b.dart` was created.',
      initialFinishReason: 'stop',
      initialStreamChunks: const ['`lib/b.dart` was created.'],
      finalAnswerChunks: const ['`lib/b.dart` was created.'],
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
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(
            _FakeMcpToolService(results: const {}),
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(conversationsNotifierProvider.notifier)
        .ensureCurrentConversation(workspaceMode: WorkspaceMode.chat);

      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Describe the result.');
      await _waitForCondition(
        () => !container.read(chatNotifierProvider).isLoading,
      );

      final answer = container.read(chatNotifierProvider).messages.last.content;
      expect(answer, '`lib/b.dart` was created.');
    },
  );
}

class _UnwrittenClaimLoggingSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      enableLlmSessionLogs: true,
      codingApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      confirmGitWrites: false,
    );
  }
}
