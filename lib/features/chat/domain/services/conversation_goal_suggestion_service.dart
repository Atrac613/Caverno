import 'dart:convert';

import '../entities/conversation.dart';
import '../entities/message.dart';
import 'memory_extraction_json_parser.dart';

enum ConversationGoalSuggestionKind { suggested, needsClarification }

class ConversationGoalSuggestion {
  const ConversationGoalSuggestion._({
    required this.kind,
    this.objective,
    this.question,
  });

  const ConversationGoalSuggestion.suggested(String objective)
    : this._(
        kind: ConversationGoalSuggestionKind.suggested,
        objective: objective,
      );

  const ConversationGoalSuggestion.needsClarification([String question = ''])
    : this._(
        kind: ConversationGoalSuggestionKind.needsClarification,
        question: question,
      );

  final ConversationGoalSuggestionKind kind;
  final String? objective;
  final String? question;

  bool get hasObjective => (objective ?? '').trim().isNotEmpty;

  bool get hasQuestion => (question ?? '').trim().isNotEmpty;
}

class ConversationGoalSuggestionService {
  const ConversationGoalSuggestionService._();

  static const systemPrompt =
      'You draft focused coding goals for Caverno coding threads. '
      'Return only JSON using this schema: '
      '{"status":"suggested|needs_clarification","objective":string,"question":string}. '
      'Use "suggested" only when the thread clearly implies one concrete coding outcome. '
      'Keep objective to one short sentence, under 140 characters, with no markdown. '
      'Use "needs_clarification" when the target outcome is ambiguous, too broad, or missing. '
      'When clarification is needed, ask exactly one concise question. '
      'Clarification questions must stay at goal level: ask what coding outcome should stay in focus, '
      'not which API, file name, storage path, framework, command, library, or programming language to use. '
      'When the request plus clarification already implies a coding artifact or code change, draft the goal '
      'and leave implementation choices for execution. '
      'This is already a coding-goal drafting context; do not ask whether the user wants code or a script '
      'when the request names a work product such as a saved Markdown report, parser, CLI, test, or file update. '
      'Do not invent files, acceptance criteria, budgets, or implementation details.';

  static bool hasUsefulContext(
    Conversation conversation, {
    String? pendingUserMessage,
    String? clarificationQuestion,
    String? clarificationAnswer,
  }) {
    if ((clarificationQuestion ?? '').trim().isNotEmpty) {
      return true;
    }
    if ((clarificationAnswer ?? '').trim().isNotEmpty) {
      return true;
    }
    if ((pendingUserMessage ?? '').trim().isNotEmpty) {
      return true;
    }

    final workflowGoal = conversation.effectiveWorkflowSpec.goal.trim();
    if (workflowGoal.isNotEmpty) {
      return true;
    }

    return conversation.messages.any((message) {
      return message.role == MessageRole.user &&
          message.content.trim().isNotEmpty;
    });
  }

  static List<Message> buildMessages({
    required Conversation conversation,
    required String languageCode,
    String? pendingUserMessage,
    String? clarificationQuestion,
    String? clarificationAnswer,
    DateTime? now,
    int maxRecentMessages = 12,
  }) {
    final timestamp = now ?? DateTime.now();
    return [
      Message(
        id: 'goal_suggestion_system',
        role: MessageRole.system,
        timestamp: timestamp,
        content: systemPrompt,
      ),
      Message(
        id: 'goal_suggestion_user',
        role: MessageRole.user,
        timestamp: timestamp,
        content: _buildInput(
          conversation: conversation,
          languageCode: languageCode,
          pendingUserMessage: pendingUserMessage,
          clarificationQuestion: clarificationQuestion,
          clarificationAnswer: clarificationAnswer,
          maxRecentMessages: maxRecentMessages,
        ),
      ),
    ];
  }

