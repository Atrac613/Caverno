import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_document_builder.dart';

void main() {
  test('recordRevision prepends new revisions and keeps history bounded', () {
    final artifact = const ConversationPlanArtifact(
      draftMarkdown: '# Plan\n\n## Goal\nCurrent draft',
    )
        .recordRevision(
          markdown: '# Plan\n\n## Goal\nCurrent draft',
          kind: ConversationPlanRevisionKind.draft,
          label: 'Saved draft',
          createdAt: DateTime(2026, 4, 18, 12, 0),
        )
        .recordRevision(
          markdown: '# Plan\n\n## Goal\nApproved draft',
          kind: ConversationPlanRevisionKind.approved,
          label: 'Approved draft',
          createdAt: DateTime(2026, 4, 18, 12, 5),
        );

    expect(artifact.historyEntries, hasLength(2));
    expect(artifact.historyEntries.first.kind, ConversationPlanRevisionKind.approved);
    expect(artifact.historyEntries.first.normalizedLabel, 'Approved draft');
  });

  test('buildApprovedArtifact seeds revision history', () {
    final artifact = ConversationPlanDocumentBuilder.buildApprovedArtifact(
      workflowStage: ConversationWorkflowStage.implement,
      workflowSpec: const ConversationWorkflowSpec(
        goal: 'Keep revision history in the plan artifact',
      ),
      updatedAt: DateTime(2026, 4, 18, 12, 30),
    );

    expect(artifact.normalizedApprovedMarkdown, isNotNull);
    expect(artifact.historyEntries, isNotEmpty);
    expect(
      artifact.historyEntries.first.kind,
      ConversationPlanRevisionKind.approved,
    );
  });

  test(
    'buildApprovedSnapshotMarkdown rebuilds the plan when the draft has no tasks',
    () {
      const workflowSpec = ConversationWorkflowSpec(
        goal: 'Keep approved snapshots aligned with saved tasks',
      );
      const tasks = [
        ConversationWorkflowTask(
          id: 'task-1',
          title: 'Implement the main CLI entrypoint',
          targetFiles: ['main.py'],
          validationCommand: 'python3 main.py --help',
        ),
      ];

      final markdown = ConversationPlanDocumentBuilder.buildApprovedSnapshotMarkdown(
        currentArtifact: const ConversationPlanArtifact(
          draftMarkdown:
              '# Plan\n'
              '\n'
              '## Stage\n'
              'plan\n'
              '\n'
              '## Goal\n'
              'Keep approved snapshots aligned with saved tasks\n',
        ),
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: workflowSpec,
        tasks: tasks,
      );

      expect(markdown, contains('## Tasks'));
      expect(markdown, contains('Implement the main CLI entrypoint'));
      expect(markdown, contains('Task ID: task-1'));
      expect(markdown, contains('## Stage\nimplement'));
    },
  );

  test(
    'buildApprovedSnapshotMarkdown rebuilds the plan from approved tasks when the draft has stale tasks',
    () {
      const workflowSpec = ConversationWorkflowSpec(
        goal: 'Keep approved snapshots aligned with approved task proposals',
      );
      const tasks = [
        ConversationWorkflowTask(
          id: 'task-1',
          title: 'Implement the ping CLI tool in main.py',
          targetFiles: ['main.py'],
          validationCommand: 'python3 main.py --help',
        ),
        ConversationWorkflowTask(
          id: 'task-2',
          title: 'Verify the CLI tool with a single ping request',
          targetFiles: ['main.py'],
          validationCommand: 'python3 main.py 127.0.0.1 -c 1',
        ),
      ];

      final markdown = ConversationPlanDocumentBuilder.buildApprovedSnapshotMarkdown(
        currentArtifact: const ConversationPlanArtifact(
          draftMarkdown:
              '# Plan\n'
              '\n'
              '## Stage\n'
              'tasks\n'
              '\n'
              '## Goal\n'
              'Keep approved snapshots aligned with approved task proposals\n'
              '\n'
              '## Tasks\n'
              '\n'
              '1. Initialize project structure\n'
              '   - Task ID: stale-1\n'
              '   - Status: completed\n'
              '\n'
              '2. Validate the CLI tool with a single ping\n'
              '   - Task ID: stale-2\n'
              '   - Status: inProgress\n',
        ),
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: workflowSpec,
        tasks: tasks,
      );

      expect(markdown, contains('Implement the ping CLI tool in main.py'));
      expect(markdown, contains('Verify the CLI tool with a single ping request'));
      expect(markdown, isNot(contains('Initialize project structure')));
      expect(markdown, isNot(contains('Validate the CLI tool with a single ping')));
      expect(markdown, contains('## Stage\nimplement'));
    },
  );
}
