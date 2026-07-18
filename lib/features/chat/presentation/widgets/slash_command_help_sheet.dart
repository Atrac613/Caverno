import 'package:flutter/material.dart';

import '../slash_commands/slash_command.dart';

class SlashCommandHelpSheet extends StatelessWidget {
  const SlashCommandHelpSheet({
    super.key,
    required this.title,
    required this.commands,
  });

  final String title;
  final List<SlashCommandDefinition> commands;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        shrinkWrap: true,
        itemCount: commands.length + 1,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(title, style: theme.textTheme.titleLarge),
            );
          }
          final command = commands[index - 1];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.terminal),
            title: Text(command.usage),
            subtitle: Text(command.description),
          );
        },
      ),
    );
  }
}
