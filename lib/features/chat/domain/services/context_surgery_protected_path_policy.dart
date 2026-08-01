import '../entities/conversation.dart';
import 'conversation_plan_execution_coordinator.dart';

// ChatNotifier decomposition collaborator: context-surgery-protected-path-policy

final class ContextSurgeryProtectedPathPolicy {
  const ContextSurgeryProtectedPathPolicy();

  Set<String> protectedPathsFor(Conversation? conversation) {
    if (conversation == null) return const <String>{};
    final task = ConversationPlanExecutionCoordinator.executionFocusTask(
      conversation,
    );
    if (task == null) return const <String>{};
    final paths = task.targetFiles
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty);
    return paths.isEmpty ? const <String>{} : Set<String>.unmodifiable(paths);
  }
}
