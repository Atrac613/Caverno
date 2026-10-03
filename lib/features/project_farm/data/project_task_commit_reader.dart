import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../domain/entities/project_task_commit_scope.dart';

/// Fixed native reads of HEAD, the complete index and task-owned worktree files.
final class ProjectTaskCommitReader {
  const ProjectTaskCommitReader();
  static const _maxBytes = 8 * 1024 * 1024;

  Future<ProjectTaskCommitSnapshot?> read(ProjectTaskCommitScope scope) async {
    try {
      Future<String> git(List<String> args) async {
        final result = await Process.run(
          'git',
          args,
          workingDirectory: scope.projectRoot,
        ).timeout(const Duration(seconds: 5));
        if (result.exitCode != 0 ||
            (result.stdout as String).length > _maxBytes) {
          throw StateError('Native commit inspection failed');
        }
        return result.stdout as String;
      }

      final head = (await git(['rev-parse', 'HEAD'])).trim();
      final index = await git(['ls-files', '--stage', '-z']);
      Future<Set<String>> changed(List<String> args) async => {
        for (final file in (await git(args)).split('\u0000'))
          if (file.isNotEmpty) scope.resolve(file),
      };
      final staged = await changed([
        'diff',
        '--no-ext-diff',
        '--no-renames',
        '--cached',
        '--name-only',
        '-z',
        'HEAD',
      ]);
      final unstaged = await changed([
        'diff',
        '--no-ext-diff',
        '--no-renames',
        '--name-only',
        '-z',
      ]);
      unstaged.addAll(
        await changed(['ls-files', '--others', '--exclude-standard', '-z']),
      );
      final files = <String, String>{};
      String? roadmapContent;
      for (final file in scope.paths) {
        if (!path.isWithin(scope.projectRoot, file)) return null;
        final type = await FileSystemEntity.type(file, followLinks: false);
        List<int> bytes;
        if (type == FileSystemEntityType.notFound) {
          bytes = const [];
        } else if (type == FileSystemEntityType.link) {
          bytes = utf8.encode(await Link(file).target());
        } else if (type == FileSystemEntityType.file) {
          if (await File(file).length() > _maxBytes) return null;
          bytes = await File(file).readAsBytes();
          if (file == scope.roadmapPath) roadmapContent = utf8.decode(bytes);
        } else {
          return null;
        }
        files[file] = '$type:${sha256.convert(bytes)}';
      }
      final roadmap = roadmapContent;
      if (roadmap == null) return null;
      bool alreadyDone() {
        final quote = scope.sourceQuote;
        if (quote == null || quote.isEmpty) {
          return false;
        }
        String identity(String value) => value
            .replaceFirst(RegExp(r'^\s*(?:[-*+]\s+)?\[[ xX]\]\s*'), '')
            .trim();
        final expected = identity(quote);
        final lines = roadmap.split('\n');
        final sourceLine = scope.sourceLine;
        final matching = lines.where((line) => identity(line) == expected);
        final candidates =
            sourceLine != null &&
                sourceLine > 0 &&
                sourceLine <= lines.length &&
                identity(lines[sourceLine - 1]) == expected
            ? [lines[sourceLine - 1]]
            : matching.length == 1
            ? matching
            : const <String>[];
        return candidates.any(
          (line) => RegExp(r'^\s*(?:[-*+]\s+)?\[[xX]\]\s+').hasMatch(line),
        );
      }

      if ((await git(['rev-parse', 'HEAD'])).trim() != head ||
          await git(['ls-files', '--stage', '-z']) != index) {
        return null;
      }
      return ProjectTaskCommitSnapshot(
        head: head,
        indexFingerprint: sha256.convert(utf8.encode(index)).toString(),
        fileFingerprints: Map.unmodifiable(files),
        stagedPaths: Set.unmodifiable(staged),
        unstagedPaths: Set.unmodifiable(unstaged),
        roadmapAlreadyDone: alreadyDone(),
      );
    } on Object {
      return null;
    }
  }
}
