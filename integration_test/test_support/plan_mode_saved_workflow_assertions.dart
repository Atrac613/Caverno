import 'dart:io';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plan_mode_scenario_spec.dart';

void assertPlanModeSavedWorkflowExpectation({
  required Conversation conversation,
  required ConversationWorkflowSpec savedWorkflow,
  required PlanModeSavedWorkflowExpectation expectation,
  required Directory scenarioDir,
  required List<PlanModeArtifactExpectation> artifactExpectations,
  required bool allowArtifactExpectationFallback,
}) {
  if (expectation.stage != null) {
    expect(conversation.workflowStage, expectation.stage);
  }
  if (expectation.goal != null) {
    expect(savedWorkflow.goal, expectation.goal);
  }
  if (expectation.taskCount != null &&
      savedWorkflow.tasks.length != expectation.taskCount!) {
    throw StateError(
      'Saved workflow task count mismatch. '
      'expectedTaskCount=${expectation.taskCount} '
      'actualTaskCount=${savedWorkflow.tasks.length} '
      'tasks=${_savedWorkflowTaskTitles(savedWorkflow)}',
    );
  }
  if (expectation.minTaskCount != null &&
      savedWorkflow.tasks.length < expectation.minTaskCount!) {
    throw StateError(
      'Saved workflow task proposal was too short. '
      'expectedMinTaskCount=${expectation.minTaskCount} '
      'actualTaskCount=${savedWorkflow.tasks.length} '
      'tasks=${_savedWorkflowTaskTitles(savedWorkflow)}',
    );
  }
  if (expectation.firstTaskTitle != null) {
    expect(
      _normalizeSavedWorkflowTaskTitle(savedWorkflow.tasks.first.title),
      _normalizeSavedWorkflowTaskTitle(expectation.firstTaskTitle!),
    );
  }
  if (expectation.firstTaskTargetFilesContain.isNotEmpty) {
    final firstTaskTargetFiles = savedWorkflow.tasks.first.targetFiles
        .map(_normalizeSavedWorkflowTargetPath)
        .toSet();
    for (final expectedTarget in expectation.firstTaskTargetFilesContain) {
      final normalizedExpectedTarget = _normalizeSavedWorkflowTargetPath(
        expectedTarget,
      );
      if (!firstTaskTargetFiles.contains(normalizedExpectedTarget) &&
          allowArtifactExpectationFallback &&
          _artifactExpectationFileExists(
            scenarioDir,
            artifactExpectations,
            normalizedExpectedTarget,
          )) {
        continue;
      }
      expect(firstTaskTargetFiles, contains(normalizedExpectedTarget));
    }
  }
  for (final openQuestion in expectation.openQuestionsContain) {
    expect(savedWorkflow.openQuestions, contains(openQuestion));
  }
}

String _savedWorkflowTaskTitles(ConversationWorkflowSpec savedWorkflow) {
  return savedWorkflow.tasks
      .map((task) => task.title.trim())
      .where((title) => title.isNotEmpty)
      .join(' | ');
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
