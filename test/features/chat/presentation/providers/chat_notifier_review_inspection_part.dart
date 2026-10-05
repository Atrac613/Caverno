part of 'chat_notifier_test.dart';

void registerChatNotifierReviewInspectionTests() {
  for (final mode in [
    'success',
    'read denied',
    'no read tool',
    'tools disabled',
    'structured findings',
    'unmarked findings',
    'verification failed',
  ]) {
    final failed = mode == 'read denied';
    final unavailable = mode == 'no read tool' || mode == 'tools disabled';
    test('Farm review bootstraps fresh owner-scoped reads; mode=$mode', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_farm_review_',
      );
      addTearDown(() => root.delete(recursive: true));
      final project = CodingProject(
        id: 'review-project',
        name: 'Review',
        rootPath: root.path,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final source = _QueuedToolLoopChatDataSource(
        initialToolCalls: const [],
        toolLoopResponses: List.generate(
          mode == 'verification failed' ? 4 : 2,
          (index) => ChatCompletionResult(
            toolCalls: mode == 'verification failed' && index.isEven
                ? [
                    ToolCallInfo(
                      id: 'pytest-$index',
                      name: 'local_execute_command',
                      arguments: {
                        'command': 'python3 -m pytest -q test_watcher.py',
                        'working_directory': project.rootPath,
                      },
                    ),
                  ]
                : null,
            content: switch (mode) {
              'structured findings' => jsonEncode({
                'status': 'findings',
                'findings': ['watcher.py:163: reject Infinity.'],
                'verificationLimits': ['The runtime check could not run.'],
                'summary':
                    'I will fix the interval validation in a later task.',
              }),
              'unmarked findings' =>
                'Review findings: fixes required.\nwatcher.py:163: reject Infinity.',
              _ => 'No findings.\nPROJECT_TASK_REVIEW_CLEAN',
            },
            finishReason: 'stop',
          ),
        ),
        finalAnswerChunks: const ['No findings.\nPROJECT_TASK_REVIEW_CLEAN'],
      );
      final service = _FakeMcpToolService(
        results: {
          if (mode == 'verification failed')
            'local_execute_command':
                '{"exit_code":1,"stderr":"No module named pytest"}',
          (mode == 'no read tool' ? 'list_directory' : 'read_file'): failed
              ? '{"ok":false,"error":"denied"}'
              : '{"content":"current code"}',
        },
      );
      final lifecycle = _MockAppLifecycleService();
      when(() => lifecycle.isInBackground).thenReturn(false);
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            () => _FarmReviewInspectionSettings(
              disabled: mode == 'tools disabled',
            ),
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(source),
          primaryRouteEndpointDataSourceFactoryProvider.overrideWithValue(
            ({required baseUrl, required apiKey, required endpointId}) =>
                source,
          ),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(service),
          appLifecycleServiceProvider.overrideWithValue(lifecycle),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(container.dispose);
      if (mode == 'verification failed') standInForTheApprover(container);
      _activatePendingBatchProject(container, project);
      _activateStructuredProjectTask(
        container,
        project,
        inheritedPaths: ['fixture.py'],
      );
      final notifier = container.read(chatNotifierProvider.notifier);
      for (var turn = 0; turn < 2; turn++) {
        final owner = await notifier.sendMessage(
          'Review task changes',
          bypassPlanMode: true,
          purpose: PrimaryTurnPurpose.codeReview,
        );
        expect(owner, isNotNull);
        await notifier.waitForTurnCompletion(owner!);
        if (unavailable) {
          expect(notifier.state.messages.last.error, isNotNull);
          expect(
            notifier.state.messages.last.content,
            isNot(contains('PROJECT_TASK_REVIEW_CLEAN')),
          );
          continue;
        }
        expect(
          notifier.state.messages.last.content.contains(
            FinalAnswerClaimDetector.unverifiedReadOnlyInspectionNotice,
          ),
          failed,
        );
        final verdict = notifier.takeProjectTaskReviewVerdict(owner);
        expect(verdict, isNotNull);
        if (mode == 'structured findings') {
          expect(verdict!.disposition.name, 'findings');
          expect(
            notifier.state.messages.last.content,
            contains('reject Infinity'),
          );
          expect(
            notifier.state.messages.last.content,
            endsWith('PROJECT_TASK_REVIEW_FINDINGS'),
          );
        } else if (mode == 'unmarked findings' ||
            mode == 'verification failed' ||
            failed) {
          expect(verdict!.isComplete, isFalse);
          expect(
            notifier.state.messages.last.content,
            isNot(contains('PROJECT_TASK_REVIEW_CLEAN')),
          );
        } else {
          expect(verdict!.disposition.name, 'clean');
        }
        expect(
          source.finalAnswerMessages,
          isEmpty,
          reason: 'A second generation must not rewrite the review.',
        );
        final system = source.toolResultRequestMessages
            .expand((messages) => messages)
            .where((message) => message.role == MessageRole.system)
            .map((message) => message.content)
            .join('\n');
        expect(system, isNot(contains('Every saved task is complete')));
        expect(system, isNot(contains('<execution_snapshot>')));
      }
      if (unavailable) {
        expect(service.executedToolNames, isEmpty);
        expect(source.initialRequestMessages, isEmpty);
        expect(source.toolResultBatches, isEmpty);
        expect(source.finalAnswerMessages, isEmpty);
        return;
      }
      expect(
        service.executedToolNames,
        mode == 'verification failed'
            ? [
                'read_file',
                'local_execute_command',
                'read_file',
                'local_execute_command',
              ]
            : ['read_file', 'read_file'],
      );
      expect(
        service.executedToolArguments
            .where((args) => args.containsKey('path'))
            .map((args) => args['path']),
        ['${root.path}/fixture.py', '${root.path}/fixture.py'],
      );
      expect(source.initialRequestMessages, isEmpty);
      expect(
        source.toolResultBatches,
        hasLength(mode == 'verification failed' ? 4 : 2),
      );
      expect(
        source.assistantContents.first,
        contains('The harness is inspecting'),
      );
      expect(
        source.toolResultDefinitions.first.every(
          (tool) =>
              !['write_file', 'edit_file'].contains(tool['function']['name']),
        ),
        isTrue,
      );
    });
  }
}

class _FarmReviewInspectionSettings
    extends _ToolEnabledNoConfirmSettingsNotifier {
  _FarmReviewInspectionSettings({this.disabled = false});
  final bool disabled;
  @override
  AppSettings build() => super.build().copyWith(
    mcpEnabled: !disabled,
    codeReviewModel: 'test-model',
    codeReviewEndpointId: 'review',
    llmEndpoints: const [
      LlmEndpoint(
        id: 'review',
        baseUrl: 'http://review.example/v1',
        model: 'test-model',
      ),
    ],
  );
}
