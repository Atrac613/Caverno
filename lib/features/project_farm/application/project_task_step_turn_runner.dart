import '../../chat/domain/entities/chat_turn_owner.dart';
import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/conversation_goal.dart';

/// Sends a project-task turn that is not judged by goal completion: a subtask
/// turn before the last one, or the post-review commit turn.
///
/// [admits] decides from the goal whether the turn may start. The workflow
/// checks the outcome from the response marker or from git, never from the
/// goal status.
///
/// When [reactivateCompleted] is set, a goal an earlier subtask turn marked
/// completed is reopened first: the prompt tells the model not to complete it
/// before the last subtask, but nothing enforces that, and a goal completed
/// early would otherwise stop the remaining subtasks.
final class ProjectTaskStepTurnRunner {
  const ProjectTaskStepTurnRunner({
    required this.readConversation,
    required this.isSelected,
    required this.isWaitingForUser,
    required this.admits,
    required this.sendTurn,
    required this.waitForCompletion,
    this.reactivateCompleted,
  });

  /// Subtask turns run only while the goal is still being worked on.
  static bool activeGoal(ConversationGoal goal) =>
      goal.enabled &&
      goal.status == ConversationGoalStatus.active &&
      !goal.budgetExceeded;

  /// The commit turn runs only after implementation completed the goal.
  static bool completedGoal(ConversationGoal goal) =>
      goal.status == ConversationGoalStatus.completed;

  final Conversation? Function() readConversation;
  final bool Function() isSelected;
  final bool Function() isWaitingForUser;
  final bool Function(ConversationGoal goal) admits;
  final Future<ChatTurnOwner?> Function(String prompt) sendTurn;
  final Future<void> Function(ChatTurnOwner) waitForCompletion;
  final Future<void> Function()? reactivateCompleted;

  Future<bool> send(String prompt) async {
    if (!isSelected() || isWaitingForUser()) return false;
    final reactivate = reactivateCompleted;
    if (reactivate != null &&
        readConversation()?.goal?.status == ConversationGoalStatus.completed) {
      await reactivate();
      if (!isSelected() || isWaitingForUser()) return false;
    }
    final goal = readConversation()?.goal;
    if (goal == null || !admits(goal)) return false;
    final owner = await sendTurn(prompt);
    if (owner == null || owner.conversationId != readConversation()?.id) {
      return false;
    }
    await waitForCompletion(owner);
    return isSelected() && !isWaitingForUser();
  }
}
