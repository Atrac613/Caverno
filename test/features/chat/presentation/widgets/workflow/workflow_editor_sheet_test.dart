import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/presentation/coordinators/workflow_editor_action_coordinator.dart';
import 'package:caverno/features/chat/presentation/widgets/workflow/workflow_editor_sheet.dart';
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

class _SheetHarness {
  WorkflowEditorSubmission? submission;
  var completed = false;
}

const _existingTask = ConversationWorkflowTask(
  id: 'existing-task',
  title: 'Keep the existing task',
);

Conversation _conversation() {
  final now = DateTime(2026, 7, 17, 12);
  return Conversation(
    id: 'conversation-1',
    title: 'Workflow editor',
    messages: const [],
    createdAt: now,
    updatedAt: now,
    workspaceMode: WorkspaceMode.coding,
    workflowStage: ConversationWorkflowStage.clarify,
    workflowSpec: const ConversationWorkflowSpec(
      goal: 'Conversation goal',
      constraints: ['Conversation constraint'],
      acceptanceCriteria: ['Conversation acceptance'],
      openQuestions: ['Conversation question'],
      tasks: [_existingTask],
    ),
  );
}

Future<_SheetHarness> _pumpSheetLauncher(
  WidgetTester tester, {
  ConversationWorkflowStage? initialWorkflowStage,
  ConversationWorkflowSpec? initialWorkflowSpec,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final harness = _SheetHarness();
  final conversation = _conversation();

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
                        await showModalBottomSheet<WorkflowEditorSubmission>(
                          context: sheetContext,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (context) => WorkflowEditorSheet(
                            currentConversation: conversation,
                            initialWorkflowStage: initialWorkflowStage,
                            initialWorkflowSpec: initialWorkflowSpec,
                            workflowStageLabelBuilder: (stage) => stage.name,
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

  testWidgets('uses conversation stage and workflow fields by default', (
    tester,
  ) async {
    await _pumpSheetLauncher(tester);

    final fields = _textFields(tester);
    expect(fields, hasLength(4));
    expect(fields[0].controller?.text, 'Conversation goal');
    expect(fields[1].controller?.text, 'Conversation constraint');
    expect(fields[2].controller?.text, 'Conversation acceptance');
    expect(fields[3].controller?.text, 'Conversation question');
    expect(find.text('clarify'), findsOneWidget);
  });

  testWidgets('normalizes explicit initial values and retains current tasks', (
    tester,
  ) async {
    final harness = await _pumpSheetLauncher(
      tester,
      initialWorkflowStage: ConversationWorkflowStage.review,
      initialWorkflowSpec: const ConversationWorkflowSpec(
        goal: 'Initial goal',
        constraints: ['Initial constraint'],
        acceptanceCriteria: ['Initial acceptance'],
        openQuestions: ['Initial question'],
        tasks: [
          ConversationWorkflowTask(
            id: 'proposal-task',
            title: 'Do not retain this proposal task',
          ),
        ],
      ),
    );
    final fields = find.byType(TextField);
    expect(find.text('review'), findsOneWidget);
    expect(
      tester.widget<TextField>(fields.at(0)).controller?.text,
      'Initial goal',
    );

    await tester.enterText(fields.at(0), '  Revised goal  ');
    await tester.enterText(
      fields.at(1),
      ' first constraint \n\n second constraint ',
    );
    await tester.enterText(fields.at(2), ' acceptance one \n acceptance two ');
    await tester.enterText(fields.at(3), ' question one \n\n question two ');
    await _tapSheetAction(tester, 'Save');

    expect(harness.completed, isTrue);
    expect(harness.submission?.action, WorkflowEditorAction.save);
    expect(harness.submission?.workflowStage, ConversationWorkflowStage.review);
    final spec = harness.submission!.workflowSpec;
    expect(spec.goal, 'Revised goal');
    expect(spec.constraints, ['first constraint', 'second constraint']);
    expect(spec.acceptanceCriteria, ['acceptance one', 'acceptance two']);
    expect(spec.openQuestions, ['question one', 'question two']);
    expect(spec.tasks, [_existingTask]);
  });

  testWidgets('returns a typed clear submission', (tester) async {
    final harness = await _pumpSheetLauncher(tester);

    await _tapSheetAction(tester, 'Clear workflow');

    expect(harness.completed, isTrue);
    expect(harness.submission?.action, WorkflowEditorAction.clear);
    expect(harness.submission?.workflowStage, ConversationWorkflowStage.idle);
    expect(harness.submission?.workflowSpec.hasContent, isFalse);
  });

  testWidgets('cancel closes without a submission', (tester) async {
    final harness = await _pumpSheetLauncher(tester);

    await _tapSheetAction(tester, 'Cancel');

    expect(harness.completed, isTrue);
    expect(harness.submission, isNull);
  });
}
