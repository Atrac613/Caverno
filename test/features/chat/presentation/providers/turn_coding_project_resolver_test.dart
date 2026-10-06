import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_state.dart';
import 'package:caverno/features/chat/presentation/providers/turn_coding_project_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 23);
  CodingProject project(String id, String rootPath) => CodingProject(
    id: id,
    name: id,
    rootPath: rootPath,
    createdAt: now,
    updatedAt: now,
  );
  Conversation thread(
    String id, {
    String projectId = '',
    String worktree = '',
  }) => Conversation(
    id: id,
    title: id,
    messages: const [],
    createdAt: now,
    updatedAt: now,
    workspaceMode: WorkspaceMode.coding,
    projectId: projectId,
    worktreePath: worktree,
  );

  final projects = CodingProjectsState(
    projects: [
      project('caverno', '/repo/caverno'),
      project('other', '/repo/other'),
    ],
    selectedProjectId: 'caverno',
  );

  TurnCodingProjectResolver resolver(
    List<Conversation> threads,
    String current,
  ) => TurnCodingProjectResolver(
    () => projects,
    ConversationsState(
      conversations: threads,
      currentConversationId: current,
      activeWorkspaceMode: WorkspaceMode.coding,
      activeProjectId: 'caverno',
    ),
  );

  test(
    'the visible thread resolves to its worktree, not the main checkout',
    () {
      final visible = thread(
        'visible',
        projectId: 'caverno',
        worktree: '/repo/caverno-worktrees/feature',
      );

      expect(
        resolver([visible], 'visible').forConversation(visible)?.rootPath,
        '/repo/caverno-worktrees/feature',
      );
    },
  );

  test('a background thread resolves to its own project and worktree', () {
    final visible = thread('visible', projectId: 'caverno');
    final background = thread(
      'background',
      projectId: 'other',
      worktree: '/repo/other-worktrees/fix',
    );
    final plain = thread('plain', projectId: 'other');
    final subject = resolver([visible, background, plain], 'visible');

    expect(
      subject.forConversation(background)?.rootPath,
      '/repo/other-worktrees/fix',
    );
    expect(subject.forConversation(plain)?.rootPath, '/repo/other');
    expect(subject.forConversation(visible)?.rootPath, '/repo/caverno');
  });
}
