import 'dart:io';

import 'package:caverno/features/project_farm/data/project_task_commit_reader.dart';
import 'package:caverno/features/project_farm/domain/entities/project_task_commit_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late ProjectTaskCommitScope scope;
  late ProjectTaskCommitSnapshot baseline;
  const reader = ProjectTaskCommitReader();
  Future<void> git(List<String> args) async {
    final result = await Process.run('git', args, workingDirectory: root.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }

  Future<void> write(String file, String text) =>
      File('${root.path}/$file').writeAsString(text);
  Future<ProjectTaskCommitSnapshot> read() async => (await reader.read(scope))!;
  Future<ProjectTaskCommitSnapshot> prepare() async {
    await write('roadmap.md', '- [x] Implement task\n');
    await git(['add', '--', 'task.txt', 'roadmap.md']);
    return read();
  }

  setUp(() async {
    final temporary = await Directory.systemTemp.createTemp('farm_commit_');
    root = Directory(temporary.resolveSymbolicLinksSync());
    await git(['init', '-q']);
    await git(['config', 'user.email', 'fixture@example.invalid']);
    await git(['config', 'user.name', 'Fixture']);
    await write('task.txt', 'before\n');
    await write('roadmap.md', '- [ ] Implement task\n');
    await write('unrelated.txt', 'before\n');
    await git(['add', '--', 'task.txt', 'roadmap.md', 'unrelated.txt']);
    await git(['-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'fixture']);
    scope = ProjectTaskCommitScope.fromObjective(
      conversationId: 'task',
      projectRoot: root.path,
      objective: 'Implement task\nSource: roadmap.md:1\n"- [ ] Implement task"',
      reviewedPaths: ['task.txt'],
    )!;
    await write('task.txt', 'reviewed\n');
    await write('unrelated.txt', 'unrelated dirty work\n');
    baseline = await read();
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'accepts staged task and completed roadmap with unrelated dirty work',
    () async {
      final prepared = await prepare();
      expect(scope.preparationProblem(baseline, prepared), isNull);
      expect(scope.authorize(prepared).commitProblem(await read()), isNull);
      expect(prepared.stagedPaths, scope.paths);
    },
  );
  test('recovery identity rejects native file and index changes', () async {
    expect(scope.sameCapturedState(baseline, await read()), isTrue);
    await write('unrelated.txt', 'another unrelated unstaged edit');
    expect(scope.sameCapturedState(baseline, await read()), isTrue);
    await write('roadmap.md', '- [x] Implement task\n');
    expect(scope.sameCapturedState(baseline, await read()), isFalse);
    await write('roadmap.md', '- [ ] Implement task\n');
    expect(scope.sameCapturedState(baseline, await read()), isTrue);
    await git(['add', '--', 'unrelated.txt']);
    expect(scope.sameCapturedState(baseline, await read()), isFalse);
  });
  test('rejects a missing roadmap update before commit', () async {
    await git(['add', '--', 'task.txt']);
    expect(
      scope.preparationProblem(baseline, await read()),
      contains('roadmap update is missing'),
    );
  });
  test(
    'a staged unrelated roadmap edit does not complete the cited task',
    () async {
      await write('roadmap.md', '- [ ] Implement task\nUnrelated note\n');
      await git(['add', '--', 'task.txt', 'roadmap.md']);
      expect(
        scope.preparationProblem(baseline, await read()),
        contains('not marked complete'),
      );
    },
  );
  test(
    'rejects partial staging and implementation changes during preparation',
    () async {
      await prepare();
      await write('task.txt', 'changed after review\n');
      expect(
        scope.preparationProblem(baseline, await read()),
        contains('reviewed task files changed'),
      );
      await git(['add', '--', 'task.txt']);
      expect(
        scope.preparationProblem(baseline, await read()),
        contains('reviewed task files changed'),
      );
    },
  );
  test('rejects an unstaged roadmap edit', () async {
    await prepare();
    await write('roadmap.md', '- [x] Implement task\nMore text\n');
    expect(
      scope.preparationProblem(baseline, await read()),
      contains('unstaged'),
    );
  });
  test('rejects unrelated staged work', () async {
    await prepare();
    await git(['add', '--', 'unrelated.txt']);
    expect(
      scope.preparationProblem(baseline, await read()),
      contains('unrelated staged'),
    );
  });
  for (final change in ['index', 'file', 'head']) {
    test('rejects $change changes after native preparation', () async {
      final authorized = scope.authorize(await prepare());
      if (change == 'index') {
        await git(['add', '--', 'unrelated.txt']);
      } else if (change == 'file') {
        await write('task.txt', 'changed while awaiting approval\n');
      } else {
        await git([
          '-c',
          'core.hooksPath=/dev/null',
          'commit',
          '-qm',
          'changed head',
        ]);
      }
      expect(authorized.commitProblem(await read()), contains('changed after'));
    });
  }
  test('already completed cited task permits unchanged roadmap', () async {
    await write('roadmap.md', '- [x] Implement task\n');
    await git(['add', '--', 'roadmap.md']);
    await git([
      '-c',
      'core.hooksPath=/dev/null',
      'commit',
      '-qm',
      'roadmap already done',
    ]);
    baseline = await read();
    await git(['add', '--', 'task.txt']);
    expect(scope.preparationProblem(baseline, await read()), isNull);
  });
  test(
    'a duplicate completed entry cannot hide the cited pending entry',
    () async {
      await write('roadmap.md', '- [ ] Implement task\n- [x] Implement task\n');
      await git(['add', '--', 'task.txt', 'roadmap.md']);
      expect(
        scope.preparationProblem(baseline, await read()),
        contains('not marked complete'),
      );
    },
  );
  test(
    'missing native file evidence fails closed and snapshot is immutable',
    () async {
      final prepared = await prepare();
      final invalid = ProjectTaskCommitSnapshot(
        head: prepared.head,
        indexFingerprint: prepared.indexFingerprint,
        fileFingerprints: {},
        stagedPaths: scope.paths,
        unstagedPaths: {},
      );
      expect(
        scope.preparationProblem(baseline, invalid),
        contains('incomplete'),
      );
      expect(
        scope.authorize(prepared).commitProblem(invalid),
        contains('incomplete'),
      );
      expect(prepared.fileFingerprints.clear, throwsUnsupportedError);
      expect(prepared.stagedPaths.clear, throwsUnsupportedError);
    },
  );
  test('hidden roadmap changes still require actual staging', () async {
    await git(['update-index', '--skip-worktree', '--', 'roadmap.md']);
    baseline = await read();
    await write('roadmap.md', '- [x] Implement task\n');
    await git(['add', '--', 'task.txt']);
    final prepared = await read();
    expect(prepared.roadmapAlreadyDone, isTrue);
    expect(prepared.unstagedPaths.contains(scope.roadmapPath), isFalse);
    expect(
      scope.preparationProblem(baseline, prepared),
      contains('roadmap update is missing'),
    );
  });
  test('roadmap deletion cannot count as completion bookkeeping', () async {
    await File(scope.roadmapPath).delete();
    await git(['add', '--', 'task.txt', 'roadmap.md']);
    expect(await reader.read(scope), isNull);
  });
  test('quoted task titles retain their full identity', () async {
    scope = ProjectTaskCommitScope.fromObjective(
      conversationId: 'task',
      projectRoot: root.path,
      objective:
          'Source: roadmap.md:1\n"- [ ] Implement "quoted" task"\n\nLater commit -m "fix: implement task" -m "Explain it.".',
      reviewedPaths: ['task.txt'],
    )!;
    expect(scope.sourceQuote, '- [ ] Implement "quoted" task');
    await write('roadmap.md', '- [x] Implement "quoted" task\n');
    expect((await read()).roadmapAlreadyDone, isTrue);
  });
  test('invalid repository and outside roadmap fail closed', () async {
    expect(
      ProjectTaskCommitScope.fromObjective(
        conversationId: 'task',
        projectRoot: root.path,
        objective: 'Source: ../outside.md',
        reviewedPaths: ['task.txt'],
      ),
      isNull,
    );
    final invalid = ProjectTaskCommitScope(
      conversationId: 'task',
      projectRoot: '${root.path}/missing',
      roadmapPath: '${root.path}/missing/roadmap.md',
      reviewedPaths: [],
    );
    expect(await reader.read(invalid), isNull);
  });
}
