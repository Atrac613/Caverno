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

/// The goal a started roadmap task carries. Automatic review is opt-in for
/// dashboard starts; the model's start-task tool still only creates a thread.
ConversationGoal projectTaskGoal(
  RoadmapItemSnapshot item,
  String roadmapPath, {
  bool autoReview = false,
}) {
  final now = DateTime.now();
  return ConversationGoal(
    id: const Uuid().v4(),
    objective: projectTaskObjective(item, roadmapPath),
    projectTaskAutoReview: autoReview,
    createdAt: now,
    updatedAt: now,
  );
}

/// Creates a coding thread for a roadmap task without selecting it. A dashboard
/// start can request the review workflow when the user opens the thread; the
/// model's start-task tool leaves that flag off and sends nothing.
///
/// This is the one command path the dashboard's Start work button and the
/// model's `start_project_task` tool share, so both create identical threads.
String startProjectTask({
  required ConversationsNotifier conversations,
  required String projectId,
  required RoadmapItemSnapshot item,
  required String roadmapPath,
  bool autoReview = false,
}) => conversations
    .addBackgroundConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: projectId,
      goal: projectTaskGoal(item, roadmapPath, autoReview: autoReview),
    )
    .id;
