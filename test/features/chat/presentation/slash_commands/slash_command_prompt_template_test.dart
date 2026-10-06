import 'package:caverno/features/chat/presentation/slash_commands/slash_command.dart';
import 'package:caverno/features/chat/presentation/slash_commands/slash_command_prompt_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SlashCommandPromptTemplate', () {
    test('expands input and command placeholders', () {
      const template = SlashCommandPromptTemplate(
        id: 'summarize',
        name: 'summarize',
        description: 'Summarize a target',
        template: 'Command {command}: summarize {input}. Args: {args}',
      );

      expect(
        template.expand(args: '  lib/features/chat  ', commandName: 'sum'),
        'Command sum: summarize lib/features/chat. Args: lib/features/chat',
      );
    });

    test('review supports Git scopes and preserves a custom target', () {
      final template = builtInSlashCommandPromptTemplates.singleWhere(
        (template) => template.id == 'review',
      );

      expect(
        template.argumentRequirement,
        SlashCommandArgumentRequirement.optional,
      );
      expect(
        template.expand(args: '', commandName: 'review'),
        contains('including staged, unstaged, and untracked files'),
      );
      expect(
        template.expand(args: 'base main', commandName: 'review'),
        contains('Review scope: base main'),
      );
      expect(
        template.expand(args: 'commit abc123', commandName: 'review'),
        contains('Review scope: commit abc123'),
      );
      final expanded = template.expand(
        args: 'parser changes',
        commandName: 'review',
      );

      expect(expanded, contains('read-only review'));
      expect(expanded, contains('parser changes'));
      expect(expanded, contains("Respond in the user's current language"));
    });

    test('skill command drives save_skill and accepts optional arguments', () {
      final template = builtInSlashCommandPromptTemplates.singleWhere(
        (template) => template.id == 'skill',
      );

      expect(
        template.argumentRequirement,
        SlashCommandArgumentRequirement.optional,
      );
      expect(template.aliases, contains('save-skill'));

      // Works with no argument (capture the whole conversation).
      final noArgs = template.expand(args: '', commandName: 'skill');
      expect(noArgs, contains('save_skill'));
      expect(noArgs, contains('updates it in place and shows a diff'));

      // And forwards an optional focus/name hint.
      final withArgs = template.expand(
        args: 'iOS Release',
        commandName: 'skill',
      );
      expect(withArgs, contains('iOS Release'));
    });

    test('built-in command names are reserved', () {
      expect(reservedSlashCommandNames, contains('goal'));
      expect(reservedSlashCommandNames, contains('pro'));
      expect(reservedSlashCommandNames, contains('skill'));
      expect(reservedSlashCommandNames, contains('save-skill'));
    });
  });
}
