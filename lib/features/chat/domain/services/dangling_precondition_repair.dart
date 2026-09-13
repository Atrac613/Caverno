import '../entities/conversation_workflow.dart';
import 'conversation_task_precondition_refs.dart';

/// Turns a precondition nobody can satisfy into one somebody can.
///
/// **Measured across three live runs.** A plan gave its first task three
/// `assumption` preconditions whose refs were question-shaped sentences the model
/// had invented — "is Japanese the right language for the README (assumed)" — and
/// matched no contract item. Readiness treats an unresolved assumption as unmet,
/// so the task waited for the rest of the run: there was no item for the user to
/// confirm and no question for them to answer. The ready queue stayed empty and
/// the parent was shown nothing to delegate.
///
/// **The edge is kept, not dropped.** Dropping it would let work start on an
/// unconfirmed assumption, which is the one thing ANA0's material-assumption
/// machinery exists to prevent. Converting it to the open question it already
/// reads like keeps the block and makes it answerable — by the user, which is
/// whose answer it always needed.
///
/// A `task` edge is left alone: an unresolved title is a different problem with a
/// different answer, and inventing a question for it would hide a plan that
/// references work it does not contain.
///
/// An id-shaped ref is left alone too — `constraint:<hash>`, `criterion:<hash>`,
/// `goal`. A hand-typed edge naming an item by id must round-trip through the plan
/// document unchanged, which is a property ANA1 pinned by test; and an id that
/// resolves to nothing today may resolve after a plan edit restores the item,
/// where prose invented as a question never becomes an assumption again.
class DanglingPreconditionRepair {
  const DanglingPreconditionRepair({
    this.refs = const ConversationTaskPreconditionRefs(),
  });

  final ConversationTaskPreconditionRefs refs;

  /// Whether [ref] names an item the way an id does rather than by its text.
  static bool _looksLikeItemId(String ref) =>
      ref == 'goal' || RegExp(r'^[a-z]+:[^\s]+$').hasMatch(ref);

  ConversationWorkflowSpec repair(ConversationWorkflowSpec spec) {
    // Resolution runs through provenance, so a spec without any cannot tell a
    // dangling ref from a real one -- every assumption would look unresolvable.
    // Provenance is attached when a plan is approved, which is the only point
    // this repair is meant to run at; anywhere earlier it declines rather than
    // converting edges it cannot judge.
    if (spec.provenance.isEmpty) return spec;
    final added = <String>[];
    final tasks = <ConversationWorkflowTask>[];
    for (final task in spec.tasks) {
      var changed = false;
      final edges = <ConversationTaskPrecondition>[];
      for (final edge in task.preconditions) {
        final ref = edge.ref.trim();
        if (edge.kind != ConversationTaskPreconditionKind.assumption ||
            ref.isEmpty ||
            _looksLikeItemId(ref) ||
            refs.itemIdFor(spec, ref) != null) {
          edges.add(edge);
          continue;
        }
        changed = true;
        edges.add(
          ConversationTaskPrecondition(
            kind: ConversationTaskPreconditionKind.question,
            ref: ref,
          ),
        );
        if (!spec.openQuestions.any((question) => question.trim() == ref) &&
            !added.contains(ref)) {
          added.add(ref);
        }
      }
      tasks.add(changed ? task.copyWith(preconditions: edges) : task);
    }
    if (added.isEmpty) return spec.copyWith(tasks: tasks);
    return spec.copyWith(
      tasks: tasks,
      openQuestions: [...spec.openQuestions, ...added],
    );
  }
}
