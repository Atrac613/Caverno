part of 'chat_notifier_test.dart';

void registerChatNotifierVerificationClaimTests() {
  test(
    'sendMessage annotates a test count claim that exceeds pass evidence',
    () async {
      final projectRoot = await Directory.systemTemp.createTemp(
        'verification_claim_project_',
      );
      addTearDown(() async {
        if (projectRoot.existsSync()) {
          await projectRoot.delete(recursive: true);
        }
      });
      final project = CodingProject(
        id: 'verification-claim',
        name: 'Verification Claim',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 7, 10),
        updatedAt: DateTime(2026, 7, 10),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'write-main',
            name: 'write_file',
            arguments: const {
              'path': 'lib/main.dart',
              'content': 'int value() => 1;\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Implementation complete. Test result: 20/20 passed.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const [
          'Implementation complete. Test result: 20/20 passed.',
        ],
      );
      final evidence = ToolResultInfo(
        id: 'verification-evidence',
        name: CodingVerificationFeedbackService.evidenceToolName,
        arguments: const {
          'changed_paths': ['lib/main.dart'],
          'trigger': 'completionClaim',
        },
        result: jsonEncode({
          'schema': CodingVerificationFeedbackService.evidenceSchemaName,
          'provider': 'dart_test_runner',
          'validation_status': 'passed',
          'counts': {'passed': 1, 'failed': 0, 'skipped': 0},
          'verification': {
            'executable': 'dart',
            'arguments': ['test', 'test'],
            'exit_code': 0,
          },
        }),
      );
      final verificationService = _FakeCodingVerificationFeedbackService.runs([
        CodingVerificationFeedbackRun(
          snapshot: null,
          toolResult: null,
          evidenceToolResult: evidence,
        ),
      ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
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
          mcpToolServiceProvider.overrideWithValue(
            _FakeMcpToolService(
              results: {
                'write_file': jsonEncode({
                  'path': changedPath,
                  'bytes_written': 18,
                }),
              },
            ),
          ),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(null),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            verificationService,
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
          .ensureCurrentConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
          );

      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Implement the requested change and run the tests.');
      await _waitForCondition(
        () => !container.read(chatNotifierProvider).isLoading,
      );

      final answer = container.read(chatNotifierProvider).messages.last.content;
      expect(answer, contains('Test result: 20/20 passed.'));
      expect(answer, contains('Verification claim check:'));
      expect(answer, contains('1 passed'));
      expect(answer, contains('`dart test test`'));
      expect(verificationService.requestedTriggers, [
        CodingVerificationTrigger.completionClaim,
      ]);
    },
  );
}
