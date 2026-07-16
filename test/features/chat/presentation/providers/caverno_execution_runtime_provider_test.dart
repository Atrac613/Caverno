import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/presentation/providers/caverno_execution_runtime_provider.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

void main() {
  test('runtime settings prefer the conversation worktree', () {
    final now = DateTime.utc(2026, 7, 16);
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/workspace/project',
      createdAt: now,
      updatedAt: now,
    );
    final conversation = Conversation(
      id: 'conversation-1',
      title: 'Worktree turn',
      messages: const [],
      createdAt: now,
      updatedAt: now,
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
      worktreePath: '/workspace/project-worktree',
    );
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_CodingSettingsNotifier.new),
        codingProjectsNotifierProvider.overrideWith(
          () => _CodingProjectsNotifier(project),
        ),
        conversationsNotifierProvider.overrideWith(
          () => _ConversationsNotifier(conversation),
        ),
      ],
    );
    addTearDown(container.dispose);

    final snapshot = container.read(cavernoRuntimeSettingsPortProvider).current;

    expect(snapshot.workspace, '/workspace/project-worktree');
  });

  test('data-root ownership port maps lease conflicts safely', () async {
    final dataRoot = await Directory.systemTemp.createTemp(
      'caverno_runtime_provider_lease_',
    );
    final workspace = await Directory('${dataRoot.path}/workspace').create();
    final firstContainer = ProviderContainer(
      overrides: [
        cavernoRuntimeDataRootProvider.overrideWithValue(dataRoot),
        cavernoRuntimeSurfaceProvider.overrideWithValue(
          CavernoRuntimeSurface.flutterGui,
        ),
      ],
    );
    final secondContainer = ProviderContainer(
      overrides: [
        cavernoRuntimeDataRootProvider.overrideWithValue(dataRoot),
        cavernoRuntimeSurfaceProvider.overrideWithValue(
          CavernoRuntimeSurface.terminal,
        ),
      ],
    );
    addTearDown(() async {
      firstContainer.dispose();
      secondContainer.dispose();
      await dataRoot.delete(recursive: true);
    });
    final request = CavernoRuntimeOwnershipRequest(
      surface: CavernoRuntimeSurface.flutterGui,
      mode: AssistantMode.coding.name,
      conversationId: 'conversation-conflict',
      workspace: workspace.path,
    );

    final first = await firstContainer
        .read(cavernoRuntimeOwnershipPortProvider)
        .acquire(request);

    await expectLater(
      secondContainer
          .read(cavernoRuntimeOwnershipPortProvider)
          .acquire(request),
      throwsA(
        isA<CavernoRuntimeOwnershipConflict>().having(
          (conflict) => conflict.message,
          'message',
          allOf(
            contains('workspace:workspace'),
            contains('flutterGui process'),
            isNot(contains(dataRoot.path)),
          ),
        ),
      ),
    );

    first.release();
    final second = await secondContainer
        .read(cavernoRuntimeOwnershipPortProvider)
        .acquire(request);
    second.release();
  });
}

final class _CodingSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() =>
      AppSettings.defaults().copyWith(assistantMode: AssistantMode.coding);
}

final class _CodingProjectsNotifier extends CodingProjectsNotifier {
  _CodingProjectsNotifier(this.project);

  final CodingProject project;

  @override
  CodingProjectsState build() =>
      CodingProjectsState(projects: [project], selectedProjectId: project.id);
}

final class _ConversationsNotifier extends ConversationsNotifier {
  _ConversationsNotifier(this.conversation);

  final Conversation conversation;

  @override
  ConversationsState build() => ConversationsState(
    conversations: [conversation],
    currentConversationId: conversation.id,
    activeWorkspaceMode: WorkspaceMode.coding,
    activeProjectId: conversation.projectId,
  );
}
