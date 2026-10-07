import '../../../../core/types/workspace_mode.dart';
import '../entities/coding_project.dart';
import '../entities/conversation.dart';

const codingProjectSortOrderPrefsKey =
    'conversationDrawer.codingProjectSortOrder';

enum CodingProjectSortOrder {
  newestFirst,
  oldestFirst,
  recentlyActiveFirst,
  leastRecentlyActiveFirst,
}

CodingProjectSortOrder codingProjectSortOrderFromName(String? name) {
  return CodingProjectSortOrder.values.firstWhere(
    (order) => order.name == name,
    orElse: () => CodingProjectSortOrder.newestFirst,
  );
}

/// Orders projects for both the desktop drawer and Remote Coding snapshots.
///
/// The mobile drawer only receives the project order and the selected
/// project's threads, so the desktop must apply the same ordering before it
/// sends a snapshot.
List<CodingProject> sortCodingProjects({
  required Iterable<CodingProject> projects,
  required Iterable<Conversation> conversations,
  required CodingProjectSortOrder sortOrder,
}) {
  final latestThreadUpdates = <String, DateTime>{};
  for (final conversation in conversations) {
    if (conversation.workspaceMode != WorkspaceMode.coding) continue;
    final projectId = conversation.normalizedProjectId;
    if (projectId == null) continue;
    final previous = latestThreadUpdates[projectId];
    if (previous == null || conversation.updatedAt.isAfter(previous)) {
      latestThreadUpdates[projectId] = conversation.updatedAt;
    }
  }

  final sortedProjects = projects.toList(growable: true)
    ..sort((left, right) {
      final byPrimarySort = switch (sortOrder) {
        CodingProjectSortOrder.newestFirst => right.createdAt.compareTo(
          left.createdAt,
        ),
        CodingProjectSortOrder.oldestFirst => left.createdAt.compareTo(
          right.createdAt,
        ),
        CodingProjectSortOrder.recentlyActiveFirst =>
          _compareLatestThreadUpdates(
            latestThreadUpdates[left.id],
            latestThreadUpdates[right.id],
            newestFirst: true,
          ),
        CodingProjectSortOrder.leastRecentlyActiveFirst =>
          _compareLatestThreadUpdates(
            latestThreadUpdates[left.id],
            latestThreadUpdates[right.id],
            newestFirst: false,
          ),
      };
      if (byPrimarySort != 0) return byPrimarySort;

      final byCreatedAt = right.createdAt.compareTo(left.createdAt);
      if (byCreatedAt != 0) return byCreatedAt;
      return left.id.compareTo(right.id);
    });

  return sortedProjects;
}

int _compareLatestThreadUpdates(
  DateTime? left,
  DateTime? right, {
  required bool newestFirst,
}) {
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  return newestFirst ? right.compareTo(left) : left.compareTo(right);
}
