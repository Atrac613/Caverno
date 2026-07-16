import 'caverno_cli_contract.dart';

final class CavernoCliInvocation {
  const CavernoCliInvocation({
    required this.action,
    required this.outputMode,
    this.command,
    this.conversationCommand,
    this.conversationId,
    this.conversationLimit = 20,
    this.prompt,
    this.promptFile,
    this.projectPath,
    this.baseUrl,
    this.model,
    this.apiKey,
    this.dataDirectory,
  });

  final CavernoCliInvocationAction action;
  final CavernoCliOutputMode outputMode;
  final CavernoCliCommand? command;
  final CavernoCliConversationCommand? conversationCommand;
  final String? conversationId;
  final int conversationLimit;
  final String? prompt;
  final String? promptFile;
  final String? projectPath;
  final String? baseUrl;
  final String? model;
  final String? apiKey;
  final String? dataDirectory;

  bool get isJson => outputMode == CavernoCliOutputMode.json;

  static bool looksLikeCliInvocation(List<String> arguments) {
    if (arguments.isEmpty) {
      return false;
    }
    final first = arguments.first.trim();
    if (first.startsWith('-psn_')) {
      return false;
    }
    return const {
          'chat',
          'coding',
          'plan',
          'conversations',
          '--help',
          '-h',
          '--version',
        }.contains(first) ||
        !first.startsWith('-');
  }

  static CavernoCliInvocation parse(List<String> arguments) {
    if (arguments.isEmpty) {
      throw const CavernoCliFailure(
        code: 'command_required',
        message:
            'A command is required. Use chat, coding, plan, or conversations.',
        exitCode: CavernoCliExitCode.usage,
      );
    }

    if (arguments.length == 1 &&
        (arguments.single == '--help' || arguments.single == '-h')) {
      return const CavernoCliInvocation(
        action: CavernoCliInvocationAction.help,
        outputMode: CavernoCliOutputMode.human,
      );
    }
    if (arguments.length == 1 && arguments.single == '--version') {
      return const CavernoCliInvocation(
        action: CavernoCliInvocationAction.version,
        outputMode: CavernoCliOutputMode.human,
      );
    }

    if (arguments.first == 'conversations') {
      return _parseConversationInvocation(arguments);
    }

    final command = switch (arguments.first) {
      'chat' => CavernoCliCommand.chat,
      'coding' => CavernoCliCommand.coding,
      'plan' => CavernoCliCommand.plan,
      final value => throw CavernoCliFailure(
        code: 'unknown_command',
        message: 'Unknown command: $value',
        exitCode: CavernoCliExitCode.usage,
      ),
    };

    var outputMode = CavernoCliOutputMode.human;
    String? explicitPrompt;
    String? promptFile;
    String? projectPath;
    String? baseUrl;
    String? model;
    String? apiKey;
    String? dataDirectory;
    var help = false;
    var optionsEnded = false;
    final positional = <String>[];

    for (var index = 1; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (optionsEnded) {
        positional.add(argument);
        continue;
      }
      if (argument == '--') {
        optionsEnded = true;
        continue;
      }
      if (argument == '--json') {
        outputMode = CavernoCliOutputMode.json;
        continue;
      }
      if (argument == '--help' || argument == '-h') {
        help = true;
        continue;
      }
      if (!argument.startsWith('-')) {
        positional.add(argument);
        continue;
      }

      final parsed = _parseOption(argument);
      switch (parsed.name) {
        case '--prompt':
          explicitPrompt = _optionValue(arguments, parsed, index: index);
        case '--prompt-file':
          promptFile = _optionValue(arguments, parsed, index: index);
        case '--project':
          projectPath = _optionValue(arguments, parsed, index: index);
        case '--base-url':
          baseUrl = _optionValue(arguments, parsed, index: index);
        case '--model':
          model = _optionValue(arguments, parsed, index: index);
        case '--api-key':
          apiKey = _optionValue(arguments, parsed, index: index);
        case '--data-dir':
          dataDirectory = _optionValue(arguments, parsed, index: index);
        default:
          throw CavernoCliFailure(
            code: 'unknown_flag',
            message: 'Unknown flag: ${parsed.name}',
            exitCode: CavernoCliExitCode.usage,
          );
      }
      if (parsed.inlineValue == null) {
        index += 1;
      }
    }

    if (help) {
      return CavernoCliInvocation(
        action: CavernoCliInvocationAction.help,
        command: command,
        outputMode: outputMode,
      );
    }

    final positionalPrompt = positional.isEmpty ? null : positional.join(' ');
    final explicitSourceCount = <String?>[
      explicitPrompt,
      promptFile,
      positionalPrompt,
    ].where((value) => value != null).length;
    if (explicitSourceCount > 1) {
      throw const CavernoCliFailure(
        code: 'conflicting_input_sources',
        message:
            'Use exactly one of a positional prompt, --prompt, or --prompt-file.',
        exitCode: CavernoCliExitCode.usage,
      );
    }

    if (command == CavernoCliCommand.chat && projectPath != null) {
      throw const CavernoCliFailure(
        code: 'project_not_supported',
        message: '--project is only valid for coding and plan commands.',
        exitCode: CavernoCliExitCode.usage,
      );
    }
    if (command != CavernoCliCommand.chat &&
        (projectPath == null || projectPath.trim().isEmpty)) {
      throw CavernoCliFailure(
        code: 'project_required',
        message: '--project is required for the ${command.name} command.',
        exitCode: CavernoCliExitCode.usage,
      );
    }

    return CavernoCliInvocation(
      action: CavernoCliInvocationAction.run,
      command: command,
      outputMode: outputMode,
      prompt: explicitPrompt ?? positionalPrompt,
      promptFile: promptFile,
      projectPath: projectPath,
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
      dataDirectory: dataDirectory,
    );
  }

