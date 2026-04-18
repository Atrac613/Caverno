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
}
