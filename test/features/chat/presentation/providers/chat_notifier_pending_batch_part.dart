part of 'chat_notifier_test.dart';

void registerChatNotifierPendingBatchTests() {
  test(
    'pending mutation executes once after bounded recovery is spent',
    () async {
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_pending_batch_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final target = File('${projectRoot.path}/lib/generated.dart');
      final finalCall = ToolCallInfo(
        id: 'final-write',
        name: 'write_file',
        arguments: {
          'path': target.path,
          'content': 'const generated = true;\n',
        },
      );
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [_pendingBatchReadCall(0, projectRoot.path)],
        toolLoopResponses: _pendingBatchResponses(
          projectRoot: projectRoot.path,
          finalCall: finalCall,
        ),
        finalAnswerChunks: const ['The pending file write completed.'],
      );
      final toolService = _PendingBatchMcpToolService(projectRoot);
      final project = _pendingBatchProject(projectRoot.path);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final container = _pendingBatchContainer(
        project: project,
        dataSource: dataSource,
        toolService: toolService,
        appLifecycleService: appLifecycleService,
        settingsOverride: _ToolEnabledNoConfirmSettingsNotifier.new,
      );
      addTearDown(container.dispose);
      _activatePendingBatchProject(container, project);

      final notifier = container.read(chatNotifierProvider.notifier);
      await notifier.sendMessage('Finish the declared file write');

      expect(target.readAsStringSync(), 'const generated = true;\n');
      expect(toolService.executedToolNames.last, 'write_file');
      expect(
        toolService.executedToolNames.where((name) => name == 'write_file'),
        hasLength(1),
      );
      expect(dataSource.toolResultBatches, hasLength(15));
      expect(
        notifier.takeLatestToolResults().any(
          (result) => result.result.contains('tool_call_not_executed'),
        ),
        isFalse,
      );
      final finalPrompt = dataSource.finalAnswerMessages
          .map((message) => message.content)
          .join('\n');
      expect(finalPrompt, contains('[Tool: write_file]'));
      expect(finalPrompt, contains(target.path));
    },
  );

  test('edit mismatch follow-up executes before exhaustion recovery', () async {
    final projectRoot = await Directory.systemTemp.createTemp(
      'caverno_pending_edit_recovery_',
    );
    addTearDown(() => projectRoot.delete(recursive: true));
    final mismatchTarget = File(
      '${projectRoot.path}/lib/src/todo_repository.dart',
    )..createSync(recursive: true);
    mismatchTarget.writeAsStringSync('class TodoRepository {}\n');
    final pendingTarget = File('${projectRoot.path}/lib/config.txt')
      ..writeAsStringSync('mode=old\n');
    const expectedContent = 'mode=correct\n';
    const staleRecoveryContent = 'mode=stale\n';
    final mismatchCall = ToolCallInfo(
      id: 'mismatched-edit',
      name: 'edit_file',
      arguments: {
        'path': mismatchTarget.path,
        'old_text': '  TodoRepository();',
        'new_text':
            '  TodoRepository(); // ignore: avoid_unused_constructor_parameters',
      },
    );
    final pendingCall = ToolCallInfo(
      id: 'correct-pending-edit',
      name: 'edit_file',
      arguments: {
        'path': pendingTarget.path,
        'old_text': 'mode=old\n',
        'new_text': expectedContent,
      },
    );
    final staleRecoveryCall = ToolCallInfo(
      id: 'stale-recovery-edit',
      name: 'edit_file',
      arguments: {
        'path': pendingTarget.path,
        'old_text': 'mode=old\n',
        'new_text': staleRecoveryContent,
      },
    );
    final dataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [_pendingBatchReadCall(0, projectRoot.path)],
      toolLoopResponses: [
        for (var index = 1; index <= 10; index += 1)
          ChatCompletionResult(
            content: 'Continue inspection $index',
            toolCalls: [_pendingBatchReadCall(index, projectRoot.path)],
            finishReason: 'tool_calls',
          ),
        ChatCompletionResult(
          content: 'Apply the first edit attempt.',
          toolCalls: [mismatchCall],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'Apply the corrected edit from the mismatch result.',
          toolCalls: [pendingCall],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'This recovery response must not replace the pending edit.',
          toolCalls: [staleRecoveryCall],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'The stale recovery edit ran unexpectedly.',
          finishReason: 'stop',
        ),
      ],
      finalAnswerChunks: const ['The corrected pending edit completed.'],
    );
    final toolService = _PendingBatchMcpToolService(projectRoot);
    final project = _pendingBatchProject(projectRoot.path);
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final container = _pendingBatchContainer(
      project: project,
      dataSource: dataSource,
      toolService: toolService,
      appLifecycleService: appLifecycleService,
      settingsOverride: _ToolEnabledNoConfirmSettingsNotifier.new,
    );
    addTearDown(container.dispose);
    _activatePendingBatchProject(container, project);

    final notifier = container.read(chatNotifierProvider.notifier);
    await notifier.sendMessage('Apply the corrected pending edit');

    expect(pendingTarget.readAsStringSync(), expectedContent);
    expect(toolService.executedEditNewTexts, [
      pendingCall.arguments['new_text'],
    ]);
    expect(
      toolService.executedEditNewTexts,
      isNot(contains(staleRecoveryCall.arguments['new_text'])),
    );
    expect(
      toolService.executedEditNewTexts.where(
        (content) => content == pendingCall.arguments['new_text'],
      ),
      hasLength(1),
    );
    expect(
      dataSource.toolResultBatches.where(
        (batch) => batch.any((result) => result.id == mismatchCall.id),
      ),
      hasLength(1),
    );
    expect(
      notifier.takeLatestToolResults().any(
        (result) => result.result.contains('tool_call_not_executed'),
      ),
      isFalse,
    );
  });

  test(
    'pending approval-gated command pauses and denial reaches final answer',
    () async {
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_pending_batch_approval_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final finalCall = ToolCallInfo(
        id: 'final-command',
        name: 'local_execute_command',
        arguments: {
          'command': 'rm -rf build',
          'working_directory': projectRoot.path,
        },
      );
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [_pendingBatchReadCall(0, projectRoot.path)],
        toolLoopResponses: _pendingBatchResponses(
          projectRoot: projectRoot.path,
          finalCall: finalCall,
        ),
        finalAnswerChunks: const ['The final command was denied.'],
      );
      final toolService = _PendingBatchMcpToolService(projectRoot);
      final project = _pendingBatchProject(projectRoot.path);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final container = _pendingBatchContainer(
        project: project,
        dataSource: dataSource,
        toolService: toolService,
        appLifecycleService: appLifecycleService,
        settingsOverride: _ToolEnabledSettingsNotifier.new,
      );
      addTearDown(container.dispose);
      _activatePendingBatchProject(container, project);

      final notifier = container.read(chatNotifierProvider.notifier);
      final sendFuture = notifier.sendMessage('Reach the final command safely');
      await _waitForCondition(() => notifier.state.pendingLocalCommand != null);
      expect(
        toolService.executedToolNames,
        isNot(contains('local_execute_command')),
      );
      final pending = notifier.state.pendingLocalCommand!;
      notifier.resolveLocalCommand(
        id: pending.id,
        approval: const LocalCommandApproval(approved: false),
      );
      await sendFuture.timeout(const Duration(seconds: 5));

      expect(
        toolService.executedToolNames,
        isNot(contains('local_execute_command')),
      );
      expect(dataSource.toolResultBatches, hasLength(15));
      final results = notifier.takeLatestToolResults();
      expect(
        results.any(
          (result) =>
              result.result.contains('User denied local command execution'),
        ),
        isTrue,
      );
      expect(
        results.any(
          (result) => result.result.contains('tool_call_not_executed'),
        ),
        isFalse,
      );
    },
  );

  test('pending dispatch failure remains honestly unexecuted', () async {
    final projectRoot = await Directory.systemTemp.createTemp(
      'caverno_pending_batch_failure_',
    );
    addTearDown(() => projectRoot.delete(recursive: true));
    final finalCall = ToolCallInfo(
      id: 'final-failure',
      name: 'fail_final',
      arguments: const {'reason': 'Exercise dispatch failure'},
    );
    final dataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [_pendingBatchReadCall(0, projectRoot.path)],
      toolLoopResponses: _pendingBatchResponses(
        projectRoot: projectRoot.path,
        finalCall: finalCall,
      ),
      finalAnswerChunks: const ['The final dispatch did not execute.'],
    );
    final toolService = _PendingBatchMcpToolService(projectRoot);
    final project = _pendingBatchProject(projectRoot.path);
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final container = _pendingBatchContainer(
      project: project,
      dataSource: dataSource,
      toolService: toolService,
      appLifecycleService: appLifecycleService,
      settingsOverride: _ToolEnabledNoConfirmSettingsNotifier.new,
    );
    addTearDown(container.dispose);
    _activatePendingBatchProject(container, project);

    final notifier = container.read(chatNotifierProvider.notifier);
    await notifier.sendMessage('Exercise the final dispatch failure');

    expect(dataSource.toolResultBatches, hasLength(15));
    final results = notifier.takeLatestToolResults();
    expect(
      results.any(
        (result) =>
            result.name == 'fail_final' &&
            result.result.contains('tool_call_not_executed'),
      ),
      isTrue,
    );
    final finalPrompt = dataSource.finalAnswerMessages
        .map((message) => message.content)
        .join('\n');
    expect(finalPrompt, contains('tool_call_not_executed'));
    expect(finalPrompt, contains('bounded_tool_loop_exhausted'));
  });
}

