import '../../../../core/services/security_scoped_bookmark_service.dart';
import '../../../../core/utils/logger.dart';
import '../providers/coding_projects_notifier.dart';

Future<void> pickAndActivateCodingProject({
  required SecurityScopedBookmarkService bookmarks,
  required CodingProjectsNotifier projects,
  required bool Function() isMounted,
  required Future<void> Function(
    String projectId, {
    bool createFreshOnFirstOpen,
  })
  activate,
}) async {
  final pick = await bookmarks.pickDirectory();
  if (!isMounted()) return;
  if (pick.error != null) {
    appLog('[Bookmark] Failed to pick project directory: ${pick.error}');
    return;
  }
  final selectedDirectory = pick.path;
  if (selectedDirectory == null) return;

  final project = await projects.addProject(
    selectedDirectory,
    bookmark: pick.bookmark,
  );
  if (project == null || !isMounted()) return;

  await activate(project.id, createFreshOnFirstOpen: true);
}
