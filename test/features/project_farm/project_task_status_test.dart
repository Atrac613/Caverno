import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/turn_diff.dart';
import 'package:caverno/features/project_farm/domain/entities/project_task_git_state.dart';
import 'package:caverno/features/project_farm/domain/project_task_progress.dart';
import 'package:caverno/features/project_farm/domain/project_task_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026);
  const subtasks = [
    ConversationWorkflowTask(id: 's1', title: 'One'),
    ConversationWorkflowTask(id: 's2', title: 'Two'),
  ];
  const reviewed = [
    TurnDiffFile(filePath: 'lib/a.dart', unifiedPatch: '@@\n-a\n+b'),
  ];
  const fixedByHand = [
    TurnDiffFile(filePath: 'lib/a.dart', unifiedPatch: '@@\n-a\n+c'),
  ];
  const dirty = ProjectTaskGitState(head: 'h', dirtyPaths: [' M lib/a.dart']);
  const clean = ProjectTaskGitState(head: 'h2', dirtyPaths: []);

  Conversation task({
    Set<String> done = const {'s1', 's2'},
    ProjectTaskReviewState review = ProjectTaskReviewState.none,
    List<TurnDiffFile> reviewedPatch = reviewed,
    bool autoReview = true,
  }) => Conversation(
    id: 't',
    title: 'Task',
    createdAt: now,
    updatedAt: now,
    messages: [
      Message(
        id: 'm',
        content: 'Done.',
        role: MessageRole.assistant,
        timestamp: now,
      ),
    ],
    workflowSpec: const ConversationWorkflowSpec(goal: 'g', tasks: subtasks),
    executionProgress: [
      for (final id in done)
        ConversationExecutionTaskProgress(
          taskId: id,
          status: ConversationWorkflowTaskStatus.completed,
        ),
    ],
    turnDiffs: [
      TurnDiff(
        id: 'd',
        assistantMessageId: 'm',
        userPromptPreview: 'task',
        timestamp: now,
        files: reviewed,
      ),
    ],
    goal: ConversationGoal(
      id: 'g',
      objective: 'Implement',
      projectTaskAutoReview: autoReview,
      projectTaskReview: review,
      projectTaskReviewedPatch: review == ProjectTaskReviewState.none
          ? ''
          : ProjectTaskStatus.fingerprint(reviewedPatch),
      createdAt: now,
      updatedAt: now,
    ),
  );

  ProjectTaskOutcome? outcome(
    Conversation task, {
    ProjectTaskGitState? git = dirty,
    List<TurnDiffFile>? patch = reviewed,
  }) => ProjectTaskStatus.derive(
    task,
    git: git,
    patch: patch == null ? null : ProjectTaskStatus.fingerprint(patch),
  )?.outcome;

  test('is null for a thread that is not a started roadmap task', () {
    expect(outcome(task(autoReview: false)), isNull);
  });

  test('pauses on the first unfinished subtask', () {
    final status = ProjectTaskStatus.derive(task(done: {'s1'}), git: dirty);
    expect(status?.outcome, ProjectTaskOutcome.paused);
    expect(status?.phase, ProjectTaskPhase.implement);
    expect(status?.subtaskIndex, 1);
    expect(status?.completedSubtasks, 1);
  });

  test('is unreviewed when no review has been recorded', () {
    expect(outcome(task()), ProjectTaskOutcome.unreviewed);
  });

  test('keeps findings while the reviewed patch is unchanged', () {
    expect(
      outcome(task(review: ProjectTaskReviewState.findings)),
      ProjectTaskOutcome.findingsRemain,
    );
  });

  test('a fix made after the review reads as unreviewed', () {
    expect(
      outcome(
        task(review: ProjectTaskReviewState.findings),
        patch: fixedByHand,
      ),
      ProjectTaskOutcome.unreviewed,
    );
  });

  test('is ready to commit when a clean review covered the change', () {
    expect(
      outcome(task(review: ProjectTaskReviewState.clean)),
      ProjectTaskOutcome.readyToCommit,
    );
  });

  test('is committed once the task files are clean, however committed', () {
    expect(
      outcome(task(review: ProjectTaskReviewState.findings), git: clean),
      ProjectTaskOutcome.committed,
    );
  });

  test('an unreadable git state is never read as reviewed or committed', () {
    expect(
      outcome(
        task(review: ProjectTaskReviewState.clean),
        git: null,
        patch: null,
      ),
      ProjectTaskOutcome.unreviewed,
    );
  });

  test('the fingerprint ignores file order', () {
    const other = TurnDiffFile(filePath: 'lib/b.dart', unifiedPatch: '+x');
    expect(
      ProjectTaskStatus.fingerprint([...reviewed, other]),
      ProjectTaskStatus.fingerprint([other, ...reviewed]),
    );
  });
}
