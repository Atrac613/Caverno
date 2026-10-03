part of 'chat_notifier_test.dart';

void registerChatNotifierReviewInspectionTests() {
  for (final mode in [
    'success',
    'read denied',
    'no read tool',
    'tools disabled',
  ]) {
    final failed = mode == 'read denied';
    final unavailable = mode == 'no read tool' || mode == 'tools disabled';
    test(
      'Farm review bootstraps fresh owner-scoped reads; mode=$mode',
      () async {
        final project = CodingProject(
          id: 'review-project',
          name: 'Review',
          rootPath: '/tmp/farm-review-project',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final source = _QueuedToolLoopChatDataSource(
          initialToolCalls: const [],
          toolLoopResponses: List.generate(
            2,
            (_) => ChatCompletionResult(
              content: 'No findings.\nPROJECT_TASK_REVIEW_CLEAN',
              finishReason: 'stop',
            ),
          ),
          finalAnswerChunks: const ['No findings.\nPROJECT_TASK_REVIEW_CLEAN'],
        );
        final service = _FakeMcpToolService(
          results: {
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
        }
        if (unavailable) {
          expect(service.executedToolNames, isEmpty);
          expect(source.initialRequestMessages, isEmpty);
          expect(source.toolResultBatches, isEmpty);
          expect(source.finalAnswerMessages, isEmpty);
          return;
        }
        expect(service.executedToolNames, ['read_file', 'read_file']);
        expect(service.executedToolArguments.map((args) => args['path']), [
          '/tmp/farm-review-project/fixture.py',
          '/tmp/farm-review-project/fixture.py',
        ]);
        expect(source.initialRequestMessages, isEmpty);
        expect(source.toolResultBatches, hasLength(2));
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
      },
    );
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
