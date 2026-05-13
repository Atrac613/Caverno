import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:caverno/core/utils/logger.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';

import 'plan_mode_approval_ui.dart';
import 'plan_mode_execution_progress.dart';
import 'plan_mode_heartbeat.dart';
import 'plan_mode_planning_decisions.dart';
import 'plan_mode_planning_progress.dart';
import 'plan_mode_scenario_config.dart';
import 'plan_mode_scenario_spec.dart';

Future<void> waitForReadyPlanModeProposal(
  WidgetTester tester,
  ProviderContainer container, {
  required Duration timeout,
  required PlanModePhaseTrace phaseTrace,
  required PlanModeLiveHeartbeatWriter heartbeatWriter,
  required PlanModeTimeoutBudgets budgets,
  required IntegrationTestWidgetsFlutterBinding binding,
  required PlanModeScenarioTestConfig config,
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
    return planModeReviewablePlanApprovalUiReady(container);
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
    final workflowSnapshot = summarizePlanModeWorkflowTasks(
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
    final planningProgressKey = buildPlanModePlanningProgressKey(
      messageCount: conversation?.messages.length ?? 0,
      workflowDraftAvailable:
          chatState.workflowProposalDraft != null ||
          planningLogsContainWorkflowDraftReady(logs),
      taskDraftAvailable:
          chatState.taskProposalDraft != null ||
          planningLogsContainTaskDraftReady(logs),
      workflowDraftPersisted: planningLogsContainWorkflowDraftPersisted(logs),
      taskDraftPersisted: planningLogsContainTaskDraftPersisted(logs),
      isGeneratingWorkflowProposal: chatState.isGeneratingWorkflowProposal,
      isGeneratingTaskProposal: chatState.isGeneratingTaskProposal,
      hasPendingDecision: chatState.pendingWorkflowDecision != null,
      workflowError: chatState.workflowProposalError,
      taskError: chatState.taskProposalError,
      workflowDraftReadyLogSeen: planningLogsContainWorkflowDraftReady(logs),
      taskDraftReadyLogSeen: planningLogsContainTaskDraftReady(logs),
      approvalUiReady: approvalUiReady,
    );
    if (planningProgressKey != lastPlanningProgressKey) {
      lastPlanningProgressKey = planningProgressKey;
      deadline = DateTime.now().add(timeout);
    }
    heartbeatWriter.write(
      phase: 'planning',
      subphase: resolvePlanningSubphase(
        hasPendingDecision: chatState.pendingWorkflowDecision != null,
        hasWorkflowDraft: chatState.workflowProposalDraft != null,
        hasTaskDraft: chatState.taskProposalDraft != null,
        approvalUiVisible: approvalUiReady,
        isGeneratingWorkflowProposal: chatState.isGeneratingWorkflowProposal,
        isGeneratingTaskProposal: chatState.isGeneratingTaskProposal,
        logs: logs,
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
      await resolvePlanModePlanningDecisions(
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
        workflowSnapshot: summarizePlanModeWorkflowTasks(
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
      workflowSnapshot: summarizePlanModeWorkflowTasks(
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

String buildPlanModePlanningProgressKey({
  required int messageCount,
  required bool workflowDraftAvailable,
  required bool taskDraftAvailable,
  required bool workflowDraftPersisted,
  required bool taskDraftPersisted,
  required bool isGeneratingWorkflowProposal,
  required bool isGeneratingTaskProposal,
  required bool hasPendingDecision,
  required String? workflowError,
  required String? taskError,
  required bool workflowDraftReadyLogSeen,
  required bool taskDraftReadyLogSeen,
  required bool approvalUiReady,
}) {
  return '$messageCount|'
      '$workflowDraftAvailable|'
      '$taskDraftAvailable|'
      '$workflowDraftPersisted|'
      '$taskDraftPersisted|'
      '$isGeneratingWorkflowProposal|'
      '$isGeneratingTaskProposal|'
      '$hasPendingDecision|'
      '$workflowError|'
      '$taskError|'
      '$workflowDraftReadyLogSeen|'
      '$taskDraftReadyLogSeen|'
      '$approvalUiReady';
}
