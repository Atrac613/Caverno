import 'dart:convert';

import '../entities/chat_turn_owner.dart';
import '../entities/conversation_workflow.dart';
import '../entities/mcp_tool_entity.dart';
import 'ask_user_question_turn_cache.dart';
import 'immutable_json_snapshot.dart';
import 'tool_terminal_response_policy.dart';

// ChatNotifier decomposition collaborator: ask-user-question-policy

const String askUserQuestionToolName = 'ask_user_question';

/// Exact identity of one user-question tool invocation.
final class AskUserQuestionOperationIdentity {
  AskUserQuestionOperationIdentity({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
  }) {
    if (toolCallId.trim().isEmpty) {
      throw ArgumentError.value(
        toolCallId,
        'toolCallId',
        'A non-empty tool call ID is required.',
      );
    }
    if (toolName != askUserQuestionToolName) {
      throw ArgumentError.value(
        toolName,
        'toolName',
        'The canonical ask_user_question tool name is required.',
      );
    }
  }

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;

  @override
  bool operator ==(Object other) {
    return other is AskUserQuestionOperationIdentity &&
        other.owner == owner &&
        other.toolCallId == toolCallId &&
        other.toolName == toolName;
  }

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName);
}

/// One immutable option that can be presented for a user question.
final class AskUserQuestionOption {
  const AskUserQuestionOption({
    required this.id,
    required this.label,
    this.description = '',
    this.preview = '',
  });

  final String id;
  final String label;
  final String description;
  final String preview;
}

/// One immutable option selected in an answer.
final class AskUserQuestionSelection {
  const AskUserQuestionSelection({
    required this.id,
    required this.label,
    this.description = '',
    this.preview = '',
  });

  final String id;
  final String label;
  final String description;
  final String preview;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    if (description.trim().isNotEmpty) 'description': description.trim(),
    if (preview.trim().isNotEmpty) 'preview': preview.trim(),
  };
}

/// Immutable answer returned by the question presentation boundary.
final class AskUserQuestionAnswer {
  AskUserQuestionAnswer({
    required this.question,
    required List<AskUserQuestionSelection> selectedOptions,
    this.otherText = '',
  }) : selectedOptions = List<AskUserQuestionSelection>.unmodifiable(
         selectedOptions,
       );

  final String question;
  final List<AskUserQuestionSelection> selectedOptions;
  final String otherText;

  bool get hasAnswer =>
      selectedOptions.isNotEmpty || otherText.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'question': question,
    'selected': selectedOptions.map((option) => option.toJson()).toList(),
    if (otherText.trim().isNotEmpty) 'other': otherText.trim(),
    'answer': [
      ...selectedOptions.map((option) => option.label),
      if (otherText.trim().isNotEmpty) otherText.trim(),
    ].join('; '),
  };
}

/// Immutable presentation request detached from notifier and UI state.
final class AskUserQuestionRequest {
  AskUserQuestionRequest({
    required this.question,
    required this.help,
    required List<AskUserQuestionOption> options,
    required this.allowMultiple,
    required this.allowOther,
    required this.otherPlaceholder,
  }) : options = List<AskUserQuestionOption>.unmodifiable(options);

  final String question;
  final String help;
  final List<AskUserQuestionOption> options;
  final bool allowMultiple;
  final bool allowOther;
  final String otherPlaceholder;
}

/// Owner-tagged completion returned by the question presentation boundary.
final class AskUserQuestionPortResult {
  const AskUserQuestionPortResult({required this.identity, this.answer});

  final AskUserQuestionOperationIdentity identity;
  final AskUserQuestionAnswer? answer;
}

/// Presents and completes a question for one exact tool invocation.
abstract interface class AskUserQuestionPort {
  Future<AskUserQuestionPortResult> ask(
    AskUserQuestionOperationIdentity identity,
    AskUserQuestionRequest request,
  );
}

/// Immutable raw tool input and saved-task snapshot for one owning turn.
final class AskUserQuestionToolInput {
  AskUserQuestionToolInput({
    required ChatTurnOwner owner,
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required this.savedTask,
  }) : identity = AskUserQuestionOperationIdentity(
         owner: owner,
         toolCallId: toolCallId,
         toolName: toolName,
       ),
       arguments = ImmutableJsonSnapshot.freezeMap(arguments);

  final AskUserQuestionOperationIdentity identity;
  final Map<String, dynamic> arguments;
  final ConversationWorkflowTask? savedTask;

  ChatTurnOwner get owner => identity.owner;
  String get toolCallId => identity.toolCallId;
  String get toolName => identity.toolName;
}

/// Validates, reuses, asks, and maps `ask_user_question` tool results.
final class AskUserQuestionPolicy {
  AskUserQuestionPolicy({
    required AskUserQuestionPort port,
    required AskUserQuestionTurnCache cache,
    required ToolTerminalResponsePolicy terminalResponsePolicy,
  }) : _port = port,
       _cache = cache,
       _terminalResponsePolicy = terminalResponsePolicy;

  static const String _savedTaskAnswer =
      'Continue autonomously with the current saved task. Run its '
      'saved validation before moving to the next task.';
  static const String _reusedAnswerNote =
      'The user already answered ask_user_question during this turn. '
      'Continue using the existing answer and do not ask again.';

