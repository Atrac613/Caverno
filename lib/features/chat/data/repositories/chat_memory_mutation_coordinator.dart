/// Coordinates one complete chat-memory mutation across frontend processes.
abstract interface class ChatMemoryMutationCoordinator {
  Future<T> run<T>(Future<T> Function() mutation);
}

/// Executes mutations directly when cross-process coordination is unavailable.
final class DirectChatMemoryMutationCoordinator
    implements ChatMemoryMutationCoordinator {
  const DirectChatMemoryMutationCoordinator();

  @override
  Future<T> run<T>(Future<T> Function() mutation) => mutation();
}
