part of 'chat_notifier_test.dart';

void registerChatNotifierCommitScopeTests() {
  for (final scenario in [
    'premature commit',
    'broad staging',
    'implementation edit',
    'shell bypass',
    'commit staging',
    'commit edit',
    'amend',
    'missing permit',
    'wrong owner',
    'changed during approval',
    'accepted commit',
  ]) {
    test('Farm native commit guard: $scenario', () async {
      final temporary = await Directory.systemTemp.createTemp('farm_guard_');
      final root = Directory(temporary.resolveSymbolicLinksSync());
      addTearDown(() => root.delete(recursive: true));
      Future<void> git(List<String> args) async {
        final result = await Process.run(
          'git',
          args,
          workingDirectory: root.path,
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }

      await git(['init', '-q']);
      await git(['config', 'user.email', 'fixture@example.invalid']);
      await git(['config', 'user.name', 'Fixture']);
      await File('${root.path}/task.txt').writeAsString('reviewed\n');
      await File('${root.path}/roadmap.md').writeAsString('- [x] Task\n');
      await git(['add', '--', 'task.txt', 'roadmap.md']);
      await git(['-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'fixture']);
      await File('${root.path}/task.txt').writeAsString('reviewed change\n');
      await git(['add', '--', 'task.txt']);
      final project = _pendingBatchProject(root.path);
      final preparing = [
        'premature commit',
        'broad staging',
        'implementation edit',
        'shell bypass',
      ].contains(scenario);
      const command =
          'commit -m "fix: update task" -m "Apply the reviewed task change."';
      final tool = ToolCallInfo(
        id: 'guarded-call',
        name: switch (scenario) {
          'implementation edit' || 'commit edit' => 'write_file',
          'shell bypass' => 'local_execute_command',
          _ => 'git_execute_command',
        },
        arguments: switch (scenario) {
          'implementation edit' => {
            'path': '${root.path}/task.txt',
            'content': 'unreviewed',
          },
          'commit edit' => {
            'path': '${root.path}/roadmap.md',
            'content': 'changed',
          },
          'shell bypass' => {'command': 'git $command'},
          _ => {
            'command': switch (scenario) {
              'broad staging' => 'add -- .',
              'commit staging' => 'add -- task.txt',
              'amend' => 'commit --amend -m "fix: update task"',
              _ => command,
            },
            'working_directory': root.path,
          },
        },
      );
      final source = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'inspect-index',
            name: 'git_execute_command',
            arguments: {
              'command': 'diff --cached',
              'working_directory': root.path,
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            finishReason: 'tool_calls',
            toolCalls: [tool],
          ),
          ChatCompletionResult(content: 'Turn settled.', finishReason: 'stop'),
        ],
        finalAnswerChunks: const ['Turn settled.'],
      );
      final service = _FakeMcpToolService(
        results: {
          'git_execute_command': jsonEncode({
            'command': 'git diff --cached',
            'working_directory': root.path,
            'exit_code': 0,
            'stdout':
                'diff --git a/task.txt b/task.txt\n--- a/task.txt\n+++ b/task.txt\n@@ -1 +1 @@\n-reviewed\n+reviewed change\n',
          }),
          'write_file': '{"ok":true}',
          'local_execute_command': '{"ok":true,"exit_code":0}',
        },
      );
      final lifecycle = _MockAppLifecycleService();
      when(() => lifecycle.isInBackground).thenReturn(false);
      final container = _pendingBatchContainer(
        project: project,
        dataSource: source,
        toolService: service,
        appLifecycleService: lifecycle,
        settingsOverride: _ToolEnabledSettingsNotifier.new,
      );
      addTearDown(container.dispose);
      _activatePendingBatchProject(container, project);
      _activateStructuredProjectTask(container, project);
      await container
          .read(conversationsNotifierProvider.notifier)
          .updateCurrentConversation([
            Message(
              id: 'old-instructions',
              content: 'Old review instruction: do not commit.',
              role: MessageRole.user,
              timestamp: DateTime(2026),
            ),
            Message(
              id: 'old-claim',
              content: 'Earlier commit reported as successful.',
              role: MessageRole.assistant,
              timestamp: DateTime(2026),
            ),
          ]);
      final notifier = container.read(chatNotifierProvider.notifier);
      final taskId = container
          .read(conversationsNotifierProvider)
          .currentConversation!
          .id;
      var scope = ProjectTaskCommitScope(
        conversationId: scenario == 'wrong owner' ? 'another-task' : taskId,
        projectRoot: root.path,
        roadmapPath: '${root.path}/roadmap.md',
        reviewedPaths: ['${root.path}/task.txt'],
      );
      if (!preparing && scenario != 'missing permit') {
        scope = scope.authorize(
          (await const ProjectTaskCommitReader().read(scope))!,
        );
      }
      var approvals = 0;
      container.listen<ChatState>(chatNotifierProvider, (previous, next) {
        final pending = next.pendingGitCommand;
        if (pending != null && pending.id != previous?.pendingGitCommand?.id) {
          approvals++;
          if (scenario == 'changed during approval') {
            File(
              '${root.path}/task.txt',
            ).writeAsStringSync('changed while awaiting approval\n');
          }
          notifier.resolveGitCommand(id: pending.id, approved: true);
        }
      });
      final owner = await notifier.sendProjectTaskCommit(
        'Settle this task phase.',
        scope,
        purpose: preparing
            ? PrimaryTurnPurpose.projectTaskCommitPreparation
            : PrimaryTurnPurpose.projectTaskCommit,
      );
      expect(owner, isNotNull);
      await notifier.waitForTurnCompletion(owner!);
      expect(
        source.initialRequestMessages.any(
          (message) =>
              message.id == 'old-instructions' || message.id == 'old-claim',
        ),
        isFalse,
      );
      expect(
        source.initialRequestMessages.first.content,
        isNot(contains('Implement and verify the task')),
      );
      final allowed = scenario == 'accepted commit';
      expect(notifier.takeLatestToolResults(owner), isNotEmpty);
      final evidence = notifier.takeProjectTaskCommitTurnEvidence(owner);
      expect(evidence, isNotNull);
      expect(evidence!.completedNormally, isTrue);
      expect(evidence.mutationAttempted, isTrue);
      expect(evidence.failed, !allowed);
      expect(evidence.mayRecover, isFalse);
      expect(notifier.takeProjectTaskCommitTurnEvidence(owner), isNull);

      expect(
        service.executedToolArguments
            .where((arguments) => arguments['command'] != 'diff --cached')
            .map((_) => tool.name),
        allowed ? ['git_execute_command'] : isEmpty,
        reason: source.toolResultBatches
            .expand((batch) => batch)
            .map((result) => result.result)
            .join('\n'),
      );
      expect(
        approvals,
        allowed || scenario == 'changed during approval' ? 1 : 0,
      );
      if (!allowed) {
        final results = source.toolResultBatches.expand((batch) => batch);
        expect(
          results.any(
            (result) => result.result.contains(
              'project_task_commit_precondition_failed',
            ),
          ),
          isTrue,
        );
      }
    });
  }
  for (final scenario in [
    'idle',
    'fragment',
    'unverified claim',
    'read-only',
    'cancelled',
    'error',
  ]) {
    test('Farm commit phase terminal evidence: $scenario', () async {
      final temporary = await Directory.systemTemp.createTemp('farm_observe_');
      final root = Directory(temporary.resolveSymbolicLinksSync());
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/roadmap.md').writeAsString('- [ ] Task');
      final gate = Completer<void>();
      final idle =
          scenario == 'idle' ||
          scenario == 'fragment' ||
          scenario == 'unverified claim';
      final answer = scenario == 'fragment'
          ? 'The'
          : scenario == 'unverified claim'
          ? 'Commit executed successfully. Observed result: the staged diff confirmed the two expected files.'
          : 'Preparation reported.';
      final interrupted = scenario == 'cancelled' || scenario == 'error';
      final ChatDataSource source = idle
          ? _NoToolStreamingWithToolsDataSource(
              streamChunks: [answer],
              completionContent: answer,
            )
          : _QueuedToolLoopChatDataSource(
              initialToolCalls: [
                ToolCallInfo(
                  id: 'inspect-task',
                  name: 'read_file',
                  arguments: {'path': '${root.path}/roadmap.md'},
                ),
              ],
              toolLoopResponses: [
                ChatCompletionResult(
                  content: 'Preparation reported.',
                  finishReason: 'stop',
                ),
              ],
              toolLoopResponseGates: interrupted ? {1: gate.future} : {},
              finalAnswerChunks: ['Preparation reported.'],
            );
      final project = _pendingBatchProject(root.path);
      final lifecycle = _MockAppLifecycleService();
      when(() => lifecycle.isInBackground).thenReturn(false);
      final container = _pendingBatchContainer(
        project: project,
        dataSource: source,
        toolService: _FakeMcpToolService(results: {'read_file': 'Task entry'}),
        appLifecycleService: lifecycle,
        settingsOverride: _ToolEnabledSettingsNotifier.new,
      );
      addTearDown(container.dispose);
      _activatePendingBatchProject(container, project);
      _activateStructuredProjectTask(container, project);
      final notifier = container.read(chatNotifierProvider.notifier);
      final sending = notifier.sendProjectTaskCommit(
        'Prepare this task.',
        ProjectTaskCommitScope(
          conversationId: notifier.conversationId!,
          projectRoot: root.path,
          roadmapPath: '${root.path}/roadmap.md',
          reviewedPaths: [],
        ),
        purpose: PrimaryTurnPurpose.projectTaskCommitPreparation,
      );
      if (interrupted) {
        await _waitForCondition(
          () => (source as _QueuedToolLoopChatDataSource)
              .toolResultBatches
              .isNotEmpty,
        );
        if (scenario == 'cancelled') {
          notifier.cancelStreaming();
          gate.complete();
        } else {
          gate.completeError(StateError('Fixture request failed'));
        }
      }
      final owner = (await sending)!;
      await notifier.waitForTurnCompletion(owner);
      expect(
        notifier.takeProjectTaskCommitTurnEvidence(
          ChatTurnOwner(
            conversationId: 'other',
            interactionGeneration: owner.interactionGeneration,
          ),
        ),
        isNull,
      );
      final evidence = notifier.takeProjectTaskCommitTurnEvidence(owner);
      expect(evidence, isNotNull);
      expect(
        evidence!.completedNormally,
        !interrupted && scenario != 'fragment',
      );
      expect(evidence.mutationAttempted, isFalse);
      expect(evidence.mayRecover, !interrupted && scenario != 'fragment');
      expect(notifier.takeProjectTaskCommitTurnEvidence(owner), isNull);
    });
  }
}
