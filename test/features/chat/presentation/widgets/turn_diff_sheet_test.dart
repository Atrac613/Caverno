import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/turn_diff.dart';
import 'package:caverno/features/chat/domain/services/file_reference_extractor.dart';
import 'package:caverno/features/chat/presentation/widgets/file_workspace_viewer_sheet.dart';

void main() {
  testWidgets('TurnDiffSheet renders three-pane summary and hunk lines', (
    tester,
  ) async {
    final diff = TurnDiff(
      id: 'd1',
      assistantMessageId: 'a1',
      userPromptPreview: 'Update the parser',
      timestamp: DateTime(2026),
      files: const [
        TurnDiffFile(
          filePath: 'lib/parser.dart',
          linesAdded: 1,
          linesRemoved: 1,
          unifiedPatch: '''
--- lib/parser.dart
+++ lib/parser.dart
@@
-old
+new''',
        ),
      ],
      filesChanged: 1,
      linesAdded: 1,
      linesRemoved: 1,
      changedFilePaths: const ['lib/parser.dart'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TurnDiffSheet(diff: diff)),
      ),
    );

    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Old'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.textContaining('1 file changed'), findsOneWidget);
    expect(find.textContaining('+1'), findsWidgets);
    expect(find.textContaining('-1'), findsWidgets);
    expect(find.textContaining('Update the parser'), findsOneWidget);
    expect(find.text('lib/parser.dart'), findsWidgets);
    expect(find.text('-old'), findsOneWidget);
    expect(find.text('+new'), findsOneWidget);
  });

  testWidgets('TurnDiffSheet renders clean git state', (tester) async {
    final diff = TurnDiff(
      id: 'git',
      assistantMessageId: 'git_worktree',
      userPromptPreview: 'Uncommitted changes (git diff HEAD)',
      timestamp: DateTime(2026),
      source: TurnDiffSource.git,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TurnDiffSheet(diff: diff)),
      ),
    );

    expect(find.text('Uncommitted changes'), findsOneWidget);
    expect(find.text('Working tree is clean'), findsWidgets);
  });

  testWidgets('FileWorkspaceViewerSheet previews referenced project files', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync(
      'caverno_file_viewer_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final libDir = Directory('${tempDir.path}/lib')..createSync();
    File(
      '${libDir.path}/parser.dart',
    ).writeAsStringSync('void main() {}\nfinal value = 1;\n');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileWorkspaceViewerSheet.forFiles(
            rootPath: tempDir.path,
            projectName: 'sample',
            references: const [FileReference(path: 'lib/parser.dart', line: 2)],
            initialPath: 'lib/parser.dart',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await tester.pump();

    expect(find.text('File viewer'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('lib/parser.dart'), findsWidgets);
    expect(find.text('void main() {}'), findsOneWidget);
    expect(find.text('final value = 1;'), findsOneWidget);
    expect(find.text('Line 2'), findsOneWidget);
  });
}
