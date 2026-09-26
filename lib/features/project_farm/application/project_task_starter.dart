import '../../../core/types/workspace_mode.dart';
import '../../chat/domain/entities/conversation_goal.dart';
import '../../chat/presentation/providers/conversations_notifier.dart';
import '../domain/entities/roadmap_snapshot.dart';

/// The goal objective a started roadmap task carries, citing its source so the
/// thread can reread the roadmap instead of trusting the summary.
String projectTaskObjective(RoadmapItemSnapshot item, String roadmapPath) {
  final heading = [
    if (item.id.trim().isNotEmpty) item.id.trim(),
    if (item.title.trim().isNotEmpty) item.title.trim(),
  ].join(': ');
  final citation = item.line == null
      ? roadmapPath
      : '$roadmapPath:${item.line}';
  return '$heading\n\nSource: $citation\n"${item.quote.trim()}"';
}

/// Starts work on a roadmap task: a new coding thread in the project whose goal
/// is the task. Nothing is sent; the user reviews the goal and sends, or
/// enters Plan Mode, from the thread.
///
/// This is the one command path the dashboard's Start work button and, from
/// FARM2, the model's `start_project_task` tool share.
Future<String?> startProjectTask({
  required ConversationsNotifier conversations,
  required ConversationsState Function() readConversations,
  required String projectId,
  required RoadmapItemSnapshot item,
  required String roadmapPath,
}) async {
  conversations.createNewConversation(
    workspaceMode: WorkspaceMode.coding,
    projectId: projectId,
  );
  final created = readConversations().currentConversation;
  if (created == null || created.normalizedProjectId != projectId) {
    return null;
  }
  await conversations.saveCurrentGoal(
    objective: projectTaskObjective(item, roadmapPath),
    enabled: true,
    status: ConversationGoalStatus.active,
  );
  return created.id;
}
