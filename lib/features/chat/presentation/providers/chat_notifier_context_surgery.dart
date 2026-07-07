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
    final routeChanged =
        _modelSwitchRouteKey(previousSettings) !=
        _modelSwitchRouteKey(settings);
    if (routeChanged) {
      _pendingPrimaryModelPreparation = _PendingPrimaryModelPreparation(
        key: _primaryModelPreparationKey(settings),
        previousModelId: _previousPrimaryModelForPreparation(
          previousSettings,
          settings,
        ),
      );
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

  String? _previousPrimaryModelForPreparation(
    AppSettings previousSettings,
    AppSettings nextSettings,
  ) {
    if (previousSettings.llmProvider != LlmProvider.openAiCompatible ||
        nextSettings.llmProvider != LlmProvider.openAiCompatible ||
        previousSettings.demoMode ||
        nextSettings.demoMode) {
      return null;
    }
    if (previousSettings.baseUrl.trim() != nextSettings.baseUrl.trim() ||
        previousSettings.apiKey.trim() != nextSettings.apiKey.trim()) {
      return null;
    }

    final previousModel = previousSettings.model.trim();
    final nextModel = nextSettings.model.trim();
    if (previousModel.isEmpty || previousModel == nextModel) {
      return null;
    }
    return previousModel;
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

  /// Collects the tool definitions offered for the current request plus the
  /// external MCP tool names, appending discovered names to [toolNames] when no
  /// override is supplied. Feeds the context window breakdown's System tools /
  /// MCP tools rows. Lives here (not in chat_notifier.dart) to keep that file
  /// within its F1 line-count budget.
  ({List<Map<String, dynamic>> definitions, Set<String> mcpNames})
  _collectRequestToolObservation({
    required List<String>? toolNamesOverride,
    required List<String> toolNames,
  }) {
    final mcpToolService = _mcpToolService;
    if (mcpToolService == null ||
        !(toolNamesOverride != null ||
            _settings.mcpEnabled ||
            _temporalReferenceContext != null)) {
      return (definitions: const [], mcpNames: const {});
    }

    final allDefinitions = mcpToolService.getOpenAiToolDefinitions();
    final mcpNames = _externalMcpToolNames(mcpToolService);
    if (toolNamesOverride == null) {
      for (final tool in allDefinitions) {
        final function = tool['function'];
        if (function is Map) {
          final name = function['name'];
          if (name is String && name.isNotEmpty) {
            toolNames.add(name);
          }
        }
      }
      return (definitions: allDefinitions, mcpNames: mcpNames);
    }

    // Overrides carry only names; recover the matching definitions from the
    // full catalog so the sent tool payload is measured accurately.
    final effectiveNames = toolNames.toSet();
    final definitions = allDefinitions
        .where((definition) {
          final function = definition['function'];
          if (function is! Map) return false;
          final name = function['name'];
          return name is String && effectiveNames.contains(name);
        })
        .toList(growable: false);
    return (definitions: definitions, mcpNames: mcpNames);
  }

  Set<String> _externalMcpToolNames(McpToolService mcpToolService) {
    if (mcpToolService.status != McpConnectionStatus.connected) {
      return const <String>{};
    }
    final names = <String>{};
    for (final tool in mcpToolService.tools) {
      final function = tool.toOpenAiTool()['function'];
      if (function is Map) {
        final name = function['name'];
        if (name is String && name.isNotEmpty) {
          names.add(name);
        }
      }
    }
    return names;
  }

  void _updateContextSurgeryObservation({
    String? systemPrompt,
    List<ToolResultInfo>? toolResults,
    List<Map<String, dynamic>>? toolDefinitions,
    Set<String>? mcpToolNames,
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
    if (toolDefinitions != null) {
      _latestObservedToolDefinitions = List<Map<String, dynamic>>.unmodifiable(
        toolDefinitions,
      );
    }
    if (mcpToolNames != null) {
      _latestObservedMcpToolNames = Set<String>.unmodifiable(mcpToolNames);
    }
    final snapshot = ContextSurgeryObservationService.buildSnapshot(
      systemPrompt: _latestObservedSystemPrompt,
      toolResults: _latestObservedToolResults,
      toolDefinitions: _latestObservedToolDefinitions,
      mcpToolNames: _latestObservedMcpToolNames,
    );
    if (state.contextSurgerySnapshot == snapshot) return;
    state = state.copyWith(contextSurgerySnapshot: snapshot);
  }
}