  static CavernoCliInvocation _parseConversationInvocation(
    List<String> arguments,
  ) {
    if (arguments.length == 1) {
      throw const CavernoCliFailure(
        code: 'conversation_command_required',
        message:
            'A conversation command is required. Use list, show, or resume.',
        exitCode: CavernoCliExitCode.usage,
      );
    }
    if (arguments.length == 2 &&
        (arguments[1] == '--help' || arguments[1] == '-h')) {
      return const CavernoCliInvocation(
        action: CavernoCliInvocationAction.help,
        outputMode: CavernoCliOutputMode.human,
      );
    }

    final conversationCommand = switch (arguments[1]) {
      'list' => CavernoCliConversationCommand.list,
      'show' => CavernoCliConversationCommand.show,
      'resume' => CavernoCliConversationCommand.resume,
      final value => throw CavernoCliFailure(
        code: 'unknown_conversation_command',
        message: 'Unknown conversation command: $value',
        exitCode: CavernoCliExitCode.usage,
      ),
    };
    var outputMode = CavernoCliOutputMode.human;
    String? dataDirectory;
    String? explicitPrompt;
    String? promptFile;
    String? baseUrl;
    String? model;
    String? apiKey;
    var conversationLimit = 20;
    var limitSpecified = false;
    var help = false;
    var optionsEnded = false;
    final positional = <String>[];

    for (var index = 2; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (optionsEnded) {
        positional.add(argument);
        continue;
      }
      if (argument == '--') {
        optionsEnded = true;
        continue;
      }
      if (argument == '--json') {
        outputMode = CavernoCliOutputMode.json;
        continue;
      }
      if (argument == '--help' || argument == '-h') {
        help = true;
        continue;
      }
      if (!argument.startsWith('-')) {
        positional.add(argument);
        continue;
      }

      final parsed = _parseOption(argument);
      switch (parsed.name) {
        case '--data-dir':
          dataDirectory = _optionValue(arguments, parsed, index: index);
        case '--prompt':
          _requireResumeOption(conversationCommand, parsed.name);
          explicitPrompt = _optionValue(arguments, parsed, index: index);
        case '--prompt-file':
          _requireResumeOption(conversationCommand, parsed.name);
          promptFile = _optionValue(arguments, parsed, index: index);
        case '--base-url':
          _requireResumeOption(conversationCommand, parsed.name);
          baseUrl = _optionValue(arguments, parsed, index: index);
        case '--model':
          _requireResumeOption(conversationCommand, parsed.name);
          model = _optionValue(arguments, parsed, index: index);
        case '--api-key':
          _requireResumeOption(conversationCommand, parsed.name);
          apiKey = _optionValue(arguments, parsed, index: index);
        case '--limit':
          limitSpecified = true;
          final value = _optionValue(arguments, parsed, index: index);
          final parsedLimit = int.tryParse(value);
          if (parsedLimit == null || parsedLimit < 1 || parsedLimit > 200) {
            throw const CavernoCliFailure(
              code: 'invalid_limit',
              message: '--limit must be an integer from 1 through 200.',
              exitCode: CavernoCliExitCode.usage,
            );
          }
          conversationLimit = parsedLimit;
        default:
          throw CavernoCliFailure(
            code: 'unknown_flag',
            message: 'Unknown flag: ${parsed.name}',
            exitCode: CavernoCliExitCode.usage,
          );
      }
      if (parsed.inlineValue == null) {
        index += 1;
      }
    }

    if (help) {
      return CavernoCliInvocation(
        action: CavernoCliInvocationAction.help,
        outputMode: outputMode,
        conversationCommand: conversationCommand,
      );
    }
    if (conversationCommand == CavernoCliConversationCommand.list) {
      if (positional.isNotEmpty) {
        throw const CavernoCliFailure(
          code: 'unexpected_conversation_argument',
          message: 'The conversations list command does not accept an ID.',
          exitCode: CavernoCliExitCode.usage,
        );
      }
      return CavernoCliInvocation(
        action: CavernoCliInvocationAction.conversationList,
        outputMode: outputMode,
        conversationCommand: conversationCommand,
        conversationLimit: conversationLimit,
        dataDirectory: dataDirectory,
      );
    }
    if (limitSpecified) {
      throw const CavernoCliFailure(
        code: 'limit_not_supported',
        message: '--limit is only valid for the conversations list command.',
        exitCode: CavernoCliExitCode.usage,
      );
    }
    if (conversationCommand == CavernoCliConversationCommand.resume) {
      if (positional.isEmpty || positional.first.trim().isEmpty) {
        throw const CavernoCliFailure(
          code: 'conversation_id_required',
          message: 'The conversations resume command requires exactly one ID.',
          exitCode: CavernoCliExitCode.usage,
        );
      }
      final positionalPrompt = positional.length <= 1
          ? null
          : positional.skip(1).join(' ');
      final explicitSourceCount = <String?>[
        explicitPrompt,
        promptFile,
        positionalPrompt,
      ].where((value) => value != null).length;
      if (explicitSourceCount > 1) {
        throw const CavernoCliFailure(
          code: 'conflicting_input_sources',
          message:
              'Use exactly one of a positional prompt, --prompt, or --prompt-file.',
          exitCode: CavernoCliExitCode.usage,
        );
      }
      return CavernoCliInvocation(
        action: CavernoCliInvocationAction.conversationResume,
        outputMode: outputMode,
        conversationCommand: conversationCommand,
        conversationId: positional.first.trim(),
        prompt: explicitPrompt ?? positionalPrompt,
        promptFile: promptFile,
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
        dataDirectory: dataDirectory,
      );
    }
    if (positional.length != 1 || positional.single.trim().isEmpty) {
      throw const CavernoCliFailure(
        code: 'conversation_id_required',
        message: 'The conversations show command requires exactly one ID.',
        exitCode: CavernoCliExitCode.usage,
      );
    }
    return CavernoCliInvocation(
      action: CavernoCliInvocationAction.conversationShow,
      outputMode: outputMode,
      conversationCommand: conversationCommand,
      conversationId: positional.single,
      dataDirectory: dataDirectory,
    );
  }

  static void _requireResumeOption(
    CavernoCliConversationCommand command,
    String option,
  ) {
    if (command == CavernoCliConversationCommand.resume) {
      return;
    }
    throw CavernoCliFailure(
      code: 'unknown_flag',
      message: 'Unknown flag: $option',
      exitCode: CavernoCliExitCode.usage,
    );
  }

  static ({String name, String? inlineValue}) _parseOption(String argument) {
    final equals = argument.indexOf('=');
    if (equals < 0) {
      return (name: argument, inlineValue: null);
    }
    return (
      name: argument.substring(0, equals),
      inlineValue: argument.substring(equals + 1),
    );
  }

  static String _optionValue(
    List<String> arguments,
    ({String name, String? inlineValue}) option, {
    required int index,
  }) {
    final value =
        option.inlineValue ??
        (index + 1 < arguments.length ? arguments[index + 1] : null);
    if (value == null || value.trim().isEmpty) {
      throw CavernoCliFailure(
        code: 'flag_value_required',
        message: '${option.name} requires a non-empty value.',
        exitCode: CavernoCliExitCode.usage,
      );
    }
    return value;
  }
}
