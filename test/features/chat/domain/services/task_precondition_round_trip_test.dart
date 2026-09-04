import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_document_builder.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_projection_service.dart';
import 'package:test/test.dart';

/// ANA1 PR 2. The plan document is the authoritative middle: a precondition
/// the model writes has to survive the build-and-project round trip, or the
/// decomposition graph is only ever as real as the turn that produced it.
///
/// This is the same round trip ANA0 PR 3a pinned for epistemic marks, and it
/// exists for the same reason — a revision re-echoes the saved contract, so
/// anything the echo drops is laundered away on the next pass.
const _task = ConversationWorkflowTask(
  id: 'build-sync',
  title: 'Build the sync engine',
  validationCommand: 'dart test',
  preconditions: [
    ConversationTaskPrecondition(
      kind: ConversationTaskPreconditionKind.task,
      ref: 'inspect-model',
    ),
    ConversationTaskPrecondition(
      kind: ConversationTaskPreconditionKind.assumption,
      ref: 'constraint:9a36e21e',
    ),
    ConversationTaskPrecondition(
      kind: ConversationTaskPreconditionKind.question,
      ref: 'Which conflict policy applies, last-write or merge?',
    ),
  ],
);

String _document({List<ConversationWorkflowTask> tasks = const [_task]}) {
  return ConversationPlanDocumentBuilder.build(
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: ConversationWorkflowSpec(
      goal: 'Add iCloud synchronization',
      tasks: tasks,
    ),
  );
}

/// A real document with [edges] typed under its task, the way a user editing
/// the plan would write them.
String _documentWithEdges(List<String> edges) {
  final markdown = _document(
    tasks: const [ConversationWorkflowTask(id: 'build-sync', title: 'Build')],
  );
  final rendered = edges.map((edge) => '   - Requires: $edge').join('\n');
  return markdown.replaceFirst(
    '   - Status: pending',
    '   - Status: pending\n$rendered',
  );
}

ConversationWorkflowTask _project(String markdown) {
  final projection =
      ConversationPlanProjectionService.deriveExecutionProjection(
        approvedMarkdown: markdown,
        requireTasks: true,
      );
  return projection.workflowSpec.tasks.single;
}

void main() {
  test('every kind of edge survives the round trip', () {
    expect(_project(_document()).preconditions, _task.preconditions);
  });

  test('a question reference keeps its commas', () {
    final projected = _project(_document());
    final question = projected.preconditions.singleWhere(
      (item) => item.kind == ConversationTaskPreconditionKind.question,
    );

    expect(
      question.ref,
      'Which conflict policy applies, last-write or merge?',
      reason:
          'Questions are referenced by their own text, which is why each edge '
          'gets its own line instead of joining a comma list.',
    );
  });

  test('an assumption id keeps the colon inside it', () {
    final projected = _project(_document());
    final assumption = projected.preconditions.singleWhere(
      (item) => item.kind == ConversationTaskPreconditionKind.assumption,
    );

    expect(
      assumption.ref,
      'constraint:9a36e21e',
      reason:
          'A contract item id is itself kind-prefixed, so only the first '
          'colon separates the edge kind from its reference.',
    );
  });

  test('a task without preconditions projects exactly as before', () {
    final markdown = _document(
      tasks: const [
        ConversationWorkflowTask(id: 'solo', title: 'Do the thing'),
      ],
    );

    expect(markdown, isNot(contains('Requires:')));
    expect(_project(markdown).preconditions, isEmpty);
  });

  test('an unreadable edge is dropped without losing the document', () {
    final markdown = _documentWithEdges(const [
      'dependency: inspect-model',
      'task: inspect-model',
    ]);

    final projected = _project(markdown);

    expect(
      projected.preconditions.single.ref,
      'inspect-model',
      reason:
          'Every other task detail is something the plan states about itself, '
          'and an unknown one is an error. This one is optional, so a '
          'misspelled kind must cost the edge rather than the whole plan.',
    );
  });

  test('a hand-typed edge is honoured', () {
    final markdown = _documentWithEdges(const [
      'assumption: constraint:stable-ids',
    ]);

    expect(
      _project(markdown).preconditions.single,
      const ConversationTaskPrecondition(
        kind: ConversationTaskPreconditionKind.assumption,
        ref: 'constraint:stable-ids',
      ),
      reason:
          'The document is a surface the user edits, so what they can type is '
          'part of the contract — the same property ANA0 PR 3a pinned for a '
          'hand-typed epistemic marker.',
    );
  });
}
