import '../entities/conversation_workflow.dart';

/// Reads the precondition edges a task proposal declares (ANA1).
///
/// The shape was chosen by measurement rather than by argument. Three arms over
/// 36 live requests compared a `preconditions` array against the same edge
/// written into the task title and against no instruction at all: the array
/// produced 1.06 edges per task to the title marker's 0.64, every edge in both
/// arms resolved to something the plan contained, and — the reason ANA0 kept
/// its own marker out of the schema — the schema arm parsed 12 of 12, exactly
/// like the other two. See the PR 2b measurement in `docs/roadmap.md`.
///
/// The measurement instrument reads edges through this, so the extractor that
/// chose the channel is the extractor that ships.
abstract final class TaskPreconditionParsing {
  /// Edges declared by one task object in a proposal.
  ///
  /// Tolerant on the way in for the reasons every parser here is: the field may
  /// arrive under a synonym, and a model that flattens the object into
  /// `"task: Audit the model"` still expressed the edge. Unreadable entries are
  /// dropped rather than failing the task, because a precondition is optional
  /// and a plan is not worth losing over one.
  static List<ConversationTaskPrecondition> fromProposalTask(
    Map<String, dynamic> task,
  ) {
    final raw = task['preconditions'] ?? task['requires'] ?? task['前提条件'];
    if (raw is! List) return const [];
    final edges = <ConversationTaskPrecondition>[];
    for (final entry in raw) {
      final edge = switch (entry) {
        Map<dynamic, dynamic>() => _fromMap(entry),
        String() => parseInline(entry),
        _ => null,
      };
      if (edge != null) edges.add(edge);
    }
    return List<ConversationTaskPrecondition>.unmodifiable(edges);
  }

  /// One edge written as `<kind>: <ref>`.
  ///
  /// Splits on the first colon only: an assumption is referenced by a contract
  /// item id, which is itself `constraint:<hash>`.
  static ConversationTaskPrecondition? parseInline(String value) {
    final separator = value.indexOf(':');
    if (separator <= 0) return null;
    final kind = kindNamed(value.substring(0, separator));
    final ref = value.substring(separator + 1).trim();
    if (kind == null || ref.isEmpty) return null;
    return ConversationTaskPrecondition(kind: kind, ref: ref);
  }

  static ConversationTaskPreconditionKind? kindNamed(String value) {
    final normalized = value.trim().toLowerCase();
    for (final kind in ConversationTaskPreconditionKind.values) {
      if (kind.name == normalized) return kind;
    }
    return null;
  }

  static ConversationTaskPrecondition? _fromMap(Map<dynamic, dynamic> entry) {
    final kind = kindNamed('${entry['kind'] ?? entry['type'] ?? ''}');
    final ref = '${entry['ref'] ?? entry['value'] ?? entry['id'] ?? ''}'.trim();
    if (kind == null || ref.isEmpty) return null;
    return ConversationTaskPrecondition(kind: kind, ref: ref);
  }
}
