import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/repositories/coding_project_repository.dart';
import 'package:caverno/features/chat/data/repositories/worktree_agent_task_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_git_worktree_preparer.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_executor.dart';
import 'package:caverno/features/chat/presentation/widgets/worktree_agent_task_banner.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('hides when no worktree agent tasks occupy a worktree', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await _pumpBanner(tester, prefs);

    expect(find.textContaining('worktree agent'), findsNothing);
  });

  testWidgets('surfaces interrupted tasks as recoverable after restart', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await WorktreeAgentTaskRepository(prefs).saveAll([
      WorktreeAgentTask(
        id: 'task-1',
        status: WorktreeAgentTaskStatus.running,
        title: 'Fix flaky widget test',
        prompt: 'Fix the failing widget test.',
        branchName: 'feature/fix-flaky-widget-test',
        worktreePath: '/tmp/caverno-worktrees/fix-flaky-widget-test',
        createdAt: DateTime.utc(2026, 6, 19),
        updatedAt: DateTime.utc(2026, 6, 19),
      ),
    ]);

    await _pumpBanner(tester, prefs);

    expect(find.text('1 worktree agent task(s) need recovery'), findsOneWidget);

    await tester.tap(find.text('1 worktree agent task(s) need recovery'));
    await tester.pumpAndSettle();

    expect(find.text('Worktree agent tasks'), findsOneWidget);
    expect(find.text('Fix flaky widget test'), findsOneWidget);
    expect(
      find.textContaining('feature/fix-flaky-widget-test'),
      findsOneWidget,
    );
    expect(find.textContaining('Needs recovery'), findsOneWidget);
    expect(
      find.text('Task was active when the app restarted.'),
      findsOneWidget,
    );
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('cancel removes a recoverable task from the banner', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await WorktreeAgentTaskRepository(prefs).saveAll([
      WorktreeAgentTask(
        id: 'task-1',
        status: WorktreeAgentTaskStatus.running,
        title: 'Fix flaky widget test',
        prompt: 'Fix the failing widget test.',
        branchName: 'feature/fix-flaky-widget-test',
        worktreePath: '/tmp/caverno-worktrees/fix-flaky-widget-test',
        createdAt: DateTime.utc(2026, 6, 19),
        updatedAt: DateTime.utc(2026, 6, 19),
      ),
    ]);

    await _pumpBanner(tester, prefs);
    await tester.tap(find.text('1 worktree agent task(s) need recovery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('No worktree agent tasks.'), findsOneWidget);
  });

  testWidgets('keeps verified completed tasks visible for review', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await WorktreeAgentTaskRepository(prefs).saveAll([
      WorktreeAgentTask(
        id: 'task-1',
        status: WorktreeAgentTaskStatus.completed,
        title: 'Update tool approval tests',
        prompt: 'Update the tool approval tests.',
        branchName: 'feature/ll13-tool-approval-tests',
        worktreePath: '/tmp/caverno-worktrees/tool-approval-tests',
        resultSummary: 'Updated the focused tests.',
        verifiedGreen: true,
        verificationSummary: 'Verification passed: fvm flutter test.',
        createdAt: DateTime.utc(2026, 6, 19),
        updatedAt: DateTime.utc(2026, 6, 19),
        finishedAt: DateTime.utc(2026, 6, 19, 1),
      ),
    ]);

    await _pumpBanner(tester, prefs);

    expect(
      find.text('1 worktree agent task(s) ready for review'),
      findsOneWidget,
    );

    await tester.tap(find.text('1 worktree agent task(s) ready for review'));
    await tester.pumpAndSettle();

    expect(find.text('Worktree agent tasks'), findsOneWidget);
    expect(find.text('Update tool approval tests'), findsOneWidget);
    expect(
      find.textContaining('feature/ll13-tool-approval-tests'),
      findsOneWidget,
    );
    expect(find.text('Verification passed'), findsOneWidget);
    expect(find.text('Verification passed: fvm flutter test.'), findsOneWidget);
    expect(find.text('Clear finished'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('panel section renders visible tasks inline', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await WorktreeAgentTaskRepository(prefs).saveAll([
      WorktreeAgentTask(
        id: 'task-1',
        status: WorktreeAgentTaskStatus.completed,
        title: 'Update tool approval tests',
        prompt: 'Update the tool approval tests.',
        branchName: 'feature/ll13-tool-approval-tests',
        worktreePath: '/tmp/caverno-worktrees/tool-approval-tests',
        resultSummary: 'Updated the focused tests.',
        verifiedGreen: true,
        verificationSummary: 'Verification passed: fvm flutter test.',
        createdAt: DateTime.utc(2026, 6, 19),
        updatedAt: DateTime.utc(2026, 6, 19),
        finishedAt: DateTime.utc(2026, 6, 19, 1),
      ),
    ]);

    await _pumpPanel(tester, prefs);

    expect(find.text('Worktree agent tasks'), findsOneWidget);
    expect(find.text('Update tool approval tests'), findsOneWidget);
    expect(
      find.textContaining('feature/ll13-tool-approval-tests'),
      findsOneWidget,
    );
    expect(find.text('Verification passed'), findsOneWidget);
    expect(find.text('Verification passed: fvm flutter test.'), findsOneWidget);
    expect(
      find.text('1 worktree agent task(s) ready for review'),
      findsNothing,
    );
  });

  testWidgets('keeps non-green completed tasks visible as finished', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await WorktreeAgentTaskRepository(prefs).saveAll([
      WorktreeAgentTask(
        id: 'task-1',
        status: WorktreeAgentTaskStatus.completed,
        title: 'Fix local stack smoke',
        prompt: 'Fix the local stack smoke test.',
        branchName: 'feature/ll13-local-stack-smoke',
        worktreePath: '/tmp/caverno-worktrees/local-stack-smoke',
        resultSummary: 'Updated the smoke harness.',
        verificationSummary: 'Verification failed: dart test.',
        createdAt: DateTime.utc(2026, 6, 19),
        updatedAt: DateTime.utc(2026, 6, 19),
        finishedAt: DateTime.utc(2026, 6, 19, 1),
      ),
    ]);

    await _pumpBanner(tester, prefs);

    expect(find.text('1 finished worktree agent task(s)'), findsOneWidget);

    await tester.tap(find.text('1 finished worktree agent task(s)'));
    await tester.pumpAndSettle();

    expect(find.text('Fix local stack smoke'), findsOneWidget);
    expect(find.text('Verification not green'), findsOneWidget);
    expect(find.text('Verification failed: dart test.'), findsOneWidget);
    expect(find.text('Clear finished'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('clear finished removes completed tasks from the sheet', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await WorktreeAgentTaskRepository(prefs).saveAll([
      WorktreeAgentTask(
        id: 'task-1',
        status: WorktreeAgentTaskStatus.completed,
        title: 'Review ready task',
        prompt: 'Finish a review ready task.',
        branchName: 'feature/ll13-review-ready',
        worktreePath: '/tmp/caverno-worktrees/review-ready',
        verifiedGreen: true,
        verificationSummary: 'Verification passed.',
        createdAt: DateTime.utc(2026, 6, 19),
        updatedAt: DateTime.utc(2026, 6, 19),
        finishedAt: DateTime.utc(2026, 6, 19, 1),
      ),
    ]);

    await _pumpBanner(tester, prefs);
    await tester.tap(find.text('1 worktree agent task(s) ready for review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear finished'));
    await tester.pumpAndSettle();

    expect(find.text('No worktree agent tasks.'), findsOneWidget);
  });

  testWidgets('run ready starts and executes queued tasks from the sheet', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await CodingProjectRepository(prefs).saveAll([
      CodingProject(
        id: 'project-1',
        name: 'caverno',
        rootPath: '/repo/app',
        createdAt: DateTime.utc(2026, 6, 19),
        updatedAt: DateTime.utc(2026, 6, 19),
      ),
    ]);
    await WorktreeAgentTaskRepository(prefs).saveAll([
      WorktreeAgentTask(
        id: 'task-1',
        status: WorktreeAgentTaskStatus.queued,
        title: 'Fix queued task',
        prompt: 'Fix the queued task.',
        codingProjectId: 'project-1',
        branchName: 'feature/ll13-fix-queued-task',
        worktreePath: '/tmp/caverno-worktrees/fix-queued-task',
        createdAt: DateTime.utc(2026, 6, 19),
        updatedAt: DateTime.utc(2026, 6, 19),
      ),
    ]);
    final contexts = <WorktreeAgentTaskExecutionContext>[];

    await _pumpBanner(
      tester,
      prefs,
      worktreePreparer: WorktreeAgentGitWorktreePreparer(
        ensureParentDirectory: (_) async {},
        runProcess: (executable, arguments, {workingDirectory}) async {
          if (_argumentsEqual(arguments, const [
            'rev-parse',
            '--show-toplevel',
          ])) {
            return ProcessResult(1, 0, workingDirectory ?? '', '');
          }
          return ProcessResult(2, 0, 'created', '');
        },
      ),
      executionDelegate: (context) async {
        contexts.add(context);
        return const WorktreeAgentTaskExecutionOutcome(
          resultSummary: 'Implemented the queued task.',
          verifiedGreen: true,
          verificationSummary: 'flutter test passed',
        );
      },
    );

    await tester.tap(find.text('1 worktree agent task(s) need recovery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run ready'));
    await tester.pumpAndSettle();

    expect(contexts.single.taskId, 'task-1');
    expect(
      find.text('Last run: 1 started, 1 executed, 0 failed, 0 skipped.'),
      findsOneWidget,
    );
    expect(find.text('Verification passed'), findsOneWidget);
    expect(find.text('flutter test passed'), findsOneWidget);
    expect(find.text('Clear finished'), findsOneWidget);
    expect(find.text('Run ready'), findsNothing);
  });

  testWidgets('run ready surfaces skipped tasks in the sheet summary', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await WorktreeAgentTaskRepository(prefs).saveAll([
      WorktreeAgentTask(
        id: 'task-1',
        status: WorktreeAgentTaskStatus.queued,
        title: 'Fix queued task',
        prompt: 'Fix the queued task.',
        branchName: 'feature/ll13-fix-queued-task',
        worktreePath: '/tmp/caverno-worktrees/fix-queued-task',
        createdAt: DateTime.utc(2026, 6, 19),
        updatedAt: DateTime.utc(2026, 6, 19),
      ),
    ]);

    await _pumpBanner(tester, prefs);

    await tester.tap(find.text('1 worktree agent task(s) need recovery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run ready'));
    await tester.pumpAndSettle();

    expect(
      find.text('Last run: 0 started, 0 executed, 0 failed, 1 skipped.'),
      findsOneWidget,
    );
    expect(find.text('Run ready'), findsOneWidget);
    expect(find.textContaining('Queued'), findsOneWidget);
  });
}

Future<void> _pumpBanner(
  WidgetTester tester,
  SharedPreferences prefs, {
  WorktreeAgentGitWorktreePreparer? worktreePreparer,
  WorktreeAgentTaskExecutionDelegate? executionDelegate,
}) async {
  await _pumpWorktreeAgentWidget(
    tester,
    prefs,
    child: const WorktreeAgentTaskBanner(),
    worktreePreparer: worktreePreparer,
    executionDelegate: executionDelegate,
  );
}

Future<void> _pumpPanel(
  WidgetTester tester,
  SharedPreferences prefs, {
  WorktreeAgentGitWorktreePreparer? worktreePreparer,
  WorktreeAgentTaskExecutionDelegate? executionDelegate,
}) async {
  await _pumpWorktreeAgentWidget(
    tester,
    prefs,
    child: const WorktreeAgentTaskPanelSection(),
    worktreePreparer: worktreePreparer,
    executionDelegate: executionDelegate,
  );
}

Future<void> _pumpWorktreeAgentWidget(
  WidgetTester tester,
  SharedPreferences prefs, {
  required Widget child,
  WorktreeAgentGitWorktreePreparer? worktreePreparer,
  WorktreeAgentTaskExecutionDelegate? executionDelegate,
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
          return ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              if (worktreePreparer != null)
                worktreeAgentGitWorktreePreparerProvider.overrideWithValue(
                  worktreePreparer,
                ),
              if (executionDelegate != null)
                worktreeAgentTaskExecutionDelegateProvider.overrideWithValue(
                  executionDelegate,
                ),
            ],
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: Scaffold(body: child),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _argumentsEqual(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
