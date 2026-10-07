import 'package:caverno/features/project_farm/domain/entities/project_task_commit_scope.dart';

export 'package:caverno/features/project_farm/domain/entities/project_task_commit_scope.dart';

/// Workflow tests supply native evidence; the reader and dispatcher have real fixtures.
ProjectTaskCommitSnapshot fakeTaskCommitSnapshot(
  ProjectTaskCommitScope scope,
  String head,
) => ProjectTaskCommitSnapshot(
  head: head,
  indexFingerprint: 'index',
  fileFingerprints: {for (final file in scope.paths) file: 'captured'},
  stagedPaths: scope.paths,
  unstagedPaths: const {},
);
