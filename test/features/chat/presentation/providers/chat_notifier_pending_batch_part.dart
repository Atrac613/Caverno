part of 'chat_notifier_test.dart';

void registerChatNotifierPendingBatchTests() {
  for (final scenario in [
    (rejected: false, extractionFails: false, reportedExitCode: null),
    (rejected: true, extractionFails: false, reportedExitCode: null),
    (rejected: true, extractionFails: true, reportedExitCode: null),
    (rejected: true, extractionFails: false, reportedExitCode: 2),
    (rejected: true, extractionFails: false, reportedExitCode: 120),
    (rejected: false, extractionFails: false, reportedExitCode: 0),
  ]) {
    final rejected = scenario.rejected;
    test(
      'project task terminal status reaches saved answer and memory $scenario',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'caverno_task_terminal_',
        );
        addTearDown(() => root.delete(recursive: true));
        final project = _pendingBatchProject(root.path);
        ToolCallInfo report(String id) => ToolCallInfo(
          id: id,
          name: 'update_goal',
          arguments: const {'completed': true},
        );
        final source = _ProjectTaskTerminalDataSource(
          extractionFails: scenario.extractionFails,
          initialToolCalls: [
            ToolCallInfo(
              id: 'write',
              name: 'write_file',
              arguments: {
                'path': '${root.path}/source.py',
                'content': 'pass\n',
              },
            ),
            ToolCallInfo(
              id: 'verify',
              name: 'local_execute_command',
              arguments: {
                'command': scenario.reportedExitCode == null
                    ? 'rm -f scratch.log && python -m pytest -q'
                    : r'python3 app.py --dry-run 2>&1 | head -40; echo "PIPELINE_EXIT=${PIPESTATUS[0]:-n/a}"',
                'working_directory': root.path,
              },
            ),
          ],
          toolLoopResponses: [
            ChatCompletionResult(
              content: '',
              toolCalls: [report('complete')],
              finishReason: 'tool_calls',
            ),
            ChatCompletionResult(
              content: 'All work is complete.',
              finishReason: 'stop',
            ),
            if (rejected)
              for (var index = 0; index < 3; index++)
                ChatCompletionResult(
                  content: '',
                  toolCalls: [report('repeat-$index')],
                  finishReason: 'tool_calls',
                ),
          ],
          finalAnswerChunks: const [
            'All work is complete.\nPROJECT_TASK_READY_FOR_REVIEW',
          ],
        );
        final memory = _TrackingSessionMemoryService();
        final lifecycle = _MockAppLifecycleService();
        when(() => lifecycle.isInBackground).thenReturn(false);
        final container = _pendingBatchContainer(
          project: project,
          dataSource: source,
          toolService: _ProjectTaskTerminalToolService(
            root,
            rejected,
            reportedExitCode: scenario.reportedExitCode,
          ),
          appLifecycleService: lifecycle,
          settingsOverride: _ToolEnabledNoConfirmSettingsNotifier.new,
          memoryService: memory,
        );
        addTearDown(container.dispose);
        standInForTheApprover(container);
        _activatePendingBatchProject(container, project);
        _activateStructuredProjectTask(container, project);
        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Implement and verify the task.',
          purpose: PrimaryTurnPurpose.projectTaskImplementation,
        );
        await memory.firstUpdate.future.timeout(const Duration(seconds: 5));
        final conversation = container
            .read(conversationsNotifierProvider)
            .currentConversation!;
        final answer = conversation.messages
            .lastWhere((message) => message.role == MessageRole.assistant)
            .content;
        expect(
          conversation.goal!.status,
          rejected
              ? ConversationGoalStatus.active
              : ConversationGoalStatus.completed,
        );
        expect(memory.updateCount, 1);
        expect(
          memory.updateMessages.single
              .lastWhere((message) => message.role == MessageRole.assistant)
              .content,
          ContentParser.parse(answer).text.trim(),
        );
        expect(
          source.memoryMessages.last.content,
          contains(
            '"status":"${rejected ? 'completionRejected' : 'completionRecorded'}"',
          ),
        );
        if (rejected) {
          expect(
            answer,
            allOf(
              contains('completion was not recorded'),
              isNot(contains('PROJECT_TASK_READY_FOR_REVIEW')),
              isNot(contains('All work is complete.')),
            ),
          );
          expect(
            memory.drafts.single!.summary,
            contains('completion was not recorded'),
          );
          expect(memory.drafts.single!.openLoops, isNotEmpty);
        } else {
          expect(answer, endsWith('PROJECT_TASK_READY_FOR_REVIEW'));
          expect(memory.drafts.single!.summary, 'Completed task.');
          expect(memory.drafts.single!.openLoops, isEmpty);
        }
      },
    );
  }

  for (final scenario in [
    (passDryRun: false, reportAgain: false),
    (passDryRun: true, reportAgain: false),
    (passDryRun: false, reportAgain: true),
    (passDryRun: true, reportAgain: true),
  ]) {
    test(
      'keeps a rejected task incomplete after a later edit $scenario',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'caverno_rejected_task_',
        );
        addTearDown(() => root.delete(recursive: true));
        final inherited = File('${root.path}/source.py')
          ..writeAsStringSync('pass\n');
        final ignored = File('${root.path}/.gitignore');
        final project = _pendingBatchProject(root.path);
        ToolCallInfo command(String id, String text) => ToolCallInfo(
          id: id,
          name: 'local_execute_command',
          arguments: {'command': text, 'working_directory': root.path},
        );
        ToolCallInfo report(String id) => ToolCallInfo(
          id: id,
          name: 'update_goal',
          arguments: const {'completed': true},
        );
        const dryRun =
            '.venv/bin/python app.py --dry-run 2>&1 | head -20; '
            'echo "--- app.log tail ---"; tail -8 app.log';
        final source = _ProjectTaskTerminalDataSource(
          initialToolCalls: [
            command('tests', '.venv/bin/python -m pytest -q'),
            command('failed-dry-run', dryRun),
          ],
          toolLoopResponses: [
            ChatCompletionResult(content: 'Ready.', finishReason: 'stop'),
            ChatCompletionResult(
              content: '',
              toolCalls: [command('retry-dry-run', dryRun)],
              finishReason: 'tool_calls',
            ),
            ChatCompletionResult(
              content: '',
              toolCalls: [report('rejected-completion')],
              finishReason: 'tool_calls',
            ),
            ChatCompletionResult(
              content: '',
              toolCalls: [
                ToolCallInfo(
                  id: 'ignore-log',
                  name: 'write_file',
                  arguments: {'path': ignored.path, 'content': 'app.log\n'},
                ),
                command('tests-after-edit', '.venv/bin/python -m pytest -q'),
              ],
              finishReason: 'tool_calls',
            ),
            if (scenario.passDryRun)
              ChatCompletionResult(
                content: '',
                toolCalls: [command('passing-dry-run', dryRun)],
                finishReason: 'tool_calls',
              ),
            if (scenario.reportAgain)
              ChatCompletionResult(
                content: '',
                toolCalls: [report('reported-after-verification')],
                finishReason: 'tool_calls',
              ),
            ChatCompletionResult(content: 'Ready.', finishReason: 'stop'),
            if (!scenario.reportAgain || !scenario.passDryRun) ...[
              ChatCompletionResult(
                content: '<think>The task is finished.</think>',
                finishReason: 'stop',
              ),
              if (!scenario.passDryRun)
                ChatCompletionResult(
                  content: 'No project repair action is returned.',
                  finishReason: 'stop',
                ),
              ChatCompletionResult(
                content: '',
                toolCalls: [
                  command('unoffered-backup', 'cp config.json backup.json'),
                ],
                finishReason: 'tool_calls',
              ),
            ],
          ],
          finalAnswerChunks: const ['Ready.\nPROJECT_TASK_READY_FOR_REVIEW'],
        );
        final service = _VerificationAfterRejectionToolService(root);
        final memory = _TrackingSessionMemoryService();
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
        _activateStructuredProjectTask(
          container,
          project,
          inheritedPaths: [inherited.path],
        );
        await container
            .read(chatNotifierProvider.notifier)
            .sendMessage(
              'Verify the task and ignore its generated log.',
              purpose: PrimaryTurnPurpose.projectTaskImplementation,
            );
        await memory.firstUpdate.future.timeout(const Duration(seconds: 5));
        final conversation = container
            .read(conversationsNotifierProvider)
            .currentConversation!;
        final accepted = scenario.passDryRun && scenario.reportAgain;
        expect(
          conversation.goal!.status,
          accepted
              ? ConversationGoalStatus.completed
              : ConversationGoalStatus.active,
        );
        final results = source.toolResultBatches
            .expand((batch) => batch)
            .toList();
        expect(
          results.where((result) => result.id == 'rejected-completion'),
          isNotEmpty,
        );
        expect(
          results
              .firstWhere((result) => result.id == 'rejected-completion')
              .result,
          contains('Completion not recorded'),
        );
        final answer = conversation.messages
            .lastWhere((message) => message.role == MessageRole.assistant)
            .content;
        expect(
          answer,
          accepted
              ? endsWith('PROJECT_TASK_READY_FOR_REVIEW')
              : isNot(contains('PROJECT_TASK_READY_FOR_REVIEW')),
        );
        if (!accepted) {
          expect(answer, contains('completion was not recorded'));
          expect(
            answer,
            contains(scenario.passDryRun ? 'update_goal' : 'app.py --dry-run'),
          );
        }
        expect(
          source.memoryMessages.last.content,
          contains(
            '"status":"${accepted ? 'completionRecorded' : 'completionRejected'}"',
          ),
        );
        expect(
          memory.drafts.single!.summary,
          accepted ? 'Completed task.' : isNot('Completed task.'),
        );
        expect(
          memory.drafts.single!.openLoops,
          accepted ? isEmpty : isNotEmpty,
        );
        expect(
          service.executedCommands,
          isNot(contains('cp config.json backup.json')),
        );
        expect(ignored.readAsStringSync(), 'app.log\n');
        expect(inherited.readAsStringSync(), 'pass\n');
      },
    );
  }

  for (final scenario in [
    (retryExit: 120, reportBlocked: true),
    (retryExit: 120, reportBlocked: false),
    (retryExit: 0, reportBlocked: false),
  ]) {
    test(
      'reports structured status after recovery verification $scenario',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'caverno_status_retry_',
        );
        addTearDown(() => root.delete(recursive: true));
        final target = File('${root.path}/source.py')
          ..writeAsStringSync('pass\n');
        final project = _pendingBatchProject(root.path);
        ToolCallInfo command(String id, String command) => ToolCallInfo(
          id: id,
          name: 'local_execute_command',
          arguments: {'command': command, 'working_directory': root.path},
        );
        final tests = command('tests', '.venv/bin/python -m pytest -q');
        const dryRun = '.venv/bin/python watcher.py --dry-run 2>&1 | head -30';
        final failed = command('failed-dry-run', dryRun);
        final retry = command('retry-dry-run', dryRun);
        final inspection = command(
          'inspect-log',
          'ls -la watcher.log && tail -5 watcher.log',
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
        final source = _ProjectTaskTerminalDataSource(
          initialToolCalls: [tests, failed],
          toolLoopResponses: [
            ChatCompletionResult(content: 'Ready.', finishReason: 'stop'),
            ChatCompletionResult(
              content: '',
              toolCalls: [retry],
              finishReason: 'tool_calls',
            ),
            ChatCompletionResult(
              content: '',
              toolCalls: [inspection],
              finishReason: 'tool_calls',
            ),
            ChatCompletionResult(content: 'Ready.', finishReason: 'stop'),
            if (scenario.retryExit != 0)
              ChatCompletionResult(
                content: '',
                toolCalls: [
                  ToolCallInfo(
                    id: 'diagnose-before-status',
                    name: 'read_file',
                    arguments: {'path': target.path},
                  ),
                ],
                finishReason: 'tool_calls',
              ),
            ChatCompletionResult(
              content: '',
              toolCalls: [
                ToolCallInfo(
                  id: 'status',
                  name: 'update_goal',
                  arguments: scenario.reportBlocked
                      ? const {
                          'completed': false,
                          'blocked_reason':
                              'The dry-run still exits 120 after retry.',
                        }
                      : const {'completed': true},
                ),
              ],
              finishReason: 'tool_calls',
            ),
            ChatCompletionResult(
              content: 'Status reported.',
              finishReason: 'stop',
            ),
          ],
          finalAnswerChunks: const ['Ready.\nPROJECT_TASK_READY_FOR_REVIEW'],
        );
        final service = _QueuedMcpToolResultService({
          'local_execute_command': [
            result(tests, 0, '53 passed in 3.08s'),
            result(failed, 120, 'HTTP Error 404: Not Found'),
            result(
              retry,
              scenario.retryExit,
              scenario.retryExit == 0
                  ? 'Dry-run completed.'
                  : 'HTTP Error 404: Not Found',
            ),
            result(inspection, 0, 'Fixture log output.'),
          ],
          'run_tests': [],
          'update_goal': [],
          'read_file': [
            McpToolResult(
              toolName: 'read_file',
              isSuccess: true,
              result: jsonEncode({'path': target.path, 'content': 'pass\n'}),
            ),
          ],
        });
        final memory = _TrackingSessionMemoryService();
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
        _activateStructuredProjectTask(
          container,
          project,
          inheritedPaths: [target.path],
        );
        await container
            .read(chatNotifierProvider.notifier)
            .sendMessage(
              'Verify the inherited task changes.',
              purpose: PrimaryTurnPurpose.projectTaskImplementation,
            );
        await memory.firstUpdate.future.timeout(const Duration(seconds: 5));
        final conversation = container
            .read(conversationsNotifierProvider)
            .currentConversation!;
        final accepted = scenario.retryExit == 0;
        expect(
          conversation.goal!.status,
          scenario.reportBlocked
              ? ConversationGoalStatus.blocked
              : accepted
              ? ConversationGoalStatus.completed
              : ConversationGoalStatus.active,
        );
        expect(
          source.memoryMessages.last.content,
          contains(
            '"status":"${scenario.reportBlocked
                ? 'blockerLogged'
                : accepted
                ? 'completionRecorded'
                : 'completionRejected'}"',
          ),
        );
        final answer = conversation.messages
            .lastWhere((message) => message.role == MessageRole.assistant)
            .content;
        expect(
          answer,
          accepted
              ? endsWith('PROJECT_TASK_READY_FOR_REVIEW')
              : isNot(contains('PROJECT_TASK_READY_FOR_REVIEW')),
        );
        expect(
          memory.drafts.single!.summary,
          accepted ? 'Completed task.' : isNot('Completed task.'),
        );
        expect(
          memory.drafts.single!.openLoops,
          accepted ? isEmpty : isNotEmpty,
        );
        expect(
          service.executedToolNames.where(
            (name) => name == 'local_execute_command',
          ),
          hasLength(4),
        );
        expect(
          source.toolResultDefinitions.where(
            (tools) =>
                tools.length == 1 &&
                (tools.single['function'] as Map)['name'] == 'update_goal',
          ),
          hasLength(scenario.reportBlocked ? 0 : 1),
        );
        expect(target.readAsStringSync(), 'pass\n');
      },
    );
  }

  test(
    'a full venv chain completes inherited work and its saved memory',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_python_chain_',
      );
      addTearDown(() => root.delete(recursive: true));
      final target = File('${root.path}/logging.py')
        ..writeAsStringSync('pass\n');
      final project = _pendingBatchProject(root.path);
      ToolCallInfo verify(String id, String interpreter) => ToolCallInfo(
        id: id,
        name: 'local_execute_command',
        arguments: {
          'command':
              'cd ${root.path} && $interpreter verify_logging.py && '
              '$interpreter -m pytest test_state.py test_watcher.py -v 2>&1',
          'working_directory': root.path,
        },
      );
      final failed = verify('system-chain', 'python3');
      final passed = verify('venv-chain', '.venv/bin/python');
      McpToolResult result(ToolCallInfo call, int exitCode) => McpToolResult(
        toolName: call.name,
        isSuccess: true,
        result: jsonEncode({
          ...call.arguments,
          'exit_code': exitCode,
          'stdout': exitCode == 0
              ? 'All 24 checks passed.\n53 passed in 3.09s'
              : 'All 24 checks passed.\npython3: No module named pytest',
        }),
        outcome: ToolOutcome(exitCode: exitCode),
      );
      final source = _ProjectTaskTerminalDataSource(
        initialToolCalls: [failed],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [passed],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(content: 'Verified.', finishReason: 'stop'),
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'complete',
                name: 'update_goal',
                arguments: const {'completed': true},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(content: 'Verified.', finishReason: 'stop'),
        ],
        finalAnswerChunks: const [
          'The task is verified.\nPROJECT_TASK_READY_FOR_REVIEW',
        ],
      );
      final service = _QueuedMcpToolResultService({
        'local_execute_command': [result(failed, 1), result(passed, 0)],
        'update_goal': [],
      });
      final memory = _TrackingSessionMemoryService();
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
      _activateStructuredProjectTask(
        container,
        project,
        inheritedPaths: [target.path],
      );
      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage(
            'Verify the inherited task changes.',
            purpose: PrimaryTurnPurpose.projectTaskImplementation,
          );
      await memory.firstUpdate.future.timeout(const Duration(seconds: 5));
      final conversation = container
          .read(conversationsNotifierProvider)
          .currentConversation!;
      expect(conversation.goal!.status, ConversationGoalStatus.completed);
      expect(
        conversation.messages
            .lastWhere((message) => message.role == MessageRole.assistant)
            .content,
        endsWith('PROJECT_TASK_READY_FOR_REVIEW'),
      );
      expect(memory.drafts.single!.summary, 'Completed task.');
      expect(memory.drafts.single!.openLoops, isEmpty);
      expect(
        source.memoryMessages.last.content,
        contains('"status":"completionRecorded"'),
      );
      expect(service.executedToolNames, [
        'local_execute_command',
        'local_execute_command',
      ]);
      expect(
        source.toolResultDefinitions.where(
          (tools) =>
              tools.length == 1 &&
              (tools.single['function'] as Map)['name'] == 'update_goal',
        ),
        hasLength(1),
      );
      expect(target.readAsStringSync(), 'pass\n');
    },
  );

  test(
    'reuses a passing venv result when the model returns to its failed runner',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_verified_replay_',
      );
      addTearDown(() => root.delete(recursive: true));
      final project = _pendingBatchProject(root.path);
      ToolCallInfo call(String id, String command) => ToolCallInfo(
        id: id,
        name: 'local_execute_command',
        arguments: {'command': command, 'working_directory': root.path},
      );
      final failed = call('failed', 'python3 -m pytest test.py -v');
      final passed = call('passed', '.venv/bin/python -m pytest test.py -v');
      final repeated = call(
        'old-runner',
        'cd ${root.path} && python3 -m pytest test.py -v 2>&1 | tail -30',
      );
      McpToolResult result(ToolCallInfo call, bool success) => McpToolResult(
        toolName: call.name,
        isSuccess: true,
        result: jsonEncode({
          ...call.arguments,
          'exit_code': success ? 0 : 1,
          'stdout': success
              ? '=== 6 passed in 3.05s ==='
              : 'python3: No module named pytest',
        }),
        outcome: ToolOutcome(
          exitCode: success ? 0 : 1,
          testOutcome: success
              ? ToolTestOutcome(
                  passedCount: 6,
                  failedCount: 0,
                  skippedCount: 0,
                  command: call.arguments['command'] as String,
                )
              : null,
        ),
      );
      final source = _QueuedToolLoopChatDataSource(
        initialToolCalls: [failed],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            finishReason: 'tool_calls',
            toolCalls: [passed],
          ),
          ChatCompletionResult(
            content: '',
            finishReason: 'tool_calls',
            toolCalls: [repeated],
          ),
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunks: const ['Verification completed: 6 passed.'],
      );
      final service = _QueuedMcpToolResultService({
        'local_execute_command': [result(failed, false), result(passed, true)],
      });
      final lifecycle = _MockAppLifecycleService();
      when(() => lifecycle.isInBackground).thenReturn(false);
      final container = _pendingBatchContainer(
        project: project,
        dataSource: source,
        toolService: service,
        appLifecycleService: lifecycle,
        settingsOverride: _ToolEnabledNoConfirmSettingsNotifier.new,
      );
      addTearDown(container.dispose);
      _activatePendingBatchProject(container, project);
      // Uncontained shells still ask, which is every Linux CI run. The
      // question this test asks is the replay, not the approval sheet.
      standInForTheApprover(container);
      final notifier = container.read(chatNotifierProvider.notifier);
      await notifier.sendMessage('Verify the current implementation.');
      expect(service.executedToolNames, [
        'local_execute_command',
        'local_execute_command',
      ]);
      final reused = source.toolResultBatches
          .expand((batch) => batch)
          .lastWhere((entry) => entry.id == repeated.id);
      expect(
        jsonDecode(reused.result)['code'],
        'verified_pytest_result_reused',
      );
      expect(reused.outcome?.testOutcome?.passedCount, 6);
      expect(notifier.state.messages.last.content, contains('6 passed'));
    },
  );
  // Both suites pin how the loop spends its iteration cap.
  registerChatNotifierBackgroundWaitRefundTests();
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
      final turnOwner = await notifier.sendMessage(
        'Finish the declared file write',
      );

      expect(target.readAsStringSync(), 'const generated = true;\n');
      expect(toolService.executedToolNames.last, 'write_file');
      expect(
        toolService.executedToolNames.where((name) => name == 'write_file'),
        hasLength(1),
      );
      expect(dataSource.toolResultBatches, hasLength(15));
      expect(
        notifier
            .takeLatestToolResults(turnOwner!)
            .any((result) => result.result.contains('tool_call_not_executed')),
        isFalse,
      );
      final finalPrompt = dataSource.finalAnswerMessages
          .map((message) => message.content)
          .join('\n');
      expect(finalPrompt, contains('[Tool: write_file]'));
      expect(finalPrompt, contains(target.path));
    },
  );

  test('loop-limit recovery request carries the earlier reads', () async {
    // Sessions 50e3f486, d84f819b and e6b3d03c: the recovery request held
    // the last batch alone, so the model finished without the facts it had
    // already gathered -- re-listing tags, or committing a guessed version.
    final projectRoot = await Directory.systemTemp.createTemp(
      'caverno_recovery_context_',
    );
    addTearDown(() => projectRoot.delete(recursive: true));
    final finalCall = ToolCallInfo(
      id: 'final-write',
      name: 'write_file',
      arguments: {
        'path': '${projectRoot.path}/lib/generated.dart',
        'content': 'const generated = true;\n',
      },
    );
    final dataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [_pendingBatchReadCall(0, projectRoot.path)],
      toolLoopResponses: _pendingBatchResponses(
        projectRoot: projectRoot.path,
        finalCall: finalCall,
      ),
      finalAnswerChunks: const ['Done.'],
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

    await container
        .read(chatNotifierProvider.notifier)
        .sendMessage('Finish the declared file write');

    final recoveryIndex = dataSource.toolResultRequestMessages.indexWhere(
      (messages) => messages.any(
        (message) => message.content.contains('bounded tool loop limit'),
      ),
    );
    expect(recoveryIndex, isNonNegative);
    final recoveryIds = dataSource.toolResultBatches[recoveryIndex]
        .map((result) => result.id)
        .toList();
    // The batch that just ran is read-11; everything before it is carried.
    expect(recoveryIds.last, 'read-11');
    expect(recoveryIds, containsAll(<String>['read-0', 'read-10']));
    // And it reaches the datasource marked as history, which prompt budgeting
    // used to strip before the request formatter could see it.
    final recoveryResults = dataSource.toolResultBatches[recoveryIndex];
    expect(
      recoveryResults
          .where((result) => result.id != 'read-11')
          .every((result) => result.fromEarlierLoop),
      isTrue,
    );
    expect(recoveryResults.last.fromEarlierLoop, isFalse);
  });

  for (final (label, promise, userRequest) in [
    (
      'visible promise',
      "I'll implement the remaining Dart code and tests.",
      'Implement both Dart files.',
    ),
    (
      'partial implementation report',
      'The Dart implementation is partially complete.\n'
          '- Implement lib/remaining.dart.\n- Run tests.\nThe task remains incomplete.',
      'Implement both Dart files.',
    ),
    (
      'let-me fix promise',
      'lib/remaining.dart needs another edit. Let me make the fixes:',
      'Implement both Dart files.',
    ),
    (
      'Japanese addition promise',
      '`lib/remaining.dart` \u306b\u30d1\u30e9\u30e1\u30fc\u30bf\u3092\u8ffd\u52a0\u3057\u307e\u3059\u3002',
      'Implement both Dart files.',
    ),
    (
      'English future status',
      "I'll implement the remaining Dart code and tests.",
      'continue',
    ),
    ('Spanish status', 'Listo.', 'Implement both Dart files.'),
    ('opaque status', '...', 'Implement both Dart files.'),
    (
      'prose remaining work',
      '**\u672a\u5b8c\u4e86\u306e\u4f5c\u696d:**\n'
          '`lib/remaining.dart` \u306b\u4fee\u6b63\u3092\u8ffd\u52a0\u3057\u3001'
          '\u5b8c\u6210\u3055\u305b\u308b\u3002\n'
          '\u30bf\u30b9\u30af\u306f\u672a\u5b8c\u3067\u3059\u3002',
      'The previous implementation turn captured no reviewable file change. '
          'Inspect the current files, then perform the remaining implementation with file tools and run relevant verification.',
    ),
  ]) {
    final structuredTask = label != 'visible promise';
    test('finalization recovers a $label with earlier read context', () async {
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_finalization_context_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final firstTarget = File('${projectRoot.path}/lib/first.dart');
      final remainingTarget = File('${projectRoot.path}/lib/remaining.dart');
      ToolCallInfo writeCall(String id, File target) => ToolCallInfo(
        id: id,
        name: 'write_file',
        arguments: {
          'path': target.path,
          'content': 'const implemented = true;\n',
        },
      );
      final rawAnswer =
          '<think>${'The code is updated, but I cannot stop yet. ' * 800}'
          '</think>$promise';
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [_pendingBatchReadCall(0, projectRoot.path)],
        toolLoopResponses: [
          ..._pendingBatchResponses(
            projectRoot: projectRoot.path,
            finalCall: writeCall('first-write', firstTarget),
          ),
          if (structuredTask)
            ChatCompletionResult(
              content: '',
              finishReason: 'tool_calls',
              toolCalls: [
                ToolCallInfo(
                  id: 'report-task-state',
                  name: 'update_goal',
                  arguments: const {
                    'completed': false,
                    'message': 'A remaining implementation step needs tools.',
                  },
                ),
              ],
            ),
          ChatCompletionResult(
            content: 'Apply the remaining implementation.',
            toolCalls: [writeCall('remaining-write', remainingTarget)],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The remaining Dart file was implemented.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunkBatches: [
          [rawAnswer],
          ['Both Dart files were implemented.'],
        ],
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
      if (structuredTask) _activateStructuredProjectTask(container, project);
      final notifier = container.read(chatNotifierProvider.notifier);

      await notifier.sendMessage(
        userRequest,
        purpose: structuredTask
            ? PrimaryTurnPurpose.projectTaskImplementation
            : PrimaryTurnPurpose.conversation,
      );

      expect(firstTarget.existsSync(), isTrue);
      expect(remainingTarget.existsSync(), isTrue);
      expect(
        toolService.executedToolNames.where((name) => name == 'write_file'),
        hasLength(2),
      );
      final recoveryBatch = dataSource.toolResultBatches.firstWhere(
        (batch) => batch.any(
          (result) => result.name == 'coding_continuation_recovery',
        ),
      );
      expect(
        recoveryBatch.map((result) => result.id),
        containsAll(['read-0', 'read-14']),
      );
      expect(dataSource.assistantContents[15], promise);
      if (structuredTask) {
        // The two writes were never verified, so the status request also
        // offers the execution tool the completion gate needs (02fec5c8),
        // and still no editor.
        expect(
          dataSource.toolResultDefinitions[15].map(
            (tool) => (tool['function'] as Map)['name'],
          ),
          ['update_goal', 'local_execute_command'],
        );
      }
      expect(
        notifier.state.messages.last.content,
        contains('Both Dart files were implemented.'),
      );
      expect(notifier.state.messages.last.content, isNot(contains(promise)));
    });
  }

  for (final status in [
    'complete',
    'complete after progress',
    'complete after progress recovery',
    'missing',
    'blocker',
    'unoffered',
  ]) {
    test('structured project finalization handles $status status', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_task_status_',
      );
      addTearDown(() => root.delete(recursive: true));
      final project = _pendingBatchProject(root.path);
      final target = File('${root.path}/test.py');
      final write = ToolCallInfo(
        id: 'write',
        name: 'write_file',
        arguments: {'path': target.path, 'content': 'pass\n'},
      );
      final report = ToolCallInfo(
        id: 'report',
        name: 'update_goal',
        arguments: status == 'blocker'
            ? const {
                'completed': false,
                'blocked_reason': 'Project dependency unavailable.',
              }
            : const {'completed': true},
      );
      final source = _QueuedToolLoopChatDataSource(
        initialToolCalls: [write],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'verify',
                name: 'local_execute_command',
                arguments: {
                  'command': 'python -m pytest',
                  'working_directory': root.path,
                },
              ),
            ],
          ),
          if (status == 'complete')
            ChatCompletionResult(
              content: '',
              finishReason: 'tool_calls',
              toolCalls: [report],
            ),
          ChatCompletionResult(content: '', finishReason: 'stop'),
          if (status != 'complete')
            ChatCompletionResult(
              content: '...',
              finishReason: status == 'missing' ? 'stop' : 'tool_calls',
              toolCalls: status == 'missing'
                  ? null
                  : [
                      status == 'unoffered'
                          ? write
                          : status.startsWith('complete after progress')
                          ? ToolCallInfo(
                              id: 'progress',
                              name: 'update_goal',
                              arguments: const {
                                'completed': false,
                                'message': 'Run verification.',
                              },
                            )
                          : report,
                    ],
            ),
          if (const ['unoffered', 'missing'].contains(status))
            ChatCompletionResult(
              content: '...',
              finishReason: status == 'missing' ? 'stop' : 'tool_calls',
              toolCalls: status == 'missing' ? null : [write],
            ),
          if (status.startsWith('complete after progress')) ...[
            ChatCompletionResult(
              content: '',
              finishReason: 'tool_calls',
              toolCalls: [
                ToolCallInfo(
                  id: 'verify-again',
                  name: 'local_execute_command',
                  arguments: {
                    'command': 'python -m pytest -q',
                    'working_directory': root.path,
                  },
                ),
              ],
            ),
            if (status == 'complete after progress recovery')
              ChatCompletionResult(content: '', finishReason: 'stop'),
            ChatCompletionResult(
              content: '',
              finishReason: 'tool_calls',
              toolCalls: [report],
            ),
            ChatCompletionResult(content: '', finishReason: 'stop'),
          ],
          if (status == 'blocker')
            ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunkBatches: const [
          ['Done.'],
          ['Stopped.'],
          ['Finished.'],
        ],
      );
      final appLifecycle = _MockAppLifecycleService();
      when(() => appLifecycle.isInBackground).thenReturn(false);
      final service = _PendingBatchMcpToolService(root);
      final logs = LlmSessionLogStore(
        rootDirectoryProvider: () async => Directory('${root.path}/logs'),
      );
      final container = _pendingBatchContainer(
        project: project,
        dataSource: source,
        toolService: service,
        appLifecycleService: appLifecycle,
        settingsOverride: _ToolEnabledLoggingNoConfirmSettingsNotifier.new,
        sessionLogStore: logs,
      );
      addTearDown(container.dispose);
      standInForTheApprover(container);
      _activatePendingBatchProject(container, project);
      _activateStructuredProjectTask(container, project);
      final notifier = container.read(chatNotifierProvider.notifier);
      await notifier.sendMessage(
        'Implement the task.',
        purpose: PrimaryTurnPurpose.projectTaskImplementation,
      );
      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation!
          .goal!;
      final conversation = container
          .read(conversationsNotifierProvider)
          .currentConversation!;
      final log = await logs.fileForContext(
        LlmSessionLogContext(
          workspaceMode: WorkspaceMode.coding,
          sessionId: conversation.id,
          conversationId: conversation.id,
        ),
        create: false,
      );
      final exits = (await log.readAsLines())
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .where((entry) => entry['operation'] == 'turn_exit')
          .toList();
      expect(exits, hasLength(1));
      expect(
        exits.single['turnExit']['transforms'],
        contains(
          'coding_task_status_${status.startsWith('complete')
              ? 'completionRecorded'
              : status == 'blocker'
              ? 'blockerLogged'
              : 'missing'}',
        ),
      );
      if (status.startsWith('complete')) {
        expect(
          source.toolResultBatches
              .expand((batch) => batch)
              .firstWhere((result) => result.name == 'write_file')
              .outcome
              ?.fileMutations,
          isNotEmpty,
        );
        final reportResult = source.toolResultBatches
            .expand((batch) => batch)
            .lastWhere((result) => result.name == 'update_goal');
        expect(reportResult.result, contains('Completion accepted'));
      }
      expect(
        goal.status,
        status.startsWith('complete')
            ? ConversationGoalStatus.completed
            : status == 'blocker'
            ? ConversationGoalStatus.blocked
            : ConversationGoalStatus.active,
      );
      final requests = source.toolResultDefinitions.where(
        (tools) =>
            tools.length == 1 &&
            (tools.single['function'] as Map)['name'] == 'update_goal',
      );
      expect(
        requests,
        hasLength(
          status == 'complete'
              ? 0
              : status == 'complete after progress recovery'
              ? 2
              : const ['unoffered', 'missing'].contains(status)
              ? 2
              : 1,
        ),
      );
      expect(
        service.executedToolNames.where((name) => name == 'write_file'),
        hasLength(1),
      );
    });
  }

  test(
    'finalization runs pending venv verification after a masked failure',
    () async {
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_pending_verification_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = _pendingBatchProject(projectRoot.path);
      const pending =
          'The implementation is complete.\n'
          'ModuleNotFoundError: No module named pytest with the system Python.\n'
          'Unexecuted verification command:\n'
          '```\n.venv/bin/python -m pytest test_watcher.py\n```';
      const failedCommand = 'python3 -m pytest test_watcher.py 2>&1 | tail -30';
      const verificationCommand = '.venv/bin/python -m pytest test_watcher.py';
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'system-test',
            name: 'local_execute_command',
            arguments: {
              'command': failedCommand,
              'working_directory': projectRoot.path,
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: '', finishReason: 'stop'),
          ChatCompletionResult(
            content: '',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'report-verification-state',
                name: 'update_goal',
                arguments: const {
                  'completed': false,
                  'message': 'Run verification with the project interpreter.',
                },
              ),
            ],
          ),
          ChatCompletionResult(
            content: 'Run the available venv verifier.',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'venv-test',
                name: 'local_execute_command',
                arguments: {
                  'command': verificationCommand,
                  'working_directory': projectRoot.path,
                },
              ),
            ],
          ),
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunkBatches: const [
          [pending],
          ['Verification finished: 6 passed.'],
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command': 'unused',
          'update_goal': 'unused',
        },
        queuedResults: {
          'local_execute_command': [
            jsonEncode({
              'command': failedCommand,
              'working_directory': projectRoot.path,
              'exit_code': 0,
              'stdout': '/opt/python/bin/python3.14: No module named pytest\n',
            }),
            jsonEncode({
              'command': verificationCommand,
              'working_directory': projectRoot.path,
              'exit_code': 0,
              'stdout':
                  '========================= 6 passed in 0.14s ==========================',
            }),
          ],
        },
      );
      final lifecycle = _MockAppLifecycleService();
      when(() => lifecycle.isInBackground).thenReturn(false);
      final container = _pendingBatchContainer(
        project: project,
        dataSource: dataSource,
        toolService: toolService,
        appLifecycleService: lifecycle,
        settingsOverride: _ToolEnabledNoConfirmSettingsNotifier.new,
      );
      addTearDown(container.dispose);
      standInForTheApprover(container);
      _activatePendingBatchProject(container, project);
      _activateStructuredProjectTask(container, project);
      final notifier = container.read(chatNotifierProvider.notifier);

      await notifier.sendMessage(
        'Implement retry and run relevant verification.',
        purpose: PrimaryTurnPurpose.projectTaskImplementation,
      );

      expect(toolService.executedToolNames, [
        'local_execute_command',
        'local_execute_command',
      ]);
      expect(
        dataSource.toolResultBatches.any(
          (batch) =>
              batch.any((result) => result.name == 'coding_output_feedback'),
        ),
        isTrue,
      );
      expect(
        dataSource.toolResultBatches.any(
          (batch) => batch.any(
            (result) => result.name == 'coding_continuation_recovery',
          ),
        ),
        isTrue,
      );
      expect(notifier.state.messages.last.content, contains('6 passed'));
      expect(
        notifier.state.messages.last.content,
        isNot(contains('Unexecuted verification')),
      );
    },
  );

  test(
    'pending read refreshes an edited file instead of a stale recovery snapshot',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_pending_refresh_',
      );
      addTearDown(() => root.delete(recursive: true));
      final target = File('${root.path}/source.py')
        ..writeAsStringSync('interval = 2\n');
      ToolCallInfo read(String id) => ToolCallInfo(
        id: id,
        name: 'read_file',
        arguments: {'path': target.path, 'offset': 1, 'limit': 20},
      );
      ToolCallInfo edit(String id, String oldText, String newText) =>
          ToolCallInfo(
            id: id,
            name: 'edit_file',
            arguments: {
              'path': target.path,
              'old_text': oldText,
              'new_text': newText,
            },
          );
      ChatCompletionResult response(ToolCallInfo call) => ChatCompletionResult(
        content: '',
        toolCalls: [call],
        finishReason: 'tool_calls',
      );
      final source = _QueuedToolLoopChatDataSource(
        initialToolCalls: [read('initial-read')],
        toolLoopResponses: [
          response(edit('applied-edit', 'interval = 2\n', 'interval = 0\n')),
          for (var index = 1; index <= 9; index++)
            response(_pendingBatchReadCall(index, root.path)),
          response(edit('mismatch', 'interval = 2\n', 'interval = 1\n')),
          response(read('pending-read-fresh')),
          response(
            edit('stale-recovery-edit', 'interval = 0\n', 'interval = 99\n'),
          ),
        ],
        finalAnswerChunks: const ['The refreshed source has interval = 0.'],
      );
      final service = _PendingReadRefreshToolService(root, target.path);
      final project = _pendingBatchProject(root.path);
      final lifecycle = _MockAppLifecycleService();
      when(() => lifecycle.isInBackground).thenReturn(false);
      final container = _pendingBatchContainer(
        project: project,
        dataSource: source,
        toolService: service,
        appLifecycleService: lifecycle,
        settingsOverride: _ToolEnabledNoConfirmSettingsNotifier.new,
      );
      addTearDown(container.dispose);
      _activatePendingBatchProject(container, project);
      final notifier = container.read(chatNotifierProvider.notifier);
      final owner = await notifier.sendMessage(
        'Refresh the source after the failed edit.',
      );
      final results = notifier.takeLatestToolResults(owner!);
      final refreshed = results.singleWhere(
        (result) => result.id == 'pending-read-fresh',
      );
      expect(jsonDecode(refreshed.result)['content'], 'interval = 0');
      expect(service.targetReadCount, 2);
      expect(target.readAsStringSync(), 'interval = 0\n');
      expect(service.executedEditNewTexts, isNot(contains('interval = 99\n')));
      expect(source.toolResultBatches, hasLength(12));
      expect(
        source.toolResultRequestMessages
            .expand((messages) => messages)
            .any(
              (message) => message.content.contains('bounded tool loop limit'),
            ),
        isFalse,
      );
      expect(
        notifier.state.messages.last.content,
        contains('refreshed source has interval = 0'),
      );
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
    final turnOwner = await notifier.sendMessage(
      'Apply the corrected pending edit',
    );

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
      notifier
          .takeLatestToolResults(turnOwner!)
          .any((result) => result.result.contains('tool_call_not_executed')),
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
      final turnOwner = await sendFuture.timeout(const Duration(seconds: 5));

      expect(
        toolService.executedToolNames,
        isNot(contains('local_execute_command')),
      );
      expect(dataSource.toolResultBatches, hasLength(15));
      final results = notifier.takeLatestToolResults(turnOwner!);
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
    final turnOwner = await notifier.sendMessage(
      'Exercise the final dispatch failure',
    );

    expect(dataSource.toolResultBatches, hasLength(15));
    final results = notifier.takeLatestToolResults(turnOwner!);
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
      toolCalls: [
        ToolCallInfo(
          id: 'pending-discovery',
          name: 'search_files',
          arguments: {'path': projectRoot, 'query': 'fixture'},
        ),
      ],
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
  final path = '$projectRoot/probe-$index.txt';
  File(path).writeAsStringSync('fixture observation');
  return ToolCallInfo(
    id: 'read-$index',
    name: 'read_file',
    arguments: {'path': path},
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
  required ChatDataSource dataSource,
  required McpToolService toolService,
  required AppLifecycleService appLifecycleService,
  required SettingsNotifier Function() settingsOverride,
  LlmSessionLogStore? sessionLogStore,
  SessionMemoryService? memoryService,
}) {
  return ProviderContainer(
    overrides: [
      if (sessionLogStore != null)
        llmSessionLogStoreProvider.overrideWithValue(sessionLogStore),
      settingsNotifierProvider.overrideWith(settingsOverride),
      conversationRepositoryProvider.overrideWithValue(
        _FakeConversationRepository(),
      ),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        memoryService ?? _TestSessionMemoryService(),
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

class _ProjectTaskTerminalDataSource extends _QueuedToolLoopChatDataSource {
  _ProjectTaskTerminalDataSource({
    required super.initialToolCalls,
    required super.toolLoopResponses,
    this.extractionFails = false,
    super.finalAnswerChunks,
  });

  final bool extractionFails;
  final List<Message> memoryMessages = [];

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
    // Additional recovery requests must not invent new execution evidence.
    // A scripted completion still goes through the normal rejection gate.
    if (_toolLoopResponses.isEmpty) {
      _toolLoopResponses.add(
        messages.last.id.startsWith('structured_coding_task_status_recovery_')
            ? ChatCompletionResult(
                content: '',
                finishReason: 'tool_calls',
                toolCalls: [
                  ToolCallInfo(
                    id: 'fixture-unresolved-status',
                    name: 'update_goal',
                    arguments: const {'completed': true},
                  ),
                ],
              )
            : ChatCompletionResult(
                content: 'No additional fixture work was performed.',
                finishReason: 'stop',
              ),
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

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (!messages.any((message) => message.id == 'memory_extractor_system')) {
      throw StateError('Unexpected secondary completion');
    }
    memoryMessages.addAll(messages);
    if (extractionFails) {
      throw StateError('Fixture secondary completion failed');
    }
    return ChatCompletionResult(
      content: jsonEncode({
        'summary': 'Completed task.',
        'open_loops': [],
        'profile': {},
        'memories': [],
      }),
      finishReason: 'stop',
    );
  }
}

class _VerificationAfterRejectionToolService
    extends _PendingBatchMcpToolService {
  _VerificationAfterRejectionToolService(super.root);

  final executedCommands = <String>[];
  int dryRunExecutions = 0;

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (name != 'local_execute_command') {
      return super.executeTool(name: name, arguments: arguments);
    }
    executedToolNames.add(name);
    final command = arguments['command'] as String;
    executedCommands.add(command);
    final dryRun = command.contains('app.py --dry-run');
    final failed = dryRun && ++dryRunExecutions <= 2;
    return McpToolResult(
      toolName: name,
      isSuccess: true,
      result: jsonEncode({
        ...arguments,
        'exit_code': 0,
        'stdout': failed
            ? 'Traceback (most recent call last):\nRuntimeError: fixture verification failed'
            : dryRun
            ? 'Dry-run passed.'
            : '53 passed in 0.1s',
      }),
      outcome: const ToolOutcome(exitCode: 0),
    );
  }
}

class _ProjectTaskTerminalToolService extends _PendingBatchMcpToolService {
  _ProjectTaskTerminalToolService(
    super.root,
    this.rejected, {
    this.reportedExitCode,
  });
  final bool rejected;
  final int? reportedExitCode;

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (name != 'local_execute_command') {
      return super.executeTool(name: name, arguments: arguments);
    }
    executedToolNames.add(name);
    final exitCode = reportedExitCode == null && rejected ? 1 : 0;
    return McpToolResult(
      toolName: name,
      isSuccess: true,
      result: jsonEncode({
        ...arguments,
        'exit_code': exitCode,
        'stdout': reportedExitCode != null
            ? 'Fixture command output\nPIPELINE_EXIT=$reportedExitCode\n'
            : rejected
            ? '1 failed in 0.1s'
            : '53 passed in 0.1s',
      }),
      outcome: ToolOutcome(exitCode: exitCode),
    );
  }
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

void _activateStructuredProjectTask(
  ProviderContainer container,
  CodingProject project, {
  List<String> inheritedPaths = const [],
}) {
  final conversations = container.read(conversationsNotifierProvider.notifier);
  final task = conversations.addBackgroundConversation(
    workspaceMode: WorkspaceMode.coding,
    projectId: project.id,
    goal: ConversationGoal(
      id: 'project-task-goal',
      objective: 'Implement and verify the task',
      projectTaskAutoReview: true,
      projectTaskInheritedPaths: inheritedPaths,
      createdAt: DateTime(2026, 9, 30),
      updatedAt: DateTime(2026, 9, 30),
    ),
  );
  conversations.selectConversation(task.id);
}

// The owner-aware delegate mirrors production: the file mutation runtime
// executes raw mutations through the service's owner-fenced boundary, so a
// double that only overrides executeTool never observes them.
class _PendingReadRefreshToolService extends _PendingBatchMcpToolService {
  _PendingReadRefreshToolService(super.root, this.targetPath);

  final String targetPath;
  int targetReadCount = 0;

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (name == 'read_file' &&
        File(arguments['path'] as String).resolveSymbolicLinksSync() ==
            File(targetPath).resolveSymbolicLinksSync()) {
      targetReadCount++;
      executedToolNames.add(name);
      return McpToolResult(
        toolName: name,
        result: await FilesystemTools.readFile(path: targetPath),
        isSuccess: true,
      );
    }
    return super.executeTool(name: name, arguments: arguments);
  }
}

class _PendingBatchMcpToolService extends McpToolService
    with FileTools, OwnerAwareMcpToolTestDelegate {
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
          'name': 'update_goal',
          'parameters': {
            'type': 'object',
            'properties': {
              'completed': {'type': 'boolean'},
              'message': {'type': 'string'},
              'blocked_reason': {'type': 'string'},
            },
            'required': ['completed'],
          },
        },
      },
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
          'name': 'search_files',
          'description': 'Search fixture files.',
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
      final execution = await FilesystemTools.writeFileResult(
        path: arguments['path'] as String,
        content: arguments['content'] as String? ?? '',
        createParents: true,
      );
      return McpToolResult(
        toolName: name,
        result: execution.result,
        isSuccess: true,
        outcome: execution.outcome,
      );
    }
    if (name == 'local_execute_command') {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({
          'exit_code': 0,
          'stdout': '1 passed',
          'command': arguments['command'],
        }),
        isSuccess: true,
        outcome: const ToolOutcome(exitCode: 0),
      );
    }
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'unexpected': true, 'root': root.path}),
      isSuccess: true,
    );
  }
}
