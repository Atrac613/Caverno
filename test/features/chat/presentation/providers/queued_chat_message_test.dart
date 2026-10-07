import 'package:caverno/features/chat/presentation/providers/queued_chat_message.dart';
import 'package:caverno/features/project_farm/domain/entities/project_task_commit_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  QueuedChatMessage queued(ProjectTaskCommitScope? scope) => QueuedChatMessage(
    id: 'queued',
    content: 'Commit',
    imageBase64: null,
    imageMimeType: null,
    languageCode: 'en',
    isVoiceMode: false,
    bypassPlanMode: true,
    conversationId: 'task',
    projectTaskCommitScope: scope,
  );
  test(
    'queued scope survives the enqueue zone without leaking into another message',
    () {
      final scope = ProjectTaskCommitScope(
        conversationId: 'task',
        projectRoot: '/repo',
        roadmapPath: '/repo/roadmap.md',
        reviewedPaths: ['/repo/task.txt'],
      );
      final message = ProjectTaskCommitScope.enqueue(
        scope,
        () => queued(ProjectTaskCommitScope.forEnqueue),
      );
      expect(ProjectTaskCommitScope.forEnqueue, isNull);
      expect(message.projectTaskCommitScope, same(scope));
      final duplicate = queued(scope);
      expect(message, duplicate);
      expect(message.hashCode, duplicate.hashCode);
      expect(message, isNot(queued(null)));
    },
  );
}
