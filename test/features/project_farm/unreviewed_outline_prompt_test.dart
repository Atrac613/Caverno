import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/plan/conversation_plan_document_builder.dart';
import 'package:caverno/features/chat/domain/services/system_prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const spec = ConversationWorkflowSpec(
    goal: 'Implement task',
    tasks: [
      ConversationWorkflowTask(id: 'project-subtask-1', title: 'Add parser'),
    ],
  );

  String promptFor(ConversationPlanArtifact artifact) =>
      SystemPromptBuilder.build(
        now: DateTime(2026, 10, 1),
        assistantMode: AssistantMode.coding,
        languageCode: 'en',
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: spec,
        planArtifact: artifact,
      );

  test('a generated project task outline is not presented as approved', () {
    final outline = ConversationPlanDocumentBuilder.buildApprovedArtifact(
      workflowStage: ConversationWorkflowStage.implement,
      workflowSpec: spec,
      label: ConversationPlanArtifact.unreviewedOutlineLabel,
    );

    expect(outline.isUnreviewedOutline, isTrue);
    final prompt = promptFor(outline);
    expect(prompt, contains('Generated task outline for this coding thread'));
    expect(prompt, isNot(contains('Approved plan document for this coding')));
  });

  test('a later approved plan replaces the unreviewed label', () {
    final outline = ConversationPlanDocumentBuilder.buildApprovedArtifact(
      workflowStage: ConversationWorkflowStage.implement,
      workflowSpec: spec,
      label: ConversationPlanArtifact.unreviewedOutlineLabel,
    );
    final approved = outline.recordRevision(
      markdown: '# Plan\n\nReviewed',
      kind: ConversationPlanRevisionKind.approved,
      label: 'Approved plan from timeline review',
    );

    expect(approved.isUnreviewedOutline, isFalse);
    expect(
      promptFor(approved),
      contains('Approved plan document for this coding thread'),
    );
  });

  test('the generic backfill keeps its approved label', () {
    final backfilled = ConversationPlanDocumentBuilder.buildApprovedArtifact(
      workflowStage: ConversationWorkflowStage.implement,
      workflowSpec: spec,
    );
    expect(backfilled.isUnreviewedOutline, isFalse);
  });
}
