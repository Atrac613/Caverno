import 'package:path/path.dart' as path;

import '../../entities/conversation.dart';
import '../../entities/turn_diff.dart';

/// The task-owned files that every dedicated Farm review must inspect anew.
final class ProjectTaskReviewInspection {
  const ProjectTaskReviewInspection();

  List<String> paths({
    required Conversation? conversation,
    required bool codeReview,
    required String? projectRoot,
  }) {
    if (!codeReview || conversation?.goal?.projectTaskAutoReview != true) {
      return const [];
    }
    String resolve(String file) => path.normalize(
      path.isAbsolute(file) || projectRoot == null
          ? file
          : path.join(projectRoot, file),
    );
    final files = <String, bool>{};
    for (final diff in conversation!.turnDiffs) {
      if (diff.source != TurnDiffSource.tool) continue;
      for (final file in diff.files) {
        if (file.filePath.trim().isNotEmpty) {
          // The latest capture wins when repair deletes or recreates a file.
          files[resolve(file.filePath)] = file.isDeletedFile;
        }
      }
    }
    for (final file in conversation.goal!.projectTaskInheritedPaths) {
      if (file.trim().isNotEmpty) files.putIfAbsent(resolve(file), () => false);
    }
    // Deleted content is reviewed through the patch and surrounding code;
    // asking read_file to succeed on a deliberate deletion is impossible.
    return [
      for (final file in files.entries)
        if (!file.value) file.key,
    ];
  }
}
