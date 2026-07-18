import 'package:caverno/features/chat/presentation/slash_commands/slash_command.dart';
import 'package:caverno/features/chat/presentation/slash_commands/slash_command_catalog.dart';
import 'package:caverno/features/chat/presentation/slash_commands/slash_command_prompt_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildSlashCommandCatalog', () {
    test('preserves built-in order and appends custom definitions', () {
      const custom = SlashCommandPromptTemplate(
        id: 'custom-id',
        name: 'custom',
        description: 'Custom description',
        template: 'Custom {input}',
        aliases: ['mine'],
        argumentHint: '<value>',
      );

      final commands = buildSlashCommandCatalog(
        text: _text,
        customPromptTemplates: const [custom],
      );

      expect(commands.map((command) => command.name), [
        'help',
        'new',
        'clear',
        'general',
        'coding',
        'plan',
        'goal',
        'cancel',
        'feedback',
        'agent',
        'review',
        'fix',
        'explain',
        'test',
        'skill',
        'custom',
      ]);
      expect(commands.first.description, 'chat.slash_help_desc');
      expect(commands.first.enabledWhileLoading, isTrue);
      expect(commands[7].enabledWhileLoading, isTrue);
      expect(commands[4].aliases, ['code']);
      expect(commands[9].aliases, ['worktree', 'worktree-agent']);
      expect(commands[9].argumentHint, '<task> [--run] [--verify <command>]');
      expect(commands.last.description, 'Custom description');
      expect(commands.last.aliases, ['mine']);
      expect(commands.last.promptTemplateId, 'custom-id');
    });
  });

  group('resolveSlashCommandPromptTemplate', () {
    test('maps legacy actions and gives built-ins ID precedence', () {
      const duplicate = SlashCommandPromptTemplate(
        id: 'review',
        name: 'custom-review',
        description: 'Custom review',
        template: 'Wrong {input}',
      );
      final invocation = _invocation(
        action: SlashCommandAction.review,
        name: 'review',
        args: 'target.dart',
      );

      final resolved = resolveSlashCommandPromptTemplate(invocation, const [
        duplicate,
      ]);

      expect(resolved, same(builtInSlashCommandPromptTemplates.first));
      expect(
        resolved!.expand(args: invocation.args, commandName: 'review'),
        contains('target.dart'),
      );
    });

    test('resolves a custom prompt-template ID', () {
      const custom = SlashCommandPromptTemplate(
        id: 'custom-id',
        name: 'custom',
        description: 'Custom',
        template: 'Custom {input}',
      );
      final invocation = _invocation(
        action: SlashCommandAction.promptTemplate,
        name: 'custom',
        args: 'value',
        promptTemplateId: 'custom-id',
      );

      expect(
        resolveSlashCommandPromptTemplate(invocation, const [custom]),
        same(custom),
      );
    });

    test('returns null when an action has no resolvable template ID', () {
      final invocation = _invocation(
        action: SlashCommandAction.promptTemplate,
        name: 'missing',
        args: '',
      );

      expect(resolveSlashCommandPromptTemplate(invocation, const []), isNull);
    });
  });
}

SlashCommandInvocation _invocation({
  required SlashCommandAction action,
  required String name,
  required String args,
  String? promptTemplateId,
}) {
  return SlashCommandInvocation(
    definition: SlashCommandDefinition(
      name: name,
      action: action,
      description: name,
      promptTemplateId: promptTemplateId,
    ),
    rawInput: '/$name $args',
    commandName: name,
    args: args,
  );
}

String _text(String key, {Map<String, String>? namedArgs}) => key;
