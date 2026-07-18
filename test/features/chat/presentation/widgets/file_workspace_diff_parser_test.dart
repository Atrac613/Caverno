import 'package:caverno/features/chat/presentation/widgets/file_workspace_diff_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileWorkspaceDiffParser', () {
    test('classifies headers before addition and removal prefixes', () {
      final rows = FileWorkspaceDiffParser.parse('''
diff --git a/lib/a.dart b/lib/a.dart
index 1111111..2222222 100644
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -10,3 +20,3 @@ block
 context
-old
+new''');

      expect(rows.map((row) => row.kind), [
        FileWorkspaceDiffRowKind.header,
        FileWorkspaceDiffRowKind.header,
        FileWorkspaceDiffRowKind.header,
        FileWorkspaceDiffRowKind.header,
        FileWorkspaceDiffRowKind.header,
        FileWorkspaceDiffRowKind.context,
        FileWorkspaceDiffRowKind.removal,
        FileWorkspaceDiffRowKind.addition,
      ]);
      expect(_lineNumbers(rows[5]), (oldLine: 10, newLine: 20));
      expect(_lineNumbers(rows[6]), (oldLine: 11, newLine: null));
      expect(_lineNumbers(rows[7]), (oldLine: null, newLine: 21));
    });

    test('resets line counters for each valid hunk', () {
      final rows = FileWorkspaceDiffParser.parse('''
@@ -1 +5 @@ first
-old
+new
@@ -30,2 +40,2 @@ second
 context
-removed
+added''');

      expect(_lineNumbers(rows[1]), (oldLine: 1, newLine: null));
      expect(_lineNumbers(rows[2]), (oldLine: null, newLine: 5));
      expect(_lineNumbers(rows[4]), (oldLine: 30, newLine: 40));
      expect(_lineNumbers(rows[5]), (oldLine: 31, newLine: null));
      expect(_lineNumbers(rows[6]), (oldLine: null, newLine: 41));
    });

    test('preserves malformed text, blank rows, and trailing newlines', () {
      final rows = FileWorkspaceDiffParser.parse(
        '@@ malformed @@\n\\ No newline at end of file\n',
      );

      expect(rows, hasLength(3));
      expect(
        rows.map((row) => row.kind),
        everyElement(FileWorkspaceDiffRowKind.context),
      );
      expect(rows.map((row) => row.text), [
        '@@ malformed @@',
        r'\ No newline at end of file',
        '',
      ]);
      expect(
        rows.map(_lineNumbers),
        everyElement((oldLine: null, newLine: null)),
      );
    });

    test('returns one blank context row for an empty patch', () {
      final rows = FileWorkspaceDiffParser.parse('');

      expect(rows, hasLength(1));
      expect(rows.single.kind, FileWorkspaceDiffRowKind.context);
      expect(rows.single.text, isEmpty);
      expect(_lineNumbers(rows.single), (oldLine: null, newLine: null));
    });
  });
}

({int? oldLine, int? newLine}) _lineNumbers(FileWorkspaceDiffRow row) {
  return (oldLine: row.oldLine, newLine: row.newLine);
}
