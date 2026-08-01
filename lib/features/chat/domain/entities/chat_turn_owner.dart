final class ChatTurnOwner {
  ChatTurnOwner({
    required String conversationId,
    required this.interactionGeneration,
  }) : conversationId = conversationId.trim() {
    if (this.conversationId.isEmpty) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'Conversation ID must not be empty.',
      );
    }
    if (interactionGeneration < 1) {
      throw ArgumentError.value(
        interactionGeneration,
        'interactionGeneration',
        'Interaction generation must be positive.',
      );
    }
  }

  final String conversationId;
  final int interactionGeneration;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ChatTurnOwner &&
            other.conversationId == conversationId &&
            other.interactionGeneration == interactionGeneration;
  }

  @override
  int get hashCode => Object.hash(conversationId, interactionGeneration);

  @override
  String toString() {
    return 'ChatTurnOwner('
        'conversationId: $conversationId, '
        'interactionGeneration: $interactionGeneration'
        ')';
  }
}
