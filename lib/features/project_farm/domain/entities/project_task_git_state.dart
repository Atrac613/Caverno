/// The repository state a project task's commit stage is checked against.
final class ProjectTaskGitState {
  const ProjectTaskGitState({required this.head, required this.dirtyPaths});

  final String head;

  /// `git status --porcelain` lines restricted to the task's files.
  final List<String> dirtyPaths;
}
