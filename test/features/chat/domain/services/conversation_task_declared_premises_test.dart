import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_task_precondition_refs.dart';
import 'package:caverno/features/chat/domain/services/task_delegation_brief_builder.dart';
import 'package:test/test.dart';

const _declared = ConversationTaskPreconditionRefs();
const _briefs = TaskDelegationBriefBuilder();
const _provenance = ConversationContractProvenanceService();

const _claim = 'The archive fits in memory';

ConversationWorkflowSpec _spec({
  bool confirmed = true,
  ConversationTaskPreconditionKind kind =
      ConversationTaskPreconditionKind.assumption,
}) => ConversationWorkflowSpec(
  goal: 'Add an archive browser',
  constraints: const [_claim],
  provenance: [
    ConversationContractItemProvenance(
      itemId: _provenance.itemId(
        kind: ConversationContractItemKind.constraint,
        value: _claim,
      ),
      kind: ConversationContractItemKind.constraint,
      assumption: true,
      material: true,
      confirmed: confirmed,
    ),
  ],
  tasks: [
    ConversationWorkflowTask(
      id: 'task-1',
      title: 'Read the archive',
      preconditions: [ConversationTaskPrecondition(kind: kind, ref: _claim)],
    ),
  ],
);

void main() {
  test('an assumption the user has since declined is still declared', () {
    final spec = _spec(confirmed: false);

    expect(
      _declared.declaredAssumptionPremises(spec, spec.tasks.single),
      [_claim],
      reason:
          'the lapse is what acceptance is looking for, so dropping the '
          'unconfirmed ones here would hide it',
    );
  });

  test('it agrees with the delegation brief while the assumption holds', () {
    final spec = _spec();

    expect(_declared.declaredAssumptionPremises(spec, spec.tasks.single), [
      _claim,
    ]);
    expect(
      _briefs.premisesFor(spec, spec.tasks.single),
      [_claim],
      reason:
          'a task is only delegated once ready, and readiness confirms every '
          'assumption edge — so at delegation time the two sets are one set',
    );
  });

  test('the delegation brief still drops what it must', () {
    final spec = _spec(confirmed: false);

    expect(
      _briefs.premisesFor(spec, spec.tasks.single),
      isEmpty,
      reason:
          'handing a child an unconfirmed claim as a premise is how an '
          'assumption turns back into a guess one level down',
    );
  });

  test('edges that are not assumptions carry no premise', () {
    final spec = _spec(kind: ConversationTaskPreconditionKind.task);

    expect(
      _declared.declaredAssumptionPremises(spec, spec.tasks.single),
      isEmpty,
    );
  });
}
