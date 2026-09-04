// setState is protected and an extension is not a State subclass; see the
// slash part for why this is narrower than it looks.
// ignore_for_file: invalid_use_of_protected_member

part of 'message_input.dart';

/// The mention half of the composer's completion handling.
///
/// Addressing and commanding are different gestures, so the two lists are
/// never open at once: `@` only starts an address in first position, and `/`
/// only starts a command there. The key handler tries mentions first for that
/// reason — when one list is open the other is empty, and the order only
/// decides which `if` falls through.
extension _MessageInputMentionKeys on _MessageInputState {
  /// Who this composer can address.
  ///
  /// One target today. When a conversation's participants become addressable
  /// this is where they join, and nothing else changes.
  List<MentionTarget> get _mentionTargets => const [anabasisMentionTarget];

  void _refreshMentionSuggestions() {
    final next = _mentionSuggestionState.refresh(
      text: _controller.text,
      targets: _mentionTargets,
    );
    if (identical(next, _mentionSuggestionState)) return;
    setState(() {
      _mentionSuggestionState = next;
    });
  }

  KeyEventResult _handleMentionKey(KeyDownEvent event) {
    if (!_mentionSuggestionState.hasSuggestions) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _mentionSuggestionState = _mentionSuggestionState.selectNext();
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _mentionSuggestionState = _mentionSuggestionState.selectPrevious();
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _applyMentionSuggestion(_mentionSuggestionState.selectedSuggestion);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _mentionSuggestionState = _mentionSuggestionState.dismiss(
          text: _controller.text,
        );
      });
      return KeyEventResult.handled;
    }
    // Enter is left alone on purpose: a mention is a prefix, not a command, so
    // the message it belongs to is not finished. Completing it with Tab and
    // sending with Enter keeps those two apart.
    return KeyEventResult.ignored;
  }

  void _applyMentionSuggestion(MentionTarget target) {
    _setComposerText(target.insertion);
    setState(() {
      _mentionSuggestionState = _mentionSuggestionState.applyCompletedText(
        target.insertion,
      );
    });
  }

  Widget _buildMentionSuggestions(BuildContext context, ThemeData theme) {
    return MessageInputMentionSuggestionList(
      suggestions: _mentionSuggestionState.suggestions,
      selectedIndex: _mentionSuggestionState.selectedIndex,
      onSelected: (index) => _applyMentionSuggestion(
        _mentionSuggestionState.selectIndex(index).selectedSuggestion,
      ),
    );
  }
}
