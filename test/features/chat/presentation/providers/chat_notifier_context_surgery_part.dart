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
}
