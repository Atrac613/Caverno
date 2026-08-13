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
    final comparison = const ModelSwitchSettingsPolicy().compare(
      previous: previousSettings,
      next: settings,
    );
    if (comparison.routeChanged) {
      _primaryRoutePreparer.notePrimaryRouteChange(
        settings: settings,
        previousModelId: comparison.previousPrimaryModelForPreparation,
      );
      _scheduleModelSwitchHandoff(
        previousSettings: previousSettings,
        nextSettings: settings,
      );
    }
    _settings = settings;
    if (comparison.shouldRebuildDataSource) {
      _dataSource = _withChatSessionLogging(
        ref.read(chatRemoteDataSourceProvider),
        settings,
      );
    }
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
    _modelSwitchHandoffs.schedule(
      conversation: conversation,
      messages: messages,
      previousModel: previousSettings.effectiveModel,
      nextModel: nextSettings.effectiveModel,
    );
  }

  void _updateContextSurgeryObservation({
    required ChatTurnOwner owner,
    String? systemPrompt,
    List<ToolResultInfo>? toolResults,
    List<Map<String, dynamic>>? toolDefinitions,
    Set<String>? mcpToolNames,
  }) {
    if (!ref.mounted) return;
    final result = _contextSurgeryObservations.apply(
      owner: owner,
      update: ContextSurgeryObservationUpdate(
        systemPrompt: systemPrompt,
        toolResults: toolResults,
        toolDefinitions: toolDefinitions,
        mcpToolNames: mcpToolNames,
      ),
    );
    if (!result.changed) return;
    _routeThreadState(
      owner.conversationId,
      (threadState) =>
          threadState.copyWith(contextSurgerySnapshot: result.snapshot),
    );
  }
}

final Expando<PrimaryTurnRouteRuntime> _primaryRouteRuntimes = Expando();
final Expando<PrimaryRouteModelPreparer> _primaryRoutePreparers = Expando();

extension ChatNotifierPrimaryModelRouting on ChatNotifier {
  PrimaryTurnRouteRuntime get _primaryRoutes =>
      _primaryRouteRuntimes[this] ??= PrimaryTurnRouteRuntime();

  PrimaryRouteModelPreparer get _primaryRoutePreparer =>
      _primaryRoutePreparers[this] ??= PrimaryRouteModelPreparer(
        serviceFactory: ref.read(primaryModelPreparationServiceFactoryProvider),
        logOutcome: (outcome) => appLog(
          '[LL24] Primary route model ${outcome.modelId}: ${outcome.status.name} (${outcome.message})',
        ),
        logError: (error, stackTrace) {
          appLog(
            '[LL24] Primary route model preparation failed: ${error.runtimeType}: $error',
          );
          appLog('[LL24] stackTrace: $stackTrace');
        },
      );

  Future<void> _capturePrimaryTurnRoute({
    required ChatTurnOwner owner,
    required Conversation? conversation,
    required bool bypassPlanMode,
  }) => _primaryRoutes.capture(
    generation: owner.interactionGeneration,
    settings: _settings,
    assistantMode: bypassPlanMode
        ? AssistantMode.coding
        : _resolveAssistantMode(currentConversation: conversation),
    primaryDataSource: _dataSource,
    health: ref.read(endpointHealthTrackerProvider),
    buildAssignedDataSource: (endpoint) => _withChatSessionLogging(
      ref.read(primaryRouteEndpointDataSourceFactoryProvider)(
        baseUrl: endpoint.baseUrl,
        apiKey: endpoint.apiKey,
        endpointId: endpoint.endpointId,
      ),
      _settings,
    ),
    preparer: _primaryRoutePreparer,
    record: (resolution) => recordPrimaryTurnRoute(
      store: ref.read(llmSessionLogStoreProvider),
      context: _llmSessionLogContextForGeneration(owner.interactionGeneration),
      generation: owner.interactionGeneration,
      resolution: resolution,
      enabled: _settings.enableLlmSessionLogs,
    ),
  );

  ChatDataSource _primaryDataSourceForGeneration(int generation) =>
      _primaryRoutes.dataSource(generation, _dataSource);
  String _primaryModelForGeneration(int generation) =>
      _primaryRoutes.model(generation, _settings);
  ModelCapabilityProfile? _primaryCapabilityProfileForGeneration(
    int? generation,
  ) => _primaryRoutes.capabilityProfile(generation, _settings);
  ModelHarnessConfig? _primaryHarnessConfigForGeneration(int? generation) =>
      _primaryRoutes.harnessConfig(generation, _settings);
  double _primaryAssistantTemperatureForGeneration(int generation) =>
      _primaryRoutes
          .temperaturePolicy(generation, _settings)
          .temperatureForAssistantMode(
            _primaryRoutes.assistantMode(generation, _settings),
          );
  double _primaryAgenticTemperatureForGeneration(int generation) =>
      _primaryRoutes
          .temperaturePolicy(generation, _settings)
          .agenticTemperature;
  void _releasePrimaryTurnRoute(ChatTurnOwner owner) =>
      _primaryRoutes.release(owner.interactionGeneration);
  @visibleForTesting
  int primaryRouteCountForTest() => _primaryRoutes.count;
}
