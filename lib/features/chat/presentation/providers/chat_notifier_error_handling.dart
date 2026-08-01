// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierErrorHandling on ChatNotifier {
  Future<void> _handleTurnOwnerSnapshotUnavailable(int generation) async {
    final owner = _activeResponseRegistry.ownerForGeneration(generation);
    if (owner == null) {
      appLog(
        '[ChatNotifier] Turn owner snapshot unavailable for unregistered '
        'generation $generation',
      );
      _failRuntimeTurn(
        generation,
        code: 'turn_owner_snapshot_unavailable',
        message: 'Turn owner snapshot unavailable',
      );
      return;
    }
    await _handleError('Turn owner snapshot unavailable', owner: owner);
  }

  Future<void> _handleError(
    Object error, {
    required ChatTurnOwner owner,
  }) async {
    appLog('[ChatNotifier] _handleError called');
    appLog('[ChatNotifier]   raw error: $error');
    final displayError = ChatErrorMessageBuilder.build(
      error.toString(),
      baseUrl: _settings.baseUrl,
    );
    if (!_activeResponseRegistry.containsOwner(owner)) {
      final runtimeFailure = _runtimeFailureClassifier.classify(
        error.toString(),
      );
      _failRuntimeTurn(
        owner.interactionGeneration,
        code: runtimeFailure.code,
        message: displayError,
        exitCode: runtimeFailure.exitCode,
      );
      appLog('[ChatNotifier]   terminalized unregistered runtime owner');
      return;
    }

    appLog('[ChatNotifier]   displayError: $displayError');

    final updatedMessages = TurnErrorMessageProjection.apply(
      messages:
          _activeResponseRegistry.messagesForOwner(owner) ?? const <Message>[],
      displayError: displayError,
      createAssistant: () => Message(
        id: _uuid.v4(),
        content: '',
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
        error: displayError,
      ),
    );

    _activeResponseRegistry.cacheMessagesForOwner(owner, updatedMessages);
    final ownerIsVisible = conversationId == owner.conversationId;
    if (ownerIsVisible && ref.mounted) {
      state = state.copyWith(
        messages: updatedMessages,
        isLoading: false,
        error: displayError,
      );
    }
    final runtimeFailure = _runtimeFailureClassifier.classify(error.toString());
    _failRuntimeTurn(
      owner.interactionGeneration,
      code: runtimeFailure.code,
      message: displayError,
      exitCode: runtimeFailure.exitCode,
    );
    if (owner.interactionGeneration == _interactionGeneration) {
      _clearTurnDiffCapture();
    }
    if (!ref.mounted) return;
    if (ownerIsVisible) {
      _dispatchExternalToolHook('Stop', error: displayError);
    }
    final messagesToSave = updatedMessages
        .where((message) => !message.isStreaming)
        .where(
          (message) =>
              message.error != null ||
              _messagePersistence.shouldKeepVisibleMessage(message),
        )
        .toList(growable: false);
    if (messagesToSave.isNotEmpty) {
      try {
        await _messagePersistence.persistMessages(
          owner.conversationId,
          messagesToSave,
        );
      } catch (persistenceError) {
        appLog(
          '[ChatNotifier] Failed to persist turn error for '
          '${owner.conversationId}: $persistenceError',
        );
      }
    }
  }
}
