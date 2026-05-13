import 'dart:io';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_saved_workflow_assertions.dart';
import '../../integration_test/test_support/plan_mode_scenario_spec.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_saved_workflow_assertions_test_',
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('accepts normalized first task titles and target files', () {
    final savedWorkflow = _workflowSpec(
      tasks: const <ConversationWorkflowTask>[
        ConversationWorkflowTask(
          id: 'task-1',
          title: '`Create README.md`.',
          targetFiles: <String>['Docs\\README.md'],
        ),
      ],
      openQuestions: const <String>['Which host should be checked first?'],
    );

    assertPlanModeSavedWorkflowExpectation(
      conversation: _conversation(),
      savedWorkflow: savedWorkflow,
      expectation: const PlanModeSavedWorkflowExpectation(
        stage: ConversationWorkflowStage.implement,
        goal: 'Build a host health checker.',
        taskCount: 1,
        firstTaskTitle: 'Create README.md',
        firstTaskTargetFilesContain: <String>['docs/readme.md'],
        openQuestionsContain: <String>['Which host should be checked first?'],
      ),
      scenarioDir: tempDir,
      artifactExpectations: const <PlanModeArtifactExpectation>[],
      allowArtifactExpectationFallback: false,
    );
  });

  test('allows live artifact fallback for first task target mismatches', () {
    File('${tempDir.path}/README.md').writeAsStringSync('# Project\n');
    final savedWorkflow = _workflowSpec(
      tasks: const <ConversationWorkflowTask>[
        ConversationWorkflowTask(
          id: 'task-1',
          title: 'Create project documentation',
          targetFiles: <String>['docs/README.md'],
        ),
      ],
    );

    assertPlanModeSavedWorkflowExpectation(
      conversation: _conversation(),
      savedWorkflow: savedWorkflow,
      expectation: const PlanModeSavedWorkflowExpectation(
        firstTaskTargetFilesContain: <String>['README.md'],
      ),
      scenarioDir: tempDir,
      artifactExpectations: const <PlanModeArtifactExpectation>[
        PlanModeArtifactExpectation(path: 'README.md'),
      ],
      allowArtifactExpectationFallback: true,
    );
  });

  test('reports saved workflow task count mismatches with task titles', () {
    final savedWorkflow = _workflowSpec(
      tasks: const <ConversationWorkflowTask>[
        ConversationWorkflowTask(id: 'task-1', title: 'Create README'),
      ],
    );

    expect(
      () => assertPlanModeSavedWorkflowExpectation(
        conversation: _conversation(),
        savedWorkflow: savedWorkflow,
        expectation: const PlanModeSavedWorkflowExpectation(taskCount: 2),
        scenarioDir: tempDir,
        artifactExpectations: const <PlanModeArtifactExpectation>[],
        allowArtifactExpectationFallback: false,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('tasks=Create README'),
        ),
      ),
    );
  });
}

Conversation _conversation() {
  return Conversation(
    id: 'conversation-1',
    title: 'Plan Mode',
    messages: const <Message>[],
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    workflowStage: ConversationWorkflowStage.implement,
  );
}

ConversationWorkflowSpec _workflowSpec({
  List<ConversationWorkflowTask> tasks = const <ConversationWorkflowTask>[],
  List<String> openQuestions = const <String>[],
}) {
  return ConversationWorkflowSpec(
    goal: 'Build a host health checker.',
    openQuestions: openQuestions,
    tasks: tasks,
  );
}
