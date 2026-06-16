import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/git_changed_paths_service.dart';

void main() {
  group('GitChangedPathsService.parsePorcelain', () {
    test('parses modified, staged, and untracked entries', () {
      final paths = GitChangedPathsService.parsePorcelain(
        ' M lib/a.dart\n'
        'MM lib/b.dart\n'
        '?? lib/new.dart\n'
        'A  lib/added.dart\n',
      );
      expect(paths, [
        'lib/a.dart',
        'lib/b.dart',
        'lib/new.dart',
        'lib/added.dart',
      ]);
    });

    test('keeps the new path of a rename', () {
      final paths = GitChangedPathsService.parsePorcelain(
        'R  lib/old.dart -> lib/new.dart\n',
      );
      expect(paths, ['lib/new.dart']);
    });

    test('unquotes paths with special characters', () {
      final paths = GitChangedPathsService.parsePorcelain(
        '?? "lib/with space.dart"\n',
      );
      expect(paths, ['lib/with space.dart']);
    });

    test('ignores blank lines', () {
      expect(GitChangedPathsService.parsePorcelain('\n\n  \n'), isEmpty);
    });
  });

  group('GitChangedPathsService.changedPaths', () {
    test('runs git status --porcelain and parses the output', () async {
      List<String>? sentArgs;
      final service = GitChangedPathsService(
        projectRoot: '/tmp/project',
        runner: (args) async {
          sentArgs = args;
          return ' M lib/a.dart\n?? lib/b.dart\n';
        },
      );

      final paths = await service.changedPaths();

      expect(sentArgs, ['status', '--porcelain']);
      expect(paths, ['lib/a.dart', 'lib/b.dart']);
    });

    test('degrades to empty when git is unavailable', () async {
      final service = GitChangedPathsService(
        projectRoot: '/tmp/project',
        runner: (args) async => throw const ProcessExceptionLike(),
      );
      expect(await service.changedPaths(), isEmpty);
    });
  });
}

class ProcessExceptionLike implements Exception {
  const ProcessExceptionLike();
}
