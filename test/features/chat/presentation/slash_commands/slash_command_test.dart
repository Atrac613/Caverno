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
    SlashCommandDefinition(
      name: 'goal',
      action: SlashCommandAction.goal,
      description: 'Show or manage the current coding goal',
      argumentHint: '[objective] | pause | resume | clear',
      argumentRequirement: SlashCommandArgumentRequirement.optional,
    ),
    SlashCommandDefinition(
      name: 'review',
      action: SlashCommandAction.review,
      description: 'Review a target',
      aliases: ['rev'],
      argumentHint: '<target>',
      argumentRequirement: SlashCommandArgumentRequirement.required,
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

    test('parses goal subcommands and multi-word objectives as arguments', () {
      final pause = parseSlashCommandInput('/goal pause');
      final objective = parseSlashCommandInput('/goal pause the deployment');

      expect(pause, isNotNull);
      expect(pause!.commandName, 'goal');
      expect(pause.args, 'pause');
      expect(objective, isNotNull);
      expect(objective!.commandName, 'goal');
      expect(objective.args, 'pause the deployment');
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
      expect(
        findSlashCommand('rev', commands)?.action,
        SlashCommandAction.review,
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
        ['help', 'clear', 'coding', 'goal', 'review'],
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
      expect(
        filterSlashCommandSuggestions(
          '/rev',
          commands,
        ).map((command) => command.name),
        ['review'],
      );
      expect(
        filterSlashCommandSuggestions(
          '/go',
          commands,
        ).map((command) => command.name),
        ['goal'],
      );
    });

    test('does not suggest for arguments or path-like input', () {
      expect(filterSlashCommandSuggestions('/clear now', commands), isEmpty);
      expect(
        filterSlashCommandSuggestions('/review lib/file.dart', commands),
        isEmpty,
      );
      expect(filterSlashCommandSuggestions('/tmp/file.txt', commands), isEmpty);
    });
  });

  group('SlashCommandDefinition', () {
    test('builds command usage with argument hints', () {
      final review = commands.last;

      expect(review.requiresArguments, isTrue);
      expect(review.acceptsArguments, isTrue);
      expect(review.usage, '/review <target>');
      expect(commands.first.usage, '/help');
    });
  });
}
