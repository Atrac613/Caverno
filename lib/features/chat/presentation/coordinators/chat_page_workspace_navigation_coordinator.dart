import '../../../../core/types/assistant_mode.dart';
import '../../../../core/types/workspace_mode.dart';
import '../../domain/entities/conversation.dart';
import '../providers/coding_projects_notifier.dart';
import '../providers/conversations_notifier.dart';

final class ChatPageWorkspaceNavigationCoordinator {
  ChatPageWorkspaceNavigationCoordinator({
    required ConversationsNotifier conversationsNotifier,
    required CodingProjectsNotifier codingProjectsNotifier,
    required ConversationsState Function() readConversationsState,
    required CodingProjectsState Function() readCodingProjectsState,
    required AssistantMode Function() readAssistantMode,
    required Future<void> Function(AssistantMode mode) updateAssistantMode,
    required void Function() leaveDashboard,
    required void Function() clearRoutineSelection,
  }) : _conversationsNotifier = conversationsNotifier,
       _codingProjectsNotifier = codingProjectsNotifier,
       _readConversationsState = readConversationsState,
       _readCodingProjectsState = readCodingProjectsState,
       _readAssistantMode = readAssistantMode,
       _updateAssistantMode = updateAssistantMode,
       _leaveDashboard = leaveDashboard,
       _clearRoutineSelection = clearRoutineSelection;

  final ConversationsNotifier _conversationsNotifier;
  final CodingProjectsNotifier _codingProjectsNotifier;
  final ConversationsState Function() _readConversationsState;
  final CodingProjectsState Function() _readCodingProjectsState;
  final AssistantMode Function() _readAssistantMode;
  final Future<void> Function(AssistantMode mode) _updateAssistantMode;
  final void Function() _leaveDashboard;
  final void Function() _clearRoutineSelection;

  Future<void> switchWorkspaceMode(WorkspaceMode workspaceMode) async {
    _leaveDashboard();

    if (workspaceMode == WorkspaceMode.chat) {
      _conversationsNotifier.activateWorkspace(
        workspaceMode: WorkspaceMode.chat,
        createIfMissing: true,
        createFreshOnFirstOpen: true,
      );
      await _updateAssistantMode(AssistantMode.general);
      return;
    }

    if (workspaceMode == WorkspaceMode.routines) {
      _conversationsNotifier.activateWorkspace(
        workspaceMode: WorkspaceMode.routines,
        createIfMissing: false,
      );
      _clearRoutineSelection();
      return;
    }

    final projectId =
        _readConversationsState().activeProjectId ??
        _readCodingProjectsState().selectedProjectId;
    if (projectId != null) {
      await activateCodingProject(projectId, createFreshOnFirstOpen: true);
      return;
    }

    _conversationsNotifier.activateWorkspace(
      workspaceMode: WorkspaceMode.coding,
      projectId: null,
      createIfMissing: false,
    );
    await _promoteGeneralModeToCoding();
  }

  Future<void> activateCodingProject(
    String projectId, {
    bool createFreshOnFirstOpen = false,
  }) async {
    _leaveDashboard();
    _codingProjectsNotifier.selectProject(projectId);
    _conversationsNotifier.activateWorkspace(
      workspaceMode: WorkspaceMode.coding,
      projectId: projectId,
      createIfMissing: createFreshOnFirstOpen,
      createFreshOnFirstOpen: createFreshOnFirstOpen,
      deferFreshConversationCreation: createFreshOnFirstOpen,
    );
    await _promoteGeneralModeToCoding();
  }

  Future<void> selectConversation(String conversationId) async {
    _leaveDashboard();
    final conversation = _findConversation(conversationId);
    if (conversation == null) {
      return;
    }

    final normalizedProjectId = conversation.normalizedProjectId;
    if (conversation.workspaceMode == WorkspaceMode.coding &&
        normalizedProjectId != null) {
      _codingProjectsNotifier.selectProject(normalizedProjectId);
    }

    _conversationsNotifier.selectConversation(conversationId);
    switch (conversation.workspaceMode) {
      case WorkspaceMode.chat:
        await _updateAssistantMode(AssistantMode.general);
        break;
      case WorkspaceMode.coding:
        await _promoteGeneralModeToCoding();
        break;
      case WorkspaceMode.routines:
        break;
    }
  }

  Conversation? _findConversation(String conversationId) {
    return _readConversationsState().conversations
        .where((conversation) => conversation.id == conversationId)
        .firstOrNull;
  }

  Future<void> _promoteGeneralModeToCoding() {
    final currentMode = _readAssistantMode();
    return _updateAssistantMode(
      currentMode == AssistantMode.general ? AssistantMode.coding : currentMode,
    );
  }
}
