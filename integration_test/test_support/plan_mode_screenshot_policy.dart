import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:caverno/core/utils/logger.dart';

import 'screenshot_capture.dart';

enum PlanModeScreenshotPhase { decision, proposal, completed }

enum PlanModeScreenshotFailureMode { skip, fail }

enum PlanModeScreenshotOutcome {
  captured,
  skippedForLive,
  skippedAfterTimeout,
  skippedAfterError,
}

class PlanModeScenarioScreenshotResult {
  const PlanModeScenarioScreenshotResult({
    required this.name,
    required this.phase,
    required this.outcome,
  });

  final String name;
  final PlanModeScreenshotPhase phase;
  final PlanModeScreenshotOutcome outcome;

  bool get captured => outcome == PlanModeScreenshotOutcome.captured;
}

bool shouldCapturePlanModeScenarioScreenshot({required bool usesLiveLlm}) {
  return !usesLiveLlm;
}

String planModeScenarioScreenshotName({
  required String scenarioName,
  required PlanModeScreenshotPhase phase,
  int? decisionIndex,
}) {
  final prefix = 'plan_mode_$scenarioName';
  return switch (phase) {
    PlanModeScreenshotPhase.decision =>
      decisionIndex == null
          ? throw StateError('Decision screenshots require a decision index.')
          : '${prefix}_decision_$decisionIndex',
    PlanModeScreenshotPhase.proposal => '${prefix}_proposal',
    PlanModeScreenshotPhase.completed => '${prefix}_completed',
  };
}

String planModeScreenshotSkippedForLiveLog({
  required PlanModeScreenshotPhase phase,
  required String scenarioName,
}) {
  return '[Screenshot] ${_phaseLabel(phase)} screenshot skipped for live scenario '
      '$scenarioName';
}

List<String> listPlanModeScenarioScreenshotPaths(Directory scenarioDir) {
  final screenshots = scenarioDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.png'))
      .map((file) => file.path)
      .toList(growable: false);
  screenshots.sort();
  return screenshots;
}

Future<PlanModeScenarioScreenshotResult> capturePlanModeScenarioScreenshot({
  required bool usesLiveLlm,
  required IntegrationTestWidgetsFlutterBinding binding,
  required WidgetTester tester,
  required GlobalKey repaintBoundaryKey,
  required String scenarioName,
  required PlanModeScreenshotPhase phase,
  required Directory outputDirectory,
  int? decisionIndex,
  Duration? timeout,
  PlanModeScreenshotFailureMode failureMode =
      PlanModeScreenshotFailureMode.skip,
  void Function(String message) log = appLog,
}) async {
  final name = planModeScenarioScreenshotName(
    scenarioName: scenarioName,
    phase: phase,
    decisionIndex: decisionIndex,
  );
  if (!shouldCapturePlanModeScenarioScreenshot(usesLiveLlm: usesLiveLlm)) {
    log(
      planModeScreenshotSkippedForLiveLog(
        phase: phase,
        scenarioName: scenarioName,
      ),
    );
    return PlanModeScenarioScreenshotResult(
      name: name,
      phase: phase,
      outcome: PlanModeScreenshotOutcome.skippedForLive,
    );
  }

  log('[Workflow] ${_phaseLabel(phase)} screenshot started');
  try {
    final capture = captureIntegrationScreenshot(
      binding: binding,
      tester: tester,
      repaintBoundaryKey: repaintBoundaryKey,
      name: name,
      outputDirectory: outputDirectory,
    );
    if (timeout == null) {
      await capture;
    } else {
      await capture.timeout(timeout);
    }
    log('[Workflow] ${_phaseLabel(phase)} screenshot finished');
    return PlanModeScenarioScreenshotResult(
      name: name,
      phase: phase,
      outcome: PlanModeScreenshotOutcome.captured,
    );
  } on TimeoutException {
    if (failureMode == PlanModeScreenshotFailureMode.fail) {
      rethrow;
    }
    log('[Workflow] ${_phaseLabel(phase)} screenshot skipped after timeout');
    return PlanModeScenarioScreenshotResult(
      name: name,
      phase: phase,
      outcome: PlanModeScreenshotOutcome.skippedAfterTimeout,
    );
  } catch (error) {
    if (failureMode == PlanModeScreenshotFailureMode.fail) {
      rethrow;
    }
    log(
      '[Workflow] ${_phaseLabel(phase)} screenshot skipped after error: $error',
    );
    return PlanModeScenarioScreenshotResult(
      name: name,
      phase: phase,
      outcome: PlanModeScreenshotOutcome.skippedAfterError,
    );
  }
}

String _phaseLabel(PlanModeScreenshotPhase phase) {
  return switch (phase) {
    PlanModeScreenshotPhase.decision => 'Decision',
    PlanModeScreenshotPhase.proposal => 'Proposal',
    PlanModeScreenshotPhase.completed => 'Completed',
  };
}
