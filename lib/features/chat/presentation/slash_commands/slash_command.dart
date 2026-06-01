import 'dart:async';

enum SlashCommandAction {
  help,
  newConversation,
  clear,
  general,
  coding,
  plan,
  cancel,
  review,
  fix,
  explain,
  test,
  promptTemplate,
}

enum SlashCommandArgumentRequirement { none, optional, required }

extension SlashCommandArgumentRequirementX on SlashCommandArgumentRequirement {
  bool get acceptsArguments => this != SlashCommandArgumentRequirement.none;

  bool get requiresArguments =>
      this == SlashCommandArgumentRequirement.required;
}

class SlashCommandDefinition {
  const SlashCommandDefinition({
    required this.name,
    required this.action,
    required this.description,
    this.aliases = const <String>[],
    this.argumentHint,
    this.argumentRequirement = SlashCommandArgumentRequirement.none,
    this.enabledWhileLoading = false,
    this.promptTemplateId,
  });

  final String name;
  final SlashCommandAction action;
  final String description;
  final List<String> aliases;
  final String? argumentHint;
  final SlashCommandArgumentRequirement argumentRequirement;
  final bool enabledWhileLoading;
  final String? promptTemplateId;

  bool get acceptsArguments => argumentRequirement.acceptsArguments;

  bool get requiresArguments => argumentRequirement.requiresArguments;

  String get usage {
    final hint = argumentHint;
    if (hint == null || hint.isEmpty) {
      return '/$name';
    }
    return '/$name $hint';
  }

  bool matchesName(String value) {
    final normalized = value.toLowerCase();
    return name.toLowerCase() == normalized ||
        aliases.any((alias) => alias.toLowerCase() == normalized);
  }
}

class SlashCommandInvocation {
  const SlashCommandInvocation({
    required this.definition,
    required this.rawInput,
    required this.commandName,
    required this.args,
  });

  final SlashCommandDefinition definition;
  final String rawInput;
  final String commandName;
  final String args;
}

class SlashCommandExecutionResult {
  const SlashCommandExecutionResult({
    this.clearInput = true,
    this.feedbackMessage,
    this.promptToSend,
  });

  final bool clearInput;
  final String? feedbackMessage;
  final String? promptToSend;

  static const handled = SlashCommandExecutionResult();

  factory SlashCommandExecutionResult.sendPrompt(
    String prompt, {
    String? feedbackMessage,
  }) {
    return SlashCommandExecutionResult(
      feedbackMessage: feedbackMessage,
      promptToSend: prompt,
    );
  }

  factory SlashCommandExecutionResult.keepInput({String? feedbackMessage}) {
    return SlashCommandExecutionResult(
      clearInput: false,
      feedbackMessage: feedbackMessage,
    );
  }
}

typedef SlashCommandHandler =
    FutureOr<SlashCommandExecutionResult> Function(
      SlashCommandInvocation invocation,
    );

class ParsedSlashCommand {
  const ParsedSlashCommand({required this.commandName, required this.args});

  final String commandName;
  final String args;
}

ParsedSlashCommand? parseSlashCommandInput(String input) {
  if (input.isEmpty || !input.startsWith('/')) {
    return null;
  }

  final trimmedRight = input.trimRight();
  if (trimmedRight == '/') {
    return null;
  }

  final withoutSlash = trimmedRight.substring(1);
  final firstSpace = withoutSlash.indexOf(RegExp(r'\s'));
  final commandName = firstSpace == -1
      ? withoutSlash
      : withoutSlash.substring(0, firstSpace);
  if (commandName.isEmpty || !looksLikeSlashCommandName(commandName)) {
    return null;
  }

  final args = firstSpace == -1
      ? ''
      : withoutSlash.substring(firstSpace + 1).trim();
  return ParsedSlashCommand(commandName: commandName, args: args);
}

bool looksLikeSlashCommandName(String commandName) {
  return RegExp(r'^[A-Za-z0-9:_-]+$').hasMatch(commandName);
}

SlashCommandDefinition? findSlashCommand(
  String commandName,
  List<SlashCommandDefinition> commands,
) {
  for (final command in commands) {
    if (command.matchesName(commandName)) {
      return command;
    }
  }
  return null;
}

List<SlashCommandDefinition> filterSlashCommandSuggestions(
  String input,
  List<SlashCommandDefinition> commands,
) {
  if (!input.startsWith('/')) {
    return const <SlashCommandDefinition>[];
  }

  final trimmedRight = input.trimRight();
  if (trimmedRight.contains(RegExp(r'\s')) && !trimmedRight.endsWith('/')) {
    final parsed = parseSlashCommandInput(trimmedRight);
    if (parsed != null && parsed.args.isNotEmpty) {
      return const <SlashCommandDefinition>[];
    }
  }

  final query = trimmedRight.length <= 1
      ? ''
      : trimmedRight.substring(1).trim().toLowerCase();
  if (query.isEmpty) {
    return commands;
  }

  if (!looksLikeSlashCommandName(query)) {
    return const <SlashCommandDefinition>[];
  }

  return commands
      .where((command) {
        final name = command.name.toLowerCase();
        final description = command.description.toLowerCase();
        return name.startsWith(query) ||
            name.contains(query) ||
            description.contains(query) ||
            command.aliases.any((alias) {
              final normalizedAlias = alias.toLowerCase();
              return normalizedAlias.startsWith(query) ||
                  normalizedAlias.contains(query);
            });
      })
      .toList(growable: false);
}
