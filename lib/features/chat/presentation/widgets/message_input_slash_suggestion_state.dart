import '../slash_commands/slash_command.dart';

class MessageInputSlashSuggestionState {
  const MessageInputSlashSuggestionState({
    this.suggestions = const <SlashCommandDefinition>[],
    this.selectedIndex = 0,
    this.dismissedText,
  });

  static const empty = MessageInputSlashSuggestionState();

  final List<SlashCommandDefinition> suggestions;
  final int selectedIndex;
  final String? dismissedText;

  bool get hasSuggestions => suggestions.isNotEmpty;

  SlashCommandDefinition get selectedSuggestion => suggestions[selectedIndex];

  MessageInputSlashSuggestionState refresh({
    required String text,
    required bool commandsEnabled,
    required bool hasAttachment,
    required List<SlashCommandDefinition> commands,
  }) {
    final nextSuggestions = _buildSuggestions(
      text: text,
      commandsEnabled: commandsEnabled,
      hasAttachment: hasAttachment,
      commands: commands,
    );
    final nextSelectedIndex = clampIndex(selectedIndex, nextSuggestions);
    return _copyIfChanged(
      suggestions: nextSuggestions,
      selectedIndex: nextSelectedIndex,
      dismissedText: dismissedText,
    );
  }

  MessageInputSlashSuggestionState selectNext() {
    if (suggestions.isEmpty) return this;
    return _copyIfChanged(
      suggestions: suggestions,
      selectedIndex: (selectedIndex + 1) % suggestions.length,
      dismissedText: dismissedText,
    );
  }

  MessageInputSlashSuggestionState selectPrevious() {
    if (suggestions.isEmpty) return this;
    return _copyIfChanged(
      suggestions: suggestions,
      selectedIndex:
          (selectedIndex - 1 + suggestions.length) % suggestions.length,
      dismissedText: dismissedText,
    );
  }

  MessageInputSlashSuggestionState selectIndex(int index) {
    return _copyIfChanged(
      suggestions: suggestions,
      selectedIndex: clampIndex(index, suggestions),
      dismissedText: dismissedText,
    );
  }

  MessageInputSlashSuggestionState dismiss({String? text}) {
    return _copyIfChanged(
      suggestions: const <SlashCommandDefinition>[],
      selectedIndex: 0,
      dismissedText: text ?? dismissedText,
    );
  }

  MessageInputSlashSuggestionState applyCompletedText(String text) {
    return _copyIfChanged(
      suggestions: const <SlashCommandDefinition>[],
      selectedIndex: 0,
      dismissedText: text,
    );
  }

  static int clampIndex(int index, List<SlashCommandDefinition> suggestions) {
    if (suggestions.isEmpty) return 0;
    if (index < 0) return 0;
    if (index >= suggestions.length) return suggestions.length - 1;
    return index;
  }

  List<SlashCommandDefinition> _buildSuggestions({
    required String text,
    required bool commandsEnabled,
    required bool hasAttachment,
    required List<SlashCommandDefinition> commands,
  }) {
    if (!commandsEnabled || hasAttachment || text == dismissedText) {
      return const <SlashCommandDefinition>[];
    }
    return filterSlashCommandSuggestions(text, commands);
  }

  MessageInputSlashSuggestionState _copyIfChanged({
    required List<SlashCommandDefinition> suggestions,
    required int selectedIndex,
    required String? dismissedText,
  }) {
    if (_sameSuggestions(this.suggestions, suggestions) &&
        this.selectedIndex == selectedIndex &&
        this.dismissedText == dismissedText) {
      return this;
    }
    return MessageInputSlashSuggestionState(
      suggestions: suggestions,
      selectedIndex: selectedIndex,
      dismissedText: dismissedText,
    );
  }

  static bool _sameSuggestions(
    List<SlashCommandDefinition> previous,
    List<SlashCommandDefinition> next,
  ) {
    if (previous.length != next.length) return false;
    for (var index = 0; index < previous.length; index += 1) {
      if (!identical(previous[index], next[index])) {
        return false;
      }
    }
    return true;
  }
}
