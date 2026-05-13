import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/presentation/widgets/plan/plan_hydrated_task_row.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final localeName = locale.countryCode == null || locale.countryCode!.isEmpty
        ? locale.languageCode
        : '${locale.languageCode}-${locale.countryCode}';
    final file = File('$path/$localeName.json');
    final fallbackFile = File('$path/${locale.languageCode}.json');
    final source = file.existsSync() ? file : fallbackFile;
    return jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
  }
}

Future<void> _pumpTaskRow(
  WidgetTester tester, {
  required ConversationWorkflowTask task,
  ConversationExecutionTaskProgress? progress,
}) async {
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
        builder: (context) {
          return MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Scaffold(
              body: PlanHydratedTaskRow(task: task, progress: progress),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('explains blocked tasks with a recovery next step', (
    tester,
  ) async {
    const task = ConversationWorkflowTask(
      id: 'task-1',
      title: 'Implement ping CLI',
      status: ConversationWorkflowTaskStatus.blocked,
    );
    final progress = ConversationExecutionTaskProgress(
      taskId: 'task-1',
      status: ConversationWorkflowTaskStatus.blocked,
      blockedReason: 'Validation cannot reach the test host.',
      updatedAt: DateTime(2026, 5, 13, 10),
      events: [
        ConversationExecutionTaskEvent(
          type: ConversationExecutionTaskEventType.blocked,
          createdAt: DateTime(2026, 5, 13, 10),
          status: ConversationWorkflowTaskStatus.blocked,
          blockedReason: 'Validation cannot reach the test host.',
        ),
      ],
    );

    await _pumpTaskRow(tester, task: task, progress: progress);

    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('Blocked reason: ', findRichText: true), findsNothing);
    expect(
      find.text(
        'Blocked reason: Validation cannot reach the test host.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Next step: Resolve the blocker, then retry validation or replan from the blocker.',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('explains failed validation before continuing', (tester) async {
    const task = ConversationWorkflowTask(
      id: 'task-2',
      title: 'Validate ping CLI',
      status: ConversationWorkflowTaskStatus.inProgress,
    );
    const progress = ConversationExecutionTaskProgress(
      taskId: 'task-2',
      status: ConversationWorkflowTaskStatus.inProgress,
      validationStatus: ConversationExecutionValidationStatus.failed,
      lastValidationCommand: 'python3 ping_cli.py --help',
      lastValidationSummary: 'The command exited with code 1.',
    );

    await _pumpTaskRow(tester, task: task, progress: progress);

    expect(find.text('Failed'), findsOneWidget);
    expect(
      find.text(
        'Next step: Review the failed validation, then retry validation or replan this task.',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps completed tasks clearly terminal', (tester) async {
    const task = ConversationWorkflowTask(
      id: 'task-3',
      title: 'Document final validation',
      status: ConversationWorkflowTaskStatus.completed,
    );
    const progress = ConversationExecutionTaskProgress(
      taskId: 'task-3',
      status: ConversationWorkflowTaskStatus.completed,
      validationStatus: ConversationExecutionValidationStatus.passed,
      summary: 'The task is complete.',
    );

    await _pumpTaskRow(tester, task: task, progress: progress);

    expect(find.text('Completed'), findsOneWidget);
    expect(
      find.text(
        'Next step: This task is complete. Continue with the next pending task or review the result.',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });
}
