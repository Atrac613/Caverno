enum WorkspaceMode { chat, coding, routines }

extension WorkspaceModeX on WorkspaceMode {
  bool get usesProjects => this == WorkspaceMode.coding;

  bool get usesConversations => this != WorkspaceMode.routines;
}
