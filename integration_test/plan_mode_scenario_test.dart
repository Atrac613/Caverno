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
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_execution_coordinator.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_projection_service.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/chat/presentation/widgets/message_input.dart';
import 'package:caverno/features/chat/presentation/widgets/plan/plan_review_sheet.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

import 'test_support/plan_mode_scenario_spec.dart';
import 'test_support/plan_mode_execution_progress.dart';
import 'test_support/plan_mode_execution_watchdog.dart';
import 'test_support/plan_mode_live_diagnostics.dart';
import 'test_support/plan_mode_live_harness_fallback.dart';
import 'test_support/plan_mode_planning_progress.dart';
import 'test_support/plan_mode_report_summary.dart';
import 'test_support/plan_mode_suite_report.dart';
import 'test_support/plan_mode_warning_policy.dart';
import 'test_support/plan_mode_approval_progress.dart';
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
    required this.deviceName,
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

  final String deviceName;
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

class _PlanModePhaseTrace {
  DateTime? proposalReadyAt;
  DateTime? taskProposalReadyAt;
  DateTime? approvalTappedAt;
  DateTime? firstTaskStartedAt;
  DateTime? firstTaskCompletedAt;
  DateTime? nextTaskStartedAt;
  DateTime? validationStartedAt;
  DateTime? lastTaskProgressAt;
  String? firstTaskTitle;

  Map<String, String?> toJson() {
    return <String, String?>{
      'proposalReadyAt': proposalReadyAt?.toIso8601String(),
      'taskProposalReadyAt': taskProposalReadyAt?.toIso8601String(),
      'approvalTappedAt': approvalTappedAt?.toIso8601String(),
      'firstTaskStartedAt': firstTaskStartedAt?.toIso8601String(),
      'firstTaskCompletedAt': firstTaskCompletedAt?.toIso8601String(),
      'nextTaskStartedAt': nextTaskStartedAt?.toIso8601String(),
      'validationStartedAt': validationStartedAt?.toIso8601String(),
      'lastTaskProgressAt': lastTaskProgressAt?.toIso8601String(),
    };
  }
}

class _PlanModeTimeoutBudgets {
  const _PlanModeTimeoutBudgets({
    required this.planningTimeout,
    required this.executionTimeout,
    required this.executionStallTimeout,
    required this.overallTimeout,
  });

  final Duration planningTimeout;
  final Duration executionTimeout;
  final Duration executionStallTimeout;
  final Duration? overallTimeout;

  Map<String, int?> toJson() {
    return <String, int?>{
      'planningTimeoutMs': planningTimeout.inMilliseconds,
      'executionTimeoutMs': executionTimeout.inMilliseconds,
      'executionStallTimeoutMs': executionStallTimeout.inMilliseconds,
      'overallTimeoutMs': overallTimeout?.inMilliseconds,
    };
  }
}

class _PostScenarioSettleResult {
  const _PostScenarioSettleResult({
    required this.initiallySettled,
    required this.settled,
    required this.cancellationUsed,
  });

  final bool initiallySettled;
  final bool settled;
  final bool cancellationUsed;

  Map<String, bool> toJson() {
    return <String, bool>{
      'initiallySettled': initiallySettled,
      'settled': settled,
      'cancellationUsed': cancellationUsed,
    };
  }
}

bool _envFlagEnabled(String name) {
  final rawValue = Platform.environment[name]?.trim().toLowerCase();
  return rawValue == '1' ||
      rawValue == 'true' ||
      rawValue == 'yes' ||
      rawValue == 'on';
}

String _envValueOrDefault(String name, String fallback) {
  final rawValue = Platform.environment[name]?.trim().toLowerCase();
  if (rawValue == null || rawValue.isEmpty) {
    return fallback;
  }
  return rawValue;
}

String _requireNonEmptyEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('Set $name before running live Plan mode scenarios.');
  }
  return value;
}

Duration? _envDurationFromSeconds(String name) {
  final rawValue = Platform.environment[name]?.trim();
  if (rawValue == null || rawValue.isEmpty) {
    return null;
  }
  final seconds = int.tryParse(rawValue);
  if (seconds == null || seconds <= 0) {
    return null;
  }
  return Duration(seconds: seconds);
}

Duration _resolvePlanningProposalTimeout(PlanModeScenarioSpec scenario) {
  return _envDurationFromSeconds(
        'CAVERNO_PLAN_MODE_PLANNING_TIMEOUT_SECONDS',
      ) ??
      scenario.planningProposalTimeout;
}

Duration _resolveExecutionCompletionTimeout(PlanModeScenarioSpec scenario) {
  return _envDurationFromSeconds(
        'CAVERNO_PLAN_MODE_EXECUTION_TIMEOUT_SECONDS',
      ) ??
      scenario.executionCompletionTimeout;
}

Duration _resolveExecutionStallTimeout(PlanModeScenarioSpec scenario) {
  return _envDurationFromSeconds(
        'CAVERNO_PLAN_MODE_EXECUTION_STALL_TIMEOUT_SECONDS',
      ) ??
      scenario.executionStallTimeout;
}

Duration _resolveOverallRunTimeout(PlanModeScenarioSpec scenario) {
  return _envDurationFromSeconds('CAVERNO_PLAN_MODE_RUN_TIMEOUT_SECONDS') ??
      scenario.planningProposalTimeout +
          scenario.executionCompletionTimeout +
          const Duration(minutes: 5);
}

String? _resolveLiveHeartbeatPath() {
  final value = Platform.environment['CAVERNO_PLAN_MODE_HEARTBEAT_PATH']
      ?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

class _PlanModeLiveHeartbeatWriter {
  _PlanModeLiveHeartbeatWriter({
    required this.scenarioName,
    required this.path,
  });

  final String scenarioName;
  final String? path;

  String? _lastPayload;

  void write({
    required String phase,
    required String subphase,
    required _PlanModePhaseTrace phaseTrace,
    required _PlanModeTimeoutBudgets budgets,
    String? activeTaskTitle,
    String? workflowSnapshot,
    int? toolResultCount,
    int? fileWriteCount,
    int? messageCount,
    bool? hasPendingApprovals,
    bool? isLoading,
  }) {
    final resolvedPath = path;
    if (resolvedPath == null || resolvedPath.isEmpty) {
      return;
    }

    final payload = <String, Object?>{
      'scenario': scenarioName,
      'updatedAt': DateTime.now().toIso8601String(),
      'phase': phase,
      'subphase': subphase,
      'phaseTimings': phaseTrace.toJson(),
      'budgets': budgets.toJson(),
      'activeTaskTitle': activeTaskTitle,
      'workflowSnapshot': workflowSnapshot,
      'toolResultCount': toolResultCount,
      'fileWriteCount': fileWriteCount,
      'messageCount': messageCount,
      'hasPendingApprovals': hasPendingApprovals,
      'isLoading': isLoading,
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);
    if (_lastPayload == encoded) {
      return;
    }
    _lastPayload = encoded;

    final file = File(resolvedPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$encoded\n');
  }
}

class _PlanModePlanningReadyObserver {
  _PlanModePlanningReadyObserver({required this.logs});

  final List<String> logs;
  _PlanModePhaseTrace? _phaseTrace;
  _PlanModeTimeoutBudgets? _budgets;
  _PlanModeLiveHeartbeatWriter? _heartbeatWriter;
  String? Function()? _workflowSnapshotResolver;
  int? Function()? _messageCountResolver;

  void configure({
    required _PlanModePhaseTrace phaseTrace,
    required _PlanModeTimeoutBudgets budgets,
    required _PlanModeLiveHeartbeatWriter heartbeatWriter,
    required String? Function() workflowSnapshotResolver,
    required int? Function() messageCountResolver,
  }) {
    _phaseTrace = phaseTrace;
    _budgets = budgets;
    _heartbeatWriter = heartbeatWriter;
    _workflowSnapshotResolver = workflowSnapshotResolver;
    _messageCountResolver = messageCountResolver;
  }

  void clear() {
    _phaseTrace = null;
    _budgets = null;
    _heartbeatWriter = null;
    _workflowSnapshotResolver = null;
    _messageCountResolver = null;
  }

  void observe(String message) {
    final phaseTrace = _phaseTrace;
    final budgets = _budgets;
    final heartbeatWriter = _heartbeatWriter;
    if (phaseTrace == null || budgets == null || heartbeatWriter == null) {
      return;
    }

    final isWorkflowMarker =
        message.contains('[Workflow] Workflow proposal ready') ||
        message.contains('[Workflow] Workflow proposal recovered on retry') ||
        message.contains('[Workflow] Workflow plan artifact draft persisted') ||
        message.contains('[Workflow] Using fallback proposal');
    final isTaskMarker =
        message.contains('[Workflow] Task proposal ready') ||
        message.contains('[Workflow] Task proposal recovered on retry') ||
        message.contains(
          '[Workflow] Task proposal recovered from truncated reasoning fallback',
        ) ||
        message.contains('[Workflow] Task plan artifact draft persisted');
    if (!isWorkflowMarker && !isTaskMarker) {
      return;
    }

    final now = DateTime.now();
    if (isWorkflowMarker) {
      phaseTrace.proposalReadyAt ??= now;
    }
    if (isTaskMarker) {
      phaseTrace.taskProposalReadyAt ??= now;
    }

    final workflowSnapshot = _workflowSnapshotResolver?.call();
    final messageCount = _messageCountResolver?.call();
    final subphase = planningLogsContainReadyDraftState(logs)
        ? 'taskDraftReady'
        : 'workflowDraftReady';
    heartbeatWriter.write(
      phase: 'planning',
      subphase: subphase,
      phaseTrace: phaseTrace,
      budgets: budgets,
      workflowSnapshot: workflowSnapshot,
      messageCount: messageCount,
      hasPendingApprovals: false,
      isLoading: subphase != 'taskDraftReady',
    );
  }
}

Map<String, Object?> _readLiveHeartbeatSnapshot() {
  final path = _resolveLiveHeartbeatPath();
  if (path == null || path.isEmpty) {
    return const <String, Object?>{};
  }
  final file = File(path);
  if (!file.existsSync()) {
    return const <String, Object?>{};
  }
  final content = file.readAsStringSync().trim();
  if (content.isEmpty) {
    return const <String, Object?>{};
  }
  final decoded = jsonDecode(content);
  if (decoded is Map<String, dynamic>) {
    return Map<String, Object?>.from(decoded);
  }
  return const <String, Object?>{};
}

String _defaultPlanModeDeviceName() {
  if (Platform.isLinux) {
    return 'linux';
  }
  if (Platform.isMacOS) {
    return 'macos';
  }
  if (Platform.isWindows) {
    return 'windows';
  }
  return Platform.operatingSystem.toLowerCase();
}

_PlanModeScenarioTestConfig _resolveScenarioTestConfig() {
  final usesLiveLlm = _envFlagEnabled('CAVERNO_PLAN_MODE_LIVE_LLM');
  final failOnWarnings = _envFlagEnabled('CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS');
  final tagMatchMode = _envValueOrDefault('CAVERNO_PLAN_MODE_TAG_MATCH', 'any');
  final deviceName = Platform.environment['CAVERNO_PLAN_MODE_DEVICE']
      ?.trim()
      .toLowerCase();
  final resolvedDeviceName = deviceName == null || deviceName.isEmpty
      ? _defaultPlanModeDeviceName()
      : deviceName;
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
            (tagMatchMode == 'all'
                ? requestedTagSet.every(
                    (tag) => scenario.tags.any(
                      (candidate) => candidate.trim().toLowerCase() == tag,
                    ),
                  )
                : scenario.tags.any(
                    (tag) => requestedTagSet.contains(tag.trim().toLowerCase()),
                  ));
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
      deviceName: resolvedDeviceName,
      mode: _PlanModeScenarioExecutionMode.fake,
      suiteName: 'plan_mode_scenarios_$resolvedDeviceName',
      reportPrefix: 'plan_mode_suite_$resolvedDeviceName',
      scenarios: filteredScenarios,
      failOnWarnings: failOnWarnings,
      requestedScenarioNames: requestedScenarioNames,
      requestedTags: requestedTags,
    );
  }

  return _PlanModeScenarioTestConfig(
    deviceName: resolvedDeviceName,
    mode: _PlanModeScenarioExecutionMode.live,
    suiteName: 'plan_mode_live_scenarios_$resolvedDeviceName',
    reportPrefix: 'plan_mode_live_suite_$resolvedDeviceName',
    scenarios: filteredScenarios,
    failOnWarnings: failOnWarnings,
    requestedScenarioNames: requestedScenarioNames,
    requestedTags: requestedTags,
    baseUrl: _requireNonEmptyEnv('CAVERNO_LLM_BASE_URL'),
    apiKey: _requireNonEmptyEnv('CAVERNO_LLM_API_KEY'),
    model: _requireNonEmptyEnv('CAVERNO_LLM_MODEL'),
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
  ProviderContainer container,
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
    if (config.usesLiveLlm) {
      final resolved = await _resolveLivePlanningDecision(
        container,
        scenario,
        scriptedDecisionIndex: scriptedDecisionIndex,
      );
      if (!resolved) {
        return;
      }
      if (scriptedDecisionIndex < scenario.decisionSelections.length) {
        scriptedDecisionIndex += 1;
      }
      resolvedDecisionCount += 1;
      continue;
    }

    await _pumpUntilIdle(tester);
    final chatState = container.read(chatNotifierProvider);
    final decisionSheetFinder = find.byType(BottomSheet);
    final confirmFinder = find.descendant(
      of: decisionSheetFinder,
      matching: find.text('Continue with this choice'),
    );
    if (shouldWaitForPlanningDecisionSheet(
      hasPendingDecision: chatState.pendingWorkflowDecision != null,
      confirmVisible: confirmFinder.evaluate().isNotEmpty,
    )) {
      appLog('[Workflow] Waiting for planning decision sheet');
      final confirmBecameVisible = await _waitForPlanningDecisionConfirm(
        tester,
      );
      if (!confirmBecameVisible) {
        throw StateError(
          'A planning decision is pending, but the decision sheet did not '
          'show its confirmation control.',
        );
      }
    }

    final refreshedChatState = container.read(chatNotifierProvider);
    final shouldHandleDecision = shouldHandlePlanningDecision(
      hasPendingDecision: refreshedChatState.pendingWorkflowDecision != null,
      confirmVisible: confirmFinder.evaluate().isNotEmpty,
    );
    if (!shouldHandleDecision) {
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

    if (config.usesLiveLlm) {
      appLog(
        '[Screenshot] Decision screenshot skipped for live scenario '
        '${scenario.name}',
      );
    } else {
      appLog('[Workflow] Decision screenshot started');
      try {
        await captureIntegrationScreenshot(
          binding: binding,
          tester: tester,
          repaintBoundaryKey: screenshotBoundaryKey,
          name:
              'plan_mode_${scenario.name}_decision_${resolvedDecisionCount + 1}',
          outputDirectory: outputDirectory,
        ).timeout(const Duration(seconds: 10));
        appLog('[Workflow] Decision screenshot finished');
      } on TimeoutException {
        appLog('[Workflow] Decision screenshot skipped after timeout');
      } catch (error) {
        appLog('[Workflow] Decision screenshot skipped after error: $error');
      }
    }

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
      await _pumpUntilIdle(tester);
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
      await _pumpUntilIdle(tester);
    } else if (config.usesLiveLlm) {
      appLog(
        '[ScenarioLive] Auto-accepted the default planning option'
        '${questionText != null ? ' for "$questionText"' : ''}.',
      );
    }

    expect(confirmFinder, findsOneWidget);
    await tester.tap(confirmFinder, warnIfMissed: false);
    await tester.pump();
    await _pumpUntilIdle(tester);
    if (scriptedSelection != null) {
      scriptedDecisionIndex += 1;
    }
    resolvedDecisionCount += 1;
  }

  throw StateError(
    'Planning decisions did not settle after $maxDecisionRounds rounds.',
  );
}

