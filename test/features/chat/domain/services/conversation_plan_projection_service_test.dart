import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_document_builder.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_projection_service.dart';

void main() {
  test('derives workflow projection from a structured plan document', () {
    final markdown = ConversationPlanDocumentBuilder.build(
      workflowStage: ConversationWorkflowStage.implement,
      workflowSpec: const ConversationWorkflowSpec(
        goal: 'Ship projection refresh',
        constraints: ['Keep markdown as the source of truth'],
        acceptanceCriteria: ['Tasks can be derived from the approved plan'],
        openQuestions: ['Should stale tasks show a badge?'],
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Parse the approved markdown',
            status: ConversationWorkflowTaskStatus.inProgress,
            targetFiles: ['lib/features/chat/domain/services'],
            validationCommand: 'flutter test',
            notes: 'Use a deterministic parser',
          ),
        ],
      ),
    );

    final projection =
        ConversationPlanProjectionService.deriveExecutionProjection(
          approvedMarkdown: markdown,
        );

    expect(projection.workflowStage, ConversationWorkflowStage.implement);
    expect(projection.workflowSpec.goal, 'Ship projection refresh');
    expect(projection.workflowSpec.constraints, [
      'Keep markdown as the source of truth',
    ]);
    expect(projection.workflowSpec.acceptanceCriteria, [
      'Tasks can be derived from the approved plan',
    ]);
    expect(projection.workflowSpec.openQuestions, [
      'Should stale tasks show a badge?',
    ]);
    expect(projection.workflowSpec.tasks, hasLength(1));
    expect(projection.workflowSpec.tasks.single.id, 'task-1');
    expect(
      projection.workflowSpec.tasks.single.status,
      ConversationWorkflowTaskStatus.inProgress,
    );
    expect(
      projection.workflowSpec.tasks.single.validationCommand,
      'flutter test',
    );
    expect(projection.sourceHash, isNotEmpty);
    expect(projection.anchoredTaskIndexes, {0});
  });

  test('replaces the stage section without discarding the edited markdown', () {
    const markdown =
        '# Plan\n'
        '\n'
        '## Stage\n'
        'plan\n'
        '\n'
        '## Goal\n'
        'Keep the edited notes\n'
        '\n'
        '## Tasks\n'
        '\n'
        '1. Refresh the projection\n'
        '   - Status: pending\n'
        '   - Notes: Preserve manual edits\n';

    final updated = ConversationPlanProjectionService.replaceWorkflowStage(
      markdown: markdown,
      workflowStage: ConversationWorkflowStage.implement,
    );

    expect(updated, contains('## Stage\nimplement'));
    expect(updated, contains('Keep the edited notes'));
    expect(updated, contains('Preserve manual edits'));
  });

  test('reuses task ids when the approved plan wording changes slightly', () {
    const previousTasks = [
      ConversationWorkflowTask(
        id: 'derived-task-1-stable',
        title: 'Ship the execution handoff',
        validationCommand: 'flutter test',
        targetFiles: ['lib/features/chat/presentation/pages/chat_page.dart'],
      ),
    ];

    const nextWorkflowSpec = ConversationWorkflowSpec(
      tasks: [
        ConversationWorkflowTask(
          id: 'derived-task-1-new',
          title: 'Ship the execution handoff flow',
          validationCommand: 'flutter test',
          targetFiles: ['lib/features/chat/presentation/pages/chat_page.dart'],
        ),
      ],
    );

    final stabilized = ConversationPlanProjectionService.stabilizeTaskIds(
      previousTasks: previousTasks,
      workflowSpec: nextWorkflowSpec,
    );

    expect(stabilized.tasks.single.id, 'derived-task-1-stable');
  });

  test('preserves explicit task anchors during stabilization', () {
    const previousTasks = [
      ConversationWorkflowTask(
        id: 'derived-task-1-stable',
        title: 'Ship the execution handoff',
      ),
    ];

    const nextWorkflowSpec = ConversationWorkflowSpec(
      tasks: [
        ConversationWorkflowTask(
          id: 'task-anchor-ship-handoff',
          title: 'Ship the execution handoff with review polish',
        ),
      ],
    );

    final stabilized = ConversationPlanProjectionService.stabilizeTaskIds(
      previousTasks: previousTasks,
      workflowSpec: nextWorkflowSpec,
      anchoredTaskIndexes: {0},
    );

    expect(stabilized.tasks.single.id, 'task-anchor-ship-handoff');
  });

  test('validateDocument reports a missing Stage section', () {
    const markdown =
        '# Plan\n'
        '\n'
        '## Goal\n'
        'Ship the next task\n';

    final validation = ConversationPlanProjectionService.validateDocument(
      markdown: markdown,
    );

    expect(validation.isValid, isFalse);
    expect(
      validation.errorMessage,
      'plan document must include a Stage section',
    );
  });

  test('validateDocument requires tasks when requested', () {
    const markdown =
        '# Plan\n'
        '\n'
        '## Stage\n'
        'implement\n'
        '\n'
        '## Goal\n'
        'Ship the next task\n';

    final validation = ConversationPlanProjectionService.validateDocument(
      markdown: markdown,
      requireTasks: true,
    );

    expect(validation.isValid, isFalse);
    expect(
      validation.errorMessage,
      'plan document must include a Tasks section',
    );
  });

  test('validateDocument surfaces malformed task details', () {
    const markdown =
        '# Plan\n'
        '\n'
        '## Stage\n'
        'implement\n'
        '\n'
        '## Tasks\n'
        '\n'
        '- Status: pending\n';

    final validation = ConversationPlanProjectionService.validateDocument(
      markdown: markdown,
      requireTasks: true,
    );

    expect(validation.isValid, isFalse);
    expect(
      validation.errorMessage,
      'task details must follow a numbered task heading',
    );
    expect(validation.issues, [
      'task details must follow a numbered task heading',
    ]);
  });

  test('validateDocument exposes preview tasks for valid markdown', () {
    const markdown =
        '# Plan\n'
        '\n'
        '## Stage\n'
        'implement\n'
        '\n'
        '## Tasks\n'
        '\n'
        '1. Refresh the saved plan projection\n'
        '   - Status: pending\n';

    final validation = ConversationPlanProjectionService.validateDocument(
      markdown: markdown,
      requireTasks: true,
    );

    expect(validation.isValid, isTrue);
    expect(validation.workflowStage, ConversationWorkflowStage.implement);
    expect(validation.previewTasks, hasLength(1));
    expect(
      validation.previewTasks.single.title,
      'Refresh the saved plan projection',
    );
  });

  test('validateDocument rejects duplicate explicit task ids', () {
    const markdown =
        '# Plan\n'
        '\n'
        '## Stage\n'
        'implement\n'
        '\n'
        '## Tasks\n'
        '\n'
        '1. Refresh the saved plan projection\n'
        '   - Task ID: task-anchor-refresh\n'
        '   - Status: pending\n'
        '\n'
        '2. Rebuild the execution preview\n'
        '   - Task ID: task-anchor-refresh\n'
        '   - Status: pending\n';

    final validation = ConversationPlanProjectionService.validateDocument(
      markdown: markdown,
      requireTasks: true,
    );

    expect(validation.isValid, isFalse);
    expect(
      validation.errorMessage,
      'plan document contains a duplicate Task ID "task-anchor-refresh"',
    );
    expect(validation.issues, [
      'plan document contains a duplicate Task ID "task-anchor-refresh"',
    ]);
  });

  test('builder emits task anchors into the markdown plan document', () {
    final markdown = ConversationPlanDocumentBuilder.build(
      workflowStage: ConversationWorkflowStage.tasks,
      workflowSpec: const ConversationWorkflowSpec(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-anchor-1',
            title: 'Keep task ids stable across replans',
          ),
        ],
      ),
    );

    expect(markdown, contains('- Task ID: task-anchor-1'));
  });
}
