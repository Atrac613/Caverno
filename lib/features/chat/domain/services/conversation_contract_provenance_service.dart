import '../entities/conversation_workflow.dart';
import 'conversation_plan_hash.dart';

class ConversationContractProvenanceService {
  const ConversationContractProvenanceService();

  ConversationWorkflowSpec attachApprovedPlanSource({
    required ConversationWorkflowSpec workflowSpec,
    required String sourceHash,
  }) {
    final normalizedHash = sourceHash.trim();
    if (!workflowSpec.hasContent || normalizedHash.isEmpty) {
      return workflowSpec;
    }
    final sourceId = 'approved-plan:$normalizedHash';
    return workflowSpec.copyWith(
      sources: [
        ConversationContractSourceReference(
          id: sourceId,
          kind: ConversationContractSourceKind.approvedPlan,
          locator: 'conversation_plan_artifact',
          contentHash: normalizedHash,
        ),
      ],
      provenance: _items(workflowSpec, sourceId: sourceId),
    );
  }

  String itemId({
    required ConversationContractItemKind kind,
    required String value,
  }) {
    if (kind == ConversationContractItemKind.goal) return 'goal';
    final normalized = value.trim().toLowerCase();
    return '${kind.name}:${computeConversationPlanHash(normalized)}';
  }

  List<ConversationContractItemProvenance> _items(
    ConversationWorkflowSpec spec, {
    required String sourceId,
  }) {
    final items = <ConversationContractItemProvenance>[];
    if (spec.goal.trim().isNotEmpty) {
      items.add(
        ConversationContractItemProvenance(
          itemId: 'goal',
          kind: ConversationContractItemKind.goal,
          sourceIds: [sourceId],
        ),
      );
    }
    void addItems(Iterable<String> values, ConversationContractItemKind kind) {
      for (final value in values) {
        if (value.trim().isEmpty) continue;
        items.add(
          ConversationContractItemProvenance(
            itemId: itemId(kind: kind, value: value),
            kind: kind,
            sourceIds: [sourceId],
          ),
        );
      }
    }

    addItems(spec.constraints, ConversationContractItemKind.constraint);
    addItems(
      spec.acceptanceCriteria,
      ConversationContractItemKind.acceptanceCriterion,
    );
    addItems(spec.openQuestions, ConversationContractItemKind.openQuestion);
    for (final task in spec.tasks) {
      final taskId = task.id.trim();
      items.add(
        ConversationContractItemProvenance(
          itemId: taskId.isEmpty
              ? itemId(
                  kind: ConversationContractItemKind.task,
                  value: task.title,
                )
              : 'task:$taskId',
          kind: ConversationContractItemKind.task,
          sourceIds: [sourceId],
        ),
      );
    }
    return items;
  }
}
