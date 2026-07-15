import 'dart:async';
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
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

import 'test_support/plan_mode_scenario_spec.dart';
import 'test_support/plan_mode_approval_progress.dart';
import 'test_support/plan_mode_approval_ui.dart';
import 'test_support/plan_mode_artifact_expectations.dart';
import 'test_support/plan_mode_execution_progress.dart';
import 'test_support/plan_mode_expectations.dart';
import 'test_support/plan_mode_heartbeat.dart';
import 'test_support/plan_mode_live_harness_execution.dart';
import 'test_support/plan_mode_live_harness_fallback.dart';
import 'test_support/plan_mode_planning_proposal_wait.dart';
import 'test_support/plan_mode_post_scenario_settle.dart';
import 'test_support/plan_mode_prompt_submission.dart';
import 'test_support/plan_mode_report_summary.dart';
import 'test_support/plan_mode_saved_workflow_assertions.dart';
import 'test_support/plan_mode_screenshot_policy.dart';
import 'test_support/plan_mode_scenario_reporting.dart';
import 'test_support/plan_mode_scenario_seed_files.dart';
import 'test_support/plan_mode_suite_report.dart';
import 'test_support/plan_mode_warning_policy.dart';
import 'test_support/plan_mode_scenario_config.dart';
import 'test_support/plan_mode_workflow_execution_completion.dart';

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
    required this.logPath,
  });

  final String outputDirectoryPath;
  final String reportPath;
  final List<String> screenshotPaths;
  final String logPath;
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
    startLocale: Locale(scenario.languageCode),
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

