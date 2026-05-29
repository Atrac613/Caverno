import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/turn_diff.dart';
import 'package:caverno/features/chat/presentation/widgets/turn_diff_sheet.dart';

void main() {
  testWidgets('TurnDiffSheet renders summary and colored hunk lines', (
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

    expect(find.textContaining('1 file changed'), findsOneWidget);
    expect(find.textContaining('+1'), findsWidgets);
    expect(find.textContaining('-1'), findsWidgets);
    expect(find.text('Update the parser'), findsOneWidget);
    expect(find.text('lib/parser.dart'), findsOneWidget);
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
}
