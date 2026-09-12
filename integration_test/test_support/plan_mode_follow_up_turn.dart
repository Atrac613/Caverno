import 'dart:async';

import 'package:caverno/core/utils/logger.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/task_delegation_brief_builder.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plan_mode_post_scenario_settle.dart';
import 'plan_mode_scenario_spec.dart';

/// What a scenario's follow-up turn did, for the scenario report.
class PlanModeFollowUpTurnResult {
  const PlanModeFollowUpTurnResult({
    required this.requested,
    required this.executionCancelled,
    required this.settled,
    required this.readyTasksOffered,
  });

  const PlanModeFollowUpTurnResult.skipped()
    : requested = false,
      executionCancelled = false,
      settled = false,
      readyTasksOffered = 0;

  final bool requested;
  final bool executionCancelled;
  final bool settled;

  /// How many tasks the delegation queue offered when the turn was sent.
  ///
  /// Recorded because zero explains a parent that did not delegate without
  /// implicating the model: it was shown nothing to choose from.
  final int readyTasksOffered;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requested': requested,
      'executionCancelled': executionCancelled,
      'settled': settled,
      'readyTasksOffered': readyTasksOffered,
    };
  }
}

/// Sends [PlanModeScenarioSpec.followUpPrompt] into the conversation the
/// scenario just planned, once the plan is saved.
///
/// Kept apart from the first submission because the two ask different
/// questions of the same conversation: the first produces a plan, and this one
/// observes what the saved plan makes available. A scenario without a
/// follow-up prompt is unaffected.
Future<PlanModeFollowUpTurnResult> runPlanModeFollowUpTurn({
  required WidgetTester tester,
  required ProviderContainer container,
  required PlanModeScenarioSpec scenario,
}) async {
  final prompt = scenario.followUpPrompt;
  if (prompt == null || prompt.isEmpty) {
    return const PlanModeFollowUpTurnResult.skipped();
  }

  final notifier = container.read(chatNotifierProvider.notifier);
  var cancelled = false;
  if (scenario.cancelExecutionBeforeFollowUp) {
    appLog('[Scenario] Cancelling execution before the follow-up turn');
    notifier.cancelStreaming();
    cancelled = await _waitUntilNotLoading(
      tester: tester,
      container: container,
      timeout: const Duration(seconds: 30),
    );
    appLog('[Scenario] Execution cancellation settled=$cancelled');
  }

  if (scenario.resolveOpenQuestionsBeforeFollowUp) {
    final answered = await _resolveOpenQuestions(container);
    appLog('[Scenario] Answered $answered open question(s) before the turn');
    await pumpPlanModeUntilIdle(tester);
  }

  // Read the queue the parent will be shown, rather than assuming the plan
  // left one behind. Anything else can be satisfied while the parent still
  // sees nothing, which is the failure this check exists to make loud: an
  // empty queue is a real state, and a follow-up sent into one measures the
  // scenario's setup instead of the parent.
  final queued = await _waitForNonEmptyDelegationQueue(
    tester: tester,
    container: container,
    timeout: const Duration(seconds: 30),
  );
  appLog('[Scenario] Delegation queue offers $queued ready task(s)');

  appLog('[Scenario] Sending follow-up turn');
  unawaited(notifier.sendMessage(prompt, languageCode: scenario.languageCode));
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await pumpPlanModeUntilIdle(tester);
  final settled = await _waitUntilNotLoading(
    tester: tester,
    container: container,
    timeout: scenario.followUpSettleTimeout,
  );
  appLog('[Scenario] Follow-up turn settled=$settled');

  return PlanModeFollowUpTurnResult(
    requested: true,
    executionCancelled: cancelled,
    settled: settled,
    readyTasksOffered: queued,
  );
}

/// Whether the chat loop stopped before [timeout].
///
/// Returned rather than thrown: an unsettled follow-up still leaves its
/// request in the session log, which is what the log expectations read, so the
/// scenario's own assertions stay the thing that decides pass or fail.
Future<bool> _waitUntilNotLoading({
  required WidgetTester tester,
  required ProviderContainer container,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  // One settled read is not enough: the loop clears isLoading between a tool
  // batch and the request that follows it.
  var consecutiveIdleReads = 0;
  while (DateTime.now().isBefore(deadline)) {
    await pumpPlanModeUntilIdle(tester);
    if (container.read(chatNotifierProvider).isLoading) {
      consecutiveIdleReads = 0;
      continue;
    }
    consecutiveIdleReads++;
    if (consecutiveIdleReads >= 3) {
      return true;
    }
  }
  return false;
}

/// Polls the real delegation queue until it offers something, and reports how
/// many it ended on.
///
/// Deliberately reads `TaskDelegationBriefBuilder` rather than task statuses:
/// the queue is what the parent is shown, so a scenario that waits on anything
/// else can be satisfied while the parent still sees nothing.
Future<int> _waitForNonEmptyDelegationQueue({
  required WidgetTester tester,
  required ProviderContainer container,
  required Duration timeout,
}) async {
  const builder = TaskDelegationBriefBuilder();
  final deadline = DateTime.now().add(timeout);
  var observed = 0;
  while (DateTime.now().isBefore(deadline)) {
    await pumpPlanModeUntilIdle(tester);
    final conversation = container
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (conversation == null) {
      continue;
    }
    observed = builder.candidates(conversation).length;
    if (observed > 0) {
      return observed;
    }
  }
  return observed;
}

/// Answers every unresolved open question on the current plan.
///
/// Stands in for the user, and only for the user: this records an answer where
/// the design says a human has to, and changes nothing about how the parent
/// then reads the queue.
Future<int> _resolveOpenQuestions(ProviderContainer container) async {
  final conversationsNotifier = container.read(
    conversationsNotifierProvider.notifier,
  );
  final conversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  if (conversation == null) {
    return 0;
  }
  final pending = conversation.unresolvedOpenQuestionProgress
      .map((entry) => entry.question)
      .where((question) => question.trim().isNotEmpty)
      .toList(growable: false);
  for (final question in pending) {
    await conversationsNotifier.updateCurrentOpenQuestionProgress(
      question: question,
      status: ConversationOpenQuestionStatus.resolved,
      note: 'Answered by the live test harness so the plan can be worked.',
    );
  }
  return pending.length;
}
