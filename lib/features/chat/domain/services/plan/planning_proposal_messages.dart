import '../../entities/message.dart';

/// Gives proposal system and user messages the same request timestamp.
abstract final class PlanningProposalMessages {
  static List<Message> workflow({
    required Message system,
    required String content,
  }) => _build('workflow_proposal', system, content);
  static List<Message> task({
    required Message system,
    required String content,
  }) => _build('task_proposal', system, content);
  static List<Message> _build(String prefix, Message system, String content) {
    final now = DateTime.now();
    return [
      system.copyWith(id: '${prefix}_system', timestamp: now),
      Message(
        id: '${prefix}_user',
        role: MessageRole.user,
        timestamp: now,
        content: content,
      ),
    ];
  }
}
