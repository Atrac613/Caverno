import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/conversation_repository.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';

/// State for the conversation list.
class ConversationsState {
  const ConversationsState({
    required this.conversations,
    required this.currentConversationId,
    this.isLoading = false,
  });

  final List<Conversation> conversations;
  final String? currentConversationId;
  final bool isLoading;

  factory ConversationsState.initial() =>
      const ConversationsState(conversations: [], currentConversationId: null);

  ConversationsState copyWith({
    List<Conversation>? conversations,
    String? currentConversationId,
    bool? isLoading,
    bool clearCurrentConversation = false,
  }) {
    return ConversationsState(
      conversations: conversations ?? this.conversations,
      currentConversationId: clearCurrentConversation
          ? null
          : (currentConversationId ?? this.currentConversationId),
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
}

/// Provider for `ConversationsNotifier`.
final conversationsNotifierProvider =
    StateNotifierProvider<ConversationsNotifier, ConversationsState>((ref) {
      final repository = ref.watch(conversationRepositoryProvider);
      return ConversationsNotifier(repository);
    });

/// Notifier that manages the conversation list.
class ConversationsNotifier extends StateNotifier<ConversationsState> {
  ConversationsNotifier(this._repository)
    : super(ConversationsState.initial()) {
    _loadConversations();
  }

  final ConversationRepository _repository;
  final _uuid = const Uuid();

  /// Loads the conversation list.
  void _loadConversations() {
    final conversations = _repository.getAll();
    state = state.copyWith(conversations: conversations);

    // Select the newest conversation when available, otherwise create one.
    if (conversations.isNotEmpty) {
      state = state.copyWith(currentConversationId: conversations.first.id);
    } else {
      createNewConversation();
    }
  }

  /// Creates a new conversation.
  void createNewConversation() {
    final now = DateTime.now();
    final conversation = Conversation(
      id: _uuid.v4(),
      title: '新しい会話',
      messages: const [],
      createdAt: now,
      updatedAt: now,
    );

    state = state.copyWith(
      conversations: [conversation, ...state.conversations],
      currentConversationId: conversation.id,
    );

    // Persist the new conversation.
    _repository.save(conversation);
  }

  /// Selects a conversation.
  void selectConversation(String id) {
    state = state.copyWith(currentConversationId: id);
  }

  /// Deletes a conversation.
  Future<void> deleteConversation(String id) async {
    await _repository.delete(id);

    final newConversations = state.conversations
        .where((c) => c.id != id)
        .toList();

    // If the deleted conversation was selected, choose a replacement.
    if (state.currentConversationId == id) {
      if (newConversations.isNotEmpty) {
        state = state.copyWith(
          conversations: newConversations,
          currentConversationId: newConversations.first.id,
        );
      } else {
        state = state.copyWith(
          conversations: newConversations,
          clearCurrentConversation: true,
        );
        // Create a new conversation to keep the UI usable.
        createNewConversation();
      }
    } else {
      state = state.copyWith(conversations: newConversations);
    }
  }

  /// Deletes all conversations.
  Future<void> deleteAllConversations() async {
    await _repository.deleteAll();

    state = state.copyWith(
      conversations: const [],
      clearCurrentConversation: true,
    );

    // Create one fresh conversation to avoid an empty state.
    createNewConversation();
  }

  /// Updates messages for the current conversation.
  Future<void> updateCurrentConversation(List<Message> messages) async {
    if (state.currentConversationId == null) return;

    final conversation = state.currentConversation;
    if (conversation == null) return;

    // Derive the title from the first user message.
    String title = conversation.title;
    if (title == '新しい会話' && messages.isNotEmpty) {
      final firstUserMessage = messages.firstWhere(
        (m) => m.role == MessageRole.user,
        orElse: () => messages.first,
      );
      // Use the first 30 characters as the title.
      title = firstUserMessage.content.length > 30
          ? '${firstUserMessage.content.substring(0, 30)}...'
          : firstUserMessage.content;
    }

    final updatedConversation = conversation.copyWith(
      title: title,
      messages: messages,
      updatedAt: DateTime.now(),
    );

    await _repository.save(updatedConversation);

    // Update local state.
    final newConversations = state.conversations.map((c) {
      if (c.id == updatedConversation.id) {
        return updatedConversation;
      }
      return c;
    }).toList();

    // Keep conversations sorted by latest update.
    newConversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    state = state.copyWith(conversations: newConversations);
  }

  /// Returns messages for the current conversation.
  List<Message> getCurrentMessages() {
    return state.currentConversation?.messages ?? [];
  }
}
