import '../../domain/entities/coding_project.dart';
import '../../domain/entities/conversation.dart';
import 'coding_projects_notifier.dart';
import 'conversations_notifier.dart';

/// Answers "which coding project does this belong to" for the visible thread
/// and for a turn running on some other thread.
///
/// Extracted from ChatNotifier because the two answers had drifted apart: the
/// active project id and the worktree override are visible-thread state, so a
/// background turn that asked for the project got the one the user was looking
/// at — its prompts described another workspace and its relative tool paths
/// resolved into it.
class TurnCodingProjectResolver {
  /// [_loadProjects] stays lazy: callers reach this with no project selected,
  /// and tests that never override the coding-projects provider must not be
  /// forced to build it.
  const TurnCodingProjectResolver(this._loadProjects, this._conversations);

  final CodingProjectsState Function() _loadProjects;
  final ConversationsState _conversations;

  /// The globally selected project, ignoring any worktree override.
  CodingProject? get active {
    final activeProjectId = _conversations.activeProjectId;
    if (activeProjectId == null) return null;
    return _loadProjects().findById(activeProjectId);
  }

  /// The visible thread's project, with its worktree override applied.
  CodingProject? get effective {
    final project = active;
    if (project == null) return null;
    return _withWorktree(
      project,
      _conversations.currentConversation?.normalizedWorktreePath,
    );
  }

  /// The project [conversation] belongs to. Falls back to [effective] for the
  /// visible thread so its behaviour is unchanged.
  CodingProject? forConversation(Conversation? conversation) {
    if (conversation == null ||
        conversation.id == _conversations.currentConversation?.id) {
      return effective;
    }
    final projectId = conversation.normalizedProjectId;
    if (projectId == null) return null;
    final project = _loadProjects().findById(projectId);
    if (project == null) return null;
    return _withWorktree(project, conversation.normalizedWorktreePath);
  }

  CodingProject? _withWorktree(CodingProject project, String? worktreePath) {
    if (worktreePath == null || worktreePath.isEmpty) return project;
    return project.copyWith(rootPath: worktreePath);
  }
}
