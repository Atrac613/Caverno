import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/turn_diff.dart';
import 'package:caverno/features/chat/domain/services/claims/final_answer_claim_detector.dart';
import 'package:caverno/features/chat/domain/services/project_task/project_task_captured_changes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026);
  Conversation thread({
    bool autoReview = true,
    List<String> inherited = const [],
    List<TurnDiff> diffs = const [],
  }) => Conversation(
    id: 'task',
    title: 'Task',
    messages: const [],
    createdAt: now,
    updatedAt: now,
    turnDiffs: diffs,
    goal: ConversationGoal(
      id: 'goal',
      objective: 'Price change detection',
      projectTaskAutoReview: autoReview,
      projectTaskInheritedPaths: inherited,
      createdAt: now,
      updatedAt: now,
    ),
  );
  TurnDiff diff(TurnDiffSource source) => TurnDiff(
    id: 'diff',
    assistantMessageId: 'assistant',
    userPromptPreview: 'task',
    timestamp: now,
    source: source,
    files: const [TurnDiffFile(filePath: 'test_state.py')],
  );

  test('inherited or captured task edits count as captured changes', () {
    expect(
      projectTaskHasCapturedChanges(thread(inherited: ['/repo/state.py'])),
      isTrue,
    );
    expect(
      projectTaskHasCapturedChanges(thread(diffs: [diff(TurnDiffSource.tool)])),
      isTrue,
    );
  });

  test('a plain thread, an opted-out task or git-only diffs do not', () {
    expect(projectTaskHasCapturedChanges(null), isFalse);
    expect(projectTaskHasCapturedChanges(thread()), isFalse);
    expect(
      projectTaskHasCapturedChanges(
        thread(autoReview: false, inherited: ['/repo/state.py']),
      ),
      isFalse,
    );
    expect(
      projectTaskHasCapturedChanges(thread(diffs: [diff(TurnDiffSource.git)])),
      isFalse,
    );
  });

  test('captured changes keep the unexecuted-write guard from firing', () {
    // Session bf893af7: the subtask title said "create unit tests" (作成),
    // the answer reported the passing tests, and the guard injected an
    // unexecuted write that rejected the completion.
    const detector = FinalAnswerClaimDetector();
    const request = '5. [now] 価格変動検出のユニットテストを作成する';
    const answer =
        '全 106 テストがパスしました。価格変動検出関連のテストカバレッジをまとめます。\n'
        '**サブタスク5「価格変動検出のユニットテストを作成する」— 完了確認**\n'
        '価格変動検出関連のテストは既に3ファイルに58件存在します。';
    expect(
      detector.buildUnexecutedFileSideEffectToolResult(
        candidateResponse: answer,
        toolResults: const [],
        latestUserContent: request,
      ),
      isNotNull,
      reason: 'the guard still fires without structural evidence',
    );
    expect(
      detector.buildUnexecutedFileSideEffectToolResult(
        candidateResponse: answer,
        toolResults: const [],
        latestUserContent: request,
        fileChangesAlreadyCaptured: projectTaskHasCapturedChanges(
          thread(inherited: ['/repo/test_state.py']),
        ),
      ),
      isNull,
    );
  });
}
