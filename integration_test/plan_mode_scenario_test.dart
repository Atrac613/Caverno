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
    required this.logPath,
  });

  final String outputDirectoryPath;
  final String reportPath;
  final List<String> screenshotPaths;
  final String logPath;
}

enum _PlanModeScenarioExecutionMode { fake, live }

class _PlanModeScenarioTestConfig {
  const _PlanModeScenarioTestConfig({
    required this.mode,
    required this.suiteName,
    required this.reportPrefix,
    required this.scenarios,
    required this.failOnWarnings,
    required this.requestedScenarioNames,
    required this.requestedTags,
    this.baseUrl,
    this.apiKey,
    this.model,
  });

  final _PlanModeScenarioExecutionMode mode;
  final String suiteName;
  final String reportPrefix;
  final List<PlanModeScenarioSpec> scenarios;
  final bool failOnWarnings;
  final List<String> requestedScenarioNames;
  final List<String> requestedTags;
  final String? baseUrl;
  final String? apiKey;
  final String? model;

  bool get usesLiveLlm => mode == _PlanModeScenarioExecutionMode.live;
}

bool _envFlagEnabled(String name) {
  final rawValue = Platform.environment[name]?.trim().toLowerCase();
  return rawValue == '1' ||
      rawValue == 'true' ||
      rawValue == 'yes' ||
      rawValue == 'on';
}

_PlanModeScenarioTestConfig _resolveScenarioTestConfig() {
  final usesLiveLlm = _envFlagEnabled('CAVERNO_PLAN_MODE_LIVE_LLM');
  final failOnWarnings = _envFlagEnabled('CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS');
  final requestedScenarioNames =
      (Platform.environment['CAVERNO_PLAN_MODE_SCENARIOS']
                  ?.split(',')
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty) ??
              const Iterable<String>.empty())
          .toList(growable: false);
  final requestedScenarioNameSet = requestedScenarioNames.toSet();
  final requestedTags =
      (Platform.environment['CAVERNO_PLAN_MODE_TAGS']
                  ?.split(',')
                  .map((value) => value.trim().toLowerCase())
                  .where((value) => value.isNotEmpty) ??
              const Iterable<String>.empty())
          .toList(growable: false);
  final requestedTagSet = requestedTags.toSet();

  final scenarios = usesLiveLlm
      ? buildLivePlanModeScenarios()
      : buildPlanModeScenarios();
  final filteredScenarios = scenarios
      .where((scenario) {
        final matchesName =
            requestedScenarioNameSet.isEmpty ||
            requestedScenarioNameSet.contains(scenario.name);
        final matchesTag =
            requestedTagSet.isEmpty ||
            scenario.tags.any(
              (tag) => requestedTagSet.contains(tag.trim().toLowerCase()),
            );
        return matchesName && matchesTag;
      })
      .toList(growable: false);

  if (filteredScenarios.isEmpty) {
    throw StateError(
      'No plan mode scenarios matched '
      'names="${Platform.environment['CAVERNO_PLAN_MODE_SCENARIOS'] ?? ''}" '
      'tags="${Platform.environment['CAVERNO_PLAN_MODE_TAGS'] ?? ''}".',
    );
  }

  if (!usesLiveLlm) {
    return _PlanModeScenarioTestConfig(
      mode: _PlanModeScenarioExecutionMode.fake,
      suiteName: 'plan_mode_scenarios',
      reportPrefix: 'plan_mode_suite',
      scenarios: filteredScenarios,
      failOnWarnings: failOnWarnings,
      requestedScenarioNames: requestedScenarioNames,
      requestedTags: requestedTags,
    );
  }

  return _PlanModeScenarioTestConfig(
    mode: _PlanModeScenarioExecutionMode.live,
    suiteName: 'plan_mode_live_scenarios',
    reportPrefix: 'plan_mode_live_suite',
    scenarios: filteredScenarios,
    failOnWarnings: failOnWarnings,
    requestedScenarioNames: requestedScenarioNames,
    requestedTags: requestedTags,
    baseUrl: Platform.environment['CAVERNO_LLM_BASE_URL']?.trim(),
    apiKey: Platform.environment['CAVERNO_LLM_API_KEY']?.trim(),
    model: Platform.environment['CAVERNO_LLM_MODEL']?.trim(),
  );
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
  _PlanModeScenarioTestConfig config,
  PlanModeScenarioSpec scenario,
  GlobalKey screenshotBoundaryKey,
  Directory outputDirectory,
) async {
  var scriptedDecisionIndex = 0;
  var resolvedDecisionCount = 0;
  const maxDecisionRounds = 8;

  while (resolvedDecisionCount < maxDecisionRounds) {
    await tester.pumpAndSettle();
    final decisionSheetFinder = find.byType(BottomSheet);
    final confirmFinder = find.descendant(
      of: decisionSheetFinder,
      matching: find.text('Continue with this choice'),
    );
    if (confirmFinder.evaluate().isEmpty) {
      return;
    }

    _assertUiExpectations(
      tester,
      scenario.uiExpectations,
      PlanModeUiPhase.decision,
    );
    final scriptedSelection =
        scriptedDecisionIndex < scenario.decisionSelections.length
        ? scenario.decisionSelections[scriptedDecisionIndex]
        : null;
    final questionText =
        scriptedSelection?.question ?? _extractVisibleDecisionQuestion(tester);

    if (scriptedSelection != null &&
        scriptedSelection.question.trim().isNotEmpty) {
      expect(find.text(scriptedSelection.question), findsOneWidget);
    } else if (!config.usesLiveLlm) {
      throw StateError(
        'Encountered an unexpected planning decision in fake mode.',
      );
    }

    await captureIntegrationScreenshot(
      binding: binding,
      tester: tester,
      repaintBoundaryKey: screenshotBoundaryKey,
      name: 'plan_mode_${scenario.name}_decision_${resolvedDecisionCount + 1}',
      outputDirectory: outputDirectory,
    );

    if (scriptedSelection?.freeTextAnswer != null) {
      final decisionTextFieldFinder = find.descendant(
        of: decisionSheetFinder,
        matching: find.byType(TextField),
      );
      expect(decisionTextFieldFinder, findsOneWidget);
      await tester.enterText(
        decisionTextFieldFinder,
        scriptedSelection!.freeTextAnswer!,
      );
      await tester.pumpAndSettle();
    } else if (scriptedSelection?.optionLabel != null) {
      final optionFinder = _findDecisionSheetText(
        tester,
        decisionSheetFinder,
        scriptedSelection!.optionLabel!,
      );
      expect(
        optionFinder,
        findsAtLeastNWidgets(1),
        reason:
            'Expected to find decision option '
            '"${scriptedSelection.optionLabel}" in the planning sheet.',
      );
      await tester.tap(optionFinder.last, warnIfMissed: false);
      await tester.pumpAndSettle();
    } else if (config.usesLiveLlm) {
      appLog(
        '[ScenarioLive] Auto-accepted the default planning option'
        '${questionText != null ? ' for "$questionText"' : ''}.',
      );
    }

    expect(confirmFinder, findsOneWidget);
    await tester.tap(confirmFinder, warnIfMissed: false);
    await tester.pump();
    await tester.pumpAndSettle();
    if (scriptedSelection != null) {
      scriptedDecisionIndex += 1;
    }
    resolvedDecisionCount += 1;
  }

  throw StateError(
    'Planning decisions did not settle after $maxDecisionRounds rounds.',
  );
}

