import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';

// ChatNotifier decomposition collaborator: ask-user-question-turn-cache

/// Stores reusable question results without allowing answers to cross turns.
final class AskUserQuestionTurnCache {
  final Map<ChatTurnOwner, List<_CachedAskUserQuestionResult>> _entriesByOwner =
      {};

  McpToolResult? findReusable({
    required ChatTurnOwner owner,
    required String question,
    required Iterable<String> optionLabels,
  }) {
    final entries = _entriesByOwner[owner];
    if (entries == null || entries.isEmpty) return null;

    final normalizedQuestion = _normalizeText(question);
    for (final entry in entries.reversed) {
      if (entry.normalizedQuestion == normalizedQuestion) {
        return entry.result;
      }
    }

    final normalizedLabels = _normalizedOptionLabels(optionLabels);
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
      _CachedAskUserQuestionResult(
        normalizedQuestion: _normalizeText(question),
        optionLabels: _normalizedOptionLabels(optionLabels),
        result: result,
      ),
    );
  }

  /// Evaluates [predicate] against each stored answer together with the
  /// options that were actually offered alongside it.
  ///
  /// A verdict that must not be spoofable by the wording of one option needs
  /// the whole offered set: an answer reporting only what the user picked
  /// cannot show that the same marker was also attached to the option they
  /// were declining.
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

  static Set<String> _normalizedOptionLabels(Iterable<String> labels) {
    return Set<String>.unmodifiable(
      labels.map(_normalizeText).where((label) => label.isNotEmpty),
    );
  }

  static String _normalizeText(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}

final class _CachedAskUserQuestionResult {
  _CachedAskUserQuestionResult({
    required this.normalizedQuestion,
    required Set<String> optionLabels,
    required this.result,
  }) : optionLabels = Set<String>.unmodifiable(optionLabels);

  final String normalizedQuestion;
  final Set<String> optionLabels;
  final McpToolResult result;
}
