import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/utils/logger.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/widgets/plan/plan_review_sheet.dart';

import 'plan_mode_approval_progress.dart';
import 'plan_mode_execution_progress.dart';
import 'plan_mode_heartbeat.dart';
import 'plan_mode_live_harness_fallback.dart';

bool planModeReviewablePlanApprovalUiReady(ProviderContainer container) {
  final reviewSheet = find.byType(PlanReviewSheet);
  if (reviewSheet.evaluate().isEmpty) {
    return false;
  }
  final approveAction = findPreferredPlanModeApproveAction();
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

bool planModeReviewablePlanArtifactReady(ProviderContainer container) {
  final conversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  return planReviewArtifactHasPreviewTasks(conversation: conversation);
}

Future<bool> waitForPlanModeReviewablePlanApprovalUi(
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
    if (planModeReviewablePlanApprovalUiReady(container)) {
      return true;
    }
    if (allowArtifactReadyFallback &&
        planModeReviewablePlanArtifactReady(container)) {
      return false;
    }
  }
  if (allowArtifactReadyFallback &&
      planModeReviewablePlanArtifactReady(container)) {
    return false;
  }
  final timeoutAction = resolvePlanModeApprovalUiWaitTimeoutAction(
    allowArtifactReadyFallback: allowArtifactReadyFallback,
    artifactReady: planModeReviewablePlanArtifactReady(container),
  );
  switch (timeoutAction) {
    case PlanModeApprovalUiWaitTimeoutAction.useArtifactReadyFallback:
    case PlanModeApprovalUiWaitTimeoutAction.useLiveHarnessValidationFallback:
      return false;
    case PlanModeApprovalUiWaitTimeoutAction.failUiExpectation:
      break;
  }
  expect(planModeReviewablePlanApprovalUiReady(container), isTrue);
  return true;
}

Finder findPreferredPlanModeApproveAction() {
  final approveLabel = find.textContaining(
    RegExp('^(?:Approve and start|\u627F\u8A8D\u3057\u3066\u958B\u59CB)\$'),
  );
  final reviewSheet = find.byType(PlanReviewSheet);
  if (reviewSheet.evaluate().isNotEmpty) {
    final sheetApprove = find.descendant(
      of: reviewSheet,
      matching: approveLabel,
    );
    if (sheetApprove.evaluate().isNotEmpty) {
      return findPlanModeApproveButtonForLabel(sheetApprove);
    }
  }
  return findPlanModeApproveButtonForLabel(approveLabel);
}

Finder findPlanModeApproveButtonForLabel(Finder approveLabel) {
  final button = find.ancestor(
    of: approveLabel,
    matching: find.byType(FilledButton),
  );
  if (button.evaluate().isNotEmpty) {
    return button.last;
  }
  return approveLabel.last;
}

Future<bool> waitForPlanModeApprovalTransition(
  WidgetTester tester,
  ProviderContainer container, {
  required PlanModePhaseTrace phaseTrace,
  required PlanModeLiveHeartbeatWriter heartbeatWriter,
  required PlanModeTimeoutBudgets budgets,
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
          workflowSnapshot: summarizePlanModeWorkflowTasks(
            container
                    .read(conversationsNotifierProvider)
                    .currentConversation
                    ?.projectedExecutionTasks ??
                const <ConversationWorkflowTask>[],
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

    final approveAction = findPreferredPlanModeApproveAction();
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

Future<void> _delayAndPumpFrame(WidgetTester tester, Duration delay) async {
  await Future<void>.delayed(delay);
  await tester.pump();
}
