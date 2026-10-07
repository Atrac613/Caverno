import '../entities/conversation.dart';
import '../entities/turn_diff.dart';

/// Whether a roadmap task thread already holds file changes for its task:
/// files an earlier run left uncommitted, or edits this thread's own turns
/// captured. These are the same changes the task workflow reviews.
///
/// A completion turn on such a thread may rightly change nothing more, so a
/// request-text heuristic must not conclude that a required write never
/// happened. Session bf893af7 lost a finished task that way: the last
/// subtask was titled "create unit tests", the tests already existed among
/// the inherited changes, and an injected `unexecuted_file_save` rejected the
/// completion and stopped the workflow before review.
bool projectTaskHasCapturedChanges(Conversation? conversation) {
  final goal = conversation?.goal;
  if (goal == null || !goal.projectTaskAutoReview) return false;
  return goal.projectTaskInheritedPaths.isNotEmpty ||
      conversation!.turnDiffs.any(
        (diff) => diff.source == TurnDiffSource.tool && diff.files.isNotEmpty,
      );
}
