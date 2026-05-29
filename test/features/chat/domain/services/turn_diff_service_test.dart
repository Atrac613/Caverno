import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/turn_diff.dart';
import 'package:caverno/features/chat/domain/services/turn_diff_service.dart';

void main() {
  group('TurnDiffService', () {
    test('buildFileDiff records every line for a new file', () {
      final result = TurnDiffService.buildFileDiff(
        filePath: 'lib/new.dart',
        oldContent: null,
        newContent: 'one\ntwo\nthree',
        oldExists: false,
        newExists: true,
      );

      expect(result, isNotNull);
      expect(result!.file.isNewFile, isTrue);
      expect(result.file.linesAdded, 3);
      expect(result.file.linesRemoved, 0);
      expect(result.file.unifiedPatch, contains('--- /dev/null'));
      expect(result.file.unifiedPatch, contains('+one'));
      expect(result.file.unifiedPatch, contains('+three'));
    });

    test('buildFileDiff counts additions and removals', () {
      final result = TurnDiffService.buildFileDiff(
        filePath: 'lib/example.dart',
        oldContent: 'one\ntwo\nthree',
        newContent: 'one\nTWO\nthree\nfour',
      );

      expect(result, isNotNull);
      expect(result!.file.linesAdded, 2);
      expect(result.file.linesRemoved, 1);
      expect(result.file.unifiedPatch, contains('-two'));
      expect(result.file.unifiedPatch, contains('+TWO'));
      expect(result.file.unifiedPatch, contains('+four'));
    });

    test('buildTurnDiff merges multiple edits for the same file', () {
      final first = TurnDiffService.buildFileDiff(
        filePath: 'README.md',
        oldContent: 'alpha\nbeta',
        newContent: 'alpha\nbeta\ngamma',
      )!.file;
      final second = TurnDiffService.buildFileDiff(
        filePath: 'README.md',
        oldContent: 'alpha\nbeta\ngamma',
        newContent: 'alpha\nBETA\ngamma',
      )!.file;

      final turnDiff = TurnDiffService.buildTurnDiff(
        assistantMessageId: 'a1',
        userPrompt: 'Update README',
        files: [first, second],
      );

      expect(turnDiff.filesChanged, 1);
      expect(turnDiff.linesAdded, 2);
      expect(turnDiff.linesRemoved, 1);
      expect(turnDiff.changedFilePaths, ['README.md']);
      expect(turnDiff.files.single.unifiedPatch, contains('+gamma'));
      expect(turnDiff.files.single.unifiedPatch, contains('-beta'));
    });

    test('buildTurnDiff truncates very large patches', () {
      final newContent = List.generate(
        600,
        (index) => 'line $index',
      ).join('\n');
      final result = TurnDiffService.buildFileDiff(
        filePath: 'large.txt',
        oldContent: null,
        newContent: newContent,
        oldExists: false,
        newExists: true,
      );

      expect(result, isNotNull);
      expect(result!.file.isTruncated, isTrue);
      expect(result.file.unifiedPatch, contains('... diff truncated ...'));
    });

    test('buildGitFiles combines numstat and hunk output', () {
      const numstat = '2\t1\tlib/example.dart\n-\t-\tassets/logo.png\n';
      const patch = '''
diff --git a/lib/example.dart b/lib/example.dart
index 1111111..2222222 100644
--- a/lib/example.dart
+++ b/lib/example.dart
@@
-old
+new
+extra
''';

      final files = TurnDiffService.buildGitFiles(
        numstatOutput: numstat,
        patchOutput: patch,
      );

      expect(files, hasLength(2));
      final source = files.firstWhere(
        (file) => file.filePath == 'lib/example.dart',
      );
      expect(source.linesAdded, 2);
      expect(source.linesRemoved, 1);
      expect(source.unifiedPatch, contains('diff --git'));
      final binary = files.firstWhere(
        (file) => file.filePath == 'assets/logo.png',
      );
      expect(binary.isBinary, isTrue);
    });

    test('summaryLabel uses singular file wording', () {
      final diff = TurnDiff(
        id: 'd1',
        assistantMessageId: 'a1',
        userPromptPreview: 'Prompt',
        timestamp: DateTime(2026),
        filesChanged: 1,
        linesAdded: 2,
        linesRemoved: 1,
      );

      expect(diff.summaryLabel, '1 file changed +2 -1');
    });
  });
}
