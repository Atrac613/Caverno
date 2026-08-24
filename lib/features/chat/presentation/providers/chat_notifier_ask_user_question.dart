// Same-library extension; see chat_notifier_git_handlers.dart for rationale.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierAskUserQuestion on ChatNotifier {
  AskUserQuestionToolRuntimeAdapter _buildAskUserQuestionRuntime() =>
      AskUserQuestionToolRuntimeAdapter(
        cache: _askUserQuestionTurnCache,
        terminalResponsePolicy: _terminalToolResponsePolicy,
        ownerIsCurrent: _isAskUserQuestionOwnerCurrent,
        startQuestion: _startAskUserQuestionUi,
        cancelQuestion: _cancelAskUserQuestionUi,
      );

  Future<McpToolResult> _handleAskUserQuestion(
    ToolCallInfo toolCall, {
    int? interactionGeneration,
  }) async {
    final owner = interactionGeneration == null
        ? null
        : _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) {
      return _turnOwnerSnapshotUnavailableResult(toolCall.name);
    }
    final savedTask = _turnOwnerSnapshotForGeneration(
      owner.interactionGeneration,
    )?.savedTask;
    return _askUserQuestionRuntime.handle(
      owner: owner,
      toolCall: toolCall,
      savedTask: savedTask,
    );
  }

  bool _isAskUserQuestionOwnerCurrent(
    AskUserQuestionOperationIdentity identity,
  ) {
    return _activeResponseRegistry.containsOwner(identity.owner);
  }

  AskUserQuestionUiStartAcknowledgement _startAskUserQuestionUi(
    AskUserQuestionOperationIdentity identity,
    AskUserQuestionRequest request,
  ) {
    if (!_isAskUserQuestionOwnerCurrent(identity)) {
      return AskUserQuestionUiStartAcknowledgement.ownerRetired(
        identity: identity,
      );
    }
    if (_pendingAskUserQuestionsByThread.containsKey(
      identity.owner.conversationId,
    )) {
      return AskUserQuestionUiStartAcknowledgement.alreadyPending(
        identity: identity,
      );
    }

    final answer = requestAskUserQuestion(
      question: request.question,
      help: request.help,
      options: request.options,
      allowMultiple: request.allowMultiple,
      allowOther: request.allowOther,
      otherPlaceholder: request.otherPlaceholder,
      targetConversationId: identity.owner.conversationId,
    );
    final pending =
        _pendingAskUserQuestionsByThread[identity.owner.conversationId];
    if (pending == null) {
      return AskUserQuestionUiStartAcknowledgement.alreadyPending(
        identity: identity,
      );
    }
    return AskUserQuestionUiStartAcknowledgement.started(
      identity: identity,
      pendingQuestionId: pending.id,
      completion: answer.then((value) {
        if (!_isAskUserQuestionOwnerCurrent(identity)) {
          return AskUserQuestionUiCompletionAcknowledgement.ownerRetired(
            identity: identity,
            pendingQuestionId: pending.id,
          );
        }
        if (value == null) {
          return AskUserQuestionUiCompletionAcknowledgement.cancelled(
            identity: identity,
            pendingQuestionId: pending.id,
          );
        }
        return AskUserQuestionUiCompletionAcknowledgement.answered(
          identity: identity,
          pendingQuestionId: pending.id,
          answer: value,
        );
      }),
    );
  }

  AskUserQuestionUiCancellationAcknowledgement _cancelAskUserQuestionUi(
    AskUserQuestionOperationIdentity identity,
    String pendingQuestionId,
  ) {
    final pending =
        _pendingAskUserQuestionsByThread[identity.owner.conversationId];
    if (pending == null) {
      return AskUserQuestionUiCancellationAcknowledgement(
        identity: identity,
        pendingQuestionId: pendingQuestionId,
        disposition: AskUserQuestionUiCancellationDisposition.alreadySettled,
      );
    }
    if (pending.id != pendingQuestionId) {
      return AskUserQuestionUiCancellationAcknowledgement(
        identity: identity,
        pendingQuestionId: pendingQuestionId,
        disposition: AskUserQuestionUiCancellationDisposition.rejected,
      );
    }
    resolveAskUserQuestion(id: pendingQuestionId);
    return AskUserQuestionUiCancellationAcknowledgement(
      identity: identity,
      pendingQuestionId: pendingQuestionId,
      disposition: AskUserQuestionUiCancellationDisposition.cancelled,
    );
  }

  Future<AskUserQuestionAnswer?> requestAskUserQuestion({
    required String question,
    required String help,
    required List<AskUserQuestionOption> options,
    required bool allowMultiple,
    required bool allowOther,
    required String otherPlaceholder,
    String? targetConversationId,
  }) {
    final resolvedTargetConversationId =
        targetConversationId ?? _activeResponseConversationId ?? conversationId;
    final existingPending = resolvedTargetConversationId == null
        ? state.pendingAskUserQuestion
        : _pendingAskUserQuestionsByThread[resolvedTargetConversationId];
    if (existingPending != null) {
      appLog('[AskUserQuestion] Ignoring question while another is pending');
      return Future<AskUserQuestionAnswer?>.value();
    }
    final completer = Completer<AskUserQuestionAnswer?>();
    final pending = PendingAskUserQuestion(
      id: const Uuid().v4(),
      conversationId: resolvedTargetConversationId,
      question: question,
      help: help,
      options: options,
      allowMultiple: allowMultiple,
      allowOther: allowOther,
      otherPlaceholder: otherPlaceholder,
      completer: completer,
      origin: _activeInteractionOrigin,
      remoteDeviceId: _activeRemoteDeviceId,
    );
    if (resolvedTargetConversationId != null) {
      _pendingAskUserQuestionsByThread[resolvedTargetConversationId] = pending;
    }
    if (resolvedTargetConversationId == null ||
        conversationId == resolvedTargetConversationId) {
      state = state.copyWith(pendingAskUserQuestion: pending);
    }
    _runtimeEvents.emitRuntimeQuestionRequired(
      _runtimeEventGeneration,
      CavernoRuntimeQuestionRequest(
        id: pending.id,
        prompt: pending.question,
        options: pending.options
            .map((option) => option.label)
            .toList(growable: false),
        multiple: pending.allowMultiple,
      ),
    );
    return completer.future;
  }

  void resolveAskUserQuestion({
    required String id,
    AskUserQuestionAnswer? answer,
  }) {
    final pending = state.pendingAskUserQuestion?.id == id
        ? state.pendingAskUserQuestion
        : _pendingAskUserQuestionsByThread.values
              .where((item) => item.id == id)
              .firstOrNull;
    if (pending == null) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(answer);
    }
    final pendingConversationId = pending.conversationId;
    if (pendingConversationId != null) {
      _pendingAskUserQuestionsByThread.remove(pendingConversationId);
    }
    if (state.pendingAskUserQuestion?.id == id) {
      state = state.copyWith(pendingAskUserQuestion: null);
    }
  }

  void _dismissPendingAskUserQuestionForConversation(
    String ownerConversationId,
  ) {
    final pending = _pendingAskUserQuestionsByThread.remove(
      ownerConversationId,
    );
    if (pending == null) return;
    if (!pending.completer.isCompleted) pending.completer.complete();
    if (state.pendingAskUserQuestion?.id != pending.id) return;
    state = state.copyWith(pendingAskUserQuestion: null);
  }

  void _dismissAllPendingAskUserQuestions() {
    final pendingQuestions = _pendingAskUserQuestionsByThread.values.toSet();
    final visiblePending = state.pendingAskUserQuestion;
    if (visiblePending != null) pendingQuestions.add(visiblePending);
    for (final pending in pendingQuestions) {
      if (!pending.completer.isCompleted) pending.completer.complete();
    }
    _pendingAskUserQuestionsByThread.clear();
    if (visiblePending == null) return;
    state = state.copyWith(pendingAskUserQuestion: null);
  }
}
