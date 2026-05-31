import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/slash_commands/slash_command.dart';

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

  group('parseSlashCommandInput', () {
    test('parses command name and arguments', () {
      final parsed = parseSlashCommandInput('/coding fix the bug');

      expect(parsed, isNotNull);
      expect(parsed!.commandName, 'coding');
      expect(parsed.args, 'fix the bug');
    });

    test('returns null for non-command input', () {
      expect(parseSlashCommandInput('hello /clear'), isNull);
      expect(parseSlashCommandInput(' /clear'), isNull);
      expect(parseSlashCommandInput('/'), isNull);
    });

    test('returns null for path-like slash input', () {
      expect(parseSlashCommandInput('/tmp/file.txt'), isNull);
      expect(parseSlashCommandInput('/Users/example/project'), isNull);
    });
  });

  group('findSlashCommand', () {
    test('finds commands by canonical name and alias', () {
      expect(
        findSlashCommand('coding', commands)?.action,
        SlashCommandAction.coding,
      );
      expect(
        findSlashCommand('code', commands)?.action,
        SlashCommandAction.coding,
      );
    });

    test('returns null for unknown command-looking names', () {
      expect(findSlashCommand('missing', commands), isNull);
    });
  });

  group('filterSlashCommandSuggestions', () {
    test('returns all commands for a bare slash', () {
      expect(
        filterSlashCommandSuggestions(
          '/',
          commands,
        ).map((command) => command.name),
        ['help', 'clear', 'coding'],
      );
    });

    test('filters by command name, alias, and description', () {
      expect(
        filterSlashCommandSuggestions(
          '/cl',
          commands,
        ).map((command) => command.name),
        ['clear'],
      );
      expect(
        filterSlashCommandSuggestions(
          '/code',
          commands,
        ).map((command) => command.name),
        ['coding'],
      );
      expect(
        filterSlashCommandSuggestions(
          '/conversation',
          commands,
        ).map((command) => command.name),
        ['clear'],
      );
    });

    test('does not suggest for arguments or path-like input', () {
      expect(filterSlashCommandSuggestions('/clear now', commands), isEmpty);
      expect(filterSlashCommandSuggestions('/tmp/file.txt', commands), isEmpty);
    });
  });
}
