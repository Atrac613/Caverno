import 'slash_command.dart';

const slashCommandPromptArgumentPlaceholder = '{input}';
const _unset = Object();

class SlashCommandPromptTemplate {
  const SlashCommandPromptTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.template,
    this.aliases = const <String>[],
    this.argumentHint,
    this.argumentRequirement = SlashCommandArgumentRequirement.required,
  });

  factory SlashCommandPromptTemplate.fromJson(Map<String, dynamic> json) {
    return SlashCommandPromptTemplate(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      aliases:
          (json['aliases'] as List<dynamic>?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const <String>[],
      argumentHint: json['argumentHint'] as String?,
      argumentRequirement: _argumentRequirementFromJson(
        json['argumentRequirement'],
      ),
      template: json['template'] as String? ?? '',
    );
  }

  final String id;
  final String name;
  final String description;
  final List<String> aliases;
  final String? argumentHint;
  final SlashCommandArgumentRequirement argumentRequirement;
  final String template;

  SlashCommandPromptTemplate copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? aliases,
    Object? argumentHint = _unset,
    SlashCommandArgumentRequirement? argumentRequirement,
    String? template,
  }) {
    return SlashCommandPromptTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      aliases: aliases ?? this.aliases,
      argumentHint: identical(argumentHint, _unset)
          ? this.argumentHint
          : argumentHint as String?,
      argumentRequirement: argumentRequirement ?? this.argumentRequirement,
      template: template ?? this.template,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'aliases': aliases,
      'argumentHint': argumentHint,
      'argumentRequirement': argumentRequirement.name,
      'template': template,
    };
  }

  SlashCommandDefinition toDefinition({
    String? descriptionOverride,
    bool enabledWhileLoading = false,
  }) {
    return SlashCommandDefinition(
      name: name,
      action: SlashCommandAction.promptTemplate,
      description: descriptionOverride ?? description,
      aliases: aliases,
      argumentHint: argumentHint,
      argumentRequirement: argumentRequirement,
      enabledWhileLoading: enabledWhileLoading,
      promptTemplateId: id,
    );
  }

  String expand({required String args, required String commandName}) {
    return expandSlashCommandPromptTemplate(
      template: template,
      args: args,
      commandName: commandName,
    );
  }
}

const builtInSlashCommandPromptTemplates = <SlashCommandPromptTemplate>[
  SlashCommandPromptTemplate(
    id: 'review',
    name: 'review',
    description: '',
    aliases: ['rev'],
    argumentHint: '<target>',
    template: '''
Review the following code, diff, file path, or implementation request.

Focus on correctness, regressions, edge cases, security, and missing tests. Lead with the most important findings and include concrete next steps.

Target:
{input}

Respond in the user's current language unless they ask otherwise.
''',
  ),
  SlashCommandPromptTemplate(
    id: 'fix',
    name: 'fix',
    description: '',
    argumentHint: '<issue>',
    template: '''
Fix or propose a fix for the following issue.

Identify the likely cause, describe the smallest safe change, and include verification steps. If code changes are needed, be explicit about the files and behavior involved.

Issue:
{input}

Respond in the user's current language unless they ask otherwise.
''',
  ),
  SlashCommandPromptTemplate(
    id: 'explain',
    name: 'explain',
    description: '',
    argumentHint: '<topic>',
    template: '''
Explain the following code, behavior, error, or concept.

Use clear structure, call out assumptions, and include examples when they help.

Topic:
{input}

Respond in the user's current language unless they ask otherwise.
''',
  ),
  SlashCommandPromptTemplate(
    id: 'test',
    name: 'test',
    description: '',
    aliases: ['tests'],
    argumentHint: '<target>',
    template: '''
Add or update tests for the following target.

Focus on observable behavior, important edge cases, and the verification command that should be run.

Target:
{input}

Respond in the user's current language unless they ask otherwise.
''',
  ),
  SlashCommandPromptTemplate(
    id: 'skill',
    name: 'skill',
    description: '',
    aliases: ['save-skill'],
    argumentHint: '[name or focus]',
    argumentRequirement: SlashCommandArgumentRequirement.optional,
    template: '''
Capture a reusable skill from this conversation using the save_skill tool.

Review what we accomplished and distill the durable, repeatable workflow worth reusing — the steps, commands, and gotchas — not the one-off specifics of this session. Optional focus or name from the user: {input}

Call save_skill with a short unique name, a one-line description, a whenToUse hint, and the full instructions as markdown. To edit or merge an existing skill, reuse its exact name (save_skill updates it in place and shows a diff for approval); to duplicate, choose a new name. The user must approve every save.

If no reusable workflow is present yet, say so instead of saving.
''',
  ),
];

final Set<String> reservedSlashCommandNames = {
  'help',
  'new',
  'clear',
  'general',
  'coding',
  'code',
  'plan',
  'goal',
  'cancel',
  for (final template in builtInSlashCommandPromptTemplates) ...[
    template.name,
    ...template.aliases,
  ],
};

String expandSlashCommandPromptTemplate({
  required String template,
  required String args,
  required String commandName,
}) {
  final trimmedArgs = args.trim();
  return template
      .replaceAll('{input}', trimmedArgs)
      .replaceAll('{args}', trimmedArgs)
      .replaceAll('{command}', commandName.trim())
      .trim();
}

SlashCommandPromptTemplate? findSlashCommandPromptTemplate(
  String id,
  Iterable<SlashCommandPromptTemplate> templates,
) {
  for (final template in templates) {
    if (template.id == id) {
      return template;
    }
  }
  return null;
}

SlashCommandArgumentRequirement _argumentRequirementFromJson(Object? value) {
  if (value is String) {
    for (final requirement in SlashCommandArgumentRequirement.values) {
      if (requirement.name == value) {
        return requirement;
      }
    }
  }
  return SlashCommandArgumentRequirement.required;
}