List<ChatCompletionResult> _pendingBatchResponses({
  required String projectRoot,
  required ToolCallInfo finalCall,
}) {
  return [
    for (var index = 1; index < 12; index += 1)
      ChatCompletionResult(
        content: 'Continue inspection $index',
        toolCalls: [_pendingBatchReadCall(index, projectRoot)],
        finishReason: 'tool_calls',
      ),
    ChatCompletionResult(
      content: 'Start bounded recovery.',
      toolCalls: [_pendingBatchReadCall(12, projectRoot)],
      finishReason: 'tool_calls',
    ),
    ChatCompletionResult(
      content: 'Recovery inspection one.',
      toolCalls: [_pendingBatchReadCall(13, projectRoot)],
      finishReason: 'tool_calls',
    ),
    ChatCompletionResult(
      content: 'Recovery inspection two.',
      toolCalls: [_pendingBatchReadCall(14, projectRoot)],
      finishReason: 'tool_calls',
    ),
    ChatCompletionResult(
      content: 'Execute the final declared action.',
      toolCalls: [finalCall],
      finishReason: 'tool_calls',
    ),
  ];
}

ToolCallInfo _pendingBatchReadCall(int index, String projectRoot) {
  return ToolCallInfo(
    id: 'read-$index',
    name: 'read_file',
    arguments: {'path': '$projectRoot/probe-$index.txt'},
  );
}

