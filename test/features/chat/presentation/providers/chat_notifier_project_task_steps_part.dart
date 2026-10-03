part of 'chat_notifier_test.dart';

void registerChatNotifierProjectTaskStepTests() {
  for (final scenario in [
    'failed then passed',
    'failed then prose',
    'failed then repeated read',
    'missing marker only',
    'read-only done',
    'premature goal completion',
    'blocked verification',
    'failed then passed detached',
    'failed then prose memory failure',
    'optional environment lookup',
    'optional runtime lookup',
    'optional pytest metadata lookup',
    'optional fallback environment lookup',
    'pytest reporting changed',
  ]) {
    test('project subtask finalization and memory: $scenario', () async {
      final root = await Directory.systemTemp.createTemp('caverno_subtask_');
      addTearDown(() => root.delete(recursive: true));
      final project = _pendingBatchProject(root.path);
      final mode = scenario
          .replaceAll(' detached', '')
          .replaceAll(' memory failure', '');
      final detached = scenario.endsWith(' detached');
      final fails = mode.startsWith('failed') || mode == 'blocked verification';
      final readOnly = mode == 'read-only done';
      final reportingChanged = mode == 'pytest reporting changed';
      final command = reportingChanged
          ? 'cd ${root.path} && python3 -m pytest test_fixture.py -v 2>&1 | tail -20'
          : 'cd ${root.path} && python3 -c "assert 1 == 1"';
      final gate = detached ? Completer<void>() : null;
      final source = _ProjectTaskStepDataSource(
        scenario: mode,
        command: command,
        firstResponseGate: gate?.future,
        extractionFails: scenario.endsWith(' memory failure'),
        initialToolCalls: [
          if (readOnly)
            ToolCallInfo(
              id: 'inspect',
              name: 'read_file',
              arguments: {'path': '${root.path}/policy.md'},
            ),
          if (!readOnly) ...[
            ToolCallInfo(
              id: 'edit',
              name: 'write_file',
              arguments: {
                'path': '${root.path}/policy.md',
                'content': 'Fixture policy.\n',
              },
            ),
            ToolCallInfo(
              id: 'verify',
              name: 'local_execute_command',
              arguments: {'command': command},
            ),
          ],
          if (reportingChanged)
            ToolCallInfo(
              id: 'project-runner',
              name: 'local_execute_command',
              arguments: {
                'command':
                    'cd ${root.path} && .venv/bin/python -m pytest test_fixture.py -q 2>&1 | tail -15',
              },
            ),
          if (mode.startsWith('optional '))
            ToolCallInfo(
              id: 'environment',
              name: 'local_execute_command',
              arguments: {
                'command': mode == 'optional runtime lookup'
                    ? 'cd ${root.path} && ls -a && which -a python3 python3.12 python3.13'
                    : mode == 'optional fallback environment lookup'
                    ? 'cd ${root.path} && ls -la .venv/bin/python* 2>/dev/null || ls -la venv/bin/python* 2>/dev/null || which python3 && python3 -c "import pytest; print(pytest.__version__)" 2>&1'
                    : mode == 'optional pytest metadata lookup'
                    ? 'ls -d ${root.path}/.venv ${root.path}/venv 2>/dev/null; which pytest 2>/dev/null; python3 -c "import pytest; print(pytest.__file__)" 2>&1'
                    : 'cd ${root.path} && python3 -m pip show pytest 2>/dev/null | head -3',
              },
            ),
          if (mode == 'premature goal completion')
            ToolCallInfo(
              id: 'early-completion',
              name: 'update_goal',
              arguments: const {'completed': true},
            ),
        ],
        finalAnswerChunks: [
          fails || mode == 'missing marker only'
              ? 'Let me run a more targeted check.'
              : 'Subtask complete.\nPROJECT_TASK_SUBTASK_DONE',
        ],
      );
      final memory = _TrackingSessionMemoryService();
      final service = _ProjectTaskStepToolService(
        root,
        fails: fails,
        rerunPasses: mode == 'failed then passed',
      );
      final lifecycle = _MockAppLifecycleService();
      when(() => lifecycle.isInBackground).thenReturn(false);
      final container = _pendingBatchContainer(
        project: project,
        dataSource: source,
        toolService: service,
        appLifecycleService: lifecycle,
        settingsOverride: _ToolEnabledNoConfirmSettingsNotifier.new,
        memoryService: memory,
      );
      addTearDown(container.dispose);
      standInForTheApprover(container);
      _activatePendingBatchProject(container, project);
      _activateStructuredProjectTask(container, project);
      final notifier = container.read(chatNotifierProvider.notifier);
      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final taskId = container
          .read(conversationsNotifierProvider)
          .currentConversation!
          .id;
      final pending = notifier.sendMessage(
        'Complete only the current subtask.',
        purpose: PrimaryTurnPurpose.projectTaskStep,
      );
      if (detached) {
        await source.firstRequestReached.future.timeout(
          const Duration(seconds: 5),
        );
        final other = conversations.addBackgroundConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
        );
        conversations.selectConversation(other.id);
        gate!.complete();
      }
      await pending;
      await memory.firstUpdate.future.timeout(const Duration(seconds: 5));
      final conversation = container
          .read(conversationsNotifierProvider)
          .conversationForId(taskId)!;
      final answer = conversation.messages
          .lastWhere((message) => message.role == MessageRole.assistant)
          .content;
      final accepted = !fails || mode == 'failed then passed';
      expect(
        conversation.goal!.status,
        mode == 'blocked verification'
            ? ConversationGoalStatus.blocked
            : ConversationGoalStatus.active,
      );
      expect(memory.updateCount, 1);
      expect(
        source.recoveryCount,
        fails || mode == 'missing marker only' ? 1 : 0,
      );
      expect(
        memory.drafts.single!.summary,
        contains(
          accepted
              ? 'subtask is complete; the overall task remains active'
              : 'subtask remains incomplete',
        ),
      );
      expect(memory.drafts.single!.openLoops, isNotEmpty);
      expect(source.memoryMessages.last.content, contains('"scope":"subtask"'));
      expect(
        answer,
        accepted
            ? endsWith('PROJECT_TASK_SUBTASK_DONE')
            : isNot(endsWith('PROJECT_TASK_SUBTASK_DONE')),
      );
      expect(
        service.verifications,
        mode == 'failed then passed'
            ? 2
            : mode.startsWith('optional ') || reportingChanged
            ? 2
            : readOnly
            ? 0
            : 1,
      );
      if (mode == 'premature goal completion') {
        expect(
          source.toolResultBatches
              .expand((batch) => batch)
              .any(
                (result) => result.result.contains(
                  'project_subtask_goal_completion_refused',
                ),
              ),
          isTrue,
        );
      }
      if (fails) {
        expect(
          source.recoveryMessages.join('\n'),
          contains('capturedEvidence'),
        );
      }
      if (detached) {
        expect(
          container
              .read(conversationsNotifierProvider)
              .currentConversation!
              .messages,
          isEmpty,
        );
      }
    });
  }
}

