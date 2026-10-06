import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/turn_diff.dart';
import 'package:caverno/features/chat/domain/services/project_task_review_inspection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = ProjectTaskReviewInspection();
  final now = DateTime(2026, 10, 3);
  final task = Conversation(
    id: 'task',
    messages: const [],
    title: 'Task',
    createdAt: now,
    updatedAt: now,
    goal: ConversationGoal(
      id: 'goal',
      objective: 'Implement',
      createdAt: now,
      updatedAt: now,
      projectTaskAutoReview: true,
      projectTaskInheritedPaths: ['src/inherited.py', 'src/changed.py'],
    ),
    turnDiffs: [
      TurnDiff(
        id: 'tool',
        assistantMessageId: 'answer',
        userPromptPreview: '',
        timestamp: now,
        files: const [
          TurnDiffFile(filePath: '/repo/src/changed.py'),
          TurnDiffFile(filePath: 'src/changed.py'),
          TurnDiffFile(filePath: 'src/removed.py', isDeletedFile: true),
        ],
      ),
      TurnDiff(
        id: 'git',
        assistantMessageId: 'other',
        userPromptPreview: '',
        timestamp: now,
        source: TurnDiffSource.git,
        files: const [TurnDiffFile(filePath: '/repo/unrelated.py')],
      ),
    ],
  );
  test('uses owned and inherited paths, deduplicated in the owner project', () {
    expect(
      policy.paths(conversation: task, codeReview: true, projectRoot: '/repo'),
      ['/repo/src/changed.py', '/repo/src/inherited.py'],
    );
  });
  test('the latest capture controls deleted and recreated files', () {
    final recreated = task.copyWith(
      turnDiffs: [
        ...task.turnDiffs,
        TurnDiff(
          id: 'repair',
          assistantMessageId: 'repair',
          userPromptPreview: '',
          timestamp: now,
          files: const [TurnDiffFile(filePath: 'src/removed.py')],
        ),
      ],
    );
    expect(
      policy.paths(
        conversation: recreated,
        codeReview: true,
        projectRoot: '/repo',
      ),
      contains('/repo/src/removed.py'),
    );
  });
  test('does not bootstrap ordinary reviews or implementation turns', () {
    expect(
      policy.paths(conversation: task, codeReview: false, projectRoot: '/repo'),
      isEmpty,
    );
    expect(
      policy.paths(
        conversation: task.copyWith(goal: null),
        codeReview: true,
        projectRoot: '/repo',
      ),
      isEmpty,
    );
  });
}