  final AskUserQuestionPort _port;
  final AskUserQuestionTurnCache _cache;
  final ToolTerminalResponsePolicy _terminalResponsePolicy;

  Future<McpToolResult> handle(AskUserQuestionToolInput input) async {
    final question = _trimStringArgument(input.arguments, 'question');
    if (question.isEmpty) {
      return _failure(input.toolName, 'question is required');
    }

    final options = parseOptions(input.arguments['options']);
    final savedTask = input.savedTask;
    if (savedTask != null &&
        _terminalResponsePolicy.isSavedWorkflowContinuationQuestion(question)) {
      final validationCommand = savedTask.validationCommand.trim();
      return McpToolResult(
        toolName: input.toolName,
        result: jsonEncode({
          'status': 'policy_resolved',
          'question': question,
          'answer': _savedTaskAnswer,
          'saved_task_id': savedTask.id,
          if (validationCommand.isNotEmpty)
            'saved_validation_command': validationCommand,
        }),
        isSuccess: true,
      );
    }

    final optionLabels = options.map((option) => option.label);
    final existingResult = _cache.findReusable(
      owner: input.owner,
      question: question,
      optionLabels: optionLabels,
    );
    if (existingResult != null) {
      return buildRepeatedResult(existingResult);
    }

    final allowOther = input.arguments['allow_other'] as bool? ?? true;
    if (options.isEmpty && !allowOther) {
      return _failure(
        input.toolName,
        'at least one option or allow_other is required',
      );
    }

    final response = await _port.ask(
      input.identity,
      AskUserQuestionRequest(
        question: question,
        help: _trimStringArgument(input.arguments, 'help'),
        options: options,
        allowMultiple: input.arguments['allow_multiple'] as bool? ?? false,
        allowOther: allowOther,
        otherPlaceholder: _trimStringArgument(
          input.arguments,
          'other_placeholder',
        ),
      ),
    );
    if (response.identity != input.identity) {
      throw StateError('Ask user question response identity mismatch.');
    }

    final answer = response.answer;
    final result = answer == null || !answer.hasAnswer
        ? McpToolResult(
            toolName: input.toolName,
            result: jsonEncode({'question': question, 'status': 'cancelled'}),
            isSuccess: false,
            errorMessage: 'User dismissed the question',
          )
        : McpToolResult(
            toolName: input.toolName,
            result: jsonEncode({'status': 'answered', ...answer.toJson()}),
            isSuccess: true,
          );
    _cache.store(
      owner: input.owner,
      question: question,
      optionLabels: optionLabels,
      result: result,
    );
    return result;
  }

  List<AskUserQuestionOption> parseOptions(Object? rawOptions) {
    if (rawOptions is! List) return const [];

    final options = <AskUserQuestionOption>[];
    final usedIds = <String>{};
    for (
      var index = 0;
      index < rawOptions.length && options.length < 8;
      index++
    ) {
      final rawOption = rawOptions[index];
      String label;
      String id;
      String description = '';
      String preview = '';

      if (rawOption is String) {
        label = rawOption.trim();
        id = _optionId(label, index);
      } else if (rawOption is Map) {
        label = (rawOption['label'] as String?)?.trim() ?? '';
        id = (rawOption['id'] as String?)?.trim().isNotEmpty == true
            ? (rawOption['id'] as String).trim()
            : _optionId(label, index);
        description = (rawOption['description'] as String?)?.trim() ?? '';
        preview = (rawOption['preview'] as String?)?.trim() ?? '';
      } else {
        continue;
      }

      if (label.isEmpty) continue;
      var uniqueId = id;
      var suffix = 2;
      while (!usedIds.add(uniqueId)) {
        uniqueId = '$id-$suffix';
        suffix++;
      }
      options.add(
        AskUserQuestionOption(
          id: uniqueId,
          label: _clipText(label, 120),
          description: _clipText(description, 500),
          preview: _clipText(preview, 2000),
        ),
      );
    }
    return List<AskUserQuestionOption>.unmodifiable(options);
  }

  McpToolResult buildRepeatedResult(McpToolResult previous) {
    final decoded = _decodeJsonObject(previous.result);
    final result = decoded == null
        ? previous.result
        : jsonEncode({...decoded, 'reused': true, 'note': _reusedAnswerNote});
    return McpToolResult(
      toolName: previous.toolName,
      result: result,
      isSuccess: previous.isSuccess,
      errorMessage: previous.errorMessage,
    );
  }

  String _optionId(String label, int index) {
    final normalized = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (normalized.isNotEmpty) {
      return normalized.length > 40 ? normalized.substring(0, 40) : normalized;
    }
    return 'option-${index + 1}';
  }

  String _clipText(String value, int maxLength) {
    final normalized = value.trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 3)}...';
  }

  McpToolResult _failure(String toolName, String message) {
    return McpToolResult(
      toolName: toolName,
      result: '',
      isSuccess: false,
      errorMessage: message,
    );
  }
}

String _trimStringArgument(Map<String, dynamic> arguments, String key) {
  return (arguments[key] as String?)?.trim() ?? '';
}

Map<String, dynamic>? _decodeJsonObject(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {
    return null;
  }
  return null;
}