class _ProjectTaskStepDataSource extends _ProjectTaskTerminalDataSource {
  _ProjectTaskStepDataSource({
    required this.scenario,
    required this.command,
    required super.initialToolCalls,
    required super.finalAnswerChunks,
    super.extractionFails,
    this.firstResponseGate,
  }) : super(
         toolLoopResponses: [
           for (var i = 0; i < 12; i++)
             ChatCompletionResult(content: '', finishReason: 'stop'),
         ],
       );

  final String scenario;
  final String command;
  final Future<void>? firstResponseGate;
  final firstRequestReached = Completer<void>();
  int recoveryCount = 0;
  final List<String> recoveryMessages = [];

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    if (scenario == 'failed then passed' && recoveryCount > 0) {
      return Stream.fromIterable([
        'Verified.\nPROJECT_TASK_SUBTASK_DONE',
      ]).asCompletion();
    }
    return super.streamChatCompletion(
      messages: messages,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (messages.isEmpty ||
        !messages.last.id.startsWith('structured_project_subtask_recovery_')) {
      if (!firstRequestReached.isCompleted) {
        firstRequestReached.complete();
        await firstResponseGate;
      }
      // After a successful recovered verifier, the normal follow-up supplies
      // a settled marker; failures reproduce the logged promise-only ending.
      if (recoveryCount > 0 && scenario == 'failed then passed') {
        return ChatCompletionResult(
          content: 'Verified.\nPROJECT_TASK_SUBTASK_DONE',
          finishReason: 'stop',
        );
      }
      return super.createChatCompletionWithToolResults(
        messages: messages,
        toolResults: toolResults,
        assistantContent: assistantContent,
        tools: tools,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      );
    }
    recoveryCount++;
    recoveryMessages.addAll(messages.map((message) => message.content));
    recoveryMessages.addAll(toolResults.map((result) => result.result));
    if (scenario == 'failed then passed') {
      return ChatCompletionResult(
        content: '',
        finishReason: 'tool_calls',
        toolCalls: [
          ToolCallInfo(
            id: 'rerun',
            name: 'local_execute_command',
            arguments: {'command': command},
          ),
        ],
      );
    }
    if (scenario == 'failed then repeated read') {
      return ChatCompletionResult(
        content: '',
        finishReason: 'tool_calls',
        toolCalls: [
          ToolCallInfo(
            id: 'redundant-read',
            name: 'read_file',
            arguments: const {'path': 'policy.md'},
          ),
        ],
      );
    }
    if (scenario == 'blocked verification') {
      return ChatCompletionResult(
        content: '',
        finishReason: 'tool_calls',
        toolCalls: [
          ToolCallInfo(
            id: 'blocker',
            name: 'update_goal',
            arguments: const {
              'completed': false,
              'blocked_reason': 'Fixture verifier unavailable.',
            },
          ),
        ],
      );
    }
    return ChatCompletionResult(
      content: 'Everything is complete.\nPROJECT_TASK_SUBTASK_DONE',
      finishReason: 'stop',
    );
  }
}