Finder _findDecisionSheetText(
  WidgetTester tester,
  Finder decisionSheetFinder,
  String targetText,
) {
  final exactFinder = find.descendant(
    of: decisionSheetFinder,
    matching: find.text(targetText),
  );
  if (exactFinder.evaluate().isNotEmpty) {
    return exactFinder;
  }

  final normalizedTarget = targetText.trim().toLowerCase();
  return find.descendant(
    of: decisionSheetFinder,
    matching: find.byWidgetPredicate((widget) {
      if (widget is! Text) {
        return false;
      }
      final data = widget.data?.trim().toLowerCase();
      return data != null && data == normalizedTarget;
    }),
  );
}

Future<void> _waitForReadyPlanProposal(
  WidgetTester tester,
  ProviderContainer container, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final chatState = container.read(chatNotifierProvider);
    final isReady =
        chatState.workflowProposalDraft != null &&
        chatState.taskProposalDraft != null &&
        !chatState.isGeneratingWorkflowProposal &&
        !chatState.isGeneratingTaskProposal;
    if (isReady) {
      await tester.pumpAndSettle();
      return;
    }

    await tester.pump(const Duration(milliseconds: 200));
  }

  final chatState = container.read(chatNotifierProvider);
  throw StateError(
    'Plan proposal did not become ready. '
    'workflowDraft=${chatState.workflowProposalDraft != null}, '
    'taskDraft=${chatState.taskProposalDraft != null}, '
    'isGeneratingWorkflow=${chatState.isGeneratingWorkflowProposal}, '
    'isGeneratingTask=${chatState.isGeneratingTaskProposal}, '
    'workflowError=${chatState.workflowProposalError}, '
    'taskError=${chatState.taskProposalError}',
  );
}