CodingProject _pendingBatchProject(String rootPath) {
  return CodingProject(
    id: 'pending-batch-project',
    name: 'Pending batch project',
    rootPath: rootPath,
    createdAt: DateTime(2026, 7, 10),
    updatedAt: DateTime(2026, 7, 10),
  );
}

ProviderContainer _pendingBatchContainer({
  required CodingProject project,
  required _QueuedToolLoopChatDataSource dataSource,
  required _PendingBatchMcpToolService toolService,
  required AppLifecycleService appLifecycleService,
  required SettingsNotifier Function() settingsOverride,
}) {
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(settingsOverride),
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
}

void _activatePendingBatchProject(
  ProviderContainer container,
  CodingProject project,
) {
  container
      .read(conversationsNotifierProvider.notifier)
      .activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
        createIfMissing: true,
      );
}

class _PendingBatchMcpToolService extends McpToolService {
  _PendingBatchMcpToolService(this.root);

  final Directory root;
  final List<String> executedToolNames = [];
  final List<String> executedEditNewTexts = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return const [
      {
        'type': 'function',
        'function': {
          'name': 'read_file',
          'description': 'Read a fixture file.',
          'parameters': {'type': 'object'},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'edit_file',
          'description': 'Edit a fixture file.',
          'parameters': {'type': 'object'},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'fail_final',
          'description': 'Fail a fixture dispatch.',
          'parameters': {'type': 'object'},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'write_file',
          'description': 'Write a fixture file.',
          'parameters': {'type': 'object'},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'local_execute_command',
          'description': 'Execute a fixture command.',
          'parameters': {'type': 'object'},
        },
      },
    ];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    if (name == 'fail_final') {
      throw StateError('Synthetic final dispatch failure');
    }
    if (name == 'read_file') {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({
          'path': arguments['path'],
          'content': 'fixture observation',
        }),
        isSuccess: true,
      );
    }
    if (name == 'edit_file') {
      final newText = arguments['new_text'] as String? ?? '';
      executedEditNewTexts.add(newText);
      final result = await FilesystemTools.editFile(
        path: arguments['path'] as String,
        oldText: arguments['old_text'] as String? ?? '',
        newText: newText,
        replaceAll: arguments['replace_all'] as bool? ?? false,
      );
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }
    if (name == 'write_file') {
      final result = await FilesystemTools.writeFile(
        path: arguments['path'] as String,
        content: arguments['content'] as String? ?? '',
        createParents: true,
      );
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'unexpected': true, 'root': root.path}),
      isSuccess: true,
    );
  }
}
