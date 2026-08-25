part of 'chat_notifier_test.dart';

void registerChatNotifierCodingVerificationFeedbackTests() {
  // SEC4.4g requires a fresh, non-cacheable approval before a command reaches
  // the native shell, and the command verification issues has to ask the same
  // question: it runs through Process.start rather than the local-command
  // handler, and a changed `test/**_test.dart` becomes its own target. A Dart
  // test file is arbitrary code -- verified end to end on 2026-08-26 that
  // `dart test` on one whose main() writes a sentinel wrote it, while
  // reporting "No tests were found".
  //
  // Full Access is deliberate here: SEC4.4g asks even at Full Access when the
  // model requests `dart test` itself. It is the app running the same command
  // on the model's behalf that asks nobody.
  test('a test file written this turn runs only once approved', () async {
    final conversationRepository = _FakeConversationRepository();
    final projectRoot = await Directory.systemTemp.createTemp(
      'caverno_verification_executes_written_test_',
    );
    addTearDown(() => projectRoot.delete(recursive: true));
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: projectRoot.path,
      createdAt: DateTime(2026, 8, 26),
      updatedAt: DateTime(2026, 8, 26),
    );
    final canaryPath = '${projectRoot.path}/test/canary_test.dart';
    final writeCanaryTest = ToolCallInfo(
      id: 'tool-1',
      name: 'write_file',
      arguments: const {
        'path': 'test/canary_test.dart',
        'content':
            "import 'dart:io';\n\n"
            "void main() {\n"
            "  File('canary_side_effect.txt').writeAsStringSync('executed');\n"
            "}\n",
      },
    );
    final toolDataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [writeCanaryTest],
      toolLoopResponses: [
        ChatCompletionResult(
          content: 'The task "Add the canary test" is complete.',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content: 'The task "Add the canary test" is complete.',
          finishReason: 'stop',
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {'write_file': ''},
      queuedResults: {
        'write_file': ['{"path":"$canaryPath","bytes_written":64}'],
      },
    );
    // The model's write really lands, because the target has to exist for the
    // runner to accept it as a target.
    await File(canaryPath).create(recursive: true);
    await File(
      canaryPath,
    ).writeAsString(writeCanaryTest.arguments['content']! as String);
    final verificationCommands = <CodingVerificationCommand>[];
    final verificationService = CodingVerificationFeedbackService(
      commandRunner: (command, timeout) async {
        verificationCommands.add(command);
        return const CodingVerificationCommandOutput(exitCode: 0, stdout: '');
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
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

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      final approvals = <PendingLocalCommand>[];
      toolContainer.listen<ChatState>(chatNotifierProvider, (previous, next) {
        final pending = next.pendingLocalCommand;
        if (pending == null ||
            pending.id == previous?.pendingLocalCommand?.id) {
          return;
        }
        approvals.add(pending);
        toolNotifier.resolveLocalCommand(
          id: pending.id,
          approval: const LocalCommandApproval(approved: true),
        );
      });

      await toolNotifier.sendMessage(
        'Add a canary test and tell me when it is done',
        bypassPlanMode: true,
      );

      final asked = approvals.single;
      expect(asked.command, contains('test/canary_test.dart'));
      expect(asked.warningTitle, 'Run a test file written this turn?');
      expect(asked.warningMessage, contains('this turn just wrote'));
      final executed = verificationCommands.single;
      expect(executed.executable, anyOf('flutter', 'dart', 'fvm'));
      expect(executed.arguments, contains('test/canary_test.dart'));
      expect(executed.workingDirectory, projectRoot.path);
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'sendMessage blocks completion claims with coding verification feedback',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_verification_feedback_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final initialWrite = ToolCallInfo(
        id: 'tool-1',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 1;\n',
        },
      );
      final repairWrite = ToolCallInfo(
        id: 'tool-2',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 2;\n',
        },
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [initialWrite],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I will fix the failing test now.',
            toolCalls: [repairWrite],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete. Validation passed.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': [
            '{"path":"$changedPath","bytes_written":18}',
            '{"path":"$changedPath","bytes_written":18}',
          ],
        },
      );
      final verificationFeedback = ToolResultInfo(
        id: 'verify-1',
        name: CodingVerificationFeedbackService.toolName,
        arguments: const {
          'project_root': 'project',
          'changed_paths': ['lib/main.dart'],
          'trigger': 'completionClaim',
        },
        result: jsonEncode({
          'schema': CodingVerificationFeedbackService.schemaName,
          'provider': 'dart_test_runner',
          'trigger': 'completionClaim',
          'validation_status': 'failed',
          'changed_paths': ['lib/main.dart'],
          'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
          'failing_tests': [
            {
              'relative_path': 'test/main_test.dart',
              'test_name': 'value returns two',
              'line': 4,
              'message': 'Expected: <2> Actual: <1>',
            },
          ],
        }),
      );
      final verificationService =
          _FakeCodingVerificationFeedbackService.sequence([
            verificationFeedback,
            null,
          ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
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

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        expect(verificationService.requestedProjectRoots, [
          projectRoot.path,
          projectRoot.path,
        ]);
        expect(verificationService.requestedChangedPaths, [
          [changedPath],
          [changedPath],
        ]);
        expect(verificationService.requestedTriggers, [
          CodingVerificationTrigger.completionClaim,
          CodingVerificationTrigger.completionClaim,
        ]);
        expect(toolService.executedToolNames, ['write_file', 'write_file']);
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches[0].map((result) => result.name),
          ['write_file'],
        );
        expect(
          toolDataSource.toolResultBatches[1].map((result) => result.name),
          [CodingVerificationFeedbackService.toolName],
        );
        expect(
          toolDataSource.toolResultBatches[2].map((result) => result.name),
          ['write_file'],
        );
        final finalContent = toolContainer
            .read(chatNotifierProvider)
            .messages
            .last
            .content;
        expect(finalContent, isNot(contains('is done')));
        expect(finalContent, contains('Validation passed'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage skips coding verification feedback when disabled',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_verification_disabled_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final writeCall = ToolCallInfo(
        id: 'tool-1',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 1;\n',
        },
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [writeCall],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': ['{"path":"$changedPath","bytes_written":18}'],
        },
      );
      final verificationFeedback = ToolResultInfo(
        id: 'verify-disabled',
        name: CodingVerificationFeedbackService.toolName,
        arguments: const {
          'project_root': 'project',
          'changed_paths': ['lib/main.dart'],
          'trigger': 'completionClaim',
        },
        result: jsonEncode({
          'schema': CodingVerificationFeedbackService.schemaName,
          'provider': 'dart_test_runner',
          'trigger': 'completionClaim',
          'validation_status': 'failed',
          'changed_paths': ['lib/main.dart'],
          'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
          'failing_tests': [
            {
              'relative_path': 'test/main_test.dart',
              'test_name': 'value returns two',
              'line': 4,
              'message': 'Expected: <2> Actual: <1>',
            },
          ],
        }),
      );
      final verificationService = _FakeCodingVerificationFeedbackService(
        verificationFeedback,
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoVerificationSettingsNotifier.new,
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

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        expect(verificationService.requestedProjectRoots, isEmpty);
        expect(toolService.executedToolNames, ['write_file']);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        expect(
          toolDataSource.toolResultBatches.single.map((result) => result.name),
          ['write_file'],
        );
        final finalContent = toolContainer
            .read(chatNotifierProvider)
            .messages
            .last
            .content;
        expect(finalContent, contains('is complete'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage skips completion verification in request-only mode',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_verification_request_only_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {
              'path': 'lib/main.dart',
              'content': 'int value() => 1;\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': ['{"path":"$changedPath","bytes_written":18}'],
        },
      );
      final verificationService = _FakeCodingVerificationFeedbackService(
        ToolResultInfo(
          id: 'verify-request-only',
          name: CodingVerificationFeedbackService.toolName,
          arguments: const {
            'project_root': 'project',
            'changed_paths': ['lib/main.dart'],
            'trigger': 'completionClaim',
          },
          result: jsonEncode({
            'schema': CodingVerificationFeedbackService.schemaName,
            'provider': 'dart_test_runner',
            'trigger': 'completionClaim',
            'validation_status': 'failed',
            'changed_paths': ['lib/main.dart'],
            'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
            'failing_tests': const [],
          }),
        ),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledRequestOnlyVerificationSettingsNotifier.new,
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

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        expect(verificationService.requestedProjectRoots, isEmpty);
        expect(toolService.executedToolNames, ['write_file']);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        final finalContent = toolContainer
            .read(chatNotifierProvider)
            .messages
            .last
            .content;
        expect(finalContent, contains('is complete'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage records coding verification snapshots on execution progress',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_verification_progress_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final testPath = '${projectRoot.path}/test/main_test.dart';
      final initialWrite = ToolCallInfo(
        id: 'tool-1',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 1;\n',
        },
      );
      final repairWrite = ToolCallInfo(
        id: 'tool-2',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 2;\n',
        },
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [initialWrite],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I will fix the failing test now.',
            toolCalls: [repairWrite],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete. Validation passed.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': [
            '{"path":"$changedPath","bytes_written":18}',
            '{"path":"$changedPath","bytes_written":18}',
          ],
        },
      );
      final failedSnapshot = _codingVerificationSnapshot(
        projectRoot: projectRoot.path,
        changedPath: 'lib/main.dart',
        validationStatus: ConversationExecutionValidationStatus.failed,
        passedCount: 0,
        failedCount: 1,
        exitCode: 1,
        failures: [
          CodingVerificationFailure(
            testName: 'value returns two',
            absolutePath: testPath,
            line: 4,
            message: 'Expected: <2> Actual: <1>',
          ),
        ],
      );
      final passedSnapshot = _codingVerificationSnapshot(
        projectRoot: projectRoot.path,
        changedPath: 'lib/main.dart',
        validationStatus: ConversationExecutionValidationStatus.passed,
        passedCount: 1,
        failedCount: 0,
        exitCode: 0,
      );
      final verificationFeedback = ToolResultInfo(
        id: 'verify-progress-1',
        name: CodingVerificationFeedbackService.toolName,
        arguments: const {
          'project_root': 'project',
          'changed_paths': ['lib/main.dart'],
          'trigger': 'completionClaim',
        },
        result: jsonEncode({
          'schema': CodingVerificationFeedbackService.schemaName,
          'provider': 'dart_test_runner',
          'trigger': 'completionClaim',
          'validation_status': 'failed',
          'changed_paths': ['lib/main.dart'],
          'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
          'failing_tests': [
            {
              'relative_path': 'test/main_test.dart',
              'test_name': 'value returns two',
              'line': 4,
              'message': 'Expected: <2> Actual: <1>',
            },
          ],
        }),
      );
      final verificationService = _FakeCodingVerificationFeedbackService.runs([
        CodingVerificationFeedbackRun(
          snapshot: failedSnapshot,
          toolResult: verificationFeedback,
        ),
        CodingVerificationFeedbackRun(
          snapshot: passedSnapshot,
          toolResult: null,
        ),
      ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
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

      try {
        final conversationsNotifier = toolContainer.read(
          conversationsNotifierProvider.notifier,
        );
        conversationsNotifier.activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
          createIfMissing: true,
        );
        await conversationsNotifier.updateCurrentPlanArtifact(
          planArtifact: const ConversationPlanArtifact(
            approvedMarkdown:
                '# Plan\n'
                '\n'
                '## Stage\n'
                'implement\n'
                '\n'
                '## Goal\n'
                'Fix a failing Dart test\n'
                '\n'
                '## Tasks\n'
                '\n'
                '1. Fix tests\n'
                '   - Status: inProgress\n'
                '   - Validation: flutter test\n',
          ),
        );
        await conversationsNotifier
            .refreshCurrentWorkflowProjectionFromApprovedPlan();
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        final progress = toolContainer
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.executionProgress
            .single;
        expect(progress, isNotNull);
        expect(progress!.status, ConversationWorkflowTaskStatus.completed);
        expect(
          progress.validationStatus,
          ConversationExecutionValidationStatus.passed,
        );
        expect(
          progress.lastValidationCommand,
          'flutter test --machine test/main_test.dart',
        );
        expect(
          progress.lastValidationSummary,
          contains('Coding verification passed'),
        );
        final validationEvents = progress.events
            .where(
              (event) =>
                  event.type == ConversationExecutionTaskEventType.validated,
            )
            .toList(growable: false);
        expect(validationEvents, hasLength(2));
        expect(
          validationEvents.first.validationStatus,
          ConversationExecutionValidationStatus.failed,
        );
        expect(
          validationEvents.first.validationSummary,
          contains('Actual: <1>'),
        );
        expect(
          validationEvents.last.validationStatus,
          ConversationExecutionValidationStatus.passed,
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage blocks streamed completion claims with verification feedback',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_stream_verification_feedback_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final initialWrite = ToolCallInfo(
        id: 'tool-1',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 1;\n',
        },
      );
      final repairWrite = ToolCallInfo(
        id: 'tool-2',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 2;\n',
        },
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [initialWrite],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'I wrote the requested Dart file.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I will repair the failing test before finishing.',
            toolCalls: [repairWrite],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete. Validation passed.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['The task "Fix tests" is done.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': [
            '{"path":"$changedPath","bytes_written":18}',
            '{"path":"$changedPath","bytes_written":18}',
          ],
        },
      );
      final verificationFeedback = ToolResultInfo(
        id: 'verify-stream-1',
        name: CodingVerificationFeedbackService.toolName,
        arguments: const {
          'project_root': 'project',
          'changed_paths': ['lib/main.dart'],
          'trigger': 'completionClaim',
        },
        result: jsonEncode({
          'schema': CodingVerificationFeedbackService.schemaName,
          'provider': 'dart_test_runner',
          'trigger': 'completionClaim',
          'validation_status': 'failed',
          'changed_paths': ['lib/main.dart'],
          'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
          'failing_tests': [
            {
              'relative_path': 'test/main_test.dart',
              'test_name': 'value returns two',
              'line': 4,
              'message': 'Expected: <2> Actual: <1>',
            },
          ],
        }),
      );
      final verificationService =
          _FakeCodingVerificationFeedbackService.sequence([
            verificationFeedback,
            null,
          ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
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

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        expect(verificationService.requestedProjectRoots, [
          projectRoot.path,
          projectRoot.path,
        ]);
        expect(verificationService.requestedChangedPaths, [
          [changedPath],
          [changedPath],
        ]);
        expect(verificationService.requestedTriggers, [
          CodingVerificationTrigger.completionClaim,
          CodingVerificationTrigger.completionClaim,
        ]);
        expect(toolService.executedToolNames, ['write_file', 'write_file']);
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches[0].map((result) => result.name),
          ['write_file'],
        );
        expect(
          toolDataSource.toolResultBatches[1].map((result) => result.name),
          [CodingVerificationFeedbackService.toolName],
        );
        expect(
          toolDataSource.toolResultBatches[2].map((result) => result.name),
          ['write_file'],
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage stops repeated verification repair for unchanged failures',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_verification_convergence_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      ToolCallInfo writeCall(String id, String content) {
        return ToolCallInfo(
          id: id,
          name: 'write_file',
          arguments: {'path': 'lib/main.dart', 'content': content},
        );
      }

      ToolResultInfo verificationFeedback(String id) {
        return ToolResultInfo(
          id: id,
          name: CodingVerificationFeedbackService.toolName,
          arguments: const {
            'project_root': 'project',
            'changed_paths': ['lib/main.dart'],
            'trigger': 'completionClaim',
          },
          result: jsonEncode({
            'schema': CodingVerificationFeedbackService.schemaName,
            'provider': 'dart_test_runner',
            'trigger': 'completionClaim',
            'validation_status': 'failed',
            'changed_paths': ['lib/main.dart'],
            'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
            'failing_tests': [
              {
                'relative_path': 'test/main_test.dart',
                'test_name': 'value returns two',
                'line': 4,
                'message': 'Expected: <2> Actual: <1>',
              },
            ],
          }),
        );
      }

      final initialWrite = writeCall('tool-1', 'int value() => 1;\n');
      final firstRepairWrite = writeCall('tool-2', 'int value() => 2;\n');
      final secondRepairWrite = writeCall('tool-3', 'int value() => 3;\n');
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [initialWrite],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I will repair the failing test.',
            toolCalls: [firstRepairWrite],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I will try one more repair.',
            toolCalls: [secondRepairWrite],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': [
            '{"path":"$changedPath","bytes_written":18}',
            '{"path":"$changedPath","bytes_written":18}',
            '{"path":"$changedPath","bytes_written":18}',
          ],
        },
      );
      final verificationService =
          _FakeCodingVerificationFeedbackService.sequence([
            verificationFeedback('verify-1'),
            verificationFeedback('verify-2'),
            verificationFeedback('verify-3'),
          ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
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

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        expect(verificationService.requestedProjectRoots, [
          projectRoot.path,
          projectRoot.path,
          projectRoot.path,
        ]);
        expect(toolService.executedToolNames, [
          'write_file',
          'write_file',
          'write_file',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(5));
        expect(
          toolDataSource.toolResultBatches.map(
            (batch) => batch.map((result) => result.name).toList(),
          ),
          [
            ['write_file'],
            [CodingVerificationFeedbackService.toolName],
            ['write_file'],
            [CodingVerificationFeedbackService.toolName],
            ['write_file'],
          ],
        );
        final finalContent = toolContainer
            .read(chatNotifierProvider)
            .messages
            .last
            .content;
        expect(finalContent, contains('not complete'));
        expect(finalContent, contains('same failing tests persisted'));
        expect(finalContent, contains('value returns two'));
      } finally {
        toolContainer.dispose();
      }
    },
  );
}
