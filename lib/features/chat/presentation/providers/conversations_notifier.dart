import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/types/workspace_mode.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_plan_artifact.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/entities/message.dart';
import '../../domain/services/conversation_plan_document_builder.dart';

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

  List<Conversation> get visibleConversations {
    return conversations
        .where((conversation) {
          if (conversation.workspaceMode != activeWorkspaceMode) {
            return false;
          }
          if (activeWorkspaceMode == WorkspaceMode.chat) {
            return true;
          }
          return conversation.normalizedProjectId == activeProjectId;
        })
        .toList(growable: false);
  }
}

/// Provider for `ConversationsNotifier`.
final conversationsNotifierProvider =
    NotifierProvider<ConversationsNotifier, ConversationsState>(
      ConversationsNotifier.new,
    );

/// Default title for new conversations (used as a sentinel for auto-title).
const defaultConversationTitle = '__new_conversation__';

/// Notifier that manages the conversation list.
class ConversationsNotifier extends Notifier<ConversationsState> {
  late final ConversationRepository _repository;
  final _uuid = const Uuid();

  @override
  ConversationsState build() {
    _repository = ref.read(conversationRepositoryProvider);
    final scopedState = _buildScopedState(
      conversations: _repository.getAll(),
      workspaceMode: WorkspaceMode.chat,
      projectId: null,
      createIfMissing: true,
    );
    Future<void>.microtask(() async {
      if (!ref.mounted) {
        return;
      }
      await ensureCurrentPlanArtifactBackfilled();
    });
    return scopedState;
  }

  ConversationsState _buildScopedState({
    required List<Conversation> conversations,
    required WorkspaceMode workspaceMode,
    required String? projectId,
    String? preferredConversationId,
    required bool createIfMissing,
  }) {
    final normalizedProjectId = workspaceMode == WorkspaceMode.coding
        ? projectId
        : null;
    final visibleConversations = conversations
        .where((conversation) {
          if (conversation.workspaceMode != workspaceMode) {
            return false;
          }
          if (workspaceMode == WorkspaceMode.chat) {
            return true;
          }
          return conversation.normalizedProjectId == normalizedProjectId;
        })
        .toList(growable: false);

    String? currentConversationId = preferredConversationId;
    if (currentConversationId != null &&
        !visibleConversations.any(
          (conversation) => conversation.id == currentConversationId,
        )) {
      currentConversationId = null;
    }
    currentConversationId ??= visibleConversations.isEmpty
        ? null
        : visibleConversations.first.id;

    var nextConversations = conversations;
    if (currentConversationId == null && createIfMissing) {
      final fresh = _createConversation(
        workspaceMode: workspaceMode,
        projectId: normalizedProjectId,
      );
      _repository.save(fresh);
      nextConversations = [fresh, ...conversations];
      _sortConversations(nextConversations);
      currentConversationId = fresh.id;
    }

    return ConversationsState(
      conversations: nextConversations,
      currentConversationId: currentConversationId,
      activeWorkspaceMode: workspaceMode,
      activeProjectId: normalizedProjectId,
    );
  }

  Conversation _createConversation({
    required WorkspaceMode workspaceMode,
    required String? projectId,
  }) {
    final now = DateTime.now();
    return Conversation(
      id: _uuid.v4(),
      title: defaultConversationTitle,
      messages: const [],
      createdAt: now,
      updatedAt: now,
      workspaceMode: workspaceMode,
      projectId: projectId ?? '',
    );
  }

