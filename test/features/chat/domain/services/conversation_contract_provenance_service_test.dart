import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';

void main() {
  const service = ConversationContractProvenanceService();

  test('approved plan sources every contract item with stable ids', () {
    const workflow = ConversationWorkflowSpec(
      goal: 'Ship the CLI',
      constraints: ['Keep compatibility'],
      acceptanceCriteria: ['Tests pass'],
      openQuestions: ['Which runtime?'],
      tasks: [ConversationWorkflowTask(id: 'task-1', title: 'Implement')],
    );

    final sourced = service.attachApprovedPlanSource(
      workflowSpec: workflow,
      sourceHash: 'hash-1',
    );

    expect(sourced.sources.single.id, 'approved-plan:hash-1');
    expect(sourced.provenance, hasLength(5));
    expect(sourced.provenance.map((item) => item.itemId), contains('goal'));
    expect(
      sourced.provenance.map((item) => item.itemId),
      contains('task:task-1'),
    );
    expect(
      sourced.provenance.every(
        (item) => item.sourceIds.single == 'approved-plan:hash-1',
      ),
      isTrue,
    );
  });
}
