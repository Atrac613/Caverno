import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/turn_diff.dart';
import 'package:caverno/features/project_farm/application/project_task_inheritance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const objective = '.gitignore\n\nSource: ROADMAP.md:22';

  Conversation thread(
    String id, {
    String projectId = 'watcher',
    String goalObjective = objective,
    bool autoReview = true,
    List<String> paths = const [],
    TurnDiffSource source = TurnDiffSource.tool,
    int minute = 0,
  }) {
    final at = DateTime(2026, 10, 1, 8, minute);
    return Conversation(
      id: id,
      title: id,
      messages: const [],
      createdAt: at,
      updatedAt: at,
      workspaceMode: WorkspaceMode.coding,
      projectId: projectId,
      goal: ConversationGoal(
        id: 'goal-$id',
        objective: goalObjective,
        projectTaskAutoReview: autoReview,
        createdAt: at,
        updatedAt: at,
      ),
      turnDiffs: [
        if (paths.isNotEmpty)
          TurnDiff(
            id: 'diff-$id',
            assistantMessageId: 'assistant-$id',
            userPromptPreview: 'task',
            timestamp: at,
            source: source,
            files: [
              for (final path in paths)
                TurnDiffFile(filePath: path, unifiedPatch: '@@ $path'),
            ],
          ),
      ],
    );
  }

  test(
    'carries earlier runs\' captured changes that are still dirty',
    () async {
      final task = thread('b2971ae0', minute: 30);
      final files = await inheritedTaskFiles(
        task: task,
        conversations: [
          task,
          thread('26d7db3e', paths: ['/repo/.gitignore', '/repo/clean.txt']),
          thread('other-project', projectId: 'caverno', paths: ['/repo/x']),
          thread('other-item', goalObjective: 'README', paths: ['/repo/y']),
          thread('manual', autoReview: false, paths: ['/repo/z']),
          thread('git-diff', source: TurnDiffSource.git, paths: ['/repo/g']),
        ],
        isDirty: (path) async => path != '/repo/clean.txt',
        load: (run) async => run,
      );

      expect(files.map((file) => file.filePath), ['/repo/.gitignore']);
    },
  );

  test('keeps earlier runs in creation order', () async {
    final task = thread('now', minute: 30);
    final files = await inheritedTaskFiles(
      task: task,
      conversations: [
        thread('second', paths: ['/repo/b'], minute: 20),
        thread('first', paths: ['/repo/a'], minute: 10),
      ],
      isDirty: (_) async => true,
      load: (run) async => run,
    );

    expect(files.map((file) => file.filePath), ['/repo/a', '/repo/b']);
  });

  test('loads a run held as a listing stub before reading its diffs', () async {
    // Session b58b0db0: after a relaunch the earlier run was a listing stub
    // with its turn diffs dropped, so nothing was inherited.
    final task = thread('b58b0db0', minute: 30);
    final full = thread('26d7db3e', paths: ['/repo/.gitignore']);
    final stub = full.copyWith(turnDiffs: const []);
    final loaded = <String>[];

    final files = await inheritedTaskFiles(
      task: task,
      conversations: [task, stub],
      isDirty: (_) async => true,
      load: (run) async {
        loaded.add(run.id);
        return full;
      },
    );

    expect(loaded, ['26d7db3e']);
    expect(files.map((file) => file.filePath), ['/repo/.gitignore']);
  });
}
