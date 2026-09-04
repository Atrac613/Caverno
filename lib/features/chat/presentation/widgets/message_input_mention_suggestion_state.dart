import '../mentions/mention_target.dart';

/// Which mention targets the composer is offering, and which one is selected.
///
/// Deliberately the same shape as the slash-command state rather than shared
/// with it. The two lists answer different questions — who this message is
/// addressed to, and what command to run — and they are never open at once, so
/// a common base would exist only to save the repetition and would have to be
/// generic over the item type to do it.
class MessageInputMentionSuggestionState {
  const MessageInputMentionSuggestionState({
    this.suggestions = const <MentionTarget>[],
    this.selectedIndex = 0,
    this.dismissedText,
  });

  static const empty = MessageInputMentionSuggestionState();

  final List<MentionTarget> suggestions;
  final int selectedIndex;

  /// The draft the user dismissed the list for, so it stays closed until they
  /// type something else.
  final String? dismissedText;

  bool get hasSuggestions => suggestions.isNotEmpty;

  MentionTarget get selectedSuggestion => suggestions[selectedIndex];

  MessageInputMentionSuggestionState refresh({
    required String text,
    required List<MentionTarget> targets,
  }) {
    final next = text == dismissedText
        ? const <MentionTarget>[]
        : filterMentionSuggestions(text, targets);
    final index = next.isEmpty
        ? 0
        : selectedIndex.clamp(0, next.length - 1).toInt();
    return _copyIfChanged(
      suggestions: next,
      selectedIndex: index,
      dismissedText: dismissedText,
    );
  }

  MessageInputMentionSuggestionState selectNext() => hasSuggestions
      ? _copyIfChanged(
          suggestions: suggestions,
          selectedIndex: (selectedIndex + 1) % suggestions.length,
          dismissedText: dismissedText,
        )
      : this;

  MessageInputMentionSuggestionState selectPrevious() => hasSuggestions
      ? _copyIfChanged(
          suggestions: suggestions,
          selectedIndex:
              (selectedIndex - 1 + suggestions.length) % suggestions.length,
          dismissedText: dismissedText,
        )
      : this;

  MessageInputMentionSuggestionState selectIndex(int index) => hasSuggestions
      ? _copyIfChanged(
          suggestions: suggestions,
          selectedIndex: index.clamp(0, suggestions.length - 1).toInt(),
          dismissedText: dismissedText,
        )
      : this;

  MessageInputMentionSuggestionState dismiss({required String text}) =>
      _copyIfChanged(
        suggestions: const <MentionTarget>[],
        selectedIndex: 0,
        dismissedText: text,
      );

  /// After the composer inserts a completion, so the list does not reopen on
  /// the text it just wrote.
  MessageInputMentionSuggestionState applyCompletedText(String text) =>
      dismiss(text: text);

  MessageInputMentionSuggestionState _copyIfChanged({
    required List<MentionTarget> suggestions,
    required int selectedIndex,
    required String? dismissedText,
  }) {
    if (_same(this.suggestions, suggestions) &&
        this.selectedIndex == selectedIndex &&
        this.dismissedText == dismissedText) {
      return this;
    }
    return MessageInputMentionSuggestionState(
      suggestions: suggestions,
      selectedIndex: selectedIndex,
      dismissedText: dismissedText,
    );
  }

  static bool _same(List<MentionTarget> previous, List<MentionTarget> next) {
    if (previous.length != next.length) return false;
    for (var index = 0; index < previous.length; index += 1) {
      if (!identical(previous[index], next[index])) return false;
    }
    return true;
  }
}
