import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import 'ask_user_question_result_entry.dart';

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
    final entries = _entriesByOwner[owner];
    if (entries == null || entries.isEmpty) return null;

    final normalizedQuestion = normalizeAskUserQuestionText(question);
    for (final entry in entries.reversed) {
      if (entry.normalizedQuestion == normalizedQuestion) {
        return entry.result;
      }
    }

    final normalizedLabels = normalizeAskUserQuestionOptionLabels(optionLabels);
    if (normalizedLabels.isEmpty) return null;
    for (final entry in entries.reversed) {
      final canReuseAcrossWording =
          entry.result.isSuccess &&
          (entry.optionLabels.length > 1 || normalizedLabels.length > 1) &&
          entry.optionLabels.intersection(normalizedLabels).isNotEmpty;
      if (canReuseAcrossWording) return entry.result;
    }
    return null;
  }

  void store({
    required ChatTurnOwner owner,
    required String question,
    required Iterable<String> optionLabels,
    required McpToolResult result,
  }) {
    final entries = _entriesByOwner.putIfAbsent(owner, () => []);
    entries.add(
      CachedAskUserQuestionResult(
        question: question,
        optionLabels: optionLabels,
        result: result,
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
