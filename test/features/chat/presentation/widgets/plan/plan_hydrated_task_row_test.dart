import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/widgets/plan/plan_hydrated_task_row.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  bool accepted = false,
  List<String> acceptanceEvidence = const [],
  String acceptanceRationale = '',
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
              body: PlanHydratedTaskRow(
                task: task,
                progress: progress,
                acceptance: accepted
                    ? ConversationTaskAcceptance(
                        taskId: task.id,
                        acceptedAt: DateTime(2026, 9, 13),
                        evidence: acceptanceEvidence,
                        rationale: acceptanceRationale,
                      )
                    : null,
              ),
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

  testWidgets('an accepted task says so, over its verification', (
    tester,
  ) async {
    const task = ConversationWorkflowTask(
      id: 'task-5',
      title: 'Read the spec',
      status: ConversationWorkflowTaskStatus.completed,
    );
    const progress = ConversationExecutionTaskProgress(
      taskId: 'task-5',
      status: ConversationWorkflowTaskStatus.completed,
      validationStatus: ConversationExecutionValidationStatus.passed,
    );

    await _pumpTaskRow(tester, task: task, progress: progress, accepted: true);

    expect(find.text('Accepted'), findsOneWidget);
    expect(
      find.text('Verified'),
      findsNothing,
      reason:
          'A judgement outranks the check it rested on; saying both would leave '
          'the reader to guess which one the panel means.',
    );
  });

  testWidgets('a finished task with no passing check reads produced', (
    tester,
  ) async {
    const task = ConversationWorkflowTask(
      id: 'task-4',
      title: 'Write the adapter',
      status: ConversationWorkflowTaskStatus.completed,
    );
    const progress = ConversationExecutionTaskProgress(
      taskId: 'task-4',
      status: ConversationWorkflowTaskStatus.completed,
      summary: 'The adapter is written.',
    );

    await _pumpTaskRow(tester, task: task, progress: progress);

    expect(find.text('Produced'), findsOneWidget);
    expect(
      find.text('Verified'),
      findsNothing,
      reason: 'Nothing checked it, so nothing may say it was checked.',
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

    // `Verified`, not `Completed`: the enum's completed answers produced,
    // verified and accepted at once, and this task's saved command passed.
    expect(find.text('Verified'), findsOneWidget);
    expect(
      find.text(
        'Next step: This task is complete. Continue with the next pending task or review the result.',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });
  testWidgets('an accepted task shows what the acceptance rested on', (
    tester,
  ) async {
    // The chip says `accepted`; until this row read them, the rationale and the
    // evidence were written by recordTaskAcceptance and read by nothing. A
    // state that owes an explanation and cannot give one sends the user back to
    // the conversation history, which is the work ANA4 exists to remove.
    await _pumpTaskRow(
      tester,
      task: const ConversationWorkflowTask(
        id: 'task-1',
        title: 'Summarize the spec',
        status: ConversationWorkflowTaskStatus.completed,
      ),
      accepted: true,
      acceptanceEvidence: const [
        'worktree branch feature/readme',
        'verified green: test -s README.md',
      ],
      acceptanceRationale: 'The summary covers every section of the spec.',
    );

    expect(
      find.text(
        'Accepted on: worktree branch feature/readme, '
        'verified green: test -s README.md',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Accepted because: The summary covers every section of the spec.',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('a task with no acceptance shows no acceptance detail', (
    tester,
  ) async {
    await _pumpTaskRow(
      tester,
      task: const ConversationWorkflowTask(
        id: 'task-1',
        title: 'Summarize the spec',
        status: ConversationWorkflowTaskStatus.completed,
      ),
    );

    expect(
      find.textContaining('Accepted on:', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('Accepted because:', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('an acceptance that recorded no evidence shows only the reason', (
    tester,
  ) async {
    // A subagent result passes no audit level, so its acceptance rests on the
    // parent's word alone and has nothing to list. An empty "Accepted on" row
    // would read as evidence that is missing rather than evidence that was
    // never owed.
    await _pumpTaskRow(
      tester,
      task: const ConversationWorkflowTask(
        id: 'task-1',
        title: 'Summarize the spec',
        status: ConversationWorkflowTaskStatus.completed,
      ),
      accepted: true,
      acceptanceRationale: 'The child read the spec and reported it back.',
    );

    expect(
      find.textContaining('Accepted on:', findRichText: true),
      findsNothing,
      reason:
          'an empty row would read as evidence that is missing rather than '
          'evidence that was never owed',
    );
    expect(
      find.textContaining('Accepted because:', findRichText: true),
      findsOneWidget,
    );
  });
  group('the companion panel row', () {
    Future<void> pumpCompanionRow(
      WidgetTester tester,
      Conversation conversation,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanionTaskRow(
              conversation: conversation,
              task: conversation.effectiveWorkflowSpec.tasks.single,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Conversation companionConversation({
      ConversationWorkflowTaskStatus status =
          ConversationWorkflowTaskStatus.pending,
      String blockedReason = '',
      List<String> acceptanceEvidence = const [],
      String acceptanceRationale = '',
    }) => Conversation(
      id: 'conversation-1',
      title: 'Plan thread',
      messages: const <Message>[],
      createdAt: DateTime(2026, 9, 14),
      updatedAt: DateTime(2026, 9, 14),
      workflowSpec: ConversationWorkflowSpec(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Add the CLI flags',
            status: status,
          ),
        ],
      ),
      executionProgress: [
        if (blockedReason.isNotEmpty)
          ConversationExecutionTaskProgress(
            taskId: 'task-1',
            status: status,
            blockedReason: blockedReason,
          ),
      ],
      taskAcceptances: [
        if (acceptanceEvidence.isNotEmpty || acceptanceRationale.isNotEmpty)
          ConversationTaskAcceptance(
            taskId: 'task-1',
            acceptedAt: DateTime(2026, 9, 14),
            evidence: acceptanceEvidence,
            rationale: acceptanceRationale,
          ),
      ],
    );

    testWidgets('a blocked task says why, where the label cannot', (
      tester,
    ) async {
      await pumpCompanionRow(
        tester,
        companionConversation(
          status: ConversationWorkflowTaskStatus.blocked,
          blockedReason: 'The validation command was refused for its shape.',
        ),
      );

      expect(
        find.text('The validation command was refused for its shape.'),
        findsOneWidget,
      );
    });

    testWidgets('an accepted task says what it was accepted on', (
      tester,
    ) async {
      await pumpCompanionRow(
        tester,
        companionConversation(
          status: ConversationWorkflowTaskStatus.completed,
          acceptanceEvidence: const ['worktree branch feature/cli'],
          acceptanceRationale: 'The flags match the spec.',
        ),
      );

      expect(
        find.text('worktree branch feature/cli -- The flags match the spec.'),
        findsOneWidget,
      );
    });

    testWidgets('an ordinary task carries neither line', (tester) async {
      await pumpCompanionRow(tester, companionConversation());

      expect(find.textContaining('--'), findsNothing);
      expect(find.text('Add the CLI flags'), findsOneWidget);
    });
  });
}
