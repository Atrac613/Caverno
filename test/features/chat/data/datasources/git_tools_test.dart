import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/git_tools.dart';

void main() {
  group('GitTools.normalizeCommand', () {
    test('strips a leading git binary prefix', () {
      expect(GitTools.normalizeCommand('git status --short'), 'status --short');
    });

    test('removes repeated git prefixes and control tokens', () {
      expect(
        GitTools.normalizeCommand(
          'git <|"|>git commit -m "Add tokyo_weather_next_week.csv"<|"|>',
        ),
        'commit -m "Add tokyo_weather_next_week.csv"',
      );
    });
  });

  group('GitTools.isReadOnly', () {
    test('classifies normalized prefixed commands correctly', () {
      expect(GitTools.isReadOnly('git status --short'), isTrue);
      expect(
        GitTools.isReadOnly(
          'git <|"|>git commit -m "Add tokyo_weather_next_week.csv"<|"|>',
        ),
        isFalse,
      );
    });

    test('classifies tag pattern listings as read-only', () {
      expect(
        GitTools.isReadOnly("tag -l '1.3.4*' --sort=-version:refname"),
        isTrue,
      );
      expect(
        GitTools.isReadOnly('tag --list 1.3.4* --sort=-version:refname'),
        isTrue,
      );
      expect(GitTools.isReadOnly('tag 1.3.4+15'), isFalse);
    });
  });

  group('GitTools.firstShellControlOperator', () {
    test('detects shell operators outside quotes', () {
      expect(
        GitTools.firstShellControlOperator(
          'add README.md && commit -m "Add README"',
        ),
        '&&',
      );
      expect(GitTools.firstShellControlOperator('status | cat'), '|');
      expect(GitTools.firstShellControlOperator('status > out.txt'), '>');
    });

    test('ignores shell-like text inside quotes', () {
      expect(
        GitTools.firstShellControlOperator(
          'commit -m "Document A && B; keep pipe | literal"',
        ),
        isNull,
      );
    });
  });

  group('GitTools.execute', () {
    test('runs init, commit, and revert lifecycle commands', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'git_tools_lifecycle_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      Map<String, dynamic> decode(String raw) =>
          jsonDecode(raw) as Map<String, dynamic>;

      final initResult = decode(
        await GitTools.execute(command: 'init', workingDirectory: tempDir.path),
      );
      expect(initResult['exit_code'], 0);
      expect(Directory('${tempDir.path}/.git').existsSync(), isTrue);

      await File('${tempDir.path}/sample.txt').writeAsString('hello\n');

      final emailResult = decode(
        await GitTools.execute(
          command: 'config user.email "canary@example.com"',
          workingDirectory: tempDir.path,
        ),
      );
      expect(emailResult['exit_code'], 0);

      final nameResult = decode(
        await GitTools.execute(
          command: 'config user.name "Canary Bot"',
          workingDirectory: tempDir.path,
        ),
      );
      expect(nameResult['exit_code'], 0);

      final addResult = decode(
        await GitTools.execute(
          command: 'add sample.txt',
          workingDirectory: tempDir.path,
        ),
      );
      expect(addResult['exit_code'], 0);

      final commitResult = decode(
        await GitTools.execute(
          command: 'commit -m "Add sample"',
          workingDirectory: tempDir.path,
        ),
      );
      expect(commitResult['exit_code'], 0);
      expect(File('${tempDir.path}/sample.txt').existsSync(), isTrue);

      final revertResult = decode(
        await GitTools.execute(
          command: 'revert --no-edit HEAD',
          workingDirectory: tempDir.path,
        ),
      );
      expect(revertResult['exit_code'], 0);
      expect(File('${tempDir.path}/sample.txt').existsSync(), isFalse);

      final statusResult = decode(
        await GitTools.execute(
          command: 'status --short',
          workingDirectory: tempDir.path,
        ),
      );
      expect(statusResult['exit_code'], 0);
      expect((statusResult['stdout'] as String).trim(), isEmpty);
    });

    test('rejects chained commands before execution', () async {
      final tempDir = await Directory.systemTemp.createTemp('git_tools_test_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      await Process.run('git', ['init'], workingDirectory: tempDir.path);
      await File('${tempDir.path}/README.md').writeAsString('hello\n');

      final raw = await GitTools.execute(
        command: 'add README.md && commit -m "Add README"',
        workingDirectory: tempDir.path,
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      expect(decoded['exit_code'], 2);
      expect(decoded['error'], contains('one git subcommand'));
      expect(decoded['error'], contains('&&'));
    });

    test(
      'rejects a piped command with directive self-correction guidance',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'git_tools_pipe_',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
          }
        });

        final raw = await GitTools.execute(
          command: 'tag --list | sort -V | tail -10',
          workingDirectory: tempDir.path,
        );
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final error = decoded['error'] as String;

        expect(decoded['exit_code'], 2);
        // The model must learn to filter with git's own arguments rather than
        // blindly retrying the unfiltered command, which is what caused the
        // observed `tag --list` inspection loop.
        expect(error, contains('Do not retry the same command'));
        expect(error, contains('tag --list'));
      },
    );

    test('rejects commit when unstaged changes would be omitted', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'git_tools_stale_index_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      Map<String, dynamic> decode(String raw) =>
          jsonDecode(raw) as Map<String, dynamic>;

      expect(
        decode(
          await GitTools.execute(
            command: 'init',
            workingDirectory: tempDir.path,
          ),
        )['exit_code'],
        0,
      );
      expect(
        decode(
          await GitTools.execute(
            command: 'config user.email "canary@example.com"',
            workingDirectory: tempDir.path,
          ),
        )['exit_code'],
        0,
      );
      expect(
        decode(
          await GitTools.execute(
            command: 'config user.name "Canary Bot"',
            workingDirectory: tempDir.path,
          ),
        )['exit_code'],
        0,
      );

      final pubspec = File('${tempDir.path}/pubspec.yaml');
      await pubspec.writeAsString('version: 1.3.5+16\n');
      expect(
        decode(
          await GitTools.execute(
            command: 'add pubspec.yaml',
            workingDirectory: tempDir.path,
          ),
        )['exit_code'],
        0,
      );
      expect(
        decode(
          await GitTools.execute(
            command: 'commit -m "Initial version"',
            workingDirectory: tempDir.path,
          ),
        )['exit_code'],
        0,
      );

      await pubspec.writeAsString('version: 1.3.5+17\n');
      expect(
        decode(
          await GitTools.execute(
            command: 'add pubspec.yaml',
            workingDirectory: tempDir.path,
          ),
        )['exit_code'],
        0,
      );
      await pubspec.writeAsString('version: 1.3.5+18\n');

      final commitResult = decode(
        await GitTools.execute(
          command: 'commit -m "Bump version to 1.3.5+18"',
          workingDirectory: tempDir.path,
        ),
      );

      expect(commitResult['exit_code'], 2);
      expect(commitResult['code'], 'git_commit_unstaged_changes');
      expect(commitResult['error'], contains('unstaged changes'));

      final headFile = decode(
        await GitTools.execute(
          command: 'show HEAD:pubspec.yaml',
          workingDirectory: tempDir.path,
        ),
      );
      expect(headFile['stdout'], 'version: 1.3.5+16\n');
    });

    test(
      'allows commit when only unrelated files are unstaged or untracked',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'git_tools_partial_stage_test_',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
          }
        });

        Map<String, dynamic> decode(String raw) =>
            jsonDecode(raw) as Map<String, dynamic>;

        Future<Map<String, dynamic>> run(String command) async => decode(
          await GitTools.execute(
            command: command,
            workingDirectory: tempDir.path,
          ),
        );

        expect((await run('init'))['exit_code'], 0);
        expect(
          (await run('config user.email "canary@example.com"'))['exit_code'],
          0,
        );
        expect((await run('config user.name "Canary Bot"'))['exit_code'], 0);

        // Establish a base commit with one tracked file.
        final tracked = File('${tempDir.path}/tracked.txt');
        await tracked.writeAsString('base\n');
        expect((await run('add tracked.txt'))['exit_code'], 0);
        expect((await run('commit -m "base"'))['exit_code'], 0);

        // Stage a NEW file we intend to commit, with a clean worktree for it.
        final staged = File('${tempDir.path}/release-notes.md');
        await staged.writeAsString('# Release notes\n');
        expect((await run('add release-notes.md'))['exit_code'], 0);

        // Leave an UNRELATED tracked file modified-but-unstaged and an
        // unrelated untracked file present — mirroring the real-world repo
        // state where lib/**/*.dart edits should not block a docs commit.
        await tracked.writeAsString('base\nlocal edit\n');
        await File('${tempDir.path}/scratch.tmp').writeAsString('wip\n');

        final commitResult = await run('commit -m "Add release notes"');
        expect(commitResult['exit_code'], 0);
        expect(commitResult['code'], isNull);

        // The staged file made it into the commit...
        final headFile = await run('show HEAD:release-notes.md');
        expect(headFile['stdout'], '# Release notes\n');

        // ...while the unrelated unstaged edit and untracked file are left as-is.
        expect(await tracked.readAsString(), 'base\nlocal edit\n');
        final statusAfter = await run('status --porcelain');
        expect(statusAfter['stdout'], contains(' M tracked.txt'));
        expect(statusAfter['stdout'], contains('?? scratch.tmp'));
      },
    );

    test('blocks merging the current branch into itself', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'git_tools_self_merge_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      Map<String, dynamic> decode(String raw) =>
          jsonDecode(raw) as Map<String, dynamic>;
      Future<Map<String, dynamic>> run(String command) async => decode(
        await GitTools.execute(
          command: command,
          workingDirectory: tempDir.path,
        ),
      );

      expect((await run('init'))['exit_code'], 0);
      expect(
        (await run('config user.email "canary@example.com"'))['exit_code'],
        0,
      );
      expect((await run('config user.name "Canary Bot"'))['exit_code'], 0);

      await File('${tempDir.path}/hello.txt').writeAsString('hello\n');
      expect((await run('add hello.txt'))['exit_code'], 0);
      expect((await run('commit -m "base"'))['exit_code'], 0);
      expect((await run('checkout -b feature/self'))['exit_code'], 0);

      final mergeResult = await run(
        'merge feature/self -m "Merge feature/self into main"',
      );

      expect(mergeResult['exit_code'], 2);
      expect(mergeResult['code'], 'git_merge_current_branch');
      expect(mergeResult['current_branch'], 'feature/self');
      expect(mergeResult['merge_target'], 'feature/self');
      expect(mergeResult['error'], contains('merge the current branch'));
      expect(mergeResult['error'], contains('git worktree list'));
    });

    test('blocks main merge intent from a non-main worktree', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'git_tools_wrong_merge_worktree_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      Map<String, dynamic> decode(String raw) =>
          jsonDecode(raw) as Map<String, dynamic>;
      Future<Map<String, dynamic>> run(
        String command, {
        String? reason,
      }) async => decode(
        await GitTools.execute(
          command: command,
          workingDirectory: tempDir.path,
          reason: reason,
        ),
      );

      expect((await run('init'))['exit_code'], 0);
      expect((await run('branch -M main'))['exit_code'], 0);
      expect(
        (await run('config user.email "canary@example.com"'))['exit_code'],
        0,
      );
      expect((await run('config user.name "Canary Bot"'))['exit_code'], 0);

      await File('${tempDir.path}/base.txt').writeAsString('base\n');
      expect((await run('add base.txt'))['exit_code'], 0);
      expect((await run('commit -m "base"'))['exit_code'], 0);
      final baseHead = await run('rev-parse HEAD');

      expect((await run('checkout -b feature/source'))['exit_code'], 0);
      await File('${tempDir.path}/hello.txt').writeAsString('hello\n');
      expect((await run('add hello.txt'))['exit_code'], 0);
      expect((await run('commit -m "add hello"'))['exit_code'], 0);

      expect((await run('checkout main'))['exit_code'], 0);
      expect((await run('checkout -b feature/other'))['exit_code'], 0);

      final mergeResult = await run(
        'merge feature/source -m "feat: add hello"',
        reason: 'Merge feature/source into main',
      );

      expect(mergeResult['exit_code'], 2);
      expect(mergeResult['code'], 'git_merge_wrong_target_worktree');
      expect(mergeResult['current_branch'], 'feature/other');
      expect(mergeResult['intended_target_branch'], 'main');
      expect(mergeResult['merge_targets'], ['feature/source']);
      expect(mergeResult['error'], contains('working directory is currently'));
      expect(mergeResult['error'], contains('main'));

      final headAfter = await run('rev-parse HEAD');
      expect(headAfter['stdout'], baseHead['stdout']);
    });

    test('base-dirty worktree finish returns a structured recovery hint',
        () async {
      final root = await Directory.systemTemp.createTemp(
        'git_tools_finish_base_dirty_',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      final basePath = '${root.path}/base';
      await Directory(basePath).create(recursive: true);

      Future<void> git(List<String> args, {String? cwd}) async {
        final result = await Process.run(
          'git',
          args,
          workingDirectory: cwd ?? basePath,
        );
        expect(
          result.exitCode,
          0,
          reason: 'git ${args.join(' ')} failed: ${result.stderr}',
        );
      }

      await git(['init']);
      await git(['branch', '-M', 'main']);
      await git(['config', 'user.email', 'canary@example.com']);
      await git(['config', 'user.name', 'Canary Bot']);
      await File('$basePath/base.txt').writeAsString('base\n');
      await git(['add', 'base.txt']);
      await git(['commit', '-m', 'base']);

      // A feature worktree with a committed change, ready to merge.
      final worktreePath = '${root.path}/wt';
      await git(['worktree', 'add', '-b', 'feature/source', worktreePath]);
      await File('$worktreePath/hello.txt').writeAsString('hello\n');
      await git(['add', 'hello.txt'], cwd: worktreePath);
      await git(['commit', '-m', 'add hello'], cwd: worktreePath);

      // Dirty the BASE worktree so the merge is blocked.
      await File('$basePath/.DS_Store').writeAsString('junk\n');

      final result =
          jsonDecode(
                await GitTools.finishWorktreeSession(
                  worktreePath: worktreePath,
                  baseBranch: 'main',
                ),
              )
              as Map<String, dynamic>;

      expect(result['code'], 'git_finish_worktree_base_dirty');
      final requiredAction = result['required_action'] as String;
      // Steers to the BASE worktree via git_execute_command, then retry — the
      // recovery the model fumbled (it cleaned the wrong worktree, used blocked
      // local-shell git, and never retried the tool).
      expect(requiredAction, contains(result['base_worktree_path'] as String));
      expect(requiredAction, contains('git_execute_command'));
      expect(requiredAction, contains('clean -fd'));
      expect(requiredAction, contains('git_finish_worktree_session'));
    });

    test('blocks double-force worktree removal in managed git tool', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'git_tools_force_remove_worktree_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      Map<String, dynamic> decode(String raw) =>
          jsonDecode(raw) as Map<String, dynamic>;
      Future<Map<String, dynamic>> run(String command) async => decode(
        await GitTools.execute(
          command: command,
          workingDirectory: tempDir.path,
        ),
      );

      expect((await run('init'))['exit_code'], 0);

      final result = await run('worktree remove -f -f /tmp/caverno-worktree');

      expect(result['exit_code'], 2);
      expect(result['code'], 'git_worktree_force_remove_blocked');
      expect(result['error'], contains('double-force removal'));
      expect(
        result['required_action'],
        contains('git_finish_worktree_session'),
      );
    });

    test('blocks a version tag that disagrees with pubspec.yaml', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'git_tools_tag_version_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      Map<String, dynamic> decode(String raw) =>
          jsonDecode(raw) as Map<String, dynamic>;
      Future<Map<String, dynamic>> run(String command) async => decode(
        await GitTools.execute(
          command: command,
          workingDirectory: tempDir.path,
        ),
      );

      expect((await run('init'))['exit_code'], 0);
      expect(
        (await run('config user.email "canary@example.com"'))['exit_code'],
        0,
      );
      expect((await run('config user.name "Canary Bot"'))['exit_code'], 0);

      await File(
        '${tempDir.path}/pubspec.yaml',
      ).writeAsString('name: demo\nversion: 1.3.8+20\n');
      expect((await run('add pubspec.yaml'))['exit_code'], 0);
      expect((await run('commit -m "init"'))['exit_code'], 0);

      // Build number disagrees (+19 vs pubspec +20): blocked.
      final mismatch = await run('tag -a 1.3.8+19 -m "Release v1.3.8"');
      expect(mismatch['exit_code'], 2);
      expect(mismatch['code'], 'git_tag_version_mismatch');
      expect(mismatch['error'], contains('1.3.8+20'));
      expect(mismatch['pubspec_version'], '1.3.8+20');

      // The tag must not have been created.
      final tagsAfterBlock = await run('tag --list');
      expect(tagsAfterBlock['stdout'], isNot(contains('1.3.8+19')));

      // Core disagrees too: blocked.
      final coreMismatch = await run('tag 1.4.0+20');
      expect(coreMismatch['code'], 'git_tag_version_mismatch');

      // Matching version is allowed and creates the tag.
      final match = await run('tag -a 1.3.8+20 -m "Release v1.3.8"');
      expect(match['exit_code'], 0);
      expect(match['code'], isNull);
      final tagsAfterMatch = await run('tag --list');
      expect(tagsAfterMatch['stdout'], contains('1.3.8+20'));

      // A non-version tag name is never subject to the check.
      final nonVersion = await run('tag nightly');
      expect(nonVersion['exit_code'], 0);
      expect(nonVersion['code'], isNull);
    });
  });
}
