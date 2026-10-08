import '../../entities/message.dart';
import '../../entities/turn_diff.dart';

/// The turn diffs whose assistant message is still in [messages], so a rewind
/// drops the diffs of the turns it removed.
List<TurnDiff> retainTurnDiffsForMessages(
  List<TurnDiff> turnDiffs,
  List<Message> messages,
) {
  final retainedAssistantMessageIds = messages
      .where((message) => message.role == MessageRole.assistant)
      .map((message) => message.id)
      .toSet();
  if (retainedAssistantMessageIds.isEmpty) {
    return const [];
  }
  return turnDiffs
      .where(
        (diff) => retainedAssistantMessageIds.contains(diff.assistantMessageId),
      )
      .toList(growable: false);
}
