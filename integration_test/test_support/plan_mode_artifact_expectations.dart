import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'plan_mode_scenario_spec.dart';

void assertPlanModeArtifactExpectations(
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

Future<void> waitForPlanModeArtifactExpectations(
  Directory scenarioDir,
  List<PlanModeArtifactExpectation> expectations, {
  Duration timeout = const Duration(seconds: 20),
  Duration pollInterval = const Duration(milliseconds: 200),
  WidgetTester? tester,
  bool useFramePump = true,
}) async {
  final requiredFiles = expectations
      .where((item) => item.shouldExist)
      .map((item) => File('${scenarioDir.path}/${item.path}'))
      .toList(growable: false);
  if (requiredFiles.isEmpty) {
    return;
  }
  if (useFramePump && tester == null) {
    throw StateError('A WidgetTester is required when useFramePump is true.');
  }

  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final allPresent = requiredFiles.every((file) => file.existsSync());
    if (allPresent) {
      return;
    }
    if (useFramePump) {
      await tester!.pump(pollInterval);
    } else {
      await Future<void>.delayed(pollInterval);
    }
  }
}
