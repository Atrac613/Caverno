import 'dart:io';

import 'package:caverno/features/chat/data/datasources/filesystem_diff_builder.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filesystem diff behavior', () {
    test('uses dev null headers for created and deleted files', () {
      final created = FilesystemDiffBuilder.buildUnifiedDiff(
        path: 'lib/example.txt',
        oldContent: null,
        newContent: 'alpha\nbeta\n',
      );
      final deleted = FilesystemDiffBuilder.buildUnifiedDiff(
        path: 'lib/example.txt',
        oldContent: 'alpha\nbeta\n',
        newContent: null,
      );

      expect(created, startsWith('--- /dev/null\n+++ lib/example.txt\n'));
      expect(created, contains('+alpha\n+beta'));
      expect(deleted, startsWith('--- lib/example.txt\n+++ /dev/null\n'));
      expect(deleted, contains('-alpha\n-beta'));
    });

    test('renders an explicit no-change body', () {
      final preview = FilesystemDiffBuilder.buildUnifiedDiff(
        path: 'lib/example.txt',
        oldContent: 'alpha\nbeta\n',
        newContent: 'alpha\nbeta\n',
      );

      expect(
        preview,
        '--- lib/example.txt\n'
        '+++ lib/example.txt\n'
        '@@\n'
        '(no changes)',
      );
    });

    test('keeps three context lines around separated hunks', () {
      final oldLines = List.generate(12, (index) => 'line-$index');
      final newLines = [...oldLines]
        ..[1] = 'changed-1'
        ..[10] = 'changed-10';

      final preview = FilesystemDiffBuilder.buildUnifiedDiff(
        path: 'lib/example.txt',
        oldContent: oldLines.join('\n'),
        newContent: newLines.join('\n'),
      );

      expect(
        RegExp(r'^@@$', multiLine: true).allMatches(preview),
        hasLength(2),
      );
      expect(preview, contains('-line-1\n+changed-1'));
      expect(preview, contains('-line-10\n+changed-10'));
      expect(preview, isNot(contains(' line-5')));
      expect(preview, isNot(contains(' line-6')));
    });

    test('uses prefix and suffix anchors above the LCS cell limit', () {
      final prefix = List.generate(122, (index) => 'prefix-$index');
      final suffix = List.generate(123, (index) => 'suffix-$index');
      final oldLines = [...prefix, 'old-middle', ...suffix];
      final newLines = [...prefix, 'new-middle', ...suffix];

      final preview = FilesystemDiffBuilder.buildUnifiedDiff(
        path: 'lib/large.txt',
        oldContent: oldLines.join('\n'),
        newContent: newLines.join('\n'),
      );

      expect(preview, contains(' prefix-119\n prefix-120\n prefix-121'));
      expect(preview, contains('-old-middle\n+new-middle'));
      expect(preview, contains(' suffix-0\n suffix-1\n suffix-2'));
      expect(preview, isNot(contains(' prefix-118')));
      expect(preview, isNot(contains(' suffix-3')));
      expect(preview, isNot(contains('diff preview truncated')));
    });

    test('caps previews by line count', () {
      final preview = FilesystemDiffBuilder.buildUnifiedDiff(
        path: 'lib/generated.txt',
        oldContent: null,
        newContent: List.generate(500, (index) => 'line-$index').join('\n'),
      );

      expect(preview.split('\n'), hasLength(401));
      expect(preview, endsWith('... diff preview truncated ...'));
    });

    test('caps previews by character count', () {
      final preview = FilesystemDiffBuilder.buildUnifiedDiff(
        path: 'lib/generated.txt',
        oldContent: null,
        newContent: List.generate(20, (_) => 'x' * 1000).join('\n'),
      );

      expect(preview.split('\n').length, lessThan(25));
      expect(preview, endsWith('... diff preview truncated ...'));
    });

    test(
      'includes proposed content when a write preview is unavailable',
      () async {
        final preview = await FilesystemTools.buildWriteDiffPreview(
          path: Directory.systemTemp.path,
          newContent: 'replacement\ncontent',
        );

        expect(
          preview,
          'Diff preview unavailable: Path is not a regular text file.\n'
          '\n'
          'Proposed content:\n'
          '+replacement\n'
          '+content',
        );
      },
    );
  });
}
