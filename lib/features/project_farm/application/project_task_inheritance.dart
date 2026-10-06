import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/turn_diff.dart';

/// The changes earlier runs of [task]'s roadmap item captured with their file
/// tools and that are still uncommitted, oldest run first.
///
/// An earlier run is another dashboard-started thread in the same project
/// whose goal objective is identical, which is what the same roadmap item
/// produces. Only captured file-tool diffs count, and [isDirty] confirms each
/// path against git, so a change since committed or reverted is not carried.
///
/// [load] returns a run's full payload. The in-memory list holds listing stubs
/// for threads not opened since launch, with their turn diffs dropped, so
/// without it every earlier run looked empty after a restart (session
/// b58b0db0).
Future<List<TurnDiffFile>> inheritedTaskFiles({
  required Conversation task,
  required Iterable<Conversation> conversations,
  required Future<bool> Function(String path) isDirty,
  required Future<Conversation> Function(Conversation run) load,
}) async {
  final objective = task.goal?.normalizedObjective;
  if (objective == null) return const [];
  final candidates =
      conversations
          .where(
            (other) =>
                other.id != task.id &&
                other.projectId == task.projectId &&
                other.goal?.projectTaskAutoReview == true &&
                other.goal?.normalizedObjective == objective,
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final earlier = [for (final run in candidates) await load(run)];
  final files = [
    for (final run in earlier)
      for (final diff in run.turnDiffs)
        if (diff.source == TurnDiffSource.tool) ...diff.files,
  ];
  final dirty = <String, bool>{};
  for (final path in {for (final file in files) file.filePath}) {
    dirty[path] = await isDirty(path);
  }
  return [
    for (final file in files)
      if (dirty[file.filePath] == true) file,
  ];
}