Future<bool> _resolveLivePlanningDecision(
  ProviderContainer container,
  PlanModeScenarioSpec scenario, {
  required int scriptedDecisionIndex,
}) async {
  final pending = container.read(chatNotifierProvider).pendingWorkflowDecision;
  if (pending == null) {
    return false;
  }

  final decision = pending.decision;
  final scriptedSelection =
      scriptedDecisionIndex < scenario.decisionSelections.length
      ? scenario.decisionSelections[scriptedDecisionIndex]
      : null;
  final answer = _buildLivePlanningDecisionAnswer(decision, scriptedSelection);
  appLog(
    '[ScenarioLive] Resolved planning decision via harness: '
    '${decision.question} -> ${answer.optionLabel}',
  );
  container
      .read(chatNotifierProvider.notifier)
      .resolveWorkflowDecision(id: pending.id, answer: answer);
  await Future<void>.delayed(const Duration(milliseconds: 100));
  return true;
}

WorkflowPlanningDecisionAnswer _buildLivePlanningDecisionAnswer(
  WorkflowPlanningDecision decision,
  PlanModeScenarioDecisionSelection? scriptedSelection,
) {
  final freeTextAnswer = scriptedSelection?.freeTextAnswer?.trim();
  if (freeTextAnswer != null && freeTextAnswer.isNotEmpty) {
    return WorkflowPlanningDecisionAnswer(
      decisionId: decision.id,
      question: decision.question,
      optionId: 'free_text',
      optionLabel: freeTextAnswer,
    );
  }

  final targetOptionLabel = scriptedSelection?.optionLabel?.trim();
  final selectedOption = targetOptionLabel == null || targetOptionLabel.isEmpty
      ? decision.options.firstOrNull
      : decision.options
                .where(
                  (option) =>
                      normalizePlanModeDecisionOptionLabel(option.label) ==
                      normalizePlanModeDecisionOptionLabel(targetOptionLabel),
                )
                .firstOrNull ??
            decision.options.firstOrNull;

  if (selectedOption != null) {
    return WorkflowPlanningDecisionAnswer(
      decisionId: decision.id,
      question: decision.question,
      optionId: selectedOption.id,
      optionLabel: selectedOption.label,
    );
  }

  if (decision.allowFreeText) {
    final fallbackAnswer = targetOptionLabel?.isNotEmpty == true
        ? targetOptionLabel!
        : 'Default';
    return WorkflowPlanningDecisionAnswer(
      decisionId: decision.id,
      question: decision.question,
      optionId: 'free_text',
      optionLabel: fallbackAnswer,
    );
  }

  throw StateError(
    'Cannot resolve live planning decision because it has no selectable '
    'options: ${decision.question}',
  );
}

Future<bool> _waitForPlanningDecisionConfirm(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    await _delayAndPumpFrame(tester, const Duration(milliseconds: 100));
    await _pumpUntilIdle(tester);
    final decisionSheetFinder = find.byType(BottomSheet);
    final confirmFinder = find.descendant(
      of: decisionSheetFinder,
      matching: find.text('Continue with this choice'),
    );
    if (confirmFinder.evaluate().isNotEmpty) {
      return true;
    }
  }
  return false;
}

Future<void> _delayAndPumpFrame(WidgetTester tester, Duration delay) async {
  await Future<void>.delayed(delay);
  await tester.pump();
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

  final normalizedTarget = normalizePlanModeDecisionOptionLabel(targetText);
  return find.descendant(
    of: decisionSheetFinder,
    matching: find.byWidgetPredicate((widget) {
      if (widget is! Text) {
        return false;
      }
      final data = widget.data == null
          ? null
          : normalizePlanModeDecisionOptionLabel(widget.data!);
      return data != null && data == normalizedTarget;
    }),
  );
}

String _resolvePlanningSubphase(
  ChatState chatState,
  List<String> logs, {
  required bool approvalUiVisible,
}) {
  return resolvePlanningSubphase(
    hasPendingDecision: chatState.pendingWorkflowDecision != null,
    hasWorkflowDraft: chatState.workflowProposalDraft != null,
    hasTaskDraft: chatState.taskProposalDraft != null,
    approvalUiVisible: approvalUiVisible,
    isGeneratingWorkflowProposal: chatState.isGeneratingWorkflowProposal,
    isGeneratingTaskProposal: chatState.isGeneratingTaskProposal,
    logs: logs,
  );
}

