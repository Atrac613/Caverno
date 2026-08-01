part of 'file_rollback_checkpoint_store.dart';

extension FileRollbackStoreLifecycle on FileRollbackCheckpointStore {
  void clearAll() {
    mutationPathFence.clearAll();
    _clearStoredState();
  }

  /// Retires all owners and drains active filesystem effects before disposal.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    final drain = mutationPathFence.close();
    final conversationIds = <String>{
      ..._states.keys.map((owner) => owner.conversationId),
      ..._completedByConversation.keys,
      ..._turnPreviewBindings.values.map(
        (binding) => binding.owner.conversationId,
      ),
      ..._turnRollbackAttempts.values.map(
        (attempt) => attempt.binding.owner.conversationId,
      ),
      ..._turnRollbackRecoveries.values.map(
        (recovery) => recovery.attempt.binding.owner.conversationId,
      ),
    };
    for (final conversationId in conversationIds) {
      await retireConversation(conversationId);
    }
    await drain;
    _clearStoredState();
  }

  void _clearStoredState() {
    _states.clear();
    _completedByConversation.clear();
    _turnPreviewBindings.clear();
    _turnRollbackAttempts.clear();
    _turnRollbackRecoveries.clear();
    _recoveryReceiptByCheckpoint.clear();
    _clearedOwners.clear();
    _retiredConversationIds.clear();
  }

  bool _isRetired(ChatTurnOwner owner) =>
      _disposed ||
      _clearedOwners.contains(owner) ||
      _retiredConversationIds.contains(owner.conversationId);
}
