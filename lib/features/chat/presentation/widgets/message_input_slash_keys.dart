// setState is protected, and an extension is not a subclass. The methods
// below are the composer's own, moved out of its file for room rather than
// for reuse, so the ignore is narrower than it looks -- the same shape the
// notifier's part files use.
// ignore_for_file: invalid_use_of_protected_member

part of 'message_input.dart';

/// The slash-command half of the composer's keyboard and suggestion handling.
///
/// A part rather than a separate class: these read `_controller`,
/// `_slashSuggestionState` and `setState` directly, and routing all three
/// through callbacks would add indirection without moving a decision. The move
/// is behaviour-preserving — the mention completion that follows needs room in
/// message_input.dart, and this is the half that was already self-contained.
extension _MessageInputSlashKeys on _MessageInputState {
  void _refreshSlashSuggestions() {
    final nextSlashSuggestionState = _slashSuggestionState.refresh(
      text: _controller.text,
      commandsEnabled: _slashCommandsEnabled,
      hasAttachment: _hasAttachment,
      commands: widget.slashCommands,
    );
    if (identical(nextSlashSuggestionState, _slashSuggestionState)) return;
    setState(() {
      _slashSuggestionState = nextSlashSuggestionState;
    });
  }

  KeyEventResult _handleSlashCommandKey(KeyDownEvent event) {
    // Mentions first: only one list can be open, so this decides which `if`
    // falls through rather than which gesture wins.
    final mention = _handleMentionKey(event);
    if (mention != KeyEventResult.ignored) return mention;
    if (!_slashCommandsEnabled) {
      return KeyEventResult.ignored;
    }

    final hasSuggestions = _slashSuggestionState.hasSuggestions;
    final key = event.logicalKey;

    if (hasSuggestions && key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _slashSuggestionState = _slashSuggestionState.selectNext();
      });
      return KeyEventResult.handled;
    }

    if (hasSuggestions && key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _slashSuggestionState = _slashSuggestionState.selectPrevious();
      });
      return KeyEventResult.handled;
    }

    if (hasSuggestions && key == LogicalKeyboardKey.tab) {
      _applySlashSuggestion(_slashSuggestionState.selectedSuggestion);
      return KeyEventResult.handled;
    }

    if (hasSuggestions && key == LogicalKeyboardKey.escape) {
      setState(() {
        _slashSuggestionState = _slashSuggestionState.dismiss(
          text: _controller.text,
        );
      });
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter) {
      if (_controller.value.composing != TextRange.empty) {
        return KeyEventResult.ignored;
      }
      if (_submitSlashCommandFromComposer(allowSelectedSuggestion: true)) {
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _applySlashSuggestion(SlashCommandDefinition command) {
    final text = '/${command.name} ';
    _setComposerText(text);
    setState(() {
      _slashSuggestionState = _slashSuggestionState.applyCompletedText(text);
    });
  }

  /// Track non-whitespace input so the trailing button can switch modes.
  void _handleTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    _refreshMentionSuggestions();
    final nextSlashSuggestionState = _slashSuggestionState.refresh(
      text: _controller.text,
      commandsEnabled: _slashCommandsEnabled,
      hasAttachment: _hasAttachment,
      commands: widget.slashCommands,
    );
    if (hasText != _hasText ||
        !identical(nextSlashSuggestionState, _slashSuggestionState)) {
      setState(() {
        _hasText = hasText;
        _slashSuggestionState = nextSlashSuggestionState;
      });
    }
  }

  Widget _buildSlashCommandSuggestions(BuildContext context, ThemeData theme) {
    return MessageInputSlashSuggestionList(
      suggestions: _slashSuggestionState.suggestions,
      selectedIndex: _slashSuggestionState.selectedIndex,
      onSelected: (index) {
        setState(() {
          _slashSuggestionState = _slashSuggestionState.selectIndex(index);
        });
        _submitSlashCommandFromComposer(allowSelectedSuggestion: true);
      },
    );
  }
}
