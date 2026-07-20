import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/slash_commands/slash_command.dart';
import 'package:caverno/features/chat/presentation/widgets/message_input_slash_suggestion_state.dart';

void main() {
  const commands = <SlashCommandDefinition>[
    SlashCommandDefinition(
      name: 'help',
      action: SlashCommandAction.help,
      description: 'Show available slash commands',
    ),
    SlashCommandDefinition(
      name: 'clear',
      action: SlashCommandAction.clear,
      description: 'Clear the current conversation',
    ),
    SlashCommandDefinition(
      name: 'coding',
      action: SlashCommandAction.coding,
      description: 'Switch to coding mode',
      aliases: ['code'],
    ),
  ];

  group('MessageInputSlashSuggestionState', () {
    test('refreshes suggestions when slash commands are available', () {
      final state = MessageInputSlashSuggestionState.empty.refresh(
        text: '/',
        commandsEnabled: true,
        hasAttachment: false,
        commands: commands,
      );

      expect(state.suggestions.map((command) => command.name), [
        'help',
        'clear',
        'coding',
      ]);
      expect(state.selectedIndex, 0);
      expect(state.hasSuggestions, isTrue);
      expect(state.selectedSuggestion.name, 'help');
    });

    test(
      'keeps suggestions empty when disabled or attachments are present',
      () {
        expect(
          MessageInputSlashSuggestionState.empty
              .refresh(
                text: '/',
                commandsEnabled: false,
                hasAttachment: false,
                commands: commands,
              )
              .suggestions,
          isEmpty,
        );
        expect(
          MessageInputSlashSuggestionState.empty
              .refresh(
                text: '/',
                commandsEnabled: true,
                hasAttachment: true,
                commands: commands,
              )
              .suggestions,
          isEmpty,
        );
      },
    );

    test('clamps selected index when the suggestion list shrinks', () {
      final allSuggestions = MessageInputSlashSuggestionState.empty
          .refresh(
            text: '/',
            commandsEnabled: true,
            hasAttachment: false,
            commands: commands,
          )
          .selectIndex(99);

      final filtered = allSuggestions.refresh(
        text: '/cl',
        commandsEnabled: true,
        hasAttachment: false,
        commands: commands,
      );

      expect(allSuggestions.selectedIndex, 2);
      expect(filtered.suggestions.map((command) => command.name), ['clear']);
      expect(filtered.selectedIndex, 0);
    });

    test('wraps selected index through next and previous selection', () {
      final state = MessageInputSlashSuggestionState.empty.refresh(
        text: '/',
        commandsEnabled: true,
        hasAttachment: false,
        commands: commands,
      );

      expect(state.selectPrevious().selectedSuggestion.name, 'coding');
      expect(
        state.selectNext().selectNext().selectNext().selectedSuggestion.name,
        'help',
      );
    });

    test('dismisses current text and suppresses matching suggestions', () {
      final dismissed = MessageInputSlashSuggestionState.empty
          .refresh(
            text: '/cl',
            commandsEnabled: true,
            hasAttachment: false,
            commands: commands,
          )
          .dismiss(text: '/cl');

      final sameText = dismissed.refresh(
        text: '/cl',
        commandsEnabled: true,
        hasAttachment: false,
        commands: commands,
      );
      final differentText = dismissed.refresh(
        text: '/cod',
        commandsEnabled: true,
        hasAttachment: false,
        commands: commands,
      );

      expect(dismissed.suggestions, isEmpty);
      expect(dismissed.selectedIndex, 0);
      expect(sameText.suggestions, isEmpty);
      expect(differentText.suggestions.map((command) => command.name), [
        'coding',
      ]);
    });

    test('applies completed text as dismissed and resets selection', () {
      final completed = MessageInputSlashSuggestionState.empty
          .refresh(
            text: '/',
            commandsEnabled: true,
            hasAttachment: false,
            commands: commands,
          )
          .selectNext()
          .applyCompletedText('/clear ');

      expect(completed.suggestions, isEmpty);
      expect(completed.selectedIndex, 0);
      expect(completed.dismissedText, '/clear ');
      expect(
        completed
            .refresh(
              text: '/clear ',
              commandsEnabled: true,
              hasAttachment: false,
              commands: commands,
            )
            .suggestions,
        isEmpty,
      );
    });

    test('returns the same instance when refresh does not change state', () {
      final state = MessageInputSlashSuggestionState.empty.refresh(
        text: '/cl',
        commandsEnabled: true,
        hasAttachment: false,
        commands: commands,
      );

      expect(
        identical(
          state,
          state.refresh(
            text: '/cl',
            commandsEnabled: true,
            hasAttachment: false,
            commands: commands,
          ),
        ),
        isTrue,
      );
    });
  });
}