Future<void> _waitForReadyPlanProposal(
  WidgetTester tester,
  ProviderContainer container, {
  required Duration timeout,
  required _PlanModePhaseTrace phaseTrace,
  required _PlanModeLiveHeartbeatWriter heartbeatWriter,
  required _PlanModeTimeoutBudgets budgets,
  required IntegrationTestWidgetsFlutterBinding binding,
  required _PlanModeScenarioTestConfig config,
  required PlanModeScenarioSpec scenario,
  required GlobalKey screenshotBoundaryKey,
  required Directory outputDirectory,
  required List<String> logs,
}) async {
  var recoveredTaskProposal = false;
  var deadline = DateTime.now().add(timeout);
  String? lastPlanningProgressKey;
  var proposalUiLogged = false;

  bool isApprovalUiReady() {
    return _reviewablePlanApprovalUiReady(container);
  }

  bool isProposalReady(ChatState chatState) {
    return isPlanningProposalReady(
      hasWorkflowDraft: chatState.workflowProposalDraft != null,
      hasTaskDraft: chatState.taskProposalDraft != null,
      hasPendingDecision: chatState.pendingWorkflowDecision != null,
      approvalUiVisible: isApprovalUiReady(),
      workflowError: chatState.workflowProposalError,
      taskError: chatState.taskProposalError,
      logs: logs,
    );
  }

  while (DateTime.now().isBefore(deadline)) {
    final chatState = container.read(chatNotifierProvider);
    final conversation = container
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (chatState.workflowProposalDraft != null ||
        planningLogsContainWorkflowDraftReady(logs) ||
        planningLogsContainWorkflowDraftPersisted(logs)) {
      phaseTrace.proposalReadyAt ??= DateTime.now();
    }
    if (chatState.taskProposalDraft != null ||
        planningLogsContainTaskDraftReady(logs) ||
        planningLogsContainTaskDraftPersisted(logs)) {
      phaseTrace.taskProposalReadyAt ??= DateTime.now();
    }
    final workflowSnapshot = _summarizeWorkflowTasks(
      conversation?.projectedExecutionTasks ??
          const <ConversationWorkflowTask>[],
    );
    final draftReadyBeforeUiProbe = isPlanningProposalReady(
      hasWorkflowDraft: chatState.workflowProposalDraft != null,
      hasTaskDraft: chatState.taskProposalDraft != null,
      hasPendingDecision: chatState.pendingWorkflowDecision != null,
      approvalUiVisible: false,
      workflowError: chatState.workflowProposalError,
      taskError: chatState.taskProposalError,
      logs: logs,
    );
    if (draftReadyBeforeUiProbe && chatState.pendingWorkflowDecision == null) {
      phaseTrace.proposalReadyAt ??= DateTime.now();
      phaseTrace.taskProposalReadyAt ??= DateTime.now();
      heartbeatWriter.write(
        phase: 'planning',
        subphase: 'taskDraftReadyAwaitingApprovalUi',
        phaseTrace: phaseTrace,
        budgets: budgets,
        workflowSnapshot: workflowSnapshot,
        messageCount: conversation?.messages.length ?? 0,
        hasPendingApprovals: false,
        isLoading: false,
      );
      return;
    }
    final approvalUiReady = isApprovalUiReady();
    if (approvalUiReady && !proposalUiLogged) {
      proposalUiLogged = true;
      appLog('[Workflow] Proposal approval UI became visible');
      heartbeatWriter.write(
        phase: 'planning',
        subphase: 'proposalUiVisible',
        phaseTrace: phaseTrace,
        budgets: budgets,
        workflowSnapshot: workflowSnapshot,
        messageCount: conversation?.messages.length ?? 0,
        hasPendingApprovals: false,
        isLoading: false,
      );
    }
    final planningProgressKey =
        '${conversation?.messages.length ?? 0}|'
        '${chatState.workflowProposalDraft != null || planningLogsContainWorkflowDraftReady(logs)}|'
        '${chatState.taskProposalDraft != null || planningLogsContainTaskDraftReady(logs)}|'
        '${planningLogsContainWorkflowDraftPersisted(logs)}|'
        '${planningLogsContainTaskDraftPersisted(logs)}|'
        '${chatState.isGeneratingWorkflowProposal}|'
        '${chatState.isGeneratingTaskProposal}|'
        '${chatState.pendingWorkflowDecision != null}|'
        '${chatState.workflowProposalError}|'
        '${chatState.taskProposalError}|'
        '${planningLogsContainWorkflowDraftReady(logs)}|'
        '${planningLogsContainTaskDraftReady(logs)}|'
        '$approvalUiReady';
    if (planningProgressKey != lastPlanningProgressKey) {
      lastPlanningProgressKey = planningProgressKey;
      deadline = DateTime.now().add(timeout);
    }
    heartbeatWriter.write(
      phase: 'planning',
      subphase: _resolvePlanningSubphase(
        chatState,
        logs,
        approvalUiVisible: approvalUiReady,
      ),
      phaseTrace: phaseTrace,
      budgets: budgets,
      workflowSnapshot: workflowSnapshot,
      messageCount: conversation?.messages.length ?? 0,
      hasPendingApprovals: chatState.pendingWorkflowDecision != null,
      isLoading:
          chatState.isLoading ||
          chatState.isGeneratingWorkflowProposal ||
          chatState.isGeneratingTaskProposal,
    );
    if (isProposalReady(chatState)) {
      phaseTrace.proposalReadyAt ??= DateTime.now();
      phaseTrace.taskProposalReadyAt ??= DateTime.now();
      heartbeatWriter.write(
        phase: 'planning',
        subphase: approvalUiReady
            ? 'taskDraftReady'
            : 'taskDraftReadyAwaitingApprovalUi',
        phaseTrace: phaseTrace,
        budgets: budgets,
        workflowSnapshot: workflowSnapshot,
        messageCount: conversation?.messages.length ?? 0,
        hasPendingApprovals: false,
        isLoading: false,
      );
      return;
    }
    if (chatState.pendingWorkflowDecision != null) {
      await _resolvePlanningDecisions(
        tester,
        container,
        binding,
        config,
        scenario,
        screenshotBoundaryKey,
        outputDirectory,
      );
      heartbeatWriter.write(
        phase: 'planning',
        subphase: 'decisionResolved',
        phaseTrace: phaseTrace,
        budgets: budgets,
        workflowSnapshot: workflowSnapshot,
        messageCount: conversation?.messages.length ?? 0,
        hasPendingApprovals: false,
        isLoading: true,
      );
      deadline = DateTime.now().add(timeout);
      await tester.pump();
      continue;
    }
    if (!recoveredTaskProposal &&
        chatState.workflowProposalDraft != null &&
        chatState.taskProposalDraft == null &&
        chatState.taskProposalError == null &&
        !chatState.isGeneratingWorkflowProposal &&
        !chatState.isGeneratingTaskProposal) {
      recoveredTaskProposal = true;
      await container
          .read(chatNotifierProvider.notifier)
          .generateTaskProposal();
      deadline = DateTime.now().add(timeout);
      await tester.pump();
      continue;
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
    final latestChatState = container.read(chatNotifierProvider);
    final latestConversation = container
        .read(conversationsNotifierProvider)
        .currentConversation;
    final latestDraftReadyBeforeUiProbe = isPlanningProposalReady(
      hasWorkflowDraft: latestChatState.workflowProposalDraft != null,
      hasTaskDraft: latestChatState.taskProposalDraft != null,
      hasPendingDecision: latestChatState.pendingWorkflowDecision != null,
      approvalUiVisible: false,
      workflowError: latestChatState.workflowProposalError,
      taskError: latestChatState.taskProposalError,
      logs: logs,
    );
    if (latestDraftReadyBeforeUiProbe &&
        latestChatState.pendingWorkflowDecision == null) {
      phaseTrace.proposalReadyAt ??= DateTime.now();
      phaseTrace.taskProposalReadyAt ??= DateTime.now();
      heartbeatWriter.write(
        phase: 'planning',
        subphase: 'taskDraftReadyAwaitingApprovalUi',
        phaseTrace: phaseTrace,
        budgets: budgets,
        workflowSnapshot: _summarizeWorkflowTasks(
          latestConversation?.projectedExecutionTasks ??
              const <ConversationWorkflowTask>[],
        ),
        messageCount: latestConversation?.messages.length ?? 0,
        hasPendingApprovals: false,
        isLoading: false,
      );
      return;
    }
    if (!config.usesLiveLlm) {
      await tester.pump();
    }
  }

  final chatState = container.read(chatNotifierProvider);
  if (isProposalReady(chatState)) {
    phaseTrace.proposalReadyAt ??= DateTime.now();
    phaseTrace.taskProposalReadyAt ??= DateTime.now();
    final conversation = container
        .read(conversationsNotifierProvider)
        .currentConversation;
    final approvalUiReady = isApprovalUiReady();
    heartbeatWriter.write(
      phase: 'planning',
      subphase: approvalUiReady
          ? 'taskDraftReady'
          : 'taskDraftReadyAwaitingApprovalUi',
      phaseTrace: phaseTrace,
      budgets: budgets,
      workflowSnapshot: _summarizeWorkflowTasks(
        conversation?.projectedExecutionTasks ??
            const <ConversationWorkflowTask>[],
      ),
      messageCount: conversation?.messages.length ?? 0,
      hasPendingApprovals: false,
      isLoading: false,
    );
    return;
  }

  throw StateError(
    'Planning phase timed out after ${timeout.inSeconds}s while waiting for the plan proposal. '
    'workflowDraft=${chatState.workflowProposalDraft != null}, '
    'taskDraft=${chatState.taskProposalDraft != null}, '
    'isGeneratingWorkflow=${chatState.isGeneratingWorkflowProposal}, '
    'isGeneratingTask=${chatState.isGeneratingTaskProposal}, '
    'pendingDecision=${chatState.pendingWorkflowDecision != null}, '
    'workflowError=${chatState.workflowProposalError}, '
    'taskError=${chatState.taskProposalError}',
  );
}

bool _reviewablePlanApprovalUiReady(ProviderContainer container) {
  final reviewSheet = find.byType(PlanReviewSheet);
  if (reviewSheet.evaluate().isEmpty) {
    return false;
  }
  final approveAction = _findPreferredPlanApproveAction();
  if (approveAction.evaluate().isEmpty) {
    return false;
  }
  final conversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  if (!planReviewArtifactHasPreviewTasks(conversation: conversation)) {
    return false;
  }
  final zeroTaskPreview = find.descendant(
    of: reviewSheet,
    matching: find.text('Preview tasks: 0'),
  );
  return zeroTaskPreview.evaluate().isEmpty;
}

bool _reviewablePlanArtifactReady(ProviderContainer container) {
  final conversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  return planReviewArtifactHasPreviewTasks(conversation: conversation);
}

Future<bool> _waitForReviewablePlanApprovalUi(
  WidgetTester tester,
  ProviderContainer container, {
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 100),
  bool allowArtifactReadyFallback = false,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(step);
    await tester.pump();
    if (_reviewablePlanApprovalUiReady(container)) {
      return true;
    }
    if (allowArtifactReadyFallback && _reviewablePlanArtifactReady(container)) {
      return false;
    }
  }
  if (allowArtifactReadyFallback && _reviewablePlanArtifactReady(container)) {
    return false;
  }
  final timeoutAction = resolvePlanModeApprovalUiWaitTimeoutAction(
    allowArtifactReadyFallback: allowArtifactReadyFallback,
    artifactReady: _reviewablePlanArtifactReady(container),
  );
  switch (timeoutAction) {
    case PlanModeApprovalUiWaitTimeoutAction.useArtifactReadyFallback:
    case PlanModeApprovalUiWaitTimeoutAction.useLiveHarnessValidationFallback:
      return false;
    case PlanModeApprovalUiWaitTimeoutAction.failUiExpectation:
      break;
  }
  expect(_reviewablePlanApprovalUiReady(container), isTrue);
  return true;
}

class _HarnessExecutionHandle {
  const _HarnessExecutionHandle(this.done);

  final Future<void> done;
}

