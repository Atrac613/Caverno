part of 'chat_notifier_test.dart';

void registerChatNotifierApprovalCacheTests() {
  test('cached command approval re-executes and audits fresh results', () async {
    final projectRoot = await Directory.systemTemp.createTemp(
      'caverno_approval_cache_',
    );
    final auditRoot = await Directory.systemTemp.createTemp(
      'caverno_approval_cache_audit_',
    );
    addTearDown(() async {
      await projectRoot.delete(recursive: true);
      await auditRoot.delete(recursive: true);
    });
    final sourceFile = File('${projectRoot.path}/lib/main.dart');
    await sourceFile.parent.create(recursive: true);
    await sourceFile.writeAsString('void main() { print("warning"); }\n');

    const command = 'dart analyze';
    final firstCommand = ToolCallInfo(
      id: 'analyze-1',
      name: 'local_execute_command',
      arguments: {
        'command': command,
        'working_directory': projectRoot.path,
        'reason': 'Find diagnostics',
      },
    );
    final repeatedCommand = ToolCallInfo(
      id: 'analyze-2',
      name: 'local_execute_command',
      arguments: {
        'command': command,
        'working_directory': projectRoot.path,
        'reason': 'Verify the fix',
      },
    );
    final dataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [firstCommand],
      toolLoopResponses: [
        ChatCompletionResult(
          content: '',
          toolCalls: [
            ToolCallInfo(
              id: 'edit-1',
              name: 'edit_file',
              arguments: {
                'path': sourceFile.path,
                'old_text': 'print("warning")',
                'new_text': 'print("clean")',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: '',
          toolCalls: [repeatedCommand],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(content: 'Verified.', finishReason: 'stop'),
      ],
      finalAnswerChunks: const ['Verified with fresh analyzer output.'],
    );
    final toolService = _FakeMcpToolService(
      results: {
        'edit_file': jsonEncode({'path': sourceFile.path, 'replacements': 1}),
      },
      queuedResults: const {
        'local_execute_command': [
          '{"command":"dart analyze","exit_code":2,"stdout":"warning"}',
          '{"command":"dart analyze","exit_code":0,"stdout":"No issues found"}',
        ],
      },
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: projectRoot.path,
      createdAt: DateTime(2026, 7, 10),
      updatedAt: DateTime(2026, 7, 10),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          _FakeConversationRepository(),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
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
        toolApprovalAuditLogProvider.overrideWithValue(
          ToolApprovalAuditLog(rootDirectoryProvider: () async => auditRoot),
        ),
      ],
    );
    addTearDown(threadContainer.dispose);
    threadContainer
        .read(conversationsNotifierProvider.notifier)
        .activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
          createIfMissing: true,
        );
    final notifier = threadContainer.read(chatNotifierProvider.notifier);

    final sendFuture = notifier.sendMessage(
      'Fix the warning and verify it',
      bypassPlanMode: true,
    );
    await _waitForCondition(() => notifier.state.pendingLocalCommand != null);
    final localApproval = notifier.state.pendingLocalCommand!;
    notifier.resolveLocalCommand(
      id: localApproval.id,
      approval: const LocalCommandApproval(approved: true),
    );
    await _waitForCondition(() => notifier.state.pendingFileOperation != null);
    final fileApproval = notifier.state.pendingFileOperation!;
    notifier.resolveFileOperation(id: fileApproval.id, approved: true);
    await sendFuture.timeout(const Duration(seconds: 5));

    expect(notifier.state.pendingLocalCommand, isNull);
    expect(toolService.executedToolNames, [
      'local_execute_command',
      'edit_file',
      'local_execute_command',
    ]);
    final commandResults = dataSource.toolResultBatches
        .expand((batch) => batch)
        .where((result) => result.name == 'local_execute_command')
        .toList(growable: false);
    expect(commandResults, hasLength(2));
    expect(commandResults.last.result, contains('No issues found'));

    final auditEntries = Directory('${auditRoot.path}/approval_audit')
        .listSync()
        .whereType<File>()
        .expand((file) => file.readAsLinesSync())
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList(growable: false);
    expect(
      auditEntries,
      contains(
        allOf(
          containsPair('tool', 'local_execute_command'),
          containsPair('decisionSource', 'cached_approval'),
        ),
      ),
    );
  });

  test('file edit aborts when the target changes during approval', () async {
    final projectRoot = await Directory.systemTemp.createTemp(
      'caverno_file_approval_state_',
    );
    addTearDown(() async {
      await projectRoot.delete(recursive: true);
    });
    final sourceFile = File('${projectRoot.path}/pubspec.yaml');
    await sourceFile.writeAsString('name: todo\n');
    final editCall = ToolCallInfo(
      id: 'edit-package-name',
      name: 'edit_file',
      arguments: {
        'path': sourceFile.path,
        'old_text': 'name: todo',
        'new_text': 'name: todo_app',
        'reason': 'Align the package name.',
      },
    );
    final dataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [editCall],
      toolLoopResponses: [
        ChatCompletionResult(
          content: 'The edit could not be applied safely.',
          finishReason: 'stop',
        ),
      ],
      finalAnswerChunks: const ['The target changed before the edit ran.'],
    );
    final toolService = _FakeMcpToolService(
      results: const {'edit_file': '{"path":"pubspec.yaml","replacements":1}'},
    );
    final project = CodingProject(
      id: 'file-approval-state',
      name: 'File Approval State',
      rootPath: projectRoot.path,
      createdAt: DateTime(2026, 7, 10),
      updatedAt: DateTime(2026, 7, 10),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          _FakeConversationRepository(),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
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
    addTearDown(container.dispose);
    container
        .read(conversationsNotifierProvider.notifier)
        .activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
          createIfMissing: true,
        );
    final notifier = container.read(chatNotifierProvider.notifier);

    final sendFuture = notifier.sendMessage(
      'Rename the package safely.',
      bypassPlanMode: true,
    );
    await _waitForCondition(() => notifier.state.pendingFileOperation != null);
    await sourceFile.writeAsString('name: externally_changed\n');
    final approval = notifier.state.pendingFileOperation!;
    notifier.resolveFileOperation(id: approval.id, approved: true);
    await sendFuture.timeout(const Duration(seconds: 5));

    expect(toolService.executedToolNames, isEmpty);
    expect(dataSource.toolResultBatches, hasLength(1));
    expect(
      dataSource.toolResultBatches.single.single.result,
      contains('file_changed_since_approval'),
    );
    expect(await sourceFile.readAsString(), 'name: externally_changed\n');
  });

  test('delete_file rejects a path outside the coding project', () async {
    final projectRoot = await Directory.systemTemp.createTemp(
      'delete_file_project_',
    );
    final outsideRoot = await Directory.systemTemp.createTemp(
      'delete_file_outside_',
    );
    addTearDown(() async {
      await projectRoot.delete(recursive: true);
      await outsideRoot.delete(recursive: true);
    });
    final outsideFile = File('${outsideRoot.path}/keep.txt')
      ..writeAsStringSync('keep\n');
    final dataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'delete-outside',
          name: 'delete_file',
          arguments: {'path': outsideFile.path},
        ),
      ],
      toolLoopResponses: [
        ChatCompletionResult(content: 'Blocked.', finishReason: 'stop'),
      ],
      finalAnswerChunks: const ['The deletion was blocked.'],
    );
    final toolService = _FakeMcpToolService(
      results: const {'delete_file': '{"deleted":true}'},
    );
    final project = CodingProject(
      id: 'delete-file-project',
      name: 'Delete File Project',
      rootPath: projectRoot.path,
      createdAt: DateTime(2026, 7, 10),
      updatedAt: DateTime(2026, 7, 10),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          _FakeConversationRepository(),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
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
    addTearDown(container.dispose);
    container
        .read(conversationsNotifierProvider.notifier)
        .activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
          createIfMissing: true,
        );

    await container
        .read(chatNotifierProvider.notifier)
        .sendMessage('Delete the obsolete file.', bypassPlanMode: true);

    expect(toolService.executedToolNames, isEmpty);
    expect(outsideFile.existsSync(), isTrue);
    expect(
      dataSource.toolResultBatches.single.single.result,
      contains('delete_path_outside_project'),
    );
  });

  test(
    'cached command denial replays without prompting or execution',
    () async {
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 7, 10),
        updatedAt: DateTime(2026, 7, 10),
      );
      const arguments = {
        'command': 'rm -rf build',
        'working_directory': '/tmp/project',
      };
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'command-1',
            name: 'local_execute_command',
            arguments: arguments,
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'command-2',
                name: 'local_execute_command',
                arguments: arguments,
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(content: 'Denied.', finishReason: 'stop'),
        ],
        finalAnswerChunks: const ['The command was denied.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {'local_execute_command': 'unexpected execution'},
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
      addTearDown(threadContainer.dispose);
      threadContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final notifier = threadContainer.read(chatNotifierProvider.notifier);

      final sendFuture = notifier.sendMessage(
        'Run the cleanup command',
        bypassPlanMode: true,
      );
      await _waitForCondition(() => notifier.state.pendingLocalCommand != null);
      final pending = notifier.state.pendingLocalCommand!;
      notifier.resolveLocalCommand(
        id: pending.id,
        approval: const LocalCommandApproval(approved: false),
      );
      await sendFuture.timeout(const Duration(seconds: 5));

      expect(notifier.state.pendingLocalCommand, isNull);
      expect(toolService.executedToolNames, isEmpty);
      final denialResults = notifier
          .takeLatestToolResults()
          .where((result) => result.name == 'local_execute_command')
          .map((result) => result.result)
          .where((result) => !result.contains('tool_call_not_executed'))
          .toList(growable: false);
      expect(denialResults, hasLength(2));
      expect(denialResults.toSet(), hasLength(1));
      expect(
        denialResults.first,
        contains('User denied local command execution'),
      );
    },
  );

  test(
    'computer-use caches denials but requires fresh approval after grants',
    () async {
      for (final firstApproved in [true, false]) {
        MacosComputerUseAuditLog.instance.clear();
        final dataSource = _ToolBatchChatDataSource(
          initialToolCalls: [
            ToolCallInfo(
              id: 'click-1',
              name: 'computer_click',
              arguments: {
                'x': 40,
                'y': 60,
                'reason': 'Select the target control.',
              },
            ),
            ToolCallInfo(
              id: 'click-2',
              name: 'computer_click',
              arguments: {
                'x': 40,
                'y': 60,
                'reason': 'Continue with the selected control.',
              },
            ),
          ],
        );
        final toolService = _FakeMcpToolService(
          results: const {
            'computer_click':
                '{"ok":true,"selectedIpcTransport":"xpc_service","code":"ok"}',
            'computer_vision_observe':
                '{"ok":true,"schemaName":"macos_computer_use_vision_observation","selectedIpcTransport":"xpc_service","code":"ok"}',
          },
        );
        final appLifecycleService = _MockAppLifecycleService();
        when(() => appLifecycleService.isInBackground).thenReturn(false);
        final container = ProviderContainer(
          overrides: [
            settingsNotifierProvider.overrideWith(
              _ToolEnabledSettingsNotifier.new,
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
          final sendFuture = notifier.sendMessage('Click the control twice.');

          await _waitForCondition(
            () => notifier.state.pendingComputerUseAction != null,
          );
          final firstPending = notifier.state.pendingComputerUseAction!;
          notifier.resolveComputerUseAction(
            id: firstPending.id,
            approved: firstApproved,
            armed: firstApproved,
          );

          if (firstApproved) {
            await _waitForCondition(
              () =>
                  notifier.state.pendingComputerUseAction != null &&
                  notifier.state.pendingComputerUseAction!.id !=
                      firstPending.id,
            );
            final secondPending = notifier.state.pendingComputerUseAction!;
            expect(
              toolService.executedToolNames.where(
                (name) => name == 'computer_click',
              ),
              hasLength(1),
            );
            notifier.resolveComputerUseAction(
              id: secondPending.id,
              approved: false,
            );
          }

          await sendFuture.timeout(const Duration(seconds: 5));

          expect(notifier.state.pendingComputerUseAction, isNull);
          expect(
            toolService.executedToolNames.where(
              (name) => name == 'computer_click',
            ),
            hasLength(firstApproved ? 1 : 0),
          );
          if (firstApproved) {
            expect(dataSource.toolResultBatches.single, hasLength(2));
          } else {
            final actionResults = notifier
                .takeLatestToolResults()
                .where(
                  (result) =>
                      result.name == 'computer_click' &&
                      !result.result.contains('tool_call_not_executed'),
                )
                .toList(growable: false);
            expect(actionResults.length, greaterThanOrEqualTo(2));
            expect(
              actionResults.map((result) => result.result).toSet(),
              hasLength(1),
            );
          }
        } finally {
          container.dispose();
          MacosComputerUseAuditLog.instance.clear();
        }
      }
    },
  );
}
