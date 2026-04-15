import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/core/utils/logger.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

import 'test_support/plan_mode_scenario_spec.dart';
import 'test_support/screenshot_capture.dart';

class _NoOpNotificationService extends NotificationService {
  @override
  Future<void> init() async {}

  @override
  Future<void> showResponseCompleteNotification(
    String title,
    String body,
  ) async {}
}

class _ScenarioRunResult {
  const _ScenarioRunResult({
    required this.outputDirectoryPath,
    required this.reportPath,
    required this.screenshotPaths,
  });

  final String outputDirectoryPath;
  final String reportPath;
  final List<String> screenshotPaths;
}

Future<Widget> _buildScenarioApp({
  required SharedPreferences prefs,
  required Box<String> conversationBox,
  required Box<String> memoryBox,
  required ChatDataSource dataSource,
  required PlanModeScenarioSpec scenario,
  required GlobalKey screenshotBoundaryKey,
}) async {
  await EasyLocalization.ensureInitialized();
  return EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('ja')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    useOnlyLangCode: true,
    child: Builder(
      builder: (context) {
        return ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            conversationBoxProvider.overrideWithValue(conversationBox),
            chatMemoryBoxProvider.overrideWithValue(memoryBox),
            chatRemoteDataSourceProvider.overrideWithValue(dataSource),
            mcpToolServiceProvider.overrideWithValue(
              FakePlanModeMcpToolService(scenario),
            ),
            notificationServiceProvider.overrideWithValue(
              _NoOpNotificationService(),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => RepaintBoundary(
              key: screenshotBoundaryKey,
              child: child ?? const SizedBox.shrink(),
            ),
            title: 'Caverno',
            debugShowCheckedModeBanner: false,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
            ),
            themeMode: ThemeMode.dark,
            home: const ChatPage(),
          ),
        );
      },
    ),
  );
}