Future<_ScenarioRunResult> _runScenario({
  required WidgetTester tester,
  required IntegrationTestWidgetsFlutterBinding binding,
  required Box<String> conversationBox,
  required Box<String> memoryBox,
  required List<String> logs,
  required PlanModeScenarioTestConfig config,
  required PlanModeScenarioSpec scenario,
  required Directory scenarioDir,
  required PlanModePhaseTrace phaseTrace,
  required PlanModeTimeoutBudgets budgets,
  required String heartbeatPath,
  required PlanModePlanningReadyObserver planningReadyObserver,
}) async {
  await seedPlanModeScenarioFiles(
    scenarioDir: scenarioDir,
    seedFiles: scenario.seedFiles,
  );
  final heartbeatWriter = PlanModeLiveHeartbeatWriter(
    scenarioName: scenario.name,
    path: heartbeatPath,
  );
  final project = CodingProject(
    id: 'project-${scenario.name}',
    name: scenario.projectName,
    rootPath: scenarioDir.path,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  final settings = AppSettings.defaults().copyWith(
    baseUrl: config.baseUrl ?? AppSettings.defaults().baseUrl,
    model: config.model ?? AppSettings.defaults().model,
    apiKey: config.apiKey ?? AppSettings.defaults().apiKey,
    temperature: scenario.temperature ?? AppSettings.defaults().temperature,
    maxTokens: scenario.maxTokens ?? AppSettings.defaults().maxTokens,
    assistantMode: AssistantMode.plan,
    language: scenario.languageCode,
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
  final dataSource = config.usesLiveLlm
      ? ChatRemoteDataSource(baseUrl: settings.baseUrl, apiKey: settings.apiKey)
      : FakePlanModeChatDataSource(scenario);

  await tester.pumpWidget(
    await _buildScenarioApp(
      prefs: prefs,
      conversationBox: conversationBox,
      memoryBox: memoryBox,
      dataSource: dataSource,
      scenario: scenario,
      screenshotBoundaryKey: screenshotBoundaryKey,
    ),
  );
  await pumpPlanModeUntilIdle(tester);
  heartbeatWriter.write(
    phase: 'startup',
    subphase: 'appReady',
    phaseTrace: phaseTrace,
    budgets: budgets,
    messageCount: 0,
    hasPendingApprovals: false,
    isLoading: false,
  );

  final container = ProviderScope.containerOf(
    tester.element(find.byType(ChatPage)),
    listen: false,
  );
  planningReadyObserver.configure(
    phaseTrace: phaseTrace,
    budgets: budgets,
    heartbeatWriter: heartbeatWriter,
    workflowSnapshotResolver: () {
      final conversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;
      return summarizePlanModeWorkflowTasks(
        conversation?.projectedExecutionTasks ??
            const <ConversationWorkflowTask>[],
      );
    },
    messageCountResolver: () {
      final conversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;
      return conversation?.messages.length ?? 0;
    },
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
  await pumpPlanModeUntilIdle(tester);

  expect(
    container
        .read(conversationsNotifierProvider)
        .currentConversation
        ?.workspaceMode,
    WorkspaceMode.coding,
  );

  await submitPlanModeScenarioPrompt(
    tester,
    container,
    config: config,
    scenario: scenario,
  );
  heartbeatWriter.write(
    phase: 'planning',
    subphase: 'promptSubmitted',
    phaseTrace: phaseTrace,
    budgets: budgets,
  );

  await waitForReadyPlanModeProposal(
    tester,
    container,
    timeout: budgets.planningTimeout,
    phaseTrace: phaseTrace,
    heartbeatWriter: heartbeatWriter,
    budgets: budgets,
    binding: binding,
    config: config,
    scenario: scenario,
    screenshotBoundaryKey: screenshotBoundaryKey,
    outputDirectory: scenarioDir,
    logs: logs,
  );

  appLog('[Workflow] Waiting for proposal approval UI');
  heartbeatWriter.write(
    phase: 'planning',
    subphase: 'proposalUiWait',
    phaseTrace: phaseTrace,
    budgets: budgets,
  );
  final proposalUiReady = await waitForPlanModeReviewablePlanApprovalUi(
    tester,
    container,
    timeout: const Duration(seconds: 20),
    allowArtifactReadyFallback: config.usesLiveLlm || config.usesHeadlessRunner,
  );
  final approvalFallbackDecision = resolvePlanModeApprovalFallbackDecision(
    proposalUiReady: proposalUiReady,
    usesLiveLlm: config.usesLiveLlm || config.usesHeadlessRunner,
  );
  PlanModeHarnessExecutionHandle? harnessExecutionHandle;
  if (approvalFallbackDecision.shouldBypassUi) {
    appLog(approvalFallbackDecision.bypassLogMessage!);
    heartbeatWriter.write(
      phase: 'planning',
      subphase: approvalFallbackDecision.bypassHeartbeatSubphase!,
      phaseTrace: phaseTrace,
      budgets: budgets,
    );
    harnessExecutionHandle = await approvePlanAndStartPlanModeHarnessExecution(
      container,
      scenarioDir: scenarioDir,
      phaseTrace: phaseTrace,
      heartbeatWriter: heartbeatWriter,
      budgets: budgets,
      taskExecutionLimit: scenario.harnessTaskExecutionLimit,
      languageCode: scenario.languageCode,
    );
  } else if (approvalFallbackDecision.shouldFailMissingUi) {
    throw StateError(approvalFallbackDecision.missingUiFailureMessage!);
  } else {
    assertPlanModeUiExpectations(
      tester,
      scenario.uiExpectations,
      PlanModeUiPhase.proposal,
    );
    expect(find.text('Approve and start'), findsAtLeastNWidgets(1));
    appLog('[Workflow] Proposal approval UI visible');
    heartbeatWriter.write(
      phase: 'planning',
      subphase: 'proposalUiReady',
      phaseTrace: phaseTrace,
      budgets: budgets,
    );

    if (shouldCapturePlanModeScenarioScreenshot(
      usesLiveLlm: config.usesLiveLlm,
    )) {
      heartbeatWriter.write(
        phase: 'planning',
        subphase: 'proposalScreenshotStarted',
        phaseTrace: phaseTrace,
        budgets: budgets,
      );
    }
    final proposalScreenshot = await capturePlanModeScenarioScreenshot(
      usesLiveLlm: config.usesLiveLlm,
      binding: binding,
      tester: tester,
      repaintBoundaryKey: screenshotBoundaryKey,
      scenarioName: scenario.name,
      phase: PlanModeScreenshotPhase.proposal,
      outputDirectory: scenarioDir,
    );
    heartbeatWriter.write(
      phase: 'planning',
      subphase: proposalScreenshot.captured
          ? 'proposalScreenshotFinished'
          : 'proposalScreenshotSkipped',
      phaseTrace: phaseTrace,
      budgets: budgets,
    );

    final approveAction = findPreferredPlanModeApproveAction();
    appLog('[Workflow] Proposal approval tap started');
    heartbeatWriter.write(
      phase: 'planning',
      subphase: 'proposalTapStarted',
      phaseTrace: phaseTrace,
      budgets: budgets,
    );
    await tester.ensureVisible(approveAction);
    await tester.tap(approveAction, warnIfMissed: false);
    appLog('[Workflow] Proposal approval tap finished');
    phaseTrace.approvalTappedAt = DateTime.now();
    heartbeatWriter.write(
      phase: 'execution',
      subphase: 'approved',
      phaseTrace: phaseTrace,
      budgets: budgets,
    );
    await tester.pump();
    final approvalTransitionObserved = await waitForPlanModeApprovalTransition(
      tester,
      container,
      phaseTrace: phaseTrace,
      heartbeatWriter: heartbeatWriter,
      budgets: budgets,
    );
    if (!approvalTransitionObserved) {
      throw StateError(
        'Plan approval did not transition into execution after tapping '
        'Approve and start.',
      );
    }
  }
  if (proposalUiReady) {
    await pumpPlanModeUntilIdle(tester);
  }

  if (scenario.waitForExecutionCompletion) {
    await waitForPlanModeWorkflowExecutionCompletion(
      tester,
      container,
      timeout: budgets.executionTimeout,
      stallTimeout: budgets.executionStallTimeout,
      logs: logs,
      phaseTrace: phaseTrace,
      budgets: budgets,
      heartbeatWriter: heartbeatWriter,
      useFramePump: !config.usesLiveLlm,
    );
  }

  await waitForPlanModeArtifactExpectations(
    scenarioDir,
    scenario.resolvedArtifactExpectations,
    mode: scenario.artifactExpectationMode,
    timeout: config.usesLiveLlm
        ? const Duration(seconds: 30)
        : const Duration(seconds: 5),
    tester: tester,
    useFramePump: !config.usesLiveLlm,
  );
  if (!config.usesLiveLlm) {
    await pumpPlanModeUntilIdle(tester);
  }
  late final PlanModePostScenarioSettleResult postScenarioSettle;
  try {
    final logExpectationsReady = await waitForPlanModeLogExpectationLowerBounds(
      tester,
      logs,
      scenario.logExpectations,
      timeout: config.usesLiveLlm
          ? const Duration(minutes: 3)
          : const Duration(seconds: 5),
      useFramePump: !config.usesLiveLlm,
    );
    if (!logExpectationsReady) {
      throw StateError(
        'Scenario log expectations were not satisfied before post-scenario settle.',
      );
    }
    postScenarioSettle = await settlePlanModePostScenarioExecution(
      tester,
      container,
      timeout: resolvePostScenarioSettleTimeout(
        usesLiveLlm: config.usesLiveLlm,
        waitForExecutionCompletion: scenario.waitForExecutionCompletion,
      ),
      waitForExecutionCompletion: scenario.waitForExecutionCompletion,
      logs: logs,
      phaseTrace: phaseTrace,
      budgets: budgets,
      heartbeatWriter: heartbeatWriter,
      useFramePump: !config.usesLiveLlm,
    );
  } finally {
    await awaitPlanModeHarnessExecutionCleanup(
      harnessExecutionHandle,
      scenarioName: scenario.name,
      timeout: resolvePlanModeHarnessCleanupTimeout(
        usesLiveLlm: config.usesLiveLlm,
        budgets: budgets,
      ),
    );
  }

  assertPlanModeArtifactExpectations(
    scenarioDir,
    scenario.resolvedArtifactExpectations,
    mode: scenario.artifactExpectationMode,
  );
  assertPlanModeScenarioSeedFilesUnchanged(
    scenarioDir: scenarioDir,
    seedFiles: scenario.seedFiles,
  );

  final postValidator = scenario.postValidator;
  if (postValidator != null) {
    final postValidation = await postValidator(scenarioDir);
    final postValidationFile = File(
      '${scenarioDir.path}/scenario_post_validation.json',
    );
    await postValidationFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(postValidation),
    );
    if (postValidation['passed'] != true) {
      throw StateError(
        'Scenario post-validation failed: '
        '${postValidation['diagnostics'] ?? postValidation}',
      );
    }
    appLog('[Scenario] Post-validation passed');
  }

  if (!config.usesHeadlessRunner) {
    assertPlanModeUiExpectations(
      tester,
      scenario.uiExpectations,
      PlanModeUiPhase.finalResult,
    );
  }

  assertPlanModeLogExpectations(logs, scenario.logExpectations);
  final warnings = collectPlanModeScenarioWarnings(logs);
  final warningSummary = summarizeScenarioWarnings(
    warnings: warnings,
    allowedPatterns: scenario.allowedWarningPatterns,
    logs: logs,
  );
  final approvalPath = harnessExecutionHandle == null
      ? planModeApprovalPathUi
      : planModeApprovalPathLiveHarnessFallback;
  if (config.failOnWarnings && warningSummary.unexpectedWarnings.isNotEmpty) {
    throw StateError(
      'Scenario emitted warnings while fail-on-warning mode was enabled:\n'
      '${warningSummary.unexpectedWarnings.join('\n')}',
    );
  }

  final currentConversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  expect(currentConversation, isNotNull);
  final conversation = currentConversation!;
  final workflowExpectation = scenario.resolvedWorkflowExpectation;
  final savedWorkflow = conversation.effectiveWorkflowSpec;
  assertPlanModeSavedWorkflowExpectation(
    conversation: conversation,
    savedWorkflow: savedWorkflow,
    expectation: workflowExpectation,
    scenarioDir: scenarioDir,
    artifactExpectations: scenario.resolvedArtifactExpectations,
    allowArtifactExpectationFallback: config.usesLiveLlm,
  );
  if (!config.usesHeadlessRunner) {
    await capturePlanModeScenarioScreenshot(
      usesLiveLlm: config.usesLiveLlm,
      binding: binding,
      tester: tester,
      repaintBoundaryKey: screenshotBoundaryKey,
      scenarioName: scenario.name,
      phase: PlanModeScreenshotPhase.completed,
      outputDirectory: scenarioDir,
      failureMode: PlanModeScreenshotFailureMode.fail,
    );
  }

  final reportArtifacts = await writePlanModePassedScenarioReport(
    scenario: scenario,
    scenarioDir: scenarioDir,
    executionModeName: config.mode.name,
    approvalPath: approvalPath,
    conversation: conversation,
    savedWorkflow: savedWorkflow,
    logs: logs,
    warnings: warnings,
    warningSummary: warningSummary,
    postScenarioSettle: postScenarioSettle,
    phaseTrace: phaseTrace,
    budgets: budgets,
    heartbeatPath: heartbeatPath,
  );
  writePlanModeCompletedScenarioHeartbeat(
    conversation: conversation,
    logs: logs,
    postScenarioSettle: postScenarioSettle,
    phaseTrace: phaseTrace,
    budgets: budgets,
    heartbeatWriter: heartbeatWriter,
  );
  return _ScenarioRunResult(
    outputDirectoryPath: scenarioDir.path,
    reportPath: reportArtifacts.reportPath,
    screenshotPaths: reportArtifacts.screenshotPaths,
    logPath: reportArtifacts.logPath,
  );
}

void main() => registerPlanModeScenarioSuite();

void registerPlanModeScenarioSuite() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final config = resolvePlanModeScenarioTestConfig();
  final scenarios = config.scenarios;

  group(config.suiteName, () {
    Box<String>? conversationBox;
    Box<String>? memoryBox;
    Directory? headlessHiveDirectory;
    late DebugPrintCallback originalDebugPrint;
    late PlanModePlanningReadyObserver planningReadyObserver;
    late List<String> logs;
    late Directory suiteRunDirectory;
    final suiteResults = <Map<String, Object?>>[];

    setUpAll(() async {
      final reportRoot = Directory(config.reportRootPath);
      await reportRoot.create(recursive: true);
      suiteRunDirectory = Directory(
        '${reportRoot.path}/${config.reportPrefix}_${DateTime.now().millisecondsSinceEpoch}',
      );
      await suiteRunDirectory.create(recursive: true);
      appLog(
        '[ScenarioSuite] Running ${config.suiteName} on ${config.deviceName} '
        'in ${config.mode.name} mode',
      );
    });

    setUp(() async {
      logs = <String>[];
      planningReadyObserver = PlanModePlanningReadyObserver(logs: logs);
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          logs.add(message);
          planningReadyObserver.observe(message);
        }
        originalDebugPrint(message, wrapWidth: wrapWidth);
      };

      if (config.usesHeadlessRunner) {
        headlessHiveDirectory = await Directory.systemTemp.createTemp(
          'caverno_plan_mode_headless_hive_',
        );
        Hive.init(headlessHiveDirectory!.path);
        SharedPreferences.setMockInitialValues(const <String, Object>{});
      } else {
        await Hive.initFlutter();
      }
      await EasyLocalization.ensureInitialized();

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      conversationBox = await Hive.openBox<String>('plan_mode_conv_$timestamp');
      memoryBox = await Hive.openBox<String>('plan_mode_mem_$timestamp');
    });

    tearDown(() async {
      debugPrint = originalDebugPrint;
      planningReadyObserver.clear();
      await conversationBox?.close();
      await memoryBox?.close();
      conversationBox = null;
      memoryBox = null;
      final hiveDirectory = headlessHiveDirectory;
      headlessHiveDirectory = null;
      if (hiveDirectory != null && hiveDirectory.existsSync()) {
        hiveDirectory.deleteSync(recursive: true);
      }
    });

    tearDownAll(() async {
      final reportDirectory = Directory(config.reportRootPath);
      await reportDirectory.create(recursive: true);

      final suiteReportConfig = PlanModeSuiteReportConfig(
        generatedAt: DateTime.now(),
        suiteName: config.suiteName,
        modeName: config.mode.name,
        failOnWarnings: config.failOnWarnings,
        requestedScenarioNames: config.requestedScenarioNames,
        requestedTags: config.requestedTags,
        suiteDirectoryPath: suiteRunDirectory.path,
        model: config.model,
        baseUrl: config.baseUrl,
      );
      final suiteReportArtifacts = await writePlanModeSuiteReportArtifacts(
        reportDirectory: reportDirectory,
        suiteRunDirectory: suiteRunDirectory,
        reportPrefix: config.reportPrefix,
        config: suiteReportConfig,
        suiteResults: suiteResults,
      );
      appLog(
        '[ScenarioSuite] Report written to '
        '${suiteReportArtifacts.latestJsonPath}',
      );
    });

    for (final scenario in scenarios) {
      testWidgets('runs ${scenario.name}', (tester) async {
        final startedAt = DateTime.now();
        final scenarioDir = await Directory.systemTemp.createTemp(
          'caverno_plan_mode_${scenario.name}_',
        );
        final heartbeatPath =
            resolvePlanModeLiveHeartbeatPath() ??
            '${scenarioDir.path}/heartbeat.json';
        final phaseTrace = PlanModePhaseTrace();
        final budgets = PlanModeTimeoutBudgets(
          planningTimeout: resolvePlanModePlanningProposalTimeout(scenario),
          executionTimeout: resolvePlanModeExecutionCompletionTimeout(scenario),
          executionStallTimeout: resolvePlanModeExecutionStallTimeout(scenario),
          overallTimeout: resolvePlanModeOverallRunTimeout(scenario),
        );
        _ScenarioRunResult? runResult;
        Object? failure;
        StackTrace? failureStackTrace;
        try {
          final scenarioRun = _runScenario(
            tester: tester,
            binding: binding,
            conversationBox: conversationBox!,
            memoryBox: memoryBox!,
            logs: logs,
            config: config,
            scenario: scenario,
            scenarioDir: scenarioDir,
            phaseTrace: phaseTrace,
            budgets: budgets,
            heartbeatPath: heartbeatPath,
            planningReadyObserver: planningReadyObserver,
          );
          runResult = await scenarioRun.timeout(
            budgets.overallTimeout!,
            onTimeout: () {
              throw TimeoutException(
                'Scenario run timed out after '
                '${budgets.overallTimeout!.inSeconds}s.',
                budgets.overallTimeout,
              );
            },
          );
        } catch (error, stackTrace) {
          failure = error;
          failureStackTrace = stackTrace;
          rethrow;
        } finally {
          final finishedAt = DateTime.now();
          final archived = await archivePlanModeScenarioRun(
            scenario: scenario,
            scenarioDir: scenarioDir,
            suiteRunDirectory: suiteRunDirectory,
            modeName: config.mode.name,
            startedAt: startedAt,
            finishedAt: finishedAt,
            tempOutputDirectoryPath:
                runResult?.outputDirectoryPath ?? scenarioDir.path,
            logs: logs,
            phaseTrace: phaseTrace,
            budgets: budgets,
            heartbeatPath: heartbeatPath,
            failure: failure,
            failureStackTrace: failureStackTrace,
          );
          suiteResults.add(archived.suiteResult);
        }
      });
    }
  });
}
