import 'dart:convert';

import 'execution_snapshot_projector.dart';

/// Selects the concrete plan step quoted by a goal continuation prompt.
///
/// Caverno's native plan projection already owns task status, so its typed
/// active task is the primary source. Imported or hand-edited plans may instead
/// use a `## Task checklist`; those remain supported through a bounded textual
/// fallback without making numbered acceptance criteria look executable.
abstract final class GoalContinuationNextStepSelector {
  static const int maxPlanWindowBytes = 8 * 1024;

  static String? select({
    required ExecutionSnapshot executionSnapshot,
    required String? planMarkdown,
  }) {
    final activeTask = executionSnapshot.activeTaskTitle.trim();
    if (activeTask.isNotEmpty) {
      return activeTask;
    }
    return firstUncheckedChecklistItem(planMarkdown);
  }

  static String? firstUncheckedChecklistItem(
    String? planMarkdown, {
    int maxBytes = maxPlanWindowBytes,
  }) {
    if (planMarkdown == null || planMarkdown.trim().isEmpty || maxBytes <= 0) {
      return null;
    }

    final bytes = utf8.encode(planMarkdown);
    final isTruncated = bytes.length > maxBytes;
    var windowBytes = bytes.take(maxBytes).toList(growable: false);
    if (isTruncated) {
      final lastCompleteLineEnd = windowBytes.lastIndexOf(0x0a);
      if (lastCompleteLineEnd < 0) {
        return null;
      }
      windowBytes = windowBytes
          .take(lastCompleteLineEnd + 1)
          .toList(growable: false);
    }

    final window = utf8.decode(windowBytes);
    var inTaskChecklist = false;
    final uncheckedItem = RegExp(r'^\s*- \[ \]\s+(.+?)\s*$');
    for (final line in const LineSplitter().convert(window)) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase() == '## task checklist') {
        inTaskChecklist = true;
        continue;
      }
      if (inTaskChecklist && trimmed.startsWith('## ')) {
        return null;
      }
      if (!inTaskChecklist) {
        continue;
      }
      final match = uncheckedItem.firstMatch(line);
      final candidate = match?.group(1)?.trim();
      if (candidate != null && candidate.isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }
}
