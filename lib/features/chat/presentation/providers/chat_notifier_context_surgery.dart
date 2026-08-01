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
      _pendingPrimaryModelPreparation = _PendingPrimaryModelPreparation(
        key: _primaryModelPreparationKey(settings),
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
