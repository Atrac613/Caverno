part of 'chat_notifier_test.dart';

void registerChatNotifierProjectVerificationRepairTests() {
  for (final mode in [
    'repaired',
    'detached',
    'premature blocker',
    'external blocker',
    'no repair action',
  ]) {
    test('project verification automatically recovers: $mode', () async {
      final root = await Directory.systemTemp.createTemp('caverno_repair_');
      addTearDown(() => root.delete(recursive: true));
      final client = File('${root.path}/client.py')
        ..writeAsStringSync("API_PATH = '/missing/search'\n");
      final config = File('${root.path}/config.json')
        ..writeAsStringSync('{"query":"User-selected query"}\n');
      final project = _pendingBatchProject(root.path);
      const command = 'python3 watcher.py --dry-run';
      ToolCallInfo verify(String id) => ToolCallInfo(
        id: id,
        name: 'local_execute_command',
        arguments: {'command': command, 'working_directory': root.path},
      );
      final external = mode == 'external blocker' || mode == 'no repair action';
      final declined = mode == 'no repair action';
      final gate = mode == 'detached' ? Completer<void>() : null;
      final source = _ProjectVerificationRepairDataSource(
        client: client,
        verify: verify,
        external: external,
        declined: declined,
        prematureBlocker: mode == 'premature blocker',
        replyGate: gate?.future,
        initialToolCalls: [verify('initial-failure')],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The dry-run returned HTTP 404.',
            finishReason: 'stop',
          ),
          if (external) ...[
            ChatCompletionResult(
              content: '',
              finishReason: 'tool_calls',
              toolCalls: [verify('retry-1')],
            ),
            for (var attempt = 0; attempt < 2; attempt++)
              ChatCompletionResult(
                content: 'The dry-run still fails.',
                finishReason: 'stop',
              ),
          ] else ...[
            ChatCompletionResult(
              content: '',
              finishReason: 'tool_calls',
              toolCalls: [
                ToolCallInfo(
                  id: 'repair',
                  name: 'edit_file',
                  arguments: {
                    'path': client.path,
                    'old_text': '/missing/search',
                    'new_text': '/valid/search',
                  },
                ),
              ],
            ),
            ChatCompletionResult(
              content: '',
              finishReason: 'tool_calls',
              toolCalls: [verify('repaired-verification')],
            ),
            ChatCompletionResult(
              content: 'Verification passed.',
              finishReason: 'stop',
            ),
            ChatCompletionResult(
              content:
                  'Implementation verified.\nPROJECT_TASK_READY_FOR_REVIEW',
              finishReason: 'stop',
            ),
          ],
        ],
        finalAnswerChunks: [
          external
              ? 'The verification outcome remains to be recorded.'
              : 'Implementation verified.\nPROJECT_TASK_READY_FOR_REVIEW',
        ],
      );
      final service = _ProjectVerificationRepairToolService(
        root,
        external: external,
      );
      final memory = _TrackingSessionMemoryService();
      final lifecycle = _MockAppLifecycleService();
      when(() => lifecycle.isInBackground).thenReturn(false);
      final container = _pendingBatchContainer(
        project: project,
        dataSource: source,
        toolService: service,
        appLifecycleService: lifecycle,
        memoryService: memory,
        settingsOverride: _ToolEnabledNoConfirmSettingsNotifier.new,
      );
      addTearDown(container.dispose);
      standInForTheApprover(container);
      _activatePendingBatchProject(container, project);
      _activateStructuredProjectTask(
        container,
        project,
        inheritedPaths: [client.path],
      );
      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final ownerId = container
          .read(conversationsNotifierProvider)
          .currentConversation!
          .id;
      final pending = container
          .read(chatNotifierProvider.notifier)
          .sendMessage(
            'Verify the inherited implementation and repair any task-related failures.',
            purpose: PrimaryTurnPurpose.projectTaskImplementation,
          );
      String? peerId;
      if (gate != null) {
        await source.firstFollowUpReached.future.timeout(
          const Duration(seconds: 5),
        );
        final peer = conversations.addBackgroundConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
        );
        peerId = peer.id;
        conversations.selectConversation(peer.id);
        gate.complete();
      }
      await pending;
      await memory.firstUpdate.future.timeout(const Duration(seconds: 5));
      final conversation = container
          .read(conversationsNotifierProvider)
          .conversationForId(ownerId)!;
      final answer = conversation.messages
          .lastWhere((message) => message.role == MessageRole.assistant)
          .content;
      final expectedRequests = external || mode == 'premature blocker' ? 2 : 1;
      expect(source.repairRequests, expectedRequests);
      expect(service.commands, everyElement(command));
      expect(
        service.commands,
        hasLength(
          declined
              ? 1
              : external
              ? 3
              : 2,
        ),
      );
      expect(config.readAsStringSync(), '{"query":"User-selected query"}\n');
      expect(
        conversation.goal!.status,
        external
            ? ConversationGoalStatus.blocked
            : ConversationGoalStatus.completed,
      );
      expect(
        source.memoryMessages.last.content,
        contains(
          '"status":"${external ? 'blockerLogged' : 'completionRecorded'}"',
        ),
      );
      expect(
        answer,
        external
            ? isNot(contains('PROJECT_TASK_READY_FOR_REVIEW'))
            : endsWith('PROJECT_TASK_READY_FOR_REVIEW'),
      );
      expect(
        client.readAsStringSync(),
        external
            ? "API_PATH = '/missing/search'\n"
            : "API_PATH = '/valid/search'\n",
      );
      expect(
        service.executedEditNewTexts,
        external ? isEmpty : ['/valid/search'],
      );
      expect(source.repairEvidence, hasLength(expectedRequests));
      expect(source.repairEvidence.first, contains('HTTP Error 404'));
      expect(source.repairEvidence.first, contains(command));
      if (peerId != null) {
        expect(
          container
              .read(conversationsNotifierProvider)
              .conversationForId(peerId)!
              .messages,
          isEmpty,
        );
      }
    });
  }
}

