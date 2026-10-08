import '../../entities/chat_turn_owner.dart';
import '../../entities/mcp_tool_entity.dart';
import 'ask_user_question_result_entry.dart';
import 'ask_user_question_reuse_policy.dart';

// ChatNotifier decomposition collaborator: ask-user-question-turn-cache

/// Stores reusable question results without allowing answers to cross turns.
final class AskUserQuestionTurnCache {
  final Map<ChatTurnOwner, List<CachedAskUserQuestionResult>> _entriesByOwner =
      {};

  McpToolResult? findReusable({
    required ChatTurnOwner owner,
    required String question,
    required Iterable<String> optionLabels,
  }) {
    return const AskUserQuestionReusePolicy().findReusable(
      entries: _entriesByOwner[owner] ?? const [],
      question: question,
      optionLabels: optionLabels,
    );
  }

  void store({
    required ChatTurnOwner owner,
    required String question,
    required Iterable<String> optionLabels,
    required McpToolResult result,
    Iterable<String> selectedLabels = const [],
  }) {
    final entries = _entriesByOwner.putIfAbsent(owner, () => []);
    entries.add(
      CachedAskUserQuestionResult(
        question: question,
        optionLabels: optionLabels,
        result: result,
        selectedLabels: selectedLabels,
      ),
    );
  }

  /// Evaluates [predicate] against each stored answer together with the
  /// options that were actually offered alongside it.
  bool anyEntry(
    ChatTurnOwner owner,
    bool Function(Set<String> offeredOptionLabels, McpToolResult result)
    predicate,
  ) {
    final entries = _entriesByOwner[owner];
    return entries != null &&
        entries.isNotEmpty &&
        entries.any((entry) => predicate(entry.optionLabels, entry.result));
  }

  bool anyResult(
    ChatTurnOwner owner,
    bool Function(McpToolResult result) predicate,
  ) {
    final entries = _entriesByOwner[owner];
    return entries != null &&
        entries.isNotEmpty &&
        entries.any((entry) => predicate(entry.result));
  }

  bool removeOwner(ChatTurnOwner owner) {
    return _entriesByOwner.remove(owner) != null;
  }

  void clearConversation(String conversationId) {
    _entriesByOwner.removeWhere(
      (owner, _) => owner.conversationId == conversationId,
    );
  }

  void clear() {
    _entriesByOwner.clear();
  }
}
