part of 'chat_notifier_test.dart';

void registerChatNotifierBlockedGoalTests() {
  for (final mode in [
    'follow-up',
    'same batch',
    'detached',
    'memory failure',
  ]) {
    test('project task stops at the recorded blocker: $mode', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_blocked_task_',
      );
      addTearDown(() => root.delete(recursive: true));
      final target = File('${root.path}/source.py')
        ..writeAsStringSync('pass\n');
      final project = _pendingBatchProject(root.path);
      const blocker = 'The dry-run cannot reach the fixture API (exit 120).';
      const falseCompletion = 'All implementation and verification finished.';
      ToolCallInfo command(String id, String text) => ToolCallInfo(
        id: id,
        name: 'local_execute_command',
        arguments: {'command': text, 'working_directory': root.path},
      );
      ToolCallInfo completion(String id) => ToolCallInfo(
        id: id,
        name: 'update_goal',
        arguments: {'completed': true, 'message': '$falseCompletion ($id)'},
      );
      final tests = command(
        'passed-tests',
        '.venv/bin/python verify_logging.py && .venv/bin/python -m pytest -q',
      );
      final dryRun = command(
        'failed-dry-run',
        '.venv/bin/python watcher.py --dry-run 2>&1 | head -20',
      );
      final lateCalls = [
        completion('completion-after-blocker'),
        ToolCallInfo(
          id: 'edit-after-blocker',
          name: 'write_file',
          arguments: {
            'path': target.path,
            'content': 'Unapproved continuation.',
          },
        ),
      ];
      final replyGate = mode == 'detached' ? Completer<void>() : null;
      final source = _BlockedProjectTaskDataSource(
        replyGate: replyGate?.future,
        extractionFails: mode == 'memory failure',
        initialToolCalls: [tests, dryRun],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [completion('rejected-completion')],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: '$falseCompletion\nPROJECT_TASK_READY_FOR_REVIEW',
            toolCalls: [
              ToolCallInfo(
                id: 'blocker',
                name: 'update_goal',
                arguments: const {
                  'completed': false,
                  'blocked_reason': blocker,
                },
              ),
              if (mode == 'same batch') ...lateCalls,
            ],
            finishReason: 'tool_calls',
          ),
          if (mode != 'same batch')
            ChatCompletionResult(
              content: falseCompletion,
              toolCalls: lateCalls,
              finishReason: 'tool_calls',
            ),
          ChatCompletionResult(
            content: '$falseCompletion\nPROJECT_TASK_READY_FOR_REVIEW',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const [
          '$falseCompletion\nPROJECT_TASK_READY_FOR_REVIEW',
        ],
      );
      McpToolResult result(ToolCallInfo call, int exitCode, String stdout) =>
          McpToolResult(
            toolName: call.name,
            isSuccess: true,
            result: jsonEncode({
              ...call.arguments,
              'exit_code': exitCode,
              'stdout': stdout,
            }),
            outcome: ToolOutcome(exitCode: exitCode),
          );
      final service = _QueuedMcpToolResultService({
        'local_execute_command': [
          result(tests, 0, 'All 24 checks passed.\n53 passed in 0.1s'),
          result(dryRun, 120, 'Fixture API unavailable.'),
        ],
      });
      final memory = _TrackingSessionMemoryService();
      final lifecycle = _MockAppLifecycleService();
      when(() => lifecycle.isInBackground).thenReturn(false);
      final logs = LlmSessionLogStore(
        rootDirectoryProvider: () async => Directory('${root.path}/logs'),
      );
      final container = _pendingBatchContainer(
        project: project,
        dataSource: source,
        toolService: service,
        memoryService: memory,
        appLifecycleService: lifecycle,
        sessionLogStore: logs,
        settingsOverride: _ToolEnabledLoggingNoConfirmSettingsNotifier.new,
      );
      addTearDown(container.dispose);
      standInForTheApprover(container);
      _activatePendingBatchProject(container, project);
      _activateStructuredProjectTask(
        container,
        project,
        inheritedPaths: [target.path],
      );
      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final taskThreadId = container
          .read(conversationsNotifierProvider)
          .currentConversation!
          .id;
      final pending = container
          .read(chatNotifierProvider.notifier)
          .sendMessage(
            'Verify the inherited task implementation.',
            purpose: PrimaryTurnPurpose.projectTaskImplementation,
          );
      String? peerId;
      if (replyGate != null) {
        await source.firstFollowUpReached.future.timeout(
          const Duration(seconds: 5),
        );
        final peer = conversations.addBackgroundConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
        );
        peerId = peer.id;
        conversations.selectConversation(peer.id);
        replyGate.complete();
      }
      await pending;
      await memory.firstUpdate.future.timeout(const Duration(seconds: 5));
      final conversation = container
          .read(conversationsNotifierProvider)
          .conversationForId(taskThreadId)!;
      final answer = conversation.messages
          .lastWhere((message) => message.role == MessageRole.assistant)
          .content;
      expect(conversation.goal!.status, ConversationGoalStatus.blocked);
      expect(conversation.goal!.blockedReason, blocker);
      final statusLine = source.memoryMessages.last.content
          .split('\n')
          .firstWhere(
            (line) => line.startsWith('Recorded project task status: '),
          );
      final status =
          jsonDecode(
                statusLine.substring('Recorded project task status: '.length),
              )
              as Map<String, dynamic>;
      expect(status['status'], 'blockerLogged');
      expect(status['gaps'], contains(blocker));
      expect(
        status['gaps'],
        isNot(contains('the tool loop stopped before the work converged')),
      );
      expect(
        answer,
        allOf(
          contains(blocker),
          contains('completion was not recorded'),
          isNot(contains(falseCompletion)),
          isNot(contains('PROJECT_TASK_READY_FOR_REVIEW')),
        ),
      );
      expect(target.readAsStringSync(), 'pass\n');
      expect(service.executedToolNames, [
        'local_execute_command',
        'local_execute_command',
      ]);
      expect(source.toolResultBatches, hasLength(2));
      expect(memory.updateCount, 1);
      expect(
        memory.drafts.single!.summary,
        contains('completion was not recorded'),
      );
      expect(memory.drafts.single!.openLoops, isNotEmpty);
      expect(memory.drafts.single!.entries, isEmpty);
      expect(
        source.memoryMessages.last.content,
        allOf(contains('"status":"blockerLogged"'), contains(blocker)),
      );
      if (peerId != null) {
        expect(
          container
              .read(conversationsNotifierProvider)
              .conversationForId(peerId)!
              .messages,
          isEmpty,
        );
      }
      final log = await logs.fileForContext(
        LlmSessionLogContext(
          workspaceMode: WorkspaceMode.coding,
          sessionId: taskThreadId,
          conversationId: taskThreadId,
        ),
        create: false,
      );
      final exits = (await log.readAsLines())
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .where((entry) => entry['operation'] == 'turn_exit');
      expect(exits, hasLength(1));
      expect(
        exits.single['turnExit']['transforms'],
        contains('coding_task_status_blockerLogged'),
      );
    });
  }
}

class _BlockedProjectTaskDataSource extends _ProjectTaskTerminalDataSource {
  _BlockedProjectTaskDataSource({
    required super.initialToolCalls,
    required super.toolLoopResponses,
    required super.finalAnswerChunks,
    super.extractionFails,
    this.replyGate,
  });

  final Future<void>? replyGate;
  final firstFollowUpReached = Completer<void>();

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
    if (!firstFollowUpReached.isCompleted) {
      firstFollowUpReached.complete();
      await replyGate;
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

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    await super.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    return ChatCompletionResult(
      content:
          '{"summary":"Completed task.","open_loops":[],"profile":{},'
          '"memories":[{"text":"All work verified.","type":"fact"}]}',
      finishReason: 'stop',
    );
  }
}