Future<_HarnessExecutionHandle> _approvePlanAndStartFromHarness(
  ProviderContainer container, {
  required _PlanModePhaseTrace phaseTrace,
  required _PlanModeLiveHeartbeatWriter heartbeatWriter,
  required _PlanModeTimeoutBudgets budgets,
}) async {
  final conversationsNotifier = container.read(
    conversationsNotifierProvider.notifier,
  );
  final chatNotifier = container.read(chatNotifierProvider.notifier);
  final conversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  if (conversation == null) {
    throw StateError('Cannot approve plan because no conversation is active.');
  }

  final currentArtifact = conversation.effectivePlanArtifact;
  final draftMarkdown =
      currentArtifact.normalizedDraftMarkdown ??
      currentArtifact.normalizedApprovedMarkdown;
  if (draftMarkdown == null) {
    throw StateError('Cannot approve plan because no plan document exists.');
  }

  final validation = ConversationPlanProjectionService.validateDocument(
    markdown: draftMarkdown,
    requireTasks: true,
  );
  if (!validation.isValid || validation.projection == null) {
    throw StateError(
      'Cannot approve plan because the plan document is invalid: '
      '${validation.errorMessage ?? 'unknown validation error'}.',
    );
  }

  final approvedWorkflowStage = switch (validation.workflowStage) {
    ConversationWorkflowStage.tasks ||
    ConversationWorkflowStage.implement ||
    ConversationWorkflowStage.review => validation.workflowStage!,
    _ =>
      validation.previewTasks.isEmpty
          ? ConversationWorkflowStage.tasks
          : ConversationWorkflowStage.implement,
  };
  final approvedMarkdown =
      ConversationPlanProjectionService.replaceWorkflowStage(
        markdown: draftMarkdown,
        workflowStage: approvedWorkflowStage,
      );
  final updatedAt = DateTime.now();
  final nextArtifact = currentArtifact
      .copyWith(
        draftMarkdown: approvedMarkdown,
        approvedMarkdown: approvedMarkdown,
        updatedAt: updatedAt,
      )
      .recordRevision(
        markdown: approvedMarkdown,
        kind: ConversationPlanRevisionKind.approved,
        label: 'Approved plan from live test harness',
        createdAt: updatedAt,
      );

  await conversationsNotifier.updateCurrentPlanArtifact(
    planArtifact: nextArtifact,
    clearPlanArtifact: !nextArtifact.hasContent,
  );
  final refreshed = await conversationsNotifier
      .refreshCurrentWorkflowProjectionFromApprovedPlan();
  if (!refreshed && validation.workflowSpec != null) {
    await conversationsNotifier.updateCurrentWorkflow(
      workflowStage: approvedWorkflowStage,
      workflowSpec: validation.workflowSpec!,
    );
  }
  await conversationsNotifier.exitPlanningSession();
  chatNotifier.dismissPlanProposal();

  final executionConversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  if (executionConversation == null) {
    throw StateError('Cannot start execution because no saved task is ready.');
  }
  final nextTask = ConversationPlanExecutionCoordinator.nextTask(
    executionConversation,
  );
  if (nextTask == null) {
    throw StateError('Cannot start execution because no saved task is ready.');
  }

  phaseTrace.approvalTappedAt = DateTime.now();
  heartbeatWriter.write(
    phase: 'execution',
    subphase: 'approvedViaHarness',
    phaseTrace: phaseTrace,
    budgets: budgets,
    activeTaskTitle: nextTask.title,
    workflowSnapshot: _summarizeWorkflowTasks(
      executionConversation.projectedExecutionTasks,
    ),
    messageCount: executionConversation.messages.length,
    hasPendingApprovals: false,
    isLoading: true,
  );

  await conversationsNotifier.updateCurrentExecutionTaskProgress(
    taskId: nextTask.id,
    status: ConversationWorkflowTaskStatus.inProgress,
    lastRunAt: DateTime.now(),
    summary: 'Started from the live test harness approval fallback.',
    eventType: ConversationExecutionTaskEventType.started,
  );

  final startedConversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  final previousAssistantMessageId = _latestAssistantMessageId(
    startedConversation,
  );
  phaseTrace.firstTaskStartedAt ??= DateTime.now();
  phaseTrace.firstTaskTitle ??= nextTask.title;
  heartbeatWriter.write(
    phase: 'execution',
    subphase: 'startedViaHarness',
    phaseTrace: phaseTrace,
    budgets: budgets,
    activeTaskTitle: nextTask.title,
    workflowSnapshot: _summarizeWorkflowTasks(
      startedConversation?.projectedExecutionTasks ??
          executionConversation.projectedExecutionTasks,
    ),
    messageCount: startedConversation?.messages.length ?? 0,
    hasPendingApprovals: false,
    isLoading: true,
  );

  return _HarnessExecutionHandle(
    _runApprovedTaskFromHarness(
      container,
      task: nextTask,
      previousAssistantMessageId: previousAssistantMessageId,
    ),
  );
}

Future<void> _runApprovedTaskFromHarness(
  ProviderContainer container, {
  required ConversationWorkflowTask task,
  required String? previousAssistantMessageId,
}) async {
  final chatNotifier = container.read(chatNotifierProvider.notifier);
  final conversationsNotifier = container.read(
    conversationsNotifierProvider.notifier,
  );
  try {
    await chatNotifier.sendMessage(
      ConversationPlanExecutionCoordinator.buildTaskPrompt(
        task: task,
        intro: 'Use the approved saved task now: ${task.title}',
        targetFilesLabel: 'Target files',
        validationLabel: 'Validation',
        notesLabel: 'Notes',
        outro:
            'Implement this task now. Use available tools and report completion evidence.',
      ),
      languageCode: 'en',
      bypassPlanMode: true,
    );

    final toolResults = chatNotifier.takeLatestToolResults();
    final hiddenAssistantResponse = chatNotifier
        .takeLatestHiddenAssistantResponse();
    final conversation = container
        .read(conversationsNotifierProvider)
        .currentConversation;
    final latestAssistantResponse = _latestAssistantResponseAfter(
      conversation,
      previousAssistantMessageId,
    );
    final fallbackResponse = _harnessFallbackAssistantResponse(
      toolResults: toolResults,
      hiddenAssistantResponse: hiddenAssistantResponse,
    );
    if (latestAssistantResponse.trim().isEmpty &&
        fallbackResponse.trim().isEmpty) {
      return;
    }

    await conversationsNotifier
        .updateCurrentExecutionTaskProgressFromAssistantTurn(
          task: task,
          assistantResponse: latestAssistantResponse,
          isValidationRun: false,
          fallbackAssistantResponse: fallbackResponse,
        );
  } catch (error, stackTrace) {
    appLog('[Workflow] Harness task execution failed: $error');
    appLog('$stackTrace');
    await conversationsNotifier.updateCurrentExecutionTaskProgress(
      taskId: task.id,
      status: ConversationWorkflowTaskStatus.blocked,
      blockedReason: error.toString(),
      summary: 'Harness task execution failed before completion.',
      eventType: ConversationExecutionTaskEventType.blocked,
      eventSummary: error.toString(),
    );
  }
}

