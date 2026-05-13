import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:caverno/core/utils/logger.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';

import 'plan_mode_approval_progress.dart';
import 'plan_mode_expectations.dart';
import 'plan_mode_post_scenario_settle.dart';
import 'plan_mode_scenario_config.dart';
import 'plan_mode_scenario_spec.dart';
import 'plan_mode_screenshot_policy.dart';

Future<void> resolvePlanModePlanningDecisions(
  WidgetTester tester,
  ProviderContainer container,
  IntegrationTestWidgetsFlutterBinding binding,
  PlanModeScenarioTestConfig config,
  PlanModeScenarioSpec scenario,
  GlobalKey screenshotBoundaryKey,
  Directory outputDirectory,
) async {
  var scriptedDecisionIndex = 0;
  var resolvedDecisionCount = 0;
  const maxDecisionRounds = 8;

  while (resolvedDecisionCount < maxDecisionRounds) {
    if (config.usesLiveLlm) {
      final resolved = await resolvePlanModeLivePlanningDecision(
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

    await pumpPlanModeUntilIdle(tester);
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
      final confirmBecameVisible = await waitForPlanModePlanningDecisionConfirm(
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

    assertPlanModeUiExpectations(
      tester,
      scenario.uiExpectations,
      PlanModeUiPhase.decision,
    );
    final scriptedSelection =
        scriptedDecisionIndex < scenario.decisionSelections.length
        ? scenario.decisionSelections[scriptedDecisionIndex]
        : null;
    final questionText =
        scriptedSelection?.question ??
        extractVisiblePlanModeDecisionQuestion(tester);

    if (scriptedSelection != null &&
        scriptedSelection.question.trim().isNotEmpty) {
      expect(find.text(scriptedSelection.question), findsOneWidget);
    } else if (!config.usesLiveLlm) {
      throw StateError(
        'Encountered an unexpected planning decision in fake mode.',
      );
    }

    await capturePlanModeScenarioScreenshot(
      usesLiveLlm: config.usesLiveLlm,
      binding: binding,
      tester: tester,
      repaintBoundaryKey: screenshotBoundaryKey,
      scenarioName: scenario.name,
      phase: PlanModeScreenshotPhase.decision,
      outputDirectory: outputDirectory,
      decisionIndex: resolvedDecisionCount + 1,
      timeout: const Duration(seconds: 10),
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
      await pumpPlanModeUntilIdle(tester);
    } else if (scriptedSelection?.optionLabel != null) {
      final optionFinder = findPlanModeDecisionSheetText(
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
      await pumpPlanModeUntilIdle(tester);
    } else if (config.usesLiveLlm) {
      appLog(
        '[ScenarioLive] Auto-accepted the default planning option'
        '${questionText != null ? ' for "$questionText"' : ''}.',
      );
    }

    expect(confirmFinder, findsOneWidget);
    await tester.tap(confirmFinder, warnIfMissed: false);
    await tester.pump();
    await pumpPlanModeUntilIdle(tester);
    if (scriptedSelection != null) {
      scriptedDecisionIndex += 1;
    }
    resolvedDecisionCount += 1;
  }

  throw StateError(
    'Planning decisions did not settle after $maxDecisionRounds rounds.',
  );
}

Future<bool> resolvePlanModeLivePlanningDecision(
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
  final answer = buildPlanModeLivePlanningDecisionAnswer(
    decision,
    scriptedSelection,
  );
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

WorkflowPlanningDecisionAnswer buildPlanModeLivePlanningDecisionAnswer(
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
      ? _firstOrNull(decision.options)
      : _firstOrNull(
              decision.options.where(
                (option) =>
                    normalizePlanModeDecisionOptionLabel(option.label) ==
                    normalizePlanModeDecisionOptionLabel(targetOptionLabel),
              ),
            ) ??
            _firstOrNull(decision.options);

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

Future<bool> waitForPlanModePlanningDecisionConfirm(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    await _delayAndPumpFrame(tester, const Duration(milliseconds: 100));
    await pumpPlanModeUntilIdle(tester);
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

Finder findPlanModeDecisionSheetText(
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

String? extractVisiblePlanModeDecisionQuestion(WidgetTester tester) {
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
  return _firstOrNull(candidates);
}

Future<void> _delayAndPumpFrame(WidgetTester tester, Duration delay) async {
  await Future<void>.delayed(delay);
  await tester.pump();
}

T? _firstOrNull<T>(Iterable<T> items) {
  for (final item in items) {
    return item;
  }
  return null;
}
