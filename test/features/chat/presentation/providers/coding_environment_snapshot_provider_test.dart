import 'dart:io';

import 'package:caverno/features/chat/presentation/providers/coding_environment_snapshot_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads branch, changed files, and combined diff stats', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'coding_environment_snapshot_test_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final snapshot = await CodingEnvironmentSnapshot.load(
      rootPath: tempDir.path,
      runProcess: (executable, arguments, {workingDirectory}) async {
        expect(executable, 'git');
        expect(workingDirectory, tempDir.path);
        return switch (arguments.join(' ')) {
          'rev-parse --show-toplevel' => ProcessResult(
            1,
            0,
            '${tempDir.path}\n',
            '',
          ),
          'branch --show-current' => ProcessResult(
            1,
            0,
            'feature/sidebar\n',
            '',
          ),
          'status --short' => ProcessResult(
            1,
            0,
            ' M lib/a.dart\nA  lib/b.dart\n?? README.md\n',
            '',
          ),
          'diff --shortstat' => ProcessResult(
            1,
            0,
            ' 2 files changed, 10 insertions(+), 3 deletions(-)\n',
            '',
          ),
          'diff --cached --shortstat' => ProcessResult(
            1,
            0,
            ' 1 file changed, 4 insertions(+)\n',
            '',
          ),
          final command => ProcessResult(1, 1, '', 'unexpected $command'),
        };
      },
    );

    expect(snapshot.isGitRepository, isTrue);
    expect(snapshot.repositoryRoot, tempDir.path);
    expect(snapshot.branchName, 'feature/sidebar');
    expect(snapshot.changedFileCount, 3);
    expect(snapshot.insertions, 14);
    expect(snapshot.deletions, 3);
    expect(snapshot.hasChanges, isTrue);
  });

  test('returns an unavailable snapshot for non-git folders', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'coding_environment_snapshot_non_git_test_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final snapshot = await CodingEnvironmentSnapshot.load(
      rootPath: tempDir.path,
      runProcess: (executable, arguments, {workingDirectory}) async {
        return ProcessResult(1, 128, '', 'not a git repository');
      },
    );

    expect(snapshot.isGitRepository, isFalse);
    expect(snapshot.hasChanges, isFalse);
    expect(snapshot.errorMessage, 'Project is not a git repository.');
  });
}
