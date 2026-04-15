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

Future<Widget> _buildScenarioApp({
  required SharedPreferences prefs,
  required Box<String> conversationBox,
  required Box<String> memoryBox,
  required ChatDataSource dataSource,
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
    expect(find.text('Choose Before Planning'), findsOneWidget);
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

void _assertExpectedLogs(
  List<String> logs,
  Map<String, int> expectedLogCounts,
) {
  for (final entry in expectedLogCounts.entries) {
    expect(
      logs.where((line) => line.contains(entry.key)),
      hasLength(entry.value),
      reason: 'Expected ${entry.value} log(s) containing "${entry.key}"',
    );
  }
}

Future<void> _runScenario({
  required WidgetTester tester,
  required IntegrationTestWidgetsFlutterBinding binding,
  required Box<String> conversationBox,
  required Box<String> memoryBox,
  required List<String> logs,
  required PlanModeScenarioSpec scenario,
}) async {
  final scenarioDir = await Directory.systemTemp.createTemp(
    'caverno_plan_mode_${scenario.name}_',
  );
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

  expect(find.text('Suggested plan'), findsOneWidget);
  expect(find.text('Approve and start'), findsOneWidget);
  for (final snippet in scenario.expectedProposalTextSnippets) {
    expect(find.textContaining(snippet), findsAtLeastNWidgets(1));
  }

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

  for (final artifact in scenario.expectedArtifacts.entries) {
    final file = File('${scenarioDir.path}/${artifact.key}');
    expect(file.existsSync(), isTrue, reason: 'Missing ${artifact.key}');
    expect(file.readAsStringSync(), artifact.value);
  }

  for (final snippet in scenario.expectedFinalTextSnippets) {
    expect(find.textContaining(snippet), findsAtLeastNWidgets(1));
  }

  _assertExpectedLogs(logs, scenario.expectedLogCounts);

  final currentConversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  expect(currentConversation, isNotNull);
  expect(
    currentConversation!.workflowSpec?.goal,
    scenario.finalWorkflowProposal.goal,
  );
  expect(
    currentConversation.workflowSpec?.tasks.first.title,
    scenario.initialTaskTitle,
  );

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
    'workflowGoal': currentConversation.workflowSpec?.goal,
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
      for (final artifact in scenario.expectedArtifacts.entries)
        artifact.key: File(
          '${scenarioDir.path}/${artifact.key}',
        ).readAsStringSync(),
    },
    'logChecks': scenario.expectedLogCounts,
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
  final reportFile = File('${scenarioDir.path}/scenario_report.json');
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  appLog('[Scenario] Report written to ${reportFile.path}');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final scenarios = buildPlanModeScenarios();

  group('Plan mode scenarios', () {
    late Box<String> conversationBox;
    late Box<String> memoryBox;
    late DebugPrintCallback originalDebugPrint;
    late List<String> logs;

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

    for (final scenario in scenarios) {
      testWidgets('runs ${scenario.name}', (tester) async {
        await _runScenario(
          tester: tester,
          binding: binding,
          conversationBox: conversationBox,
          memoryBox: memoryBox,
          logs: logs,
          scenario: scenario,
        );
      });
    }
  });
}
