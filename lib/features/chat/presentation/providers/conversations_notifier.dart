import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/conversation_repository.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';

/// 会話一覧の状態
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

  /// 現在の会話を取得
  Conversation? get currentConversation {
    if (currentConversationId == null) return null;
    try {
      return conversations.firstWhere((c) => c.id == currentConversationId);
    } catch (_) {
      return null;
    }
  }
}

/// ConversationsNotifierのProvider
final conversationsNotifierProvider =
    StateNotifierProvider<ConversationsNotifier, ConversationsState>((ref) {
      final repository = ref.watch(conversationRepositoryProvider);
      return ConversationsNotifier(repository);
    });

/// 会話一覧を管理するNotifier
class ConversationsNotifier extends StateNotifier<ConversationsState> {
  ConversationsNotifier(this._repository)
    : super(ConversationsState.initial()) {
    _loadConversations();
  }

  final ConversationRepository _repository;
  final _uuid = const Uuid();

  /// 会話一覧を読み込み
  void _loadConversations() {
    final conversations = _repository.getAll();
    state = state.copyWith(conversations: conversations);

    // 会話があれば最新のものを選択、なければ新規作成
    if (conversations.isNotEmpty) {
      state = state.copyWith(currentConversationId: conversations.first.id);
    } else {
      createNewConversation();
    }
  }

  /// 新規会話を作成
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

    // 保存
    _repository.save(conversation);
  }

  /// 会話を選択
  void selectConversation(String id) {
    state = state.copyWith(currentConversationId: id);
  }

  /// 会話を削除
  Future<void> deleteConversation(String id) async {
    await _repository.delete(id);

    final newConversations = state.conversations
        .where((c) => c.id != id)
        .toList();

    // 削除した会話が現在の会話だった場合
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
        // 新規会話を作成
        createNewConversation();
      }
    } else {
      state = state.copyWith(conversations: newConversations);
    }
  }

  /// 全ての会話を削除
  Future<void> deleteAllConversations() async {
    await _repository.deleteAll();

    state = state.copyWith(
      conversations: const [],
      clearCurrentConversation: true,
    );

    // 空状態を避けるため、新規会話を1件作成
    createNewConversation();
  }

  /// 現在の会話のメッセージを更新（ChatNotifierから呼ばれる）
  Future<void> updateCurrentConversation(List<Message> messages) async {
    if (state.currentConversationId == null) return;

    final conversation = state.currentConversation;
    if (conversation == null) return;

    // タイトルを最初のユーザーメッセージから生成
    String title = conversation.title;
    if (title == '新しい会話' && messages.isNotEmpty) {
      final firstUserMessage = messages.firstWhere(
        (m) => m.role == MessageRole.user,
        orElse: () => messages.first,
      );
      // 最初の30文字をタイトルに
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

    // 状態を更新
    final newConversations = state.conversations.map((c) {
      if (c.id == updatedConversation.id) {
        return updatedConversation;
      }
      return c;
    }).toList();

    // 更新日時でソート
    newConversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    state = state.copyWith(conversations: newConversations);
  }

  /// 現在の会話のメッセージを取得
  List<Message> getCurrentMessages() {
    return state.currentConversation?.messages ?? [];
  }
}
