import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/dangling_precondition_repair.dart';
import 'package:flutter_test/flutter_test.dart';

const _repair = DanglingPreconditionRepair();

/// Approved-plan shape: provenance attached, because resolution runs through it
/// and the repair declines on a spec that has none.
ConversationWorkflowSpec _spec({
  required List<ConversationTaskPrecondition> preconditions,
  List<String> constraints = const ['The output goes to the project root'],
  List<String> openQuestions = const <String>[],
}) => const ConversationContractProvenanceService().attachApprovedPlanSource(
  workflowSpec: _rawSpec(
    preconditions: preconditions,
    constraints: constraints,
    openQuestions: openQuestions,
  ),
  sourceHash: 'hash',
);

ConversationWorkflowSpec _rawSpec({
  required List<ConversationTaskPrecondition> preconditions,
  List<String> constraints = const <String>[],
  List<String> openQuestions = const <String>[],
}) => ConversationWorkflowSpec(
  goal: 'Summarize the spec',
  constraints: constraints,
  openQuestions: openQuestions,
  tasks: [
    ConversationWorkflowTask(
      id: 'task-1',
      title: 'Write the README',
      preconditions: preconditions,
    ),
  ],
);

void main() {
  // Three live runs: the plan's first task waited on assumptions it had invented,
  // nothing resolved them, and the ready queue stayed empty for the whole run.
  test('an assumption nothing names becomes the question it reads like', () {
    final repaired = _repair.repair(
      _spec(
        preconditions: const [
          ConversationTaskPrecondition(
            kind: ConversationTaskPreconditionKind.assumption,
            ref: 'Is Japanese the right language (assumed)',
          ),
        ],
      ),
    );

    expect(
      repaired.openQuestions,
      contains('Is Japanese the right language (assumed)'),
      reason: 'The block survives and the user can now answer it.',
    );
    expect(
      repaired.tasks.single.preconditions.single.kind,
      ConversationTaskPreconditionKind.question,
    );
  });

  test('an assumption the contract does name is left alone', () {
    const ref = 'The output goes to the project root';
    final repaired = _repair.repair(
      _spec(
        preconditions: const [
          ConversationTaskPrecondition(
            kind: ConversationTaskPreconditionKind.assumption,
            ref: ref,
          ),
        ],
      ),
    );

    expect(repaired.openQuestions, isEmpty);
    expect(
      repaired.tasks.single.preconditions.single.kind,
      ConversationTaskPreconditionKind.assumption,
      reason: 'It resolves, so only the user confirming it may change anything.',
    );
  });

  test('a task edge is left alone, resolvable or not', () {
    final repaired = _repair.repair(
      _spec(
        preconditions: const [
          ConversationTaskPrecondition(
            kind: ConversationTaskPreconditionKind.task,
            ref: 'Some task that does not exist',
          ),
        ],
      ),
    );

    expect(repaired.openQuestions, isEmpty);
    expect(
      repaired.tasks.single.preconditions.single.kind,
      ConversationTaskPreconditionKind.task,
      reason:
          'Inventing a question for it would hide a plan that references work '
          'it does not contain.',
    );
  });

  test('a question already in the plan is not added twice', () {
    const ref = 'Is Japanese the right language (assumed)';
    final repaired = _repair.repair(
      _spec(
        preconditions: const [
          ConversationTaskPrecondition(
            kind: ConversationTaskPreconditionKind.assumption,
            ref: ref,
          ),
        ],
        openQuestions: const [ref],
      ),
    );

    expect(repaired.openQuestions, [ref]);
  });

  test('a spec with no provenance is left untouched', () {
    final raw = _rawSpec(
      preconditions: const [
        ConversationTaskPrecondition(
          kind: ConversationTaskPreconditionKind.assumption,
          ref: 'Is Japanese the right language (assumed)',
        ),
      ],
    );

    expect(
      _repair.repair(raw),
      raw,
      reason:
          'Without provenance every assumption looks unresolvable, so the repair '
          'would convert the real ones too.',
    );
  });

  test('an id-shaped ref is left alone even when it resolves to nothing', () {
    // A hand-typed edge naming an item by id round-trips through the plan
    // document unchanged, which ANA1 pinned by test; and an id can resolve again
    // after a plan edit restores the item, where prose turned into a question
    // never becomes an assumption again.
    final repaired = _repair.repair(
      _spec(
        preconditions: const [
          ConversationTaskPrecondition(
            kind: ConversationTaskPreconditionKind.assumption,
            ref: 'constraint:stable-ids',
          ),
        ],
      ),
    );

    expect(repaired.openQuestions, isEmpty);
    expect(
      repaired.tasks.single.preconditions.single.kind,
      ConversationTaskPreconditionKind.assumption,
    );
  });
}