  static ConversationGoalSuggestion? parse(String rawContent) {
    final parsed = MemoryExtractionJsonParser.parse(rawContent);
    final decoded = parsed?.decoded;
    if (decoded == null) {
      return null;
    }

    final status = _cleanString(
      decoded['status'] ?? decoded['kind'],
    )?.toLowerCase().replaceAll('-', '_');
    final objective = _cleanString(decoded['objective'] ?? decoded['goal']);
    final question = _cleanString(
      decoded['question'] ?? decoded['clarifyingQuestion'],
    );

    if (_isSuggestedStatus(status) && objective != null) {
      return ConversationGoalSuggestion.suggested(_clampObjective(objective));
    }

    if (_isClarificationStatus(status) && question != null) {
      return ConversationGoalSuggestion.needsClarification(question);
    }

    if (objective != null) {
      return ConversationGoalSuggestion.suggested(_clampObjective(objective));
    }

    if (question != null) {
      return ConversationGoalSuggestion.needsClarification(question);
    }

    return null;
  }

  static String _buildInput({
    required Conversation conversation,
    required String languageCode,
    required String? pendingUserMessage,
    required String? clarificationQuestion,
    required String? clarificationAnswer,
    required int maxRecentMessages,
  }) {
    final buffer = StringBuffer()
      ..writeln('Preferred response language code: $languageCode')
      ..writeln('Thread title: ${_cleanLine(conversation.title)}');

    final workflowSpec = conversation.effectiveWorkflowSpec;
    if (workflowSpec.goal.trim().isNotEmpty) {
      buffer.writeln('Saved workflow goal: ${_cleanLine(workflowSpec.goal)}');
    }
    if (workflowSpec.acceptanceCriteria.isNotEmpty) {
      buffer.writeln('Saved acceptance criteria:');
      for (final criterion in workflowSpec.acceptanceCriteria.take(4)) {
        buffer.writeln('- ${_cleanLine(criterion)}');
      }
    }

    final recentMessages = conversation.messages
        .where((message) => message.content.trim().isNotEmpty)
        .toList(growable: false);
    final visibleMessages = recentMessages.length > maxRecentMessages
        ? recentMessages.sublist(recentMessages.length - maxRecentMessages)
        : recentMessages;

    if (visibleMessages.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Recent thread messages:');
      for (final message in visibleMessages) {
        buffer.writeln(
          '- ${message.role.name}: ${_truncate(_cleanLine(message.content), 800)}',
        );
      }
    }
    final pendingMessage = pendingUserMessage?.trim();
    if (pendingMessage != null && pendingMessage.isNotEmpty) {
      if (visibleMessages.isEmpty) {
        buffer.writeln();
        buffer.writeln('Recent thread messages:');
      }
      buffer.writeln(
        '- user (pending send): ${_truncate(_cleanLine(pendingMessage), 800)}',
      );
    }
    final question = clarificationQuestion?.trim();
    final clarification = clarificationAnswer?.trim();
    if (question != null && question.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Goal clarification question asked:');
      buffer.writeln(_truncate(_cleanLine(question), 800));
    }
    if (clarification != null && clarification.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('User clarification answer for the goal:');
      buffer.writeln(_truncate(_cleanLine(clarification), 800));
    }

    buffer
      ..writeln()
      ..writeln(
        'Decide whether there is enough context to prefill a coding goal.',
      );

    return buffer.toString().trimRight();
  }

  static bool _isSuggestedStatus(String? status) {
    return status == 'suggested' || status == 'suggestion' || status == 'goal';
  }

  static bool _isClarificationStatus(String? status) {
    return status == 'needs_clarification' ||
        status == 'clarify' ||
        status == 'ask_user' ||
        status == 'ambiguous';
  }

  static String? _cleanString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _cleanLine(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('\u0000', '')
        .trim();
  }

  static String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength - 3)}...';
  }

  static String _clampObjective(String value) {
    final cleaned = _cleanLine(value);
    if (cleaned.length <= 140) {
      return cleaned;
    }
    return _truncate(cleaned, 140);
  }

  static String encodeForDebug(ConversationGoalSuggestion suggestion) {
    return jsonEncode({
      'kind': suggestion.kind.name,
      if (suggestion.objective != null) 'objective': suggestion.objective,
      if (suggestion.question != null) 'question': suggestion.question,
    });
  }
}
