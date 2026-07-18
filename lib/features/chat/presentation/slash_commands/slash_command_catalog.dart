import 'slash_command.dart';
import 'slash_command_prompt_template.dart';

typedef SlashCommandTextResolver =
    String Function(String key, {Map<String, String>? namedArgs});

List<SlashCommandDefinition> buildSlashCommandCatalog({
  required SlashCommandTextResolver text,
  required List<SlashCommandPromptTemplate> customPromptTemplates,
}) {
  return [
    SlashCommandDefinition(
      name: 'help',
      action: SlashCommandAction.help,
      description: text('chat.slash_help_desc'),
      enabledWhileLoading: true,
    ),
    SlashCommandDefinition(
      name: 'new',
      action: SlashCommandAction.newConversation,
      description: text('chat.slash_new_desc'),
    ),
    SlashCommandDefinition(
      name: 'clear',
      action: SlashCommandAction.clear,
      description: text('chat.slash_clear_desc'),
    ),
    SlashCommandDefinition(
      name: 'general',
      action: SlashCommandAction.general,
      description: text('chat.slash_general_desc'),
    ),
    SlashCommandDefinition(
      name: 'coding',
      action: SlashCommandAction.coding,
      description: text('chat.slash_coding_desc'),
      aliases: const ['code'],
    ),
    SlashCommandDefinition(
      name: 'plan',
      action: SlashCommandAction.plan,
      description: text('chat.slash_plan_desc'),
    ),
    SlashCommandDefinition(
      name: 'goal',
      action: SlashCommandAction.goal,
      description: text('chat.slash_goal_desc'),
      argumentHint: '[objective] | pause | resume | clear | auto on|off',
      argumentRequirement: SlashCommandArgumentRequirement.optional,
    ),
    SlashCommandDefinition(
      name: 'cancel',
      action: SlashCommandAction.cancel,
      description: text('chat.slash_cancel_desc'),
      enabledWhileLoading: true,
    ),
    SlashCommandDefinition(
      name: 'feedback',
      action: SlashCommandAction.feedback,
      description: text('chat.slash_feedback_desc'),
      argumentHint: '<feedback>',
      argumentRequirement: SlashCommandArgumentRequirement.required,
    ),
    SlashCommandDefinition(
      name: 'agent',
      action: SlashCommandAction.worktreeAgent,
      description: text('chat.slash_agent_desc'),
      aliases: const ['worktree', 'worktree-agent'],
      argumentHint: '<task> [--run] [--verify <command>]',
      argumentRequirement: SlashCommandArgumentRequirement.required,
    ),
    for (final template in builtInSlashCommandPromptTemplates)
      template.toDefinition(
        descriptionOverride: text('chat.slash_${template.id}_desc'),
      ),
    for (final template in customPromptTemplates) template.toDefinition(),
  ];
}

SlashCommandPromptTemplate? resolveSlashCommandPromptTemplate(
  SlashCommandInvocation invocation,
  List<SlashCommandPromptTemplate> customPromptTemplates,
) {
  final templateId =
      invocation.definition.promptTemplateId ??
      switch (invocation.definition.action) {
        SlashCommandAction.review => 'review',
        SlashCommandAction.fix => 'fix',
        SlashCommandAction.explain => 'explain',
        SlashCommandAction.test => 'test',
        _ => null,
      };
  if (templateId == null) {
    return null;
  }
  return findSlashCommandPromptTemplate(templateId, [
    ...builtInSlashCommandPromptTemplates,
    ...customPromptTemplates,
  ]);
}
