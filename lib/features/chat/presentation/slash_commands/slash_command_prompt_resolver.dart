import 'slash_command.dart';
import 'slash_command_prompt_template.dart';

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
  if (templateId == null) return null;
  return findSlashCommandPromptTemplate(templateId, [
    ...builtInSlashCommandPromptTemplates,
    ...customPromptTemplates,
  ]);
}