class _ProjectTaskStepToolService extends _PendingBatchMcpToolService {
  _ProjectTaskStepToolService(
    super.root, {
    required this.fails,
    required this.rerunPasses,
  });
  final bool fails;
  final bool rerunPasses;
  int verifications = 0;

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (name != 'local_execute_command') {
      return super.executeTool(name: name, arguments: arguments);
    }
    executedToolNames.add(name);
    verifications++;
    if (arguments['command'].toString().contains('-m pytest')) {
      final passed = arguments['command'].toString().contains(
        '.venv/bin/python',
      );
      return McpToolResult(
        toolName: name,
        isSuccess: true,
        result: jsonEncode({
          ...arguments,
          'working_directory': root.path,
          'exit_code': passed ? 0 : 1,
          'stdout': passed
              ? '53 passed in 3.08s'
              : 'python3: No module named pytest',
        }),
        outcome: ToolOutcome(
          exitCode: passed ? 0 : 1,
          testOutcome: passed
              ? ToolTestOutcome(
                  passedCount: 53,
                  failedCount: 0,
                  skippedCount: 0,
                  command: arguments['command'] as String,
                )
              : null,
        ),
      );
    }
    if (arguments['command'].toString().contains('-m pip show') ||
        arguments['command'].toString().contains('which -a') ||
        arguments['command'].toString().contains('pytest.__file__') ||
        arguments['command'].toString().contains('pytest.__version__')) {
      return McpToolResult(
        toolName: name,
        isSuccess: true,
        result: jsonEncode({
          ...arguments,
          'working_directory': root.path,
          'exit_code': 1,
          'stdout': 'ModuleNotFoundError: No module named \'pytest\'',
        }),
        outcome: const ToolOutcome(exitCode: 1),
      );
    }
    final exit = fails && !(rerunPasses && verifications > 1) ? 1 : 0;
    return McpToolResult(
      toolName: name,
      isSuccess: true,
      result: jsonEncode({
        ...arguments,
        'exit_code': exit,
        'stdout': exit == 0
            ? 'Verified.'
            : 'INCONSISTENCIES FOUND: documentation mismatch',
      }),
      outcome: ToolOutcome(exitCode: exit),
    );
  }
}
