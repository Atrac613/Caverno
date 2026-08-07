import '../entities/message.dart';

/// The decisions behind mid-turn interruption, separated from the notifier
/// state they are applied to.
///
/// Everything here is a pure function of its arguments, so the rules can be
/// tested without a running turn. The notifier keeps only the plumbing: which
/// registry to read, whose messages to rewrite, where to route the state.
final class TurnSteeringPolicy {
  const TurnSteeringPolicy._();

  /// How many times one turn may abandon a stream to take an interruption.
  ///
  /// A restart re-issues the turn's request, so this is what keeps a user
  /// typing corrections faster than the model answers from looping the turn.
  static const int restartBudgetPerTurn = 2;

  /// Whether a message typed against a busy thread can join its turn.
  ///
  /// Attachments and voice are excluded, not unsupported: an image would need
  /// the vision payload plumbed through the continuation request, and voice
  /// mode already interrupts by cancelling (barge-in). Both fall back to the
  /// queue, which handles them today.
  static bool canSteer({
    required String content,
    required bool hasImage,
    required bool isVoiceMode,
  }) => content.trim().isNotEmpty && !hasImage && !isVoiceMode;

  /// Where an interruption belongs in [messages].
  ///
  /// Ahead of the reply still being written, so the transcript keeps the order
  /// the user lived through: the interruption arrived while that reply was in
  /// flight, not after it finished. Requests filter streaming messages out
  /// anyway, so this placement is for the reader, not the model.
  static int insertIndex(List<Message> messages) {
    var index = messages.length;
    while (index > 0 && messages[index - 1].isStreaming) {
      index -= 1;
    }
    return index;
  }

  /// The transcript entry for one interruption.
  static Message steeringMessage({
    required String id,
    required String content,
    required DateTime receivedAt,
  }) => Message(
    id: id,
    content: content.trim(),
    role: MessageRole.user,
    timestamp: receivedAt,
  );
}
