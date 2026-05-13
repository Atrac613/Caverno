import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/utils/logger.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';

import 'plan_mode_approval_progress.dart';
import 'plan_mode_execution_progress.dart';
import 'plan_mode_heartbeat.dart';

class PlanModePostScenarioSettleResult {
  const PlanModePostScenarioSettleResult({
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

bool chatStateHasPlanModePendingApprovals(ChatState chatState) {
  return chatState.pendingSshConnect != null ||
      chatState.pendingSshCommand != null ||
      chatState.pendingGitCommand != null ||
      chatState.pendingLocalCommand != null ||
      chatState.pendingFileOperation != null ||
      chatState.pendingBleConnect != null ||
      chatState.pendingWorkflowDecision != null;
}

void writePlanModePostScenarioHeartbeat({
  required ProviderContainer container,
  required List<String> logs,
  required PlanModePhaseTrace phaseTrace,
  required PlanModeTimeoutBudgets budgets,
  required PlanModeLiveHeartbeatWriter heartbeatWriter,
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
    activeTaskTitle: activePlanModeWorkflowTaskTitle(tasks),
    workflowSnapshot: summarizePlanModeWorkflowTasks(tasks),
    toolResultCount: countPlanModeContentToolResults(logs),
    fileWriteCount: countPlanModeFileWriteExecutions(logs),
    messageCount: conversation?.messages.length ?? 0,
    hasPendingApprovals: chatStateHasPlanModePendingApprovals(chatState),
    isLoading: chatState.isLoading,
  );
}

Future<void> pumpPlanModeUntilIdle(
  WidgetTester tester, {
  Duration step = const Duration(milliseconds: 100),
  int maxPumps = 50,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await Future<void>.delayed(step);
    await tester.pump();
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

Future<bool> pumpPlanModeUntilExecutionSettles(
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
      await Future<void>.delayed(step);
      await tester.pump();
    } else {
      await Future<void>.delayed(step);
    }
    final now = DateTime.now();
    final chatState = container.read(chatNotifierProvider);
    final hasPendingApprovals = chatStateHasPlanModePendingApprovals(chatState);
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
        await pumpPlanModeUntilIdle(tester);
      }
      final latestChatState = container.read(chatNotifierProvider);
      if (planModeExecutionIsSettled(
        isLoading: latestChatState.isLoading,
        hasPendingApprovals: chatStateHasPlanModePendingApprovals(
          latestChatState,
        ),
      )) {
        return true;
      }
      settledSince = null;
    }
  }
  if (useFramePump) {
    await pumpPlanModeUntilIdle(tester);
  }
  return false;
}

Future<PlanModePostScenarioSettleResult> settlePlanModePostScenarioExecution(
  WidgetTester tester,
  ProviderContainer container, {
  required Duration timeout,
  required bool waitForExecutionCompletion,
  required List<String> logs,
  required PlanModePhaseTrace phaseTrace,
  required PlanModeTimeoutBudgets budgets,
  required PlanModeLiveHeartbeatWriter heartbeatWriter,
  required bool useFramePump,
}) async {
  final initiallySettled = await pumpPlanModeUntilExecutionSettles(
    tester,
    container,
    timeout: timeout,
    useFramePump: useFramePump,
  );
  if (initiallySettled) {
    writePlanModePostScenarioHeartbeat(
      container: container,
      logs: logs,
      phaseTrace: phaseTrace,
      budgets: budgets,
      heartbeatWriter: heartbeatWriter,
      phase: 'completed',
      subphase: 'postScenarioSettled',
    );
    return const PlanModePostScenarioSettleResult(
      initiallySettled: true,
      settled: true,
      cancellationUsed: false,
    );
  }

  appLog('[Scenario] Background execution still active after settle timeout');
  writePlanModePostScenarioHeartbeat(
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
    return const PlanModePostScenarioSettleResult(
      initiallySettled: false,
      settled: false,
      cancellationUsed: false,
    );
  }

  appLog('[Scenario] Cancelling background execution after settle timeout');
  container.read(chatNotifierProvider.notifier).cancelStreaming();
  final settledAfterCancel = await pumpPlanModeUntilExecutionSettles(
    tester,
    container,
    timeout: const Duration(seconds: 10),
    useFramePump: useFramePump,
  );
  writePlanModePostScenarioHeartbeat(
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
  return PlanModePostScenarioSettleResult(
    initiallySettled: false,
    settled: settledAfterCancel,
    cancellationUsed: true,
  );
}
