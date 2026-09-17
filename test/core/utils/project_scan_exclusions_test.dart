import 'dart:io';

import 'package:caverno/core/utils/project_scan_exclusions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectScanExclusions', () {
    test('excludes the agent worktree roots, not their parents', () {
      expect(ProjectScanExclusions.excludesDirectory('.claude/worktrees'), isTrue);
      expect(ProjectScanExclusions.excludesDirectory('.codex/worktrees'), isTrue);
      // The rest of .claude is ordinary project content an agent is expected
      // to find: settings.json, agents/, launch.json.
      expect(ProjectScanExclusions.excludesDirectory('.claude'), isFalse);
      expect(ProjectScanExclusions.excludesDirectory('.claude/agents'), isFalse);
    });

    test('excludes build output wherever it appears', () {
      expect(ProjectScanExclusions.excludesDirectory('build'), isTrue);
      expect(ProjectScanExclusions.excludesDirectory('ios/Pods'), isTrue);
      expect(ProjectScanExclusions.excludesDirectory('a/b/.dart_tool'), isTrue);
      expect(ProjectScanExclusions.excludesDirectory('lib/features'), isFalse);
    });

    test('excludesPath reports a file inside an excluded subtree', () {
      expect(
        ProjectScanExclusions.excludesPath('.claude/worktrees/x/pubspec.yaml'),
        isTrue,
      );
      expect(ProjectScanExclusions.excludesPath('build/app/out.txt'), isTrue);
      expect(ProjectScanExclusions.excludesPath('pubspec.yaml'), isFalse);
      expect(
        ProjectScanExclusions.excludesPath('lib/core/utils/logger.dart'),
        isFalse,
      );
    });

    group('files()', () {
      late Directory root;

      setUp(() async {
        root = await Directory.systemTemp.createTemp('scan-exclusions');
        Future<void> write(String relative) async {
          final file = File('${root.path}/$relative');
          await file.parent.create(recursive: true);
          await file.writeAsString('version: 1.0.0+1\n');
        }

        await write('pubspec.yaml');
        await write('lib/main.dart');
        // The shape measured on 2026-09-17: 72 sandbox checkouts inside the
        // project root, each carrying its own pubspec.yaml.
        await write('.claude/worktrees/feature-a/pubspec.yaml');
        await write('.claude/worktrees/feature-b/pubspec.yaml');
        await write('.claude/settings.json');
        await write('build/ios/pubspec.yaml');
        await write('.dart_tool/package_config.json');
      });

      tearDown(() async => root.delete(recursive: true));

      Future<List<String>> scan(Directory from) async {
        final found = <String>[];
        await for (final file in ProjectScanExclusions.files(from)) {
          found.add(file.path.substring(from.absolute.path.length + 1));
        }
        found.sort();
        return found;
      }

      test('prunes worktrees and build output but keeps the project', () async {
        expect(await scan(root), [
          '.claude/settings.json',
          'lib/main.dart',
          'pubspec.yaml',
        ]);
      });

      test('a scan rooted inside an excluded subtree still sees it', () async {
        // The exclusion applies while descending. A worktree child addressed
        // by path stays readable, which is what delegation depends on.
        final worktree = Directory('${root.path}/.claude/worktrees/feature-a');
        expect(await scan(worktree), ['pubspec.yaml']);
      });
    });
  });
}
