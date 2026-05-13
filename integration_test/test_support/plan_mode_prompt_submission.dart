import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/widgets/message_input.dart';

import 'plan_mode_post_scenario_settle.dart';
import 'plan_mode_scenario_config.dart';
import 'plan_mode_scenario_spec.dart';

Future<void> submitPlanModeScenarioPrompt(
  WidgetTester tester,
  ProviderContainer container, {
  required PlanModeScenarioTestConfig config,
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

  await enterPlanModePromptAndSubmit(tester, prompt: scenario.userPrompt);
}

Future<void> enterPlanModePromptAndSubmit(
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

  await waitForPlanModeFinder(tester, find.byType(MessageInput));
  await waitForPlanModeFinder(tester, inputFieldFinder);
  await tester.tap(inputFieldFinder.first);
  await tester.enterText(inputFieldFinder.first, prompt);
  await pumpPlanModeUntilIdle(tester);
  await waitForPlanModeFinder(tester, sendButtonFinder);
  await tester.tap(sendButtonFinder.first);
  await tester.pump();
  await pumpPlanModeUntilIdle(tester);
}

Future<void> waitForPlanModeFinder(
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

Future<void> _delayAndPumpFrame(WidgetTester tester, Duration delay) async {
  await Future<void>.delayed(delay);
  await tester.pump();
}
