import 'package:uuid/uuid.dart';

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

/// The goal a started roadmap task carries. Auto-continue stays off: nothing
/// runs until the user sends from the thread.
ConversationGoal projectTaskGoal(RoadmapItemSnapshot item, String roadmapPath) {
  final now = DateTime.now();
  return ConversationGoal(
    id: const Uuid().v4(),
    objective: projectTaskObjective(item, roadmapPath),
    createdAt: now,
    updatedAt: now,
  );
}

/// Starts work on a roadmap task: a new coding thread in the project whose goal
/// is the task, added without switching threads. Nothing is sent; the caller
/// decides whether to open it (the dashboard does, the model's tool does not).
///
/// This is the one command path the dashboard's Start work button and the
/// model's `start_project_task` tool share, so both create identical threads.
String startProjectTask({
  required ConversationsNotifier conversations,
  required String projectId,
  required RoadmapItemSnapshot item,
  required String roadmapPath,
}) => conversations
    .addBackgroundConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: projectId,
      goal: projectTaskGoal(item, roadmapPath),
    )
    .id;
