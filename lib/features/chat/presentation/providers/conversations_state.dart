import '../../../../core/types/workspace_mode.dart';
import '../../domain/entities/conversation.dart';

/// State for the conversation list.
class ConversationsState {
  const ConversationsState({
    required this.conversations,
    required this.currentConversationId,
    required this.activeWorkspaceMode,
    required this.activeProjectId,
    this.isLoading = false,
  });

  final List<Conversation> conversations;
  final String? currentConversationId;
  final WorkspaceMode activeWorkspaceMode;
  final String? activeProjectId;
  final bool isLoading;

  factory ConversationsState.initial() => const ConversationsState(
    conversations: [],
    currentConversationId: null,
    activeWorkspaceMode: WorkspaceMode.chat,
    activeProjectId: null,
  );

  ConversationsState copyWith({
    List<Conversation>? conversations,
    String? currentConversationId,
    WorkspaceMode? activeWorkspaceMode,
    String? activeProjectId,
    bool? isLoading,
    bool clearCurrentConversation = false,
    bool clearActiveProject = false,
  }) {
    return ConversationsState(
      conversations: conversations ?? this.conversations,
      currentConversationId: clearCurrentConversation
          ? null
          : (currentConversationId ?? this.currentConversationId),
      activeWorkspaceMode: activeWorkspaceMode ?? this.activeWorkspaceMode,
      activeProjectId: clearActiveProject
          ? null
          : (activeProjectId ?? this.activeProjectId),
      isLoading: isLoading ?? this.isLoading,
    );
  }

  /// Returns the currently selected conversation.
  Conversation? get currentConversation {
    if (currentConversationId == null) return null;
    try {
      return conversations.firstWhere((c) => c.id == currentConversationId);
    } catch (_) {
      return null;
    }
  }

  Conversation? conversationForId(String? conversationId) =>
      conversationId == null
      ? currentConversation
      : conversations
            .where((candidate) => candidate.id == conversationId)
            .firstOrNull;

  List<Conversation> get visibleConversations {
    if (!activeWorkspaceMode.usesConversations) {
      return const [];
    }
    return conversations
        .where((conversation) {
          if (conversation.workspaceMode != activeWorkspaceMode) {
            return false;
          }
          if (!activeWorkspaceMode.usesProjects) {
            return true;
          }
          return conversation.normalizedProjectId == activeProjectId;
        })
        .toList(growable: false);
  }
}