  void _sortConversations(List<Conversation> conversations) {
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> _persistUpdatedConversation(
    Conversation updatedConversation,
  ) async {
    await _repository.save(updatedConversation);

    final newConversations = state.conversations.map((conversation) {
      if (conversation.id == updatedConversation.id) {
        return updatedConversation;
      }
      return conversation;
    }).toList();

    _sortConversations(newConversations);
    state = state.copyWith(conversations: newConversations);
  }

  /// Creates a new conversation.
  void createNewConversation({
    WorkspaceMode? workspaceMode,
    String? projectId,
  }) {
    final resolvedWorkspaceMode = workspaceMode ?? state.activeWorkspaceMode;
    final resolvedProjectId = resolvedWorkspaceMode == WorkspaceMode.coding
        ? (projectId ?? state.activeProjectId)
        : null;
    final conversation = _createConversation(
      workspaceMode: resolvedWorkspaceMode,
      projectId: resolvedProjectId,
    );

    state = state.copyWith(
      conversations: [conversation, ...state.conversations],
      currentConversationId: conversation.id,
      activeWorkspaceMode: resolvedWorkspaceMode,
      activeProjectId: resolvedProjectId,
      clearActiveProject:
          resolvedWorkspaceMode == WorkspaceMode.chat ||
          resolvedProjectId == null,
    );

    // Persist the new conversation.
    _repository.save(conversation);
  }

  /// Selects a conversation.
  void selectConversation(String id) {
    final conversation = state.conversations
        .where((item) => item.id == id)
        .firstOrNull;
    if (conversation == null) return;

    state = state.copyWith(
      currentConversationId: id,
      activeWorkspaceMode: conversation.workspaceMode,
      activeProjectId: conversation.normalizedProjectId,
      clearActiveProject: conversation.workspaceMode == WorkspaceMode.chat,
    );
    ensureCurrentPlanArtifactBackfilled();
  }

  void activateWorkspace({
    required WorkspaceMode workspaceMode,
    String? projectId,
    bool createIfMissing = true,
  }) {
    state = _buildScopedState(
      conversations: state.conversations,
      workspaceMode: workspaceMode,
      projectId: projectId,
      preferredConversationId: state.currentConversationId,
      createIfMissing: createIfMissing,
    );
    ensureCurrentPlanArtifactBackfilled();
  }

  /// Deletes a conversation.
  Future<void> deleteConversation(String id) async {
    await _repository.delete(id);

    final newConversations = state.conversations
        .where((c) => c.id != id)
        .toList();
    state = _buildScopedState(
      conversations: newConversations,
      workspaceMode: state.activeWorkspaceMode,
      projectId: state.activeProjectId,
      preferredConversationId: state.currentConversationId == id
          ? null
          : state.currentConversationId,
      createIfMissing:
          state.activeWorkspaceMode == WorkspaceMode.chat ||
          state.activeProjectId != null,
    );
  }

  /// Deletes all conversations in the active scope.
  Future<void> deleteScopedConversations() async {
    final visibleConversationIds = state.visibleConversations
        .map((conversation) => conversation.id)
        .toList(growable: false);
    for (final id in visibleConversationIds) {
      await _repository.delete(id);
    }

    final newConversations = state.conversations
        .where(
          (conversation) => !visibleConversationIds.contains(conversation.id),
        )
        .toList();

    state = _buildScopedState(
      conversations: newConversations,
      workspaceMode: state.activeWorkspaceMode,
      projectId: state.activeProjectId,
      createIfMissing:
          state.activeWorkspaceMode == WorkspaceMode.chat ||
          state.activeProjectId != null,
    );
  }

  Future<void> deleteConversationsForProject(String projectId) async {
    final targetIds = state.conversations
        .where(
          (conversation) =>
              conversation.workspaceMode == WorkspaceMode.coding &&
              conversation.normalizedProjectId == projectId,
        )
        .map((conversation) => conversation.id)
        .toList(growable: false);
    for (final id in targetIds) {
      await _repository.delete(id);
    }

    state = state.copyWith(
      conversations: state.conversations
          .where((conversation) => !targetIds.contains(conversation.id))
          .toList(),
      clearCurrentConversation: targetIds.contains(state.currentConversationId),
    );
  }

  /// Updates messages for the current conversation.
  Future<void> updateCurrentConversation(List<Message> messages) async {
    if (state.currentConversationId == null) return;

    final conversation = state.currentConversation;
    if (conversation == null) return;

    String title = conversation.title;
    if (title == defaultConversationTitle && messages.isNotEmpty) {
      title = _deriveDefaultTitle(messages) ?? title;
    }

    final updatedConversation = conversation.copyWith(
      title: title,
      messages: messages,
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedConversation(updatedConversation);
  }

  String? _deriveDefaultTitle(List<Message> messages) {
    for (final message in messages) {
      if (message.role != MessageRole.user) continue;

      final trimmed = message.content.trim();
      if (trimmed.isEmpty) continue;

      return trimmed.length > 30 ? '${trimmed.substring(0, 30)}...' : trimmed;
    }

    return null;
  }

  Future<void> updateCurrentWorkflow({
    ConversationWorkflowStage? workflowStage,
    ConversationWorkflowSpec? workflowSpec,
    bool clearWorkflowSpec = false,
  }) async {
    final conversation = state.currentConversation;
    if (conversation == null) return;

    final nextStage = workflowStage ?? conversation.workflowStage;
    final nextWorkflowSpec = clearWorkflowSpec
        ? null
        : (workflowSpec ?? conversation.workflowSpec);

    final updatedConversation = conversation.copyWith(
      workflowStage: nextStage,
      workflowSpec: nextWorkflowSpec,
      updatedAt: DateTime.now(),
    );

    await _persistUpdatedConversation(updatedConversation);
    await ensureCurrentPlanArtifactBackfilled();
  }

  Future<void> updateCurrentPlanArtifact({
    ConversationPlanArtifact? planArtifact,
    bool clearPlanArtifact = false,
  }) async {
    final conversation = state.currentConversation;
    if (conversation == null) return;

    final nextPlanArtifact = clearPlanArtifact
        ? null
        : (planArtifact?.hasContent ?? false)
        ? planArtifact
        : null;

    final updatedConversation = conversation.copyWith(
      planArtifact: nextPlanArtifact,
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedConversation(updatedConversation);
  }

  Future<void> ensureCurrentPlanArtifactBackfilled() async {
    final conversation = state.currentConversation;
    if (conversation == null ||
        conversation.hasPlanArtifact ||
        !conversation.hasWorkflowContext) {
      return;
    }

    final planArtifact = ConversationPlanDocumentBuilder.buildApprovedArtifact(
      workflowStage: conversation.workflowStage,
      workflowSpec: conversation.effectiveWorkflowSpec,
      updatedAt: DateTime.now(),
    );
    final updatedConversation = conversation.copyWith(
      planArtifact: planArtifact,
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedConversation(updatedConversation);
  }

  Future<void> enterPlanningSession() async {
    await _updateCurrentExecutionMode(ConversationExecutionMode.planning);
  }

  Future<void> exitPlanningSession() async {
    await _updateCurrentExecutionMode(ConversationExecutionMode.normal);
  }

  Future<void> _updateCurrentExecutionMode(
    ConversationExecutionMode executionMode,
  ) async {
    final conversation = state.currentConversation;
    if (conversation == null || conversation.executionMode == executionMode) {
      return;
    }

    final updatedConversation = conversation.copyWith(
      executionMode: executionMode,
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedConversation(updatedConversation);
  }

  /// Returns messages for the current conversation.
  List<Message> getCurrentMessages() {
    return state.currentConversation?.messages ?? [];
  }
}