Future<void> _awaitHarnessExecutionCleanup(
  _HarnessExecutionHandle? executionHandle, {
  required PlanModeScenarioSpec scenario,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final executionFuture = executionHandle?.done;
  if (executionFuture == null) {
    return;
  }
  try {
    await executionFuture.timeout(timeout);
  } on TimeoutException {
    appLog(
      '[Workflow] Harness background execution did not finish before cleanup '
      'timeout for ${scenario.name}',
    );
  }
}

Duration _resolveHarnessCleanupTimeout(
  _PlanModeScenarioTestConfig config,
  _PlanModeTimeoutBudgets budgets,
) {
  if (!config.usesLiveLlm) {
    return const Duration(seconds: 30);
  }
  const minimumLiveTimeout = Duration(seconds: 90);
  return budgets.executionTimeout > minimumLiveTimeout
      ? budgets.executionTimeout
      : minimumLiveTimeout;
}

String? _latestAssistantMessageId(Conversation? conversation) {
  return _latestAssistantMessage(conversation)?.id;
}

String _latestAssistantResponseAfter(
  Conversation? conversation,
  String? previousAssistantMessageId,
) {
  final latest = _latestAssistantMessage(conversation);
  if (latest == null || latest.id == previousAssistantMessageId) {
    return '';
  }
  return latest.content.trim();
}

Message? _latestAssistantMessage(Conversation? conversation) {
  if (conversation == null) {
    return null;
  }
  for (final message in conversation.messages.reversed) {
    if (message.role == MessageRole.assistant) {
      return message;
    }
  }
  return null;
}

String _harnessFallbackAssistantResponse({
  required List<ToolResultInfo> toolResults,
  required String? hiddenAssistantResponse,
}) {
  final hidden = hiddenAssistantResponse?.trim() ?? '';
  if (hidden.isNotEmpty) {
    return hidden;
  }
  if (toolResults.isEmpty) {
    return '';
  }
  final toolNames = toolResults
      .map((result) => result.name.trim())
      .where((name) => name.isNotEmpty)
      .toSet()
      .join(', ');
  if (toolNames.isEmpty) {
    return 'The saved task completed with tool execution evidence.';
  }
  return 'The saved task completed with tool execution evidence from: $toolNames.';
}

Future<void> _waitForWorkflowExecutionCompletion(
  WidgetTester tester,
  ProviderContainer container, {
  required Duration timeout,
  required Duration stallTimeout,
  required List<String> logs,
  required _PlanModePhaseTrace phaseTrace,
  required _PlanModeTimeoutBudgets budgets,
  required _PlanModeLiveHeartbeatWriter heartbeatWriter,
  required bool useFramePump,
}) async {
  final deadline = DateTime.now().add(timeout);
  final watchdog = PlanModeExecutionWatchdog(stallTimeout: stallTimeout);
  final blockedTimeout = stallTimeout < const Duration(seconds: 15)
      ? stallTimeout
      : const Duration(seconds: 15);
  String? lastHeartbeatKey;
  DateTime? blockedSince;
  var lastObservedLogCount = 0;
  while (DateTime.now().isBefore(deadline)) {
    final now = DateTime.now();
    final chatState = container.read(chatNotifierProvider);
    final conversation = container
        .read(conversationsNotifierProvider)
        .currentConversation;
    final tasks = conversation?.projectedExecutionTasks ?? const [];
    final hasPendingWork = tasks.any(
      (task) =>
          task.status == ConversationWorkflowTaskStatus.pending ||
          task.status == ConversationWorkflowTaskStatus.inProgress,
    );
    final hasBlockedTasks = tasks.any(
      (task) => task.status == ConversationWorkflowTaskStatus.blocked,
    );
    final hasPendingApprovals =
        chatState.pendingSshConnect != null ||
        chatState.pendingSshCommand != null ||
        chatState.pendingGitCommand != null ||
        chatState.pendingLocalCommand != null ||
        chatState.pendingFileOperation != null ||
        chatState.pendingBleConnect != null ||
        chatState.pendingWorkflowDecision != null;

    if (shouldRecoverExecutionFromExecutionDocument(
      conversation: conversation,
      isLoading: chatState.isLoading,
      hasPendingApprovals: hasPendingApprovals,
      approvalTappedAt: phaseTrace.approvalTappedAt,
    )) {
      final refreshed = await container
          .read(conversationsNotifierProvider.notifier)
          .refreshCurrentWorkflowProjectionFromApprovedPlan();
      if (refreshed) {
        final refreshedConversation = container
            .read(conversationsNotifierProvider)
            .currentConversation;
        final refreshedTasks =
            refreshedConversation?.projectedExecutionTasks ?? const [];
        final refreshedActiveTaskTitle = _activeWorkflowTaskTitle(
          refreshedTasks,
        );
        final refreshedWorkflowSnapshot = _summarizeWorkflowTasks(
          refreshedTasks,
        );
        appLog(
          '[Workflow] Execution projection recovered from execution document',
        );
        heartbeatWriter.write(
          phase: 'execution',
          subphase: 'executionProjectionRecovered',
          phaseTrace: phaseTrace,
          budgets: budgets,
          activeTaskTitle: refreshedActiveTaskTitle,
          workflowSnapshot: refreshedWorkflowSnapshot,
          toolResultCount: _countContentToolResults(logs),
          fileWriteCount: _countFileWriteExecutions(logs),
          messageCount: refreshedConversation?.messages.length ?? 0,
          hasPendingApprovals: false,
          isLoading: chatState.isLoading,
        );
        phaseTrace.lastTaskProgressAt = now;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
    }

    final hasInProgressTask = tasks.any(
      (task) => task.status == ConversationWorkflowTaskStatus.inProgress,
    );

    if (hasInProgressTask) {
      phaseTrace.firstTaskStartedAt ??= now;
      phaseTrace.firstTaskTitle ??= _activeWorkflowTaskTitle(tasks);
    }
    if (tasks.any(
      (task) => task.status == ConversationWorkflowTaskStatus.completed,
    )) {
      phaseTrace.firstTaskCompletedAt ??= now;
    }
    final activeTaskTitle = _activeWorkflowTaskTitle(tasks);
    final workflowSnapshot = _summarizeWorkflowTasks(tasks);
    if (!hasPendingApprovals && executionLogsContainWorkflowCompleted(logs)) {
      phaseTrace.firstTaskCompletedAt ??= now;
      phaseTrace.lastTaskProgressAt = now;
      heartbeatWriter.write(
        phase: 'completed',
        subphase: 'workflowCompletedRecovered',
        phaseTrace: phaseTrace,
        budgets: budgets,
        activeTaskTitle: activeTaskTitle,
        workflowSnapshot: workflowSnapshot,
        toolResultCount: _countContentToolResults(logs),
        fileWriteCount: _countFileWriteExecutions(logs),
        messageCount: conversation?.messages.length ?? 0,
        hasPendingApprovals: false,
        isLoading: false,
      );
      await _pumpUntilExecutionSettles(
        tester,
        container,
        useFramePump: useFramePump,
      );
      return;
    }
    if (phaseTrace.firstTaskTitle != null &&
        activeTaskTitle != null &&
        activeTaskTitle != phaseTrace.firstTaskTitle) {
      phaseTrace.nextTaskStartedAt ??= now;
    }
    if (_countValidationLikeExecutions(logs) > 0) {
      phaseTrace.validationStartedAt ??= now;
    }
    if (hasInProgressTask &&
        logs.length > lastObservedLogCount &&
        executionLogsContainLateValidationAnswerProgress(logs)) {
      phaseTrace.lastTaskProgressAt = now;
      heartbeatWriter.write(
        phase: 'execution',
        subphase: 'answering',
        phaseTrace: phaseTrace,
        budgets: budgets,
        activeTaskTitle: activeTaskTitle,
        workflowSnapshot: workflowSnapshot,
        toolResultCount: _countContentToolResults(logs),
        fileWriteCount: _countFileWriteExecutions(logs),
        messageCount: conversation?.messages.length ?? 0,
        hasPendingApprovals: hasPendingApprovals,
        isLoading: chatState.isLoading,
      );
    }
    lastObservedLogCount = logs.length;

    if (hasBlockedTasks &&
        !hasInProgressTask &&
        !chatState.isLoading &&
        !hasPendingApprovals) {
      blockedSince ??= now;
      final blockedFor = now.difference(blockedSince);
      if (blockedFor >= blockedTimeout) {
        final workflowSnapshot = _summarizeWorkflowTasks(tasks);
        final diagnostics = buildPlanModeFailureDiagnostics(
          logs: logs,
          errorText:
              'Workflow execution remained blocked. tasks=$workflowSnapshot',
          lastWorkflowSnapshot: workflowSnapshot,
          budgetPhase: 'execution',
          activeTaskTitle: _activeWorkflowTaskTitle(tasks),
          toolResultCount: _countContentToolResults(logs),
          fileWriteCount: _countFileWriteExecutions(logs),
          phaseTimings: phaseTrace.toJson(),
          budgets: budgets.toJson(),
        );
        throw StateError(
          'Workflow execution remained blocked after '
          '${blockedFor.inSeconds}s. '
          'activeTask=${diagnostics.activeTaskTitle ?? 'none'} '
          'toolResults=${diagnostics.toolResultCount ?? 0} '
          'fileWrites=${diagnostics.fileWriteCount ?? 0} '
          'tasks=$workflowSnapshot '
          'lastTool=${diagnostics.lastToolName ?? 'none'} '
          'lastAssistant=${diagnostics.lastAssistantSummary ?? 'none'}',
        );
      }
    } else {
      blockedSince = null;
    }

    if (tasks.isNotEmpty &&
        !chatState.isLoading &&
        !hasPendingApprovals &&
        !hasPendingWork) {
      if (hasBlockedTasks) {
        throw StateError(
          'Workflow execution finished in a blocked state: '
          '${_summarizeWorkflowTasks(tasks)}',
        );
      }
      if (useFramePump) {
        await _pumpUntilIdle(tester);
      }
      return;
    }

    final heartbeat = PlanModeExecutionHeartbeat(
      activeTaskTitle: activeTaskTitle,
      workflowSnapshot: workflowSnapshot,
      toolResultCount: _countContentToolResults(logs),
      fileWriteCount: _countFileWriteExecutions(logs),
      hasPendingApprovals: hasPendingApprovals,
      isLoading: chatState.isLoading,
    );
    if (lastHeartbeatKey != heartbeat.progressKey) {
      lastHeartbeatKey = heartbeat.progressKey;
      phaseTrace.lastTaskProgressAt = now;
    }
    heartbeatWriter.write(
      phase: 'execution',
      subphase: _resolveExecutionSubphase(phaseTrace, activeTaskTitle),
      phaseTrace: phaseTrace,
      budgets: budgets,
      activeTaskTitle: heartbeat.activeTaskTitle,
      workflowSnapshot: heartbeat.workflowSnapshot,
      toolResultCount: heartbeat.toolResultCount,
      fileWriteCount: heartbeat.fileWriteCount,
      messageCount: conversation?.messages.length ?? 0,
      hasPendingApprovals: heartbeat.hasPendingApprovals,
      isLoading: heartbeat.isLoading,
    );
    final stalledSample = watchdog.recordHeartbeat(heartbeat, now);
    if (stalledSample != null && tasks.isNotEmpty && hasPendingWork) {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: logs,
        errorText: 'Workflow execution stalled. tasks=$workflowSnapshot',
        lastWorkflowSnapshot: workflowSnapshot,
        stallDurationMs: stalledSample.stalledFor.inMilliseconds,
        budgetPhase: 'execution',
        activeTaskTitle: stalledSample.heartbeat.activeTaskTitle,
        toolResultCount: stalledSample.heartbeat.toolResultCount,
        fileWriteCount: stalledSample.heartbeat.fileWriteCount,
        phaseTimings: phaseTrace.toJson(),
        budgets: budgets.toJson(),
      );
      throw StateError(
        'Workflow execution stalled after '
        '${stalledSample.stalledFor.inSeconds}s. '
        'activeTask=${stalledSample.heartbeat.activeTaskTitle ?? 'none'} '
        'toolResults=${stalledSample.heartbeat.toolResultCount} '
        'fileWrites=${stalledSample.heartbeat.fileWriteCount} '
        'tasks=$workflowSnapshot '
        'lastTool=${diagnostics.lastToolName ?? 'none'} '
        'lastAssistant=${diagnostics.lastAssistantSummary ?? 'none'}',
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  final chatState = container.read(chatNotifierProvider);
  final conversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  final tasks = conversation?.projectedExecutionTasks ?? const [];
  final hasPendingApprovals =
      chatState.pendingSshConnect != null ||
      chatState.pendingSshCommand != null ||
      chatState.pendingGitCommand != null ||
      chatState.pendingLocalCommand != null ||
      chatState.pendingFileOperation != null ||
      chatState.pendingBleConnect != null ||
      chatState.pendingWorkflowDecision != null;
  if (!chatState.isLoading &&
      !hasPendingApprovals &&
      executionTasksContainOnlyCompleted(tasks)) {
    final workflowSnapshot = _summarizeWorkflowTasks(tasks);
    phaseTrace.firstTaskCompletedAt ??= DateTime.now();
    phaseTrace.lastTaskProgressAt ??= DateTime.now();
    heartbeatWriter.write(
      phase: 'completed',
      subphase: 'workflowCompletedRecoveredAtTimeout',
      phaseTrace: phaseTrace,
      budgets: budgets,
      activeTaskTitle: _activeWorkflowTaskTitle(tasks),
      workflowSnapshot: workflowSnapshot,
      toolResultCount: _countContentToolResults(logs),
      fileWriteCount: _countFileWriteExecutions(logs),
      messageCount: conversation?.messages.length ?? 0,
      hasPendingApprovals: false,
      isLoading: false,
    );
    if (useFramePump) {
      await _pumpUntilIdle(tester);
    }
    return;
  }
  final activeTaskTitle = _activeWorkflowTaskTitle(tasks);
  throw StateError(
    'Execution phase timed out after ${timeout.inSeconds}s. '
    'isLoading=${chatState.isLoading}, '
    'pendingApprovals=$hasPendingApprovals, '
    'activeTask=${activeTaskTitle ?? 'none'}, '
    'toolResults=${_countContentToolResults(logs)}, '
    'fileWrites=${_countFileWriteExecutions(logs)}, '
    'tasks=${_summarizeWorkflowTasks(tasks)}',
  );
}

String? _activeWorkflowTaskTitle(List<ConversationWorkflowTask> tasks) {
  for (final task in tasks) {
    if (task.status == ConversationWorkflowTaskStatus.inProgress) {
      return task.title;
    }
  }
  for (final task in tasks) {
    if (task.status == ConversationWorkflowTaskStatus.blocked) {
      return task.title;
    }
  }
  for (final task in tasks) {
    if (task.status == ConversationWorkflowTaskStatus.pending) {
      return task.title;
    }
  }
  return tasks.isEmpty ? null : tasks.last.title;
}

int _countContentToolResults(List<String> logs) {
  return logs
      .where(
        (line) => line.contains('[ContentTool] Appended result to message'),
      )
      .length;
}

int _countFileWriteExecutions(List<String> logs) {
  const writeToolPatterns = <String>[
    '[McpToolService] Executing tool: write_file',
    '[McpToolService] Executing tool: edit_file',
    '[McpToolService] Executing tool: create_file',
    '[McpToolService] Executing tool: update_file',
    '[McpToolService] Executing tool: delete_file',
    '[McpToolService] Executing tool: rollback_last_file_change',
  ];
  return logs
      .where(
        (line) => writeToolPatterns.any((pattern) => line.contains(pattern)),
      )
      .length;
}

int _countValidationLikeExecutions(List<String> logs) {
  const validationPatterns = <String>[
    '[McpToolService] Executing tool: run_tests',
    '[McpToolService] Executing tool: local_execute_command',
  ];
  return logs
      .where(
        (line) => validationPatterns.any((pattern) => line.contains(pattern)),
      )
      .length;
}

String _resolveExecutionSubphase(
  _PlanModePhaseTrace phaseTrace,
  String? activeTaskTitle,
) {
  if (phaseTrace.validationStartedAt != null) {
    return 'validation';
  }
  if (phaseTrace.nextTaskStartedAt != null) {
    return 'nextTask';
  }
  if (phaseTrace.firstTaskStartedAt != null) {
    return activeTaskTitle == null ? 'execution' : 'savedTask';
  }
  return 'execution';
}

String _summarizeWorkflowTasks(List<ConversationWorkflowTask> tasks) {
  if (tasks.isEmpty) {
    return 'none';
  }
  return tasks.map((task) => '${task.title}:${task.status.name}').join(', ');
}

bool _chatStateHasPendingApprovals(ChatState chatState) {
  return chatState.pendingSshConnect != null ||
      chatState.pendingSshCommand != null ||
      chatState.pendingGitCommand != null ||
      chatState.pendingLocalCommand != null ||
      chatState.pendingFileOperation != null ||
      chatState.pendingBleConnect != null ||
      chatState.pendingWorkflowDecision != null;
}

void _writePostScenarioHeartbeat({
  required ProviderContainer container,
  required List<String> logs,
  required _PlanModePhaseTrace phaseTrace,
  required _PlanModeTimeoutBudgets budgets,
  required _PlanModeLiveHeartbeatWriter heartbeatWriter,
  required String phase,
  required String subphase,
}) {
  final chatState = container.read(chatNotifierProvider);
  final conversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  final tasks = conversation?.projectedExecutionTasks ?? const [];
  heartbeatWriter.write(
    phase: phase,
    subphase: subphase,
    phaseTrace: phaseTrace,
    budgets: budgets,
    activeTaskTitle: _activeWorkflowTaskTitle(tasks),
    workflowSnapshot: _summarizeWorkflowTasks(tasks),
    toolResultCount: _countContentToolResults(logs),
    fileWriteCount: _countFileWriteExecutions(logs),
    messageCount: conversation?.messages.length ?? 0,
    hasPendingApprovals: _chatStateHasPendingApprovals(chatState),
    isLoading: chatState.isLoading,
  );
}

Future<void> _pumpUntilIdle(
  WidgetTester tester, {
  Duration step = const Duration(milliseconds: 100),
  int maxPumps = 50,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await _delayAndPumpFrame(tester, step);
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

Future<bool> _pumpUntilExecutionSettles(
  WidgetTester tester,
  ProviderContainer container, {
  Duration timeout = const Duration(seconds: 5),
  Duration step = const Duration(milliseconds: 100),
  Duration stableDuration = const Duration(seconds: 1),
  bool useFramePump = true,
}) async {
  final deadline = DateTime.now().add(timeout);
  DateTime? settledSince;
  while (DateTime.now().isBefore(deadline)) {
    if (useFramePump) {
      await _delayAndPumpFrame(tester, step);
    } else {
      await Future<void>.delayed(step);
    }
    final now = DateTime.now();
    final chatState = container.read(chatNotifierProvider);
    final hasPendingApprovals = _chatStateHasPendingApprovals(chatState);
    final isSettled = planModeExecutionIsSettled(
      isLoading: chatState.isLoading,
      hasPendingApprovals: hasPendingApprovals,
    );
    if (!isSettled) {
      settledSince = null;
      continue;
    }
    settledSince ??= now;
    if (now.difference(settledSince) >= stableDuration) {
      if (useFramePump) {
        await _pumpUntilIdle(tester);
      }
      final latestChatState = container.read(chatNotifierProvider);
      if (planModeExecutionIsSettled(
        isLoading: latestChatState.isLoading,
        hasPendingApprovals: _chatStateHasPendingApprovals(latestChatState),
      )) {
        return true;
      }
      settledSince = null;
    }
  }
  if (useFramePump) {
    await _pumpUntilIdle(tester);
  }
  return false;
}

Future<_PostScenarioSettleResult> _settlePostScenarioExecution(
  WidgetTester tester,
  ProviderContainer container, {
  required Duration timeout,
  required bool waitForExecutionCompletion,
  required List<String> logs,
  required _PlanModePhaseTrace phaseTrace,
  required _PlanModeTimeoutBudgets budgets,
  required _PlanModeLiveHeartbeatWriter heartbeatWriter,
  required bool useFramePump,
}) async {
  final initiallySettled = await _pumpUntilExecutionSettles(
    tester,
    container,
    timeout: timeout,
    useFramePump: useFramePump,
  );
  if (initiallySettled) {
    _writePostScenarioHeartbeat(
      container: container,
      logs: logs,
      phaseTrace: phaseTrace,
      budgets: budgets,
      heartbeatWriter: heartbeatWriter,
      phase: 'completed',
      subphase: 'postScenarioSettled',
    );
    return const _PostScenarioSettleResult(
      initiallySettled: true,
      settled: true,
      cancellationUsed: false,
    );
  }

  appLog('[Scenario] Background execution still active after settle timeout');
  _writePostScenarioHeartbeat(
    container: container,
    logs: logs,
    phaseTrace: phaseTrace,
    budgets: budgets,
    heartbeatWriter: heartbeatWriter,
    phase: 'execution',
    subphase: 'postScenarioStillActive',
  );
  if (!shouldCancelBackgroundExecutionAfterSettleTimeout(
    waitForExecutionCompletion: waitForExecutionCompletion,
    settled: initiallySettled,
  )) {
    return const _PostScenarioSettleResult(
      initiallySettled: false,
      settled: false,
      cancellationUsed: false,
    );
  }

  appLog('[Scenario] Cancelling background execution after settle timeout');
  container.read(chatNotifierProvider.notifier).cancelStreaming();
  final settledAfterCancel = await _pumpUntilExecutionSettles(
    tester,
    container,
    timeout: const Duration(seconds: 10),
    useFramePump: useFramePump,
  );
  _writePostScenarioHeartbeat(
    container: container,
    logs: logs,
    phaseTrace: phaseTrace,
    budgets: budgets,
    heartbeatWriter: heartbeatWriter,
    phase: settledAfterCancel ? 'completed' : 'execution',
    subphase: settledAfterCancel
        ? 'postScenarioCancelledAndSettled'
        : 'postScenarioCancelTimedOut',
  );
  return _PostScenarioSettleResult(
    initiallySettled: false,
    settled: settledAfterCancel,
    cancellationUsed: true,
  );
}

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await _delayAndPumpFrame(tester, step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsAtLeastNWidgets(1));
}

Future<void> _enterPromptAndSubmit(
  WidgetTester tester, {
  required String prompt,
}) async {
  final inputFieldFinder = find.descendant(
    of: find.byType(MessageInput),
    matching: find.byType(TextField),
  );
  final sendButtonFinder = find.descendant(
    of: find.byType(MessageInput),
    matching: find.byIcon(Icons.send),
  );

  await _waitForFinder(tester, find.byType(MessageInput));
  await _waitForFinder(tester, inputFieldFinder);
  await tester.tap(inputFieldFinder.first);
  await tester.enterText(inputFieldFinder.first, prompt);
  await _pumpUntilIdle(tester);
  await _waitForFinder(tester, sendButtonFinder);
  await tester.tap(sendButtonFinder.first);
  await tester.pump();
  await _pumpUntilIdle(tester);
}

Future<void> _submitScenarioPrompt(
  WidgetTester tester,
  ProviderContainer container, {
  required _PlanModeScenarioTestConfig config,
  required PlanModeScenarioSpec scenario,
}) async {
  if (config.usesLiveLlm) {
    unawaited(
      container
          .read(chatNotifierProvider.notifier)
          .sendMessage(scenario.userPrompt, languageCode: 'en'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return;
  }

  await _enterPromptAndSubmit(tester, prompt: scenario.userPrompt);
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
  bool useFramePump = true,
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
    if (useFramePump) {
      await _delayAndPumpFrame(tester, const Duration(milliseconds: 200));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}

void _assertLogExpectations(
  List<String> logs,
  List<PlanModeLogExpectation> expectations,
) {
  for (final expectation in expectations) {
    final count = countPlanModeLogsMatching(logs, expectation.pattern);

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

Future<void> _waitForLogExpectationLowerBounds(
  WidgetTester tester,
  List<String> logs,
  List<PlanModeLogExpectation> expectations, {
  Duration timeout = const Duration(seconds: 5),
  bool useFramePump = true,
}) async {
  if (planModeLogLowerBoundsSatisfied(logs, expectations)) {
    return;
  }

  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (useFramePump) {
      await _delayAndPumpFrame(tester, const Duration(milliseconds: 200));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (planModeLogLowerBoundsSatisfied(logs, expectations)) {
      return;
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
  required _PlanModePhaseTrace phaseTrace,
  required _PlanModeTimeoutBudgets budgets,
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
  final warningSummary = summarizeScenarioWarnings(
    warnings: warnings,
    allowedPatterns: scenario.allowedWarningPatterns,
    logs: logs,
  );
  final approvalPath = resolvePlanModeApprovalPathFromLogs(logs);

  final logFile = File('${scenarioDir.path}/scenario_log.txt');
  await logFile.writeAsString('${logs.join('\n')}\n');
  final lastHeartbeat = _readLiveHeartbeatSnapshot();
  final diagnostics = buildPlanModeFailureDiagnostics(
    logs: logs,
    errorText: error.toString(),
    phaseTimings: phaseTrace.toJson(),
    budgets: budgets.toJson(),
    activeTaskTitle: lastHeartbeat['activeTaskTitle'] as String?,
    toolResultCount: lastHeartbeat['toolResultCount'] as int?,
    fileWriteCount: lastHeartbeat['fileWriteCount'] as int?,
  );

  final report = <String, Object?>{
    'scenario': scenario.name,
    'status': 'failed',
    'failureClass': diagnostics.failureClass.name,
    'projectRoot': scenarioDir.path,
    'approvalPath': approvalPath,
    'fallbackPath': fallbackPathForApprovalPath(approvalPath),
    'usedHarnessApprovalFallback':
        approvalPath == planModeApprovalPathLiveHarnessFallback,
    'error': error.toString(),
    'stackTrace': stackTrace.toString(),
    'screenshots': screenshotPaths,
    'warnings': warnings,
    'allowedWarnings': warningSummary.allowedWarnings,
    'unexpectedWarnings': warningSummary.unexpectedWarnings,
    'warningSummary': warningSummary.toJson(),
    'phaseTimings': phaseTrace.toJson(),
    'budgets': budgets.toJson(),
    'lastHeartbeat': lastHeartbeat,
    'diagnostics': diagnostics.toJson(),
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

Future<_ScenarioRunResult> _runScenario({
  required WidgetTester tester,
  required IntegrationTestWidgetsFlutterBinding binding,
  required Box<String> conversationBox,
  required Box<String> memoryBox,
  required List<String> logs,
  required _PlanModeScenarioTestConfig config,
  required PlanModeScenarioSpec scenario,
  required Directory scenarioDir,
  required _PlanModePhaseTrace phaseTrace,
  required _PlanModeTimeoutBudgets budgets,
  required _PlanModePlanningReadyObserver planningReadyObserver,
}) async {
  final heartbeatWriter = _PlanModeLiveHeartbeatWriter(
    scenarioName: scenario.name,
    path: _resolveLiveHeartbeatPath(),
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
  await _pumpUntilIdle(tester);
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
      return _summarizeWorkflowTasks(
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
  await _pumpUntilIdle(tester);

  expect(find.text('Coding'), findsAtLeastNWidgets(1));

  await _submitScenarioPrompt(
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

  await _waitForReadyPlanProposal(
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
  final proposalUiReady = await _waitForReviewablePlanApprovalUi(
    tester,
    container,
    timeout: const Duration(seconds: 20),
    allowArtifactReadyFallback: config.usesLiveLlm,
  );
  final approvalFallbackDecision = resolvePlanModeApprovalFallbackDecision(
    proposalUiReady: proposalUiReady,
    usesLiveLlm: config.usesLiveLlm,
  );
  _HarnessExecutionHandle? harnessExecutionHandle;
  if (approvalFallbackDecision.shouldBypassUi) {
    appLog('[Workflow] Proposal approval UI bypassed by live harness');
    heartbeatWriter.write(
      phase: 'planning',
      subphase: 'proposalUiBypassedForLiveHarness',
      phaseTrace: phaseTrace,
      budgets: budgets,
    );
    harnessExecutionHandle = await _approvePlanAndStartFromHarness(
      container,
      phaseTrace: phaseTrace,
      heartbeatWriter: heartbeatWriter,
      budgets: budgets,
    );
  } else if (!proposalUiReady) {
    throw StateError(
      'Plan approval UI was not ready and live harness fallback is unavailable.',
    );
  } else {
    _assertUiExpectations(
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

    appLog('[Workflow] Proposal screenshot started');
    heartbeatWriter.write(
      phase: 'planning',
      subphase: 'proposalScreenshotStarted',
      phaseTrace: phaseTrace,
      budgets: budgets,
    );
    try {
      await captureIntegrationScreenshot(
        binding: binding,
        tester: tester,
        repaintBoundaryKey: screenshotBoundaryKey,
        name: 'plan_mode_${scenario.name}_proposal',
        outputDirectory: scenarioDir,
      );
      appLog('[Workflow] Proposal screenshot finished');
      heartbeatWriter.write(
        phase: 'planning',
        subphase: 'proposalScreenshotFinished',
        phaseTrace: phaseTrace,
        budgets: budgets,
      );
    } on TimeoutException {
      appLog('[Workflow] Proposal screenshot skipped after timeout');
      heartbeatWriter.write(
        phase: 'planning',
        subphase: 'proposalScreenshotSkipped',
        phaseTrace: phaseTrace,
        budgets: budgets,
      );
    } catch (error) {
      appLog('[Workflow] Proposal screenshot skipped after error: $error');
      heartbeatWriter.write(
        phase: 'planning',
        subphase: 'proposalScreenshotSkipped',
        phaseTrace: phaseTrace,
        budgets: budgets,
      );
    }

    final approveAction = _findPreferredPlanApproveAction();
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
    final approvalTransitionObserved = await _waitForPlanApprovalTransition(
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
    await _pumpUntilIdle(tester);
  }

  if (scenario.waitForExecutionCompletion) {
    await _waitForWorkflowExecutionCompletion(
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

  await _waitForArtifactExpectations(
    tester,
    scenarioDir,
    scenario.resolvedArtifactExpectations,
    timeout: config.usesLiveLlm
        ? const Duration(seconds: 30)
        : const Duration(seconds: 5),
    useFramePump: !config.usesLiveLlm,
  );
  if (!config.usesLiveLlm) {
    await _pumpUntilIdle(tester);
  }
  await _awaitHarnessExecutionCleanup(
    harnessExecutionHandle,
    scenario: scenario,
    timeout: _resolveHarnessCleanupTimeout(config, budgets),
  );
  await _waitForLogExpectationLowerBounds(
    tester,
    logs,
    scenario.logExpectations,
    timeout: config.usesLiveLlm
        ? const Duration(seconds: 60)
        : const Duration(seconds: 5),
    useFramePump: !config.usesLiveLlm,
  );
  final postScenarioSettle = await _settlePostScenarioExecution(
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
  if (workflowExpectation.stage != null) {
    expect(conversation.workflowStage, workflowExpectation.stage);
  }
  if (workflowExpectation.goal != null) {
    expect(savedWorkflow.goal, workflowExpectation.goal);
  }
  if (workflowExpectation.taskCount != null) {
    if (savedWorkflow.tasks.length != workflowExpectation.taskCount!) {
      final taskTitles = savedWorkflow.tasks
          .map((task) => task.title.trim())
          .where((title) => title.isNotEmpty)
          .join(' | ');
      throw StateError(
        'Saved workflow task count mismatch. '
        'expectedTaskCount=${workflowExpectation.taskCount} '
        'actualTaskCount=${savedWorkflow.tasks.length} '
        'tasks=$taskTitles',
      );
    }
  }
  if (workflowExpectation.minTaskCount != null) {
    if (savedWorkflow.tasks.length < workflowExpectation.minTaskCount!) {
      final taskTitles = savedWorkflow.tasks
          .map((task) => task.title.trim())
          .where((title) => title.isNotEmpty)
          .join(' | ');
      throw StateError(
        'Saved workflow task proposal was too short. '
        'expectedMinTaskCount=${workflowExpectation.minTaskCount} '
        'actualTaskCount=${savedWorkflow.tasks.length} '
        'tasks=$taskTitles',
      );
    }
  }
  if (workflowExpectation.firstTaskTitle != null) {
    expect(
      _normalizeSavedWorkflowTaskTitle(savedWorkflow.tasks.first.title),
      _normalizeSavedWorkflowTaskTitle(workflowExpectation.firstTaskTitle!),
    );
  }
  if (workflowExpectation.firstTaskTargetFilesContain.isNotEmpty) {
    final firstTaskTargetFiles = savedWorkflow.tasks.first.targetFiles
        .map(_normalizeSavedWorkflowTargetPath)
        .toSet();
    for (final expectedTarget
        in workflowExpectation.firstTaskTargetFilesContain) {
      final normalizedExpectedTarget = _normalizeSavedWorkflowTargetPath(
        expectedTarget,
      );
      if (!firstTaskTargetFiles.contains(normalizedExpectedTarget) &&
          config.usesLiveLlm &&
          _artifactExpectationFileExists(
            scenarioDir,
            scenario.resolvedArtifactExpectations,
            normalizedExpectedTarget,
          )) {
        continue;
      }
      expect(firstTaskTargetFiles, contains(normalizedExpectedTarget));
    }
  }
  for (final openQuestion in workflowExpectation.openQuestionsContain) {
    expect(savedWorkflow.openQuestions, contains(openQuestion));
  }

  if (config.usesLiveLlm) {
    appLog(
      '[Screenshot] Completed screenshot skipped for live scenario '
      '${scenario.name}',
    );
  } else {
    await captureIntegrationScreenshot(
      binding: binding,
      tester: tester,
      repaintBoundaryKey: screenshotBoundaryKey,
      name: 'plan_mode_${scenario.name}_completed',
      outputDirectory: scenarioDir,
    );
  }

  final report = <String, dynamic>{
    'scenario': scenario.name,
    'tags': scenario.tags,
    'status': 'passed',
    'failureClass': PlanModeFailureClass.passed.name,
    'executionMode': config.mode.name,
    'projectRoot': scenarioDir.path,
    'approvalPath': approvalPath,
    'fallbackPath': fallbackPathForApprovalPath(approvalPath),
    'usedHarnessApprovalFallback':
        approvalPath == planModeApprovalPathLiveHarnessFallback,
    'workflowStage': conversation.workflowStage.name,
    'workflowGoal': savedWorkflow.goal,
    'workflowOpenQuestions': savedWorkflow.openQuestions,
    'phaseTimings': phaseTrace.toJson(),
    'budgets': budgets.toJson(),
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
    'allowedWarnings': warningSummary.allowedWarnings,
    'unexpectedWarnings': warningSummary.unexpectedWarnings,
    'warningSummary': warningSummary.toJson(),
    'postScenarioSettled': postScenarioSettle.settled,
    'postScenarioInitiallySettled': postScenarioSettle.initiallySettled,
    'postScenarioCancellationUsed': postScenarioSettle.cancellationUsed,
    'postScenarioSettle': postScenarioSettle.toJson(),
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
  report['lastHeartbeat'] = _readLiveHeartbeatSnapshot();
  report['diagnostics'] = buildPlanModeFailureDiagnostics(
    logs: logs,
    lastWorkflowSnapshot: _summarizeWorkflowTasks(
      conversation.projectedExecutionTasks,
    ),
    budgetPhase: 'completed',
    activeTaskTitle: _activeWorkflowTaskTitle(
      conversation.projectedExecutionTasks,
    ),
    toolResultCount: _countContentToolResults(logs),
    fileWriteCount: _countFileWriteExecutions(logs),
    phaseTimings: phaseTrace.toJson(),
    budgets: budgets.toJson(),
  ).toJson();
  final screenshotPaths = _listScenarioScreenshotPaths(scenarioDir);
  report['screenshots'] = screenshotPaths;
  final logFile = File('${scenarioDir.path}/scenario_log.txt');
  await logFile.writeAsString('${logs.join('\n')}\n');
  final reportFile = File('${scenarioDir.path}/scenario_report.json');
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  appLog('[Scenario] Report written to ${reportFile.path}');
  if (postScenarioSettle.settled) {
    heartbeatWriter.write(
      phase: 'completed',
      subphase: postScenarioSettle.cancellationUsed
          ? 'scenarioCompletedAfterCleanupCancel'
          : 'scenarioCompleted',
      phaseTrace: phaseTrace,
      budgets: budgets,
      activeTaskTitle: _activeWorkflowTaskTitle(
        conversation.projectedExecutionTasks,
      ),
      workflowSnapshot: _summarizeWorkflowTasks(
        conversation.projectedExecutionTasks,
      ),
      toolResultCount: _countContentToolResults(logs),
      fileWriteCount: _countFileWriteExecutions(logs),
      messageCount: conversation.messages.length,
      hasPendingApprovals: false,
      isLoading: false,
    );
  }
  return _ScenarioRunResult(
    outputDirectoryPath: scenarioDir.path,
    reportPath: reportFile.path,
    screenshotPaths: screenshotPaths,
    logPath: logFile.path,
  );
}

Finder _findPreferredPlanApproveAction() {
  final approveLabel = find.text('Approve and start');
  final reviewSheet = find.byType(PlanReviewSheet);
  if (reviewSheet.evaluate().isNotEmpty) {
    final sheetApprove = find.descendant(
      of: reviewSheet,
      matching: approveLabel,
    );
    if (sheetApprove.evaluate().isNotEmpty) {
      return _findPlanApproveButtonForLabel(sheetApprove);
    }
  }
  return _findPlanApproveButtonForLabel(approveLabel);
}

Finder _findPlanApproveButtonForLabel(Finder approveLabel) {
  final button = find.ancestor(
    of: approveLabel,
    matching: find.byType(FilledButton),
  );
  if (button.evaluate().isNotEmpty) {
    return button.last;
  }
  return approveLabel.last;
}

Future<bool> _waitForPlanApprovalTransition(
  WidgetTester tester,
  ProviderContainer container, {
  required _PlanModePhaseTrace phaseTrace,
  required _PlanModeLiveHeartbeatWriter heartbeatWriter,
  required _PlanModeTimeoutBudgets budgets,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 12));
  var retryCount = 0;
  const maxApprovalTapRetries = 3;

  while (DateTime.now().isBefore(deadline)) {
    final now = DateTime.now();
    final conversation = container
        .read(conversationsNotifierProvider)
        .currentConversation;
    final chatState = container.read(chatNotifierProvider);
    if (planApprovalTransitionObserved(
      conversation: conversation,
      isLoading: chatState.isLoading,
    )) {
      return true;
    }

    if (shouldRecoverPlanApprovalFromExecutionDocument(
      conversation: conversation,
      isLoading: chatState.isLoading,
    )) {
      final refreshed = await container
          .read(conversationsNotifierProvider.notifier)
          .refreshCurrentWorkflowProjectionFromApprovedPlan();
      if (refreshed) {
        appLog(
          '[Workflow] Proposal approval recovered from execution document',
        );
        heartbeatWriter.write(
          phase: 'execution',
          subphase: 'approvedProjectionRecovered',
          phaseTrace: phaseTrace,
          budgets: budgets,
          workflowSnapshot: _summarizeWorkflowTasks(
            container
                    .read(conversationsNotifierProvider)
                    .currentConversation
                    ?.projectedExecutionTasks ??
                const [],
          ),
        );
        return true;
      }
    }

    if (shouldWaitForPlanApprovalToSettle(
      approvalTappedAt: phaseTrace.approvalTappedAt,
      now: now,
    )) {
      heartbeatWriter.write(
        phase: 'execution',
        subphase: 'proposalTapSettling',
        phaseTrace: phaseTrace,
        budgets: budgets,
      );
      await _delayAndPumpFrame(tester, const Duration(milliseconds: 200));
      continue;
    }

    final approveAction = _findPreferredPlanApproveAction();
    final approvalVisible = approveAction.evaluate().isNotEmpty;
    if (retryCount < maxApprovalTapRetries &&
        shouldRetryPlanApprovalTap(
          conversation: conversation,
          isLoading: chatState.isLoading,
          approvalVisible: approvalVisible,
        )) {
      retryCount += 1;
      appLog('[Workflow] Proposal approval tap retry started');
      heartbeatWriter.write(
        phase: 'planning',
        subphase: 'proposalTapRetryStarted',
        phaseTrace: phaseTrace,
        budgets: budgets,
      );
      await tester.ensureVisible(approveAction);
      await tester.tap(approveAction, warnIfMissed: false);
      phaseTrace.approvalTappedAt = DateTime.now();
      await _delayAndPumpFrame(tester, const Duration(milliseconds: 250));
      await _delayAndPumpFrame(tester, const Duration(milliseconds: 250));
      appLog('[Workflow] Proposal approval tap retry finished');
      heartbeatWriter.write(
        phase: 'execution',
        subphase: 'proposalTapRetryFinished',
        phaseTrace: phaseTrace,
        budgets: budgets,
      );
      continue;
    }

    await _delayAndPumpFrame(tester, const Duration(milliseconds: 200));
  }
  return false;
}

String _normalizeSavedWorkflowTaskTitle(String value) {
  return value
      .replaceAll('`', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[.!?]+$'), '')
      .trim()
      .toLowerCase();
}

String _normalizeSavedWorkflowTargetPath(String value) {
  return value.replaceAll('\\', '/').trim().toLowerCase();
}

bool _artifactExpectationFileExists(
  Directory scenarioDir,
  List<PlanModeArtifactExpectation> expectations,
  String normalizedTargetPath,
) {
  return expectations.any((expectation) {
    if (!expectation.shouldExist) {
      return false;
    }
    final normalizedExpectationPath = _normalizeSavedWorkflowTargetPath(
      expectation.path,
    );
    return normalizedExpectationPath == normalizedTargetPath &&
        File('${scenarioDir.path}/${expectation.path}').existsSync();
  });
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final config = _resolveScenarioTestConfig();
  final scenarios = config.scenarios;

  group(config.suiteName, () {
    late Box<String> conversationBox;
    late Box<String> memoryBox;
    late DebugPrintCallback originalDebugPrint;
    late _PlanModePlanningReadyObserver planningReadyObserver;
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
        '[ScenarioSuite] Running ${config.suiteName} on ${config.deviceName} '
        'in ${config.mode.name} mode',
      );
    });

    setUp(() async {
      await Hive.initFlutter();
      await EasyLocalization.ensureInitialized();

      logs = <String>[];
      planningReadyObserver = _PlanModePlanningReadyObserver(logs: logs);
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          logs.add(message);
          planningReadyObserver.observe(message);
        }
        originalDebugPrint(message, wrapWidth: wrapWidth);
      };

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      conversationBox = await Hive.openBox<String>('plan_mode_conv_$timestamp');
      memoryBox = await Hive.openBox<String>('plan_mode_mem_$timestamp');
    });

    tearDown(() async {
      debugPrint = originalDebugPrint;
      planningReadyObserver.clear();
      await conversationBox.close();
      await memoryBox.close();
    });

    tearDownAll(() async {
      final reportDirectory = Directory(
        '${Directory.current.path}/build/integration_test_reports',
      );
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
      final suiteReport = buildPlanModeSuiteJsonReport(
        config: suiteReportConfig,
        suiteResults: suiteResults,
      );
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
      final suiteMarkdown = buildPlanModeSuiteMarkdownReport(
        config: suiteReportConfig,
        suiteResults: suiteResults,
      );
      final suiteJUnit = buildPlanModeSuiteJUnitReport(
        config: suiteReportConfig,
        suiteResults: suiteResults,
      );
      final suiteRunMarkdownFile = File(
        '${suiteRunDirectory.path}/${config.reportPrefix}_report.md',
      );
      await suiteRunMarkdownFile.writeAsString(suiteMarkdown);
      final suiteRunJUnitFile = File(
        '${suiteRunDirectory.path}/${config.reportPrefix}_report.xml',
      );
      await suiteRunJUnitFile.writeAsString(suiteJUnit);
      final suiteMarkdownFile = File(
        '${reportDirectory.path}/${config.reportPrefix}_report.md',
      );
      await suiteMarkdownFile.writeAsString(suiteMarkdown);
      final suiteJUnitFile = File(
        '${reportDirectory.path}/${config.reportPrefix}_report.xml',
      );
      await suiteJUnitFile.writeAsString(suiteJUnit);
      appLog('[ScenarioSuite] Report written to ${suiteReportFile.path}');
    });

    for (final scenario in scenarios) {
      testWidgets('runs ${scenario.name}', (tester) async {
        final startedAt = DateTime.now();
        final scenarioDir = await Directory.systemTemp.createTemp(
          'caverno_plan_mode_${scenario.name}_',
        );
        final phaseTrace = _PlanModePhaseTrace();
        final budgets = _PlanModeTimeoutBudgets(
          planningTimeout: _resolvePlanningProposalTimeout(scenario),
          executionTimeout: _resolveExecutionCompletionTimeout(scenario),
          executionStallTimeout: _resolveExecutionStallTimeout(scenario),
          overallTimeout: _resolveOverallRunTimeout(scenario),
        );
        _ScenarioRunResult? runResult;
        Object? failure;
        StackTrace? failureStackTrace;
        try {
          final scenarioRun = _runScenario(
            tester: tester,
            binding: binding,
            conversationBox: conversationBox,
            memoryBox: memoryBox,
            logs: logs,
            config: config,
            scenario: scenario,
            scenarioDir: scenarioDir,
            phaseTrace: phaseTrace,
            budgets: budgets,
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
          if (failure != null && failureStackTrace != null) {
            await _writeFailureScenarioArtifacts(
              scenario: scenario,
              scenarioDir: scenarioDir,
              logs: logs,
              error: failure,
              stackTrace: failureStackTrace,
              phaseTrace: phaseTrace,
              budgets: budgets,
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
          List<dynamic> archivedAllowedWarnings = const <dynamic>[];
          List<dynamic> archivedUnexpectedWarnings = const <dynamic>[];
          Map<String, dynamic> archivedReport = const <String, dynamic>{};
          Map<String, dynamic> archivedDiagnostics = const <String, dynamic>{};
          Map<String, dynamic> archivedHeartbeat = const <String, dynamic>{};
          bool? archivedPostScenarioSettled;
          bool? archivedPostScenarioCancellationUsed;
          String archivedApprovalPath = planModeApprovalPathUnknown;
          String archivedFallbackPath = planModeFallbackPathNone;
          if (archivedReportPath.existsSync()) {
            archivedReport =
                jsonDecode(archivedReportPath.readAsStringSync())
                    as Map<String, dynamic>;
            archivedDiagnostics =
                archivedReport['diagnostics'] as Map<String, dynamic>? ??
                const <String, dynamic>{};
            archivedHeartbeat =
                archivedReport['lastHeartbeat'] as Map<String, dynamic>? ??
                const <String, dynamic>{};
            archivedWarnings =
                archivedReport['warnings'] as List<dynamic>? ??
                const <dynamic>[];
            archivedAllowedWarnings =
                archivedReport['allowedWarnings'] as List<dynamic>? ??
                const <dynamic>[];
            archivedUnexpectedWarnings =
                archivedReport['unexpectedWarnings'] as List<dynamic>? ??
                const <dynamic>[];
            archivedPostScenarioSettled =
                archivedReport['postScenarioSettled'] as bool?;
            archivedPostScenarioCancellationUsed =
                archivedReport['postScenarioCancellationUsed'] as bool?;
            archivedApprovalPath =
                archivedReport['approvalPath'] as String? ??
                planModeApprovalPathUnknown;
            archivedFallbackPath =
                archivedReport['fallbackPath'] as String? ??
                fallbackPathForApprovalPath(archivedApprovalPath);
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
            'failureClass': archivedReportPath.existsSync()
                ? archivedReport['failureClass'] as String? ??
                      (failure == null ? 'passed' : 'unclassified')
                : (failure == null ? 'passed' : 'unclassified'),
            'budgetPhase': archivedReportPath.existsSync()
                ? archivedDiagnostics['budgetPhase'] as String?
                : null,
            'lastKnownPhase': archivedHeartbeat['phase'] as String?,
            'activeTaskTitle': archivedHeartbeat['activeTaskTitle'] as String?,
            'lastUpdatedAt': archivedHeartbeat['updatedAt'] as String?,
            'lastHeartbeat': archivedHeartbeat,
            'phaseTimings': archivedReport['phaseTimings'],
            'budgets': archivedReport['budgets'],
            'postScenarioSettled': archivedPostScenarioSettled,
            'postScenarioCancellationUsed':
                archivedPostScenarioCancellationUsed,
            'approvalPath': archivedApprovalPath,
            'fallbackPath': archivedFallbackPath,
            'usedHarnessApprovalFallback':
                archivedApprovalPath == planModeApprovalPathLiveHarnessFallback,
            'warnings': archivedWarnings,
            'allowedWarnings': archivedAllowedWarnings,
            'unexpectedWarnings': archivedUnexpectedWarnings,
            'error': failure?.toString(),
            'stackTrace': failureStackTrace?.toString(),
          });
        }
      });
    }
  });
}
