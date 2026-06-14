// Same-library extension for LL14 context observation state updates.
//
// Riverpod marks `ref` as `@protected`, which is not aware of extensions even
// in the same library.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierContextSurgery on ChatNotifier {
  void updateConnectionSettings(AppSettings settings) =>
      _updateConnectionSettings(settings);

  void _updateConnectionSettings(AppSettings settings) {
    final previousSettings = _settings;
    if (_modelSwitchRouteKey(previousSettings) !=
        _modelSwitchRouteKey(settings)) {
      _scheduleModelSwitchHandoff(
        previousSettings: previousSettings,
        nextSettings: settings,
      );
    }
    final shouldRebuildDataSource = _shouldRebuildChatDataSource(
      previousSettings,
      settings,
    );
    _settings = settings;
    if (shouldRebuildDataSource) {
      _dataSource = _withChatSessionLogging(
        ref.read(chatRemoteDataSourceProvider),
        settings,
      );
    }
  }

  @visibleForTesting
  void scheduleModelSwitchHandoffForTest({
    required AppSettings previousSettings,
    required AppSettings nextSettings,
  }) {
    _scheduleModelSwitchHandoff(
      previousSettings: previousSettings,
      nextSettings: nextSettings,
    );
  }

  String _modelSwitchRouteKey(AppSettings settings) {
    return ModelCapabilityProfile.buildId(
      provider: settings.llmProvider,
      baseUrl: settings.baseUrl,
      model: settings.effectiveModel,
    );
  }

  bool _shouldRebuildChatDataSource(
    AppSettings previousSettings,
    AppSettings nextSettings,
  ) {
    return previousSettings.demoMode != nextSettings.demoMode ||
        previousSettings.llmProvider != nextSettings.llmProvider ||
        previousSettings.baseUrl != nextSettings.baseUrl ||
        previousSettings.apiKey != nextSettings.apiKey ||
        previousSettings.reasoningEffort != nextSettings.reasoningEffort ||
        previousSettings.enableLlmSessionLogs !=
            nextSettings.enableLlmSessionLogs;
  }

  void _scheduleModelSwitchHandoff({
    required AppSettings previousSettings,
    required AppSettings nextSettings,
  }) {
    final conversationsState = ref.read(conversationsNotifierProvider);
    final conversation = conversationsState.currentConversation;
    final messages = state.messages.isNotEmpty
        ? state.messages
        : (conversation?.messages ?? const <Message>[]);
    final brief = ModelSwitchHandoffBriefService.build(
      conversation: conversation,
      messages: messages,
      previousModel: previousSettings.effectiveModel,
      nextModel: nextSettings.effectiveModel,
    );
    _modelSwitchHandoffBrief = brief;
    _modelSwitchHandoffConversationId = brief == null ? null : conversation?.id;
  }

  String? _takePendingModelSwitchHandoffBrief(String? conversationId) {
    final brief = _modelSwitchHandoffBrief;
    if (brief == null) return null;
    final expectedConversationId = _modelSwitchHandoffConversationId;
    if (expectedConversationId != null &&
        expectedConversationId != conversationId) {
      return null;
    }
    _modelSwitchHandoffBrief = null;
    _modelSwitchHandoffConversationId = null;
    return brief;
  }

  void _clearPendingModelSwitchHandoff() {
    _modelSwitchHandoffBrief = null;
    _modelSwitchHandoffConversationId = null;
  }

  bool _consumeForcePromptCompactionFlag({
    required bool forceCompaction,
    required bool hasModelSwitchHandoff,
  }) {
    final shouldForceCompaction =
        forceCompaction ||
        _forcePromptCompactionForNextRequest ||
        hasModelSwitchHandoff;
    _forcePromptCompactionForNextRequest = false;
    return shouldForceCompaction;
  }

  void _addModelSwitchHandoffPromptMessage(
    List<Message> promptMessages,
    String? brief,
  ) {
    if (brief == null) return;
    promptMessages.add(
      Message(
        id: 'system_model_handoff',
        content: brief,
        role: MessageRole.system,
        timestamp: DateTime.now(),
      ),
    );
  }

  Set<String> _contextSurgeryProtectedPaths() {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (conversation == null) return const <String>{};
    final task = ConversationPlanExecutionCoordinator.executionFocusTask(
      conversation,
    );
    if (task == null) return const <String>{};
    return task.targetFiles
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet();
  }

  void _updateContextSurgeryObservation({
    String? systemPrompt,
    List<ToolResultInfo>? toolResults,
  }) {
    if (!ref.mounted) return;
    if (systemPrompt != null) {
      _latestObservedSystemPrompt = systemPrompt;
    }
    if (toolResults != null) {
      _latestObservedToolResults = List<ToolResultInfo>.unmodifiable(
        toolResults,
      );
    }
    final snapshot = ContextSurgeryObservationService.buildSnapshot(
      systemPrompt: _latestObservedSystemPrompt,
      toolResults: _latestObservedToolResults,
    );
    if (state.contextSurgerySnapshot == snapshot) return;
    state = state.copyWith(contextSurgerySnapshot: snapshot);
  }
}
