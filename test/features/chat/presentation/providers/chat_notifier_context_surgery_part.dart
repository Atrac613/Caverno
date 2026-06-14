part of 'chat_notifier_test.dart';

class _MutableContextSurgerySettingsNotifier extends _TestSettingsNotifier {
  @override
  Future<void> upsertModelCapabilityProfile(
    ModelCapabilityProfile profile,
  ) async {
    final normalized = profile.normalizedForPersistence();
    final profiles = List<ModelCapabilityProfile>.from(
      state.modelCapabilityProfiles,
    );
    final index = profiles.indexWhere((item) => item.id == normalized.id);
    if (index == -1) {
      profiles.add(normalized);
    } else {
      profiles[index] = normalized;
    }
    state = state.copyWith(modelCapabilityProfiles: profiles);
  }
}

class _PlanModeContextSurgerySettingsNotifier
    extends _MutableContextSurgerySettingsNotifier {
  @override
  AppSettings build() =>
      super.build().copyWith(assistantMode: AssistantMode.plan);
}

void registerChatNotifierContextSurgeryTests() {
  test('model profile updates keep the current chat data source', () async {
    final dataSource = _ToolBatchChatDataSource(
      initialToolCalls: const [],
      finalAnswerChunks: const ['Profile feedback preserved the data source'],
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _MutableContextSurgerySettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final notifier = container.read(chatNotifierProvider.notifier);
      final settings = container.read(settingsNotifierProvider);
      final profile = ModelCapabilityProfile(
        id: ModelCapabilityProfile.buildId(
          provider: settings.llmProvider,
          baseUrl: settings.baseUrl,
          model: settings.effectiveModel,
        ),
        provider: settings.llmProvider,
        baseUrl: settings.baseUrl,
        model: settings.effectiveModel,
        probeMetadata: const {'feedback': 'runtime'},
      ).normalizedForPersistence();

      await container
          .read(settingsNotifierProvider.notifier)
          .upsertModelCapabilityProfile(profile);
      await notifier.sendMessage('Use the current data source');
      await _waitForCondition(
        () => notifier.state.messages.any(
          (message) =>
              message.content == 'Profile feedback preserved the data source',
        ),
      );

      expect(dataSource.finalAnswerRequestMessages, hasLength(1));
      expect(
        notifier.state.messages.map((message) => message.content),
        contains('Profile feedback preserved the data source'),
      );
    } finally {
      container.dispose();
    }
  });

  test('json proposal repairs record runtime sampler feedback', () async {
    final dataSource = _ToolBatchChatDataSource(
      initialToolCalls: const [],
      finalAnswerChunks: const ['unused'],
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _PlanModeContextSurgerySettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final notifier = container.read(chatNotifierProvider.notifier);
      const rawContent = '''
{"workflowStage":"plan","goal":"Ship repaired JSON feedback","constraints":["Keep parsing resilient"],"acceptanceCriteria":["The sampler feedback count updates"],"openQuestions":[]
''';

      final proposal = notifier.parseWorkflowProposalForTest(rawContent);

      expect(proposal, isNotNull);
      expect(proposal!.workflowSpec.goal, 'Ship repaired JSON feedback');
      await _waitForCondition(() {
        final metadata = container
            .read(settingsNotifierProvider)
            .effectiveModelCapabilityProfile
            ?.probeMetadata;
        return metadata?['ll16.sampler.plan.runtime.jsonRepairCount'] == '1';
      });
      final metadata = container
          .read(settingsNotifierProvider)
          .effectiveModelCapabilityProfile!
          .probeMetadata;
      expect(metadata['ll16.sampler.plan.runtime.jsonRepairCount'], '1');
      expect(metadata['ll16.sampler.toolLoop.runtime.jsonRepairCount'], isNull);
    } finally {
      container.dispose();
    }
  });
}
