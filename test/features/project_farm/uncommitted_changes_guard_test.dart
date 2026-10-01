import 'dart:io';

import 'package:caverno/features/project_farm/data/project_git_status_reader.dart';
import 'package:caverno/features/project_farm/presentation/widgets/uncommitted_changes_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProjectGitStatusReader _reader(String porcelain, {int exitCode = 0}) =>
    ProjectGitStatusReader(
      run: (args, _) async => ProcessResult(0, exitCode, switch (args.first) {
        'rev-parse' => 'main',
        'status' => porcelain,
        'rev-list' => '0',
        _ => 'abc feat: thing',
      }, ''),
    );

/// Presses a Start button guarded by the dialog, answers it with [answer]
/// when one appears, and returns what the guard completed with.
Future<bool?> _press(
  WidgetTester tester,
  ProjectGitStatusReader reader, {
  String? answer,
}) async {
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              result = await confirmStartOverUncommittedChanges(
                context,
                projectRoot: '/repo',
                reader: reader,
              ),
          child: const Text('start'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('start'));
  await tester.pumpAndSettle();
  if (answer != null) {
    await tester.tap(find.byKey(ValueKey(answer)));
    await tester.pumpAndSettle();
  }
  return result;
}

void main() {
  testWidgets('starts without asking on a clean tree', (tester) async {
    expect(await _press(tester, _reader('')), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('does not block a project git cannot read', (tester) async {
    expect(await _press(tester, _reader('', exitCode: 128)), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('waits for the user over uncommitted work', (tester) async {
    // The reported case: the next roadmap task started while the previous
    // task's eight files were still uncommitted.
    expect(await _press(tester, _reader(' M a.dart\n?? b.dart\n')), isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('project_dashboard.uncommitted_title'), findsOneWidget);
  });

  testWidgets('cancel refuses the start', (tester) async {
    expect(
      await _press(
        tester,
        _reader(' M a.dart\n'),
        answer: 'project-start-uncommitted-cancel',
      ),
      isFalse,
    );
  });

  testWidgets('Start anyway allows the start', (tester) async {
    expect(
      await _press(
        tester,
        _reader(' M a.dart\n'),
        answer: 'project-start-uncommitted-proceed',
      ),
      isTrue,
    );
  });
}