Future<void> _resolvePlanningDecisions(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  PlanModeScenarioSpec scenario,
  GlobalKey screenshotBoundaryKey,
  Directory outputDirectory,
) async {
  for (var index = 0; index < scenario.decisionSelections.length; index++) {
    final selection = scenario.decisionSelections[index];

    await tester.pumpAndSettle();
    _assertUiExpectations(
      tester,
      scenario.uiExpectations,
      PlanModeUiPhase.decision,
    );
    expect(find.text(selection.question), findsOneWidget);

    await captureIntegrationScreenshot(
      binding: binding,
      tester: tester,
      repaintBoundaryKey: screenshotBoundaryKey,
      name: 'plan_mode_${scenario.name}_decision_${index + 1}',
      outputDirectory: outputDirectory,
    );

    if (selection.freeTextAnswer != null) {
      await tester.enterText(
        find.byType(TextField).last,
        selection.freeTextAnswer!,
      );
      await tester.pumpAndSettle();
    } else {
      final optionFinder = find.text(selection.optionLabel!);
      expect(optionFinder, findsAtLeastNWidgets(1));
      await tester.tap(optionFinder.last, warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    final confirmFinder = find.text('Continue with this choice');
    expect(confirmFinder, findsOneWidget);
    await tester.tap(confirmFinder, warnIfMissed: false);
    await tester.pump();
    await tester.pumpAndSettle();
  }
}

void _assertUiExpectations(
  WidgetTester tester,
  List<PlanModeUiExpectation> expectations,
  PlanModeUiPhase phase,
) {
  for (final expectation in expectations.where((item) => item.phase == phase)) {
    final finder = find.textContaining(expectation.text);
    if (expectation.shouldBePresent) {
      expect(
        finder,
        findsAtLeastNWidgets(expectation.minCount),
        reason:
            'Expected UI to show "${expectation.text}" during $phase at least ${expectation.minCount} time(s).',
      );
    } else {
      expect(
        finder,
        findsNothing,
        reason: 'Expected UI to hide "${expectation.text}" during $phase.',
      );
    }
  }
}

void _assertArtifactExpectations(
  Directory scenarioDir,
  List<PlanModeArtifactExpectation> expectations,
) {
  for (final expectation in expectations) {
    final file = File('${scenarioDir.path}/${expectation.path}');
    expect(
      file.existsSync(),
      expectation.shouldExist,
      reason: expectation.shouldExist
          ? 'Missing ${expectation.path}'
          : 'Expected ${expectation.path} to be absent',
    );
    if (!expectation.shouldExist) {
      continue;
    }

    final content = file.readAsStringSync();
    if (expectation.exactContent != null) {
      expect(content, expectation.exactContent);
    }
    for (final snippet in expectation.contains) {
      expect(
        content,
        contains(snippet),
        reason: 'Expected ${expectation.path} to contain "$snippet".',
      );
    }
    for (final snippet in expectation.absentSnippets) {
      expect(
        content,
        isNot(contains(snippet)),
        reason: 'Expected ${expectation.path} to exclude "$snippet".',
      );
    }
  }
}

void _assertLogExpectations(
  List<String> logs,
  List<PlanModeLogExpectation> expectations,
) {
  for (final expectation in expectations) {
    final count = logs
        .where((line) => line.contains(expectation.pattern))
        .length;

    if (expectation.exactCount != null) {
      expect(
        count,
        expectation.exactCount,
        reason:
            'Expected exactly ${expectation.exactCount} log(s) containing "${expectation.pattern}".',
      );
    }
    if (expectation.minCount != null) {
      expect(
        count,
        greaterThanOrEqualTo(expectation.minCount!),
        reason:
            'Expected at least ${expectation.minCount} log(s) containing "${expectation.pattern}".',
      );
    }
    if (expectation.maxCount != null) {
      expect(
        count,
        lessThanOrEqualTo(expectation.maxCount!),
        reason:
            'Expected at most ${expectation.maxCount} log(s) containing "${expectation.pattern}".',
      );
    }
  }
}

List<String> _listScenarioScreenshotPaths(Directory scenarioDir) {
  final screenshots = scenarioDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.png'))
      .map((file) => file.path)
      .toList(growable: false);
  screenshots.sort();
  return screenshots;
}

Future<_ScenarioRunResult> _runScenario({
  required WidgetTester tester,
  required IntegrationTestWidgetsFlutterBinding binding,
  required Box<String> conversationBox,
  required Box<String> memoryBox,
  required List<String> logs,
  required PlanModeScenarioSpec scenario,
  required Directory scenarioDir,
}) async {
  final project = CodingProject(
    id: 'project-${scenario.name}',
    name: scenario.projectName,
    rootPath: scenarioDir.path,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  final settings = AppSettings.defaults().copyWith(
    assistantMode: AssistantMode.plan,
    language: 'en',
    mcpEnabled: true,
    mcpUrl: '',
    mcpUrls: const [],
    mcpServers: const [],
    confirmFileMutations: false,
    confirmLocalCommands: false,
    confirmGitWrites: false,
    showMemoryUpdates: false,
  );

  SharedPreferences.setMockInitialValues({
    'app_settings': jsonEncode(settings.toJson()),
    'coding_projects': jsonEncode([project.toJson()]),
  });
  final prefs = await SharedPreferences.getInstance();
  final screenshotBoundaryKey = GlobalKey();

  await tester.pumpWidget(
    await _buildScenarioApp(
      prefs: prefs,
      conversationBox: conversationBox,
      memoryBox: memoryBox,
      dataSource: FakePlanModeChatDataSource(scenario),
      scenario: scenario,
      screenshotBoundaryKey: screenshotBoundaryKey,
    ),
  );
  await tester.pumpAndSettle();

  final container = ProviderScope.containerOf(
    tester.element(find.byType(ChatPage)),
    listen: false,
  );
  container
      .read(codingProjectsNotifierProvider.notifier)
      .selectProject(project.id);
  container
      .read(conversationsNotifierProvider.notifier)
      .activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
        createIfMissing: true,
      );
  await tester.pumpAndSettle();

  expect(find.text('Coding'), findsOneWidget);
  expect(find.text('Plan mode'), findsAtLeastNWidgets(1));

  await tester.enterText(find.byType(TextField), scenario.userPrompt);
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.send));
  await tester.pump();
  await tester.pumpAndSettle();

  await _resolvePlanningDecisions(
    tester,
    binding,
    scenario,
    screenshotBoundaryKey,
    scenarioDir,
  );

  _assertUiExpectations(
    tester,
    scenario.uiExpectations,
    PlanModeUiPhase.proposal,
  );
  expect(find.text('Approve and start'), findsOneWidget);

  await captureIntegrationScreenshot(
    binding: binding,
    tester: tester,
    repaintBoundaryKey: screenshotBoundaryKey,
    name: 'plan_mode_${scenario.name}_proposal',
    outputDirectory: scenarioDir,
  );

  final approveFinder = find.text('Approve and start');
  await tester.ensureVisible(approveFinder);
  await tester.tap(approveFinder, warnIfMissed: false);
  await tester.pump();
  await tester.pumpAndSettle();

  _assertArtifactExpectations(
    scenarioDir,
    scenario.resolvedArtifactExpectations,
  );

  _assertUiExpectations(
    tester,
    scenario.uiExpectations,
    PlanModeUiPhase.finalResult,
  );

  _assertLogExpectations(logs, scenario.logExpectations);

  final currentConversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  expect(currentConversation, isNotNull);
  final conversation = currentConversation!;
  final workflowExpectation = scenario.resolvedWorkflowExpectation;
  final savedWorkflow = conversation.effectiveWorkflowSpec;
  if (workflowExpectation.stage != null) {
    expect(conversation.workflowStage, workflowExpectation.stage);
  }
  if (workflowExpectation.goal != null) {
    expect(savedWorkflow.goal, workflowExpectation.goal);
  }
  if (workflowExpectation.taskCount != null) {
    expect(savedWorkflow.tasks, hasLength(workflowExpectation.taskCount!));
  }
  if (workflowExpectation.firstTaskTitle != null) {
    expect(savedWorkflow.tasks.first.title, workflowExpectation.firstTaskTitle);
  }
  for (final openQuestion in workflowExpectation.openQuestionsContain) {
    expect(savedWorkflow.openQuestions, contains(openQuestion));
  }

  await captureIntegrationScreenshot(
    binding: binding,
    tester: tester,
    repaintBoundaryKey: screenshotBoundaryKey,
    name: 'plan_mode_${scenario.name}_completed',
    outputDirectory: scenarioDir,
  );

  final report = <String, dynamic>{
    'scenario': scenario.name,
    'status': 'passed',
    'projectRoot': scenarioDir.path,
    'workflowStage': conversation.workflowStage.name,
    'workflowGoal': savedWorkflow.goal,
    'workflowOpenQuestions': savedWorkflow.openQuestions,
    'selectedDecisions': scenario.decisionSelections
        .map(
          (selection) => <String, String?>{
            'question': selection.question,
            'optionLabel': selection.optionLabel,
            'freeTextAnswer': selection.freeTextAnswer,
          },
        )
        .toList(growable: false),
    'artifacts': <String, String>{
      for (final artifact in scenario.resolvedArtifactExpectations.where(
        (item) => item.shouldExist,
      ))
        artifact.path: File(
          '${scenarioDir.path}/${artifact.path}',
        ).readAsStringSync(),
    },
    'logChecks': scenario.logExpectations
        .map(
          (expectation) => <String, Object?>{
            'pattern': expectation.pattern,
            'exactCount': expectation.exactCount,
            'minCount': expectation.minCount,
            'maxCount': expectation.maxCount,
          },
        )
        .toList(growable: false),
    'capturedLogs': logs
        .where(
          (line) =>
              line.contains('[ScenarioLLM]') ||
              line.contains('[Tool]') ||
              line.contains('[LLM]') ||
              line.contains('[ContentTool]') ||
              line.contains('[Screenshot]'),
        )
        .toList(growable: false),
  };
  final screenshotPaths = _listScenarioScreenshotPaths(scenarioDir);
  report['screenshots'] = screenshotPaths;
  final reportFile = File('${scenarioDir.path}/scenario_report.json');
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  appLog('[Scenario] Report written to ${reportFile.path}');
  return _ScenarioRunResult(
    outputDirectoryPath: scenarioDir.path,
    reportPath: reportFile.path,
    screenshotPaths: screenshotPaths,
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final scenarios = buildPlanModeScenarios();

  group('Plan mode scenarios', () {
    late Box<String> conversationBox;
    late Box<String> memoryBox;
    late DebugPrintCallback originalDebugPrint;
    late List<String> logs;
    final suiteResults = <Map<String, Object?>>[];

    setUp(() async {
      await Hive.initFlutter();
      await EasyLocalization.ensureInitialized();

      logs = <String>[];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          logs.add(message);
        }
        originalDebugPrint(message, wrapWidth: wrapWidth);
      };

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      conversationBox = await Hive.openBox<String>('plan_mode_conv_$timestamp');
      memoryBox = await Hive.openBox<String>('plan_mode_mem_$timestamp');
    });

    tearDown(() async {
      debugPrint = originalDebugPrint;
      await conversationBox.close();
      await memoryBox.close();
    });

    tearDownAll(() async {
      final reportDirectory = Directory(
        '/Users/noguwo/Documents/Workspace/Flutter/caverno/build/integration_test_reports',
      );
      await reportDirectory.create(recursive: true);

      final passedCount = suiteResults
          .where((result) => result['status'] == 'passed')
          .length;
      final suiteReport = <String, Object?>{
        'generatedAt': DateTime.now().toIso8601String(),
        'suite': 'plan_mode_scenarios',
        'scenarioCount': suiteResults.length,
        'passedCount': passedCount,
        'failedCount': suiteResults.length - passedCount,
        'scenarios': suiteResults,
      };
      final suiteReportFile = File(
        '${reportDirectory.path}/plan_mode_suite_report.json',
      );
      await suiteReportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(suiteReport),
      );
      appLog('[ScenarioSuite] Report written to ${suiteReportFile.path}');
    });

    for (final scenario in scenarios) {
      testWidgets('runs ${scenario.name}', (tester) async {
        final startedAt = DateTime.now();
        final scenarioDir = await Directory.systemTemp.createTemp(
          'caverno_plan_mode_${scenario.name}_',
        );
        _ScenarioRunResult? runResult;
        Object? failure;
        try {
          runResult = await _runScenario(
            tester: tester,
            binding: binding,
            conversationBox: conversationBox,
            memoryBox: memoryBox,
            logs: logs,
            scenario: scenario,
            scenarioDir: scenarioDir,
          );
        } catch (error) {
          failure = error;
          rethrow;
        } finally {
          final finishedAt = DateTime.now();
          suiteResults.add(<String, Object?>{
            'scenario': scenario.name,
            'status': failure == null ? 'passed' : 'failed',
            'startedAt': startedAt.toIso8601String(),
            'finishedAt': finishedAt.toIso8601String(),
            'durationMs': finishedAt.difference(startedAt).inMilliseconds,
            'outputDirectory':
                runResult?.outputDirectoryPath ?? scenarioDir.path,
            'scenarioReport': runResult?.reportPath,
            'screenshots':
                runResult?.screenshotPaths ??
                _listScenarioScreenshotPaths(scenarioDir),
            'error': failure?.toString(),
          });
        }
      });
    }
  });
}