class _ProjectVerificationRepairDataSource
    extends _ProjectTaskTerminalDataSource {
  _ProjectVerificationRepairDataSource({
    required super.initialToolCalls,
    required super.toolLoopResponses,
    super.finalAnswerChunks,
    required this.client,
    required this.verify,
    required this.external,
    required this.declined,
    required this.prematureBlocker,
    this.replyGate,
  });
  final File client;
  final ToolCallInfo Function(String) verify;
  final bool external;
  final bool declined;
  final bool prematureBlocker;
  final Future<void>? replyGate;
  final firstFollowUpReached = Completer<void>();
  int repairRequests = 0;
  final repairEvidence = <String>{};

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
    if (messages.last.id.startsWith('project_verification_repair_recovery_')) {
      repairRequests++;
      final names = tools!.map((tool) => (tool['function'] as Map)['name']);
      expect(
        names,
        containsAll(['read_file', 'edit_file', 'local_execute_command']),
      );
      expect(names, isNot(contains('update_goal')));
      expect(
        messages.last.content,
        contains('establish the cause from evidence'),
      );
      final feedback = toolResults.lastWhere(
        (result) => result.name == 'coding_continuation_recovery',
      );
      expect(
        jsonDecode(
          feedback.result,
        )['capturedEvidence']['unresolvedVerification']['workingDirectory'],
        client.parent.path,
      );
      repairEvidence.add(feedback.result);
      if (prematureBlocker && repairRequests == 1) {
        return ChatCompletionResult(
          content: '',
          finishReason: 'tool_calls',
          toolCalls: [
            ToolCallInfo(
              id: 'premature-blocker',
              name: 'update_goal',
              arguments: const {
                'completed': false,
                'blocked_reason': 'The sandbox has no network.',
              },
            ),
          ],
        );
      }
      if (declined) {
        return ChatCompletionResult(
          content: 'The external fixture service needs to be restored.',
          finishReason: 'stop',
        );
      }
      return ChatCompletionResult(
        content: '',
        finishReason: 'tool_calls',
        toolCalls: [
          external && repairRequests > 1
              ? verify('retry-$repairRequests')
              : ToolCallInfo(
                  id: 'diagnose',
                  name: 'read_file',
                  arguments: {'path': client.path},
                ),
        ],
      );
    }
    if (messages.last.id.startsWith(
      'structured_coding_task_status_recovery_',
    )) {
      return ChatCompletionResult(
        content: '',
        finishReason: 'tool_calls',
        toolCalls: [
          ToolCallInfo(
            id: 'terminal-status',
            name: 'update_goal',
            arguments: external
                ? const {
                    'completed': false,
                    'blocked_reason':
                        'The fixture API is unavailable after diagnosis and two retries; restore the external service.',
                  }
                : const {
                    'completed': true,
                    'message':
                        'Repaired the client path and reran the same dry-run successfully.',
                  },
          ),
        ],
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
}

class _ProjectVerificationRepairToolService
    extends _PendingBatchMcpToolService {
  _ProjectVerificationRepairToolService(super.root, {required this.external});
  final bool external;
  final commands = <String>[];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (name != 'local_execute_command') {
      return super.executeTool(name: name, arguments: arguments);
    }
    executedToolNames.add(name);
    commands.add(arguments['command'] as String);
    final passed =
        !external &&
        File(
          '${root.path}/client.py',
        ).readAsStringSync().contains('/valid/search');
    return McpToolResult(
      toolName: name,
      isSuccess: true,
      result: jsonEncode({
        ...arguments,
        'exit_code': passed ? 0 : 1,
        'stdout': passed ? 'Dry-run completed.' : 'HTTP Error 404: Not Found',
      }),
      outcome: ToolOutcome(exitCode: passed ? 0 : 1),
    );
  }
}
