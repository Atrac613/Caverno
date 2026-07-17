import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/presentation/coordinators/workflow_task_action_coordinator.dart';
import 'package:caverno/features/chat/presentation/widgets/workflow/workflow_task_editor_sheet.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

final class _SheetHarness {
  WorkflowTaskEditorSubmission? submission;
  var completed = false;
}

const _existingTask = ConversationWorkflowTask(
  id: 'task-1',
  title: 'Existing task',
  status: ConversationWorkflowTaskStatus.inProgress,
  targetFiles: ['lib/one.dart', 'test/one_test.dart'],
  validationCommand: 'dart test',
  notes: 'Existing notes',
);

Future<_SheetHarness> _pumpSheetLauncher(
  WidgetTester tester, {
  ConversationWorkflowTask? task,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final harness = _SheetHarness();

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      useOnlyLangCode: true,
      saveLocale: false,
      assetLoader: const _TestTranslationLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: Scaffold(
            body: Builder(
              builder: (sheetContext) => Center(
                child: FilledButton(
                  onPressed: () async {
                    harness.submission =
                        await showModalBottomSheet<
                          WorkflowTaskEditorSubmission
                        >(
                          context: sheetContext,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (context) => WorkflowTaskEditorSheet(
                            task: task,
                            statusLabelBuilder: (status) => status.name,
                          ),
                        );
                    harness.completed = true;
                  },
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
  return harness;
}

List<TextField> _textFields(WidgetTester tester) => tester
    .widgetList<TextField>(find.byType(TextField))
    .toList(growable: false);

Future<void> _tapSheetAction(WidgetTester tester, String label) async {
  final action = find.text(label);
  expect(action, findsOneWidget);
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('seeds all fields and status from an existing task', (
    tester,
  ) async {
    await _pumpSheetLauncher(tester, task: _existingTask);

    final fields = _textFields(tester);
    expect(fields, hasLength(4));
    expect(fields[0].controller?.text, 'Existing task');
    expect(fields[1].controller?.text, 'lib/one.dart\ntest/one_test.dart');
    expect(fields[2].controller?.text, 'dart test');
    expect(fields[3].controller?.text, 'Existing notes');
    expect(find.text('inProgress'), findsOneWidget);
    expect(find.text('Delete task'), findsOneWidget);
  });

  testWidgets('normalizes edited task fields and preserves the ID', (
    tester,
  ) async {
    final harness = await _pumpSheetLauncher(tester, task: _existingTask);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '  Updated task  ');
    await tester.enterText(fields.at(1), ' lib/a.dart \n\n test/a_test.dart ');
    await tester.enterText(fields.at(2), '  flutter test  ');
    await tester.enterText(fields.at(3), '  Updated notes  ');
    await tester.tap(find.text('inProgress'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('blocked').last);
    await tester.pumpAndSettle();
    await _tapSheetAction(tester, 'Save');

    expect(harness.completed, isTrue);
    expect(harness.submission?.action, WorkflowTaskEditorAction.save);
    final task = harness.submission!.task;
    expect(task.id, 'task-1');
    expect(task.title, 'Updated task');
    expect(task.status, ConversationWorkflowTaskStatus.blocked);
    expect(task.targetFiles, ['lib/a.dart', 'test/a_test.dart']);
    expect(task.validationCommand, 'flutter test');
    expect(task.notes, 'Updated notes');
  });

  testWidgets('new task defaults to pending and has no delete action', (
    tester,
  ) async {
    final harness = await _pumpSheetLauncher(tester);

    expect(find.text('pending'), findsOneWidget);
    expect(find.text('Delete task'), findsNothing);
    await _tapSheetAction(tester, 'Save');

    expect(harness.submission?.action, WorkflowTaskEditorAction.save);
    expect(harness.submission?.task.id, isEmpty);
    expect(
      harness.submission?.task.status,
      ConversationWorkflowTaskStatus.pending,
    );
  });

  testWidgets('delete returns the existing task', (tester) async {
    final harness = await _pumpSheetLauncher(tester, task: _existingTask);

    await _tapSheetAction(tester, 'Delete task');

    expect(harness.completed, isTrue);
    expect(harness.submission?.action, WorkflowTaskEditorAction.delete);
    expect(harness.submission?.task, _existingTask);
  });

  testWidgets('cancel closes without a submission', (tester) async {
    final harness = await _pumpSheetLauncher(tester, task: _existingTask);

    await _tapSheetAction(tester, 'Cancel');

    expect(harness.completed, isTrue);
    expect(harness.submission, isNull);
  });
}