String? _extractVisibleDecisionQuestion(WidgetTester tester) {
  final candidates = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data?.trim())
      .whereType<String>()
      .where((text) => text.isNotEmpty)
      .where(
        (text) =>
            text != 'Choose Before Planning' &&
            text != 'Continue with this choice' &&
            text != 'Cancel' &&
            text !=
                'Review the generated workflow and tasks, then approve when you are ready to start implementation.',
      )
      .toList(growable: false);

  for (final candidate in candidates) {
    if (candidate.endsWith('?')) {
      return candidate;
    }
  }
  return candidates.firstOrNull;
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

Future<void> _waitForArtifactExpectations(
  WidgetTester tester,
  Directory scenarioDir,
  List<PlanModeArtifactExpectation> expectations, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final requiredFiles = expectations
      .where((item) => item.shouldExist)
      .map((item) => File('${scenarioDir.path}/${item.path}'))
      .toList(growable: false);
  if (requiredFiles.isEmpty) {
    return;
  }

  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final allPresent = requiredFiles.every((file) => file.existsSync());
    if (allPresent) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 200));
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

Future<void> _copyDirectoryContents({
  required Directory source,
  required Directory destination,
}) async {
  await destination.create(recursive: true);
  for (final entity in source.listSync()) {
    if (entity is File) {
      await entity.copy('${destination.path}/${entity.uri.pathSegments.last}');
      continue;
    }
    if (entity is Directory) {
      await _copyDirectoryContents(
        source: entity,
        destination: Directory(
          '${destination.path}/${entity.uri.pathSegments.last}',
        ),
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

Future<void> _writeFailureScenarioArtifacts({
  required PlanModeScenarioSpec scenario,
  required Directory scenarioDir,
  required List<String> logs,
  required Object error,
  required StackTrace stackTrace,
}) async {
  final screenshotPaths = _listScenarioScreenshotPaths(scenarioDir);
  final filteredLogs = logs
      .where(
        (line) =>
            line.contains('[ScenarioLLM]') ||
            line.contains('[Tool]') ||
            line.contains('[LLM]') ||
            line.contains('[ContentTool]') ||
            line.contains('[Screenshot]') ||
            line.contains('[Workflow]'),
      )
      .toList(growable: false);
  final warnings = _collectScenarioWarnings(logs);

  final logFile = File('${scenarioDir.path}/scenario_log.txt');
  await logFile.writeAsString('${logs.join('\n')}\n');

  final report = <String, Object?>{
    'scenario': scenario.name,
    'status': 'failed',
    'projectRoot': scenarioDir.path,
    'error': error.toString(),
    'stackTrace': stackTrace.toString(),
    'screenshots': screenshotPaths,
    'warnings': warnings,
    'capturedLogs': filteredLogs,
  };
  final reportFile = File('${scenarioDir.path}/scenario_report.json');
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
}

List<String> _collectScenarioWarnings(List<String> logs) {
  const warningPatterns = <String>[
    '[Workflow] Workflow proposal parse failed',
    '[Workflow] Workflow proposal recovered on retry',
    '[Workflow] Using fallback proposal',
    '[LLM] Recovered raw text response after create parse failure',
    'Connection closed before full header was received',
    '[LLM] streamChatCompletion error:',
    '[LLM] createChatCompletion error:',
    '[ChatNotifier] _handleError called',
  ];

  final warnings = <String>[];
  for (final line in logs) {
    final isWarning = warningPatterns.any(line.contains);
    if (!isWarning || warnings.contains(line)) {
      continue;
    }
    warnings.add(line);
  }
  return warnings;
}

String _buildSuiteMarkdownReport({
  required _PlanModeScenarioTestConfig config,
  required List<Map<String, Object?>> suiteResults,
  required Directory suiteRunDirectory,
}) {
  final passedCount = suiteResults
      .where((result) => result['status'] == 'passed')
      .length;
  final buffer = StringBuffer()
    ..writeln('# Plan Mode Scenario Suite')
    ..writeln()
    ..writeln('- Generated at: ${DateTime.now().toIso8601String()}')
    ..writeln('- Suite: ${config.suiteName}')
    ..writeln('- Mode: ${config.mode.name}')
    ..writeln('- Fail on warnings: ${config.failOnWarnings}')
    ..writeln(
      '- Scenario filter: ${config.requestedScenarioNames.isEmpty ? 'all' : config.requestedScenarioNames.join(', ')}',
    )
    ..writeln(
      '- Tag filter: ${config.requestedTags.isEmpty ? 'all' : config.requestedTags.join(', ')}',
    )
    ..writeln('- Suite directory: ${suiteRunDirectory.path}')
    ..writeln(
      '- Model: ${config.model?.isNotEmpty == true ? config.model : 'default'}',
    );
  if (config.baseUrl?.isNotEmpty == true) {
    buffer.writeln('- Base URL: ${config.baseUrl}');
  }
  buffer
    ..writeln('- Scenario count: ${suiteResults.length}')
    ..writeln('- Passed: $passedCount')
    ..writeln('- Failed: ${suiteResults.length - passedCount}')
    ..writeln()
    ..writeln(
      '| Scenario | Tags | Status | Duration (ms) | Warnings | Screenshots | Report | Log | Error |',
    )
    ..writeln('| --- | --- | --- | ---: | ---: | ---: | --- | --- | --- |');

  for (final result in suiteResults) {
    final screenshots = (result['screenshots'] as List<Object?>?) ?? const [];
    final warnings = (result['warnings'] as List<Object?>?) ?? const [];
    final tags = (result['tags'] as List<Object?>?) ?? const [];
    final error = (result['error'] as String?)?.replaceAll('\n', ' ') ?? '';
    buffer.writeln(
      '| ${result['scenario']} | ${tags.isEmpty ? '-' : tags.join(', ')} | ${result['status']} | '
      '${result['durationMs']} | ${warnings.length} | ${screenshots.length} | '
      '${result['scenarioReport'] ?? '-'} | ${result['scenarioLog'] ?? '-'} | '
      '${error.isEmpty ? '-' : error} |',
    );
  }

  final scenariosWithWarnings = suiteResults
      .where((result) {
        final warnings = (result['warnings'] as List<Object?>?) ?? const [];
        return warnings.isNotEmpty;
      })
      .toList(growable: false);

  if (scenariosWithWarnings.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Warnings')
      ..writeln();
    for (final result in scenariosWithWarnings) {
      final warnings = (result['warnings'] as List<Object?>?) ?? const [];
      buffer.writeln('### ${result['scenario']}');
      for (final warning in warnings) {
        buffer.writeln('- $warning');
      }
      buffer.writeln();
    }
  }

  return buffer.toString();
}

Future<_ScenarioRunResult> _runScenario({
  required WidgetTester tester,
  required IntegrationTestWidgetsFlutterBinding binding,
  required Box<String> conversationBox,
  required Box<String> memoryBox,
  required List<String> logs,
  required _PlanModeScenarioTestConfig config,
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
    baseUrl: config.baseUrl ?? AppSettings.defaults().baseUrl,
    model: config.model ?? AppSettings.defaults().model,
    apiKey: config.apiKey ?? AppSettings.defaults().apiKey,
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
    config,
    scenario,
    screenshotBoundaryKey,
    scenarioDir,
  );

  await _waitForReadyPlanProposal(
    tester,
    container,
    timeout: config.usesLiveLlm
        ? const Duration(seconds: 30)
        : const Duration(seconds: 5),
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

  await _waitForArtifactExpectations(
    tester,
    scenarioDir,
    scenario.resolvedArtifactExpectations,
    timeout: config.usesLiveLlm
        ? const Duration(seconds: 30)
        : const Duration(seconds: 5),
  );
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
  final warnings = _collectScenarioWarnings(logs);
  if (config.failOnWarnings && warnings.isNotEmpty) {
    throw StateError(
      'Scenario emitted warnings while fail-on-warning mode was enabled:\n'
      '${warnings.join('\n')}',
    );
  }

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
    'tags': scenario.tags,
    'status': 'passed',
    'executionMode': config.mode.name,
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
    'warnings': warnings,
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
  final logFile = File('${scenarioDir.path}/scenario_log.txt');
  await logFile.writeAsString('${logs.join('\n')}\n');
  final reportFile = File('${scenarioDir.path}/scenario_report.json');
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  appLog('[Scenario] Report written to ${reportFile.path}');
  return _ScenarioRunResult(
    outputDirectoryPath: scenarioDir.path,
    reportPath: reportFile.path,
    screenshotPaths: screenshotPaths,
    logPath: logFile.path,
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final config = _resolveScenarioTestConfig();
  final scenarios = config.scenarios;

  group(config.suiteName, () {
    late Box<String> conversationBox;
    late Box<String> memoryBox;
    late DebugPrintCallback originalDebugPrint;
    late List<String> logs;
    late Directory suiteRunDirectory;
    final suiteResults = <Map<String, Object?>>[];

    setUpAll(() async {
      final reportRoot = Directory(
        '${Directory.current.path}/build/integration_test_reports',
      );
      await reportRoot.create(recursive: true);
      suiteRunDirectory = Directory(
        '${reportRoot.path}/${config.reportPrefix}_${DateTime.now().millisecondsSinceEpoch}',
      );
      await suiteRunDirectory.create(recursive: true);
      appLog(
        '[ScenarioSuite] Running ${config.suiteName} in ${config.mode.name} mode',
      );
    });

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
        '${Directory.current.path}/build/integration_test_reports',
      );
      await reportDirectory.create(recursive: true);

      final passedCount = suiteResults
          .where((result) => result['status'] == 'passed')
          .length;
      final suiteReport = <String, Object?>{
        'generatedAt': DateTime.now().toIso8601String(),
        'suite': config.suiteName,
        'mode': config.mode.name,
        'requestedScenarioNames': config.requestedScenarioNames,
        'requestedTags': config.requestedTags,
        'suiteDirectory': suiteRunDirectory.path,
        'model': config.model,
        'baseUrl': config.baseUrl,
        'failOnWarnings': config.failOnWarnings,
        'scenarioCount': suiteResults.length,
        'passedCount': passedCount,
        'failedCount': suiteResults.length - passedCount,
        'scenarios': suiteResults,
      };
      final suiteRunReportFile = File(
        '${suiteRunDirectory.path}/${config.reportPrefix}_report.json',
      );
      await suiteRunReportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(suiteReport),
      );
      final suiteReportFile = File(
        '${reportDirectory.path}/${config.reportPrefix}_report.json',
      );
      await suiteReportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(suiteReport),
      );
      final suiteMarkdown = _buildSuiteMarkdownReport(
        config: config,
        suiteResults: suiteResults,
        suiteRunDirectory: suiteRunDirectory,
      );
      final suiteRunMarkdownFile = File(
        '${suiteRunDirectory.path}/${config.reportPrefix}_report.md',
      );
      await suiteRunMarkdownFile.writeAsString(suiteMarkdown);
      final suiteMarkdownFile = File(
        '${reportDirectory.path}/${config.reportPrefix}_report.md',
      );
      await suiteMarkdownFile.writeAsString(suiteMarkdown);
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
        StackTrace? failureStackTrace;
        try {
          runResult = await _runScenario(
            tester: tester,
            binding: binding,
            conversationBox: conversationBox,
            memoryBox: memoryBox,
            logs: logs,
            config: config,
            scenario: scenario,
            scenarioDir: scenarioDir,
          );
        } catch (error, stackTrace) {
          failure = error;
          failureStackTrace = stackTrace;
          rethrow;
        } finally {
          final finishedAt = DateTime.now();
          if (failure != null && failureStackTrace != null) {
            await _writeFailureScenarioArtifacts(
              scenario: scenario,
              scenarioDir: scenarioDir,
              logs: logs,
              error: failure,
              stackTrace: failureStackTrace,
            );
          }
          final archivedScenarioDir = Directory(
            '${suiteRunDirectory.path}/${scenario.name}',
          );
          await _copyDirectoryContents(
            source: scenarioDir,
            destination: archivedScenarioDir,
          );
          final archivedScreenshotPaths = _listScenarioScreenshotPaths(
            archivedScenarioDir,
          );
          final archivedReportPath = File(
            '${archivedScenarioDir.path}/scenario_report.json',
          );
          final archivedLogPath = File(
            '${archivedScenarioDir.path}/scenario_log.txt',
          );
          List<dynamic> archivedWarnings = const <dynamic>[];
          if (archivedReportPath.existsSync()) {
            final archivedReport =
                jsonDecode(archivedReportPath.readAsStringSync())
                    as Map<String, dynamic>;
            archivedWarnings =
                archivedReport['warnings'] as List<dynamic>? ??
                const <dynamic>[];
          }
          suiteResults.add(<String, Object?>{
            'scenario': scenario.name,
            'tags': scenario.tags,
            'mode': config.mode.name,
            'status': failure == null ? 'passed' : 'failed',
            'startedAt': startedAt.toIso8601String(),
            'finishedAt': finishedAt.toIso8601String(),
            'durationMs': finishedAt.difference(startedAt).inMilliseconds,
            'tempOutputDirectory':
                runResult?.outputDirectoryPath ?? scenarioDir.path,
            'archivedOutputDirectory': archivedScenarioDir.path,
            'scenarioReport': archivedReportPath.existsSync()
                ? archivedReportPath.path
                : null,
            'scenarioLog': archivedLogPath.existsSync()
                ? archivedLogPath.path
                : null,
            'screenshots': archivedScreenshotPaths,
            'warnings': archivedWarnings,
            'error': failure?.toString(),
            'stackTrace': failureStackTrace?.toString(),
          });
        }
      });
    }
  });
}
