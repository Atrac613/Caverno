import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/utils/logger.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';

import 'plan_mode_execution_progress.dart';
import 'plan_mode_execution_watchdog.dart';
import 'plan_mode_heartbeat.dart';
import 'plan_mode_live_diagnostics.dart';
import 'plan_mode_post_scenario_settle.dart';

Future<void> waitForPlanModeWorkflowExecutionCompletion(
  WidgetTester tester,
  ProviderContainer container, {
  required Duration timeout,
  required Duration stallTimeout,
  required List<String> logs,
  required PlanModePhaseTrace phaseTrace,
  required PlanModeTimeoutBudgets budgets,
  required PlanModeLiveHeartbeatWriter heartbeatWriter,
  required bool useFramePump,
}) async {
  final deadline = DateTime.now().add(timeout);
  final watchdog = PlanModeExecutionWatchdog(stallTimeout: stallTimeout);
  final blockedTimeout = resolvePlanModeBlockedWorkflowTimeout(stallTimeout);
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
    final hasPendingApprovals = chatStateHasPlanModePendingApprovals(chatState);

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
        final refreshedActiveTaskTitle = activePlanModeWorkflowTaskTitle(
          refreshedTasks,
        );
        final refreshedWorkflowSnapshot = summarizePlanModeWorkflowTasks(
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
          toolResultCount: countPlanModeContentToolResults(logs),
          fileWriteCount: countPlanModeFileWriteExecutions(logs),
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
      phaseTrace.firstTaskTitle ??= activePlanModeWorkflowTaskTitle(tasks);
    }
    if (tasks.any(
      (task) => task.status == ConversationWorkflowTaskStatus.completed,
    )) {
      phaseTrace.firstTaskCompletedAt ??= now;
    }
    final activeTaskTitle = activePlanModeWorkflowTaskTitle(tasks);
    final workflowSnapshot = summarizePlanModeWorkflowTasks(tasks);
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
        toolResultCount: countPlanModeContentToolResults(logs),
        fileWriteCount: countPlanModeFileWriteExecutions(logs),
        messageCount: conversation?.messages.length ?? 0,
        hasPendingApprovals: false,
        isLoading: false,
      );
      await pumpPlanModeUntilExecutionSettles(
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
    if (countPlanModeValidationLikeExecutions(logs) > 0) {
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
        toolResultCount: countPlanModeContentToolResults(logs),
        fileWriteCount: countPlanModeFileWriteExecutions(logs),
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
        final workflowSnapshot = summarizePlanModeWorkflowTasks(tasks);
        final diagnostics = buildPlanModeFailureDiagnostics(
          logs: logs,
          errorText:
              'Workflow execution remained blocked. tasks=$workflowSnapshot',
          lastWorkflowSnapshot: workflowSnapshot,
          budgetPhase: 'execution',
          activeTaskTitle: activePlanModeWorkflowTaskTitle(tasks),
          toolResultCount: countPlanModeContentToolResults(logs),
          fileWriteCount: countPlanModeFileWriteExecutions(logs),
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
          '${summarizePlanModeWorkflowTasks(tasks)}',
        );
      }
      if (useFramePump) {
        await pumpPlanModeUntilIdle(tester);
      }
      return;
    }

    final heartbeat = PlanModeExecutionHeartbeat(
      activeTaskTitle: activeTaskTitle,
      workflowSnapshot: workflowSnapshot,
      toolResultCount: countPlanModeContentToolResults(logs),
      fileWriteCount: countPlanModeFileWriteExecutions(logs),
      hasPendingApprovals: hasPendingApprovals,
      isLoading: chatState.isLoading,
    );
    if (lastHeartbeatKey != heartbeat.progressKey) {
      lastHeartbeatKey = heartbeat.progressKey;
      phaseTrace.lastTaskProgressAt = now;
    }
    heartbeatWriter.write(
      phase: 'execution',
      subphase: resolvePlanModeExecutionSubphase(phaseTrace, activeTaskTitle),
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
  final hasPendingApprovals = chatStateHasPlanModePendingApprovals(chatState);
  if (!chatState.isLoading &&
      !hasPendingApprovals &&
      executionTasksContainOnlyCompleted(tasks)) {
    final workflowSnapshot = summarizePlanModeWorkflowTasks(tasks);
    phaseTrace.firstTaskCompletedAt ??= DateTime.now();
    phaseTrace.lastTaskProgressAt ??= DateTime.now();
    heartbeatWriter.write(
      phase: 'completed',
      subphase: 'workflowCompletedRecoveredAtTimeout',
      phaseTrace: phaseTrace,
      budgets: budgets,
      activeTaskTitle: activePlanModeWorkflowTaskTitle(tasks),
      workflowSnapshot: workflowSnapshot,
      toolResultCount: countPlanModeContentToolResults(logs),
      fileWriteCount: countPlanModeFileWriteExecutions(logs),
      messageCount: conversation?.messages.length ?? 0,
      hasPendingApprovals: false,
      isLoading: false,
    );
    if (useFramePump) {
      await pumpPlanModeUntilIdle(tester);
    }
    return;
  }
  final activeTaskTitle = activePlanModeWorkflowTaskTitle(tasks);
  throw StateError(
    'Execution phase timed out after ${timeout.inSeconds}s. '
    'isLoading=${chatState.isLoading}, '
    'pendingApprovals=$hasPendingApprovals, '
    'activeTask=${activeTaskTitle ?? 'none'}, '
    'toolResults=${countPlanModeContentToolResults(logs)}, '
    'fileWrites=${countPlanModeFileWriteExecutions(logs)}, '
    'tasks=${summarizePlanModeWorkflowTasks(tasks)}',
  );
}

Duration resolvePlanModeBlockedWorkflowTimeout(Duration stallTimeout) {
  const maximumBlockedTimeout = Duration(seconds: 15);
  return stallTimeout < maximumBlockedTimeout
      ? stallTimeout
      : maximumBlockedTimeout;
}
