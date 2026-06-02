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
      'Preserve the requested outcome and artifact type. Do not convert a request to save, update, inspect, '
      'summarize, or report into creating a script, CLI, app, test, helper, or automation unless the user explicitly asks for that artifact. '
      'For a saved Markdown report request, the goal should be to create or save the report, not to create a script that generates it. '
      'This is already a coding-goal drafting context; do not ask whether the user wants code or a script '
      'when the request names a work product such as a saved Markdown report, parser, CLI, test, or file update. '
      'Example: for "\u6771\u4eac\u306e\u660e\u65e5\u306e\u5929\u6c17\u3092\u8abf\u3079\u3066\u30de\u30fc\u30af\u30c0\u30a6\u30f3\u5f62\u5f0f\u3067\u4fdd\u5b58\u3092", return a suggested goal to save the Tokyo tomorrow weather in Markdown, not a clarification about making a script. '
      'Do not invent files, acceptance criteria, budgets, artifact types, or implementation details.';

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

  static ConversationGoalSuggestion validateSuggestion({
    required ConversationGoalSuggestion suggestion,
    required Conversation conversation,
    String? pendingUserMessage,
    String? clarificationQuestion,
    String? clarificationAnswer,
  }) {
    final contract = _GoalRequestContract.fromContext(
      conversation: conversation,
      pendingUserMessage: pendingUserMessage,
      clarificationQuestion: clarificationQuestion,
      clarificationAnswer: clarificationAnswer,
    );
    if (contract == null) {
      return suggestion;
    }

    switch (suggestion.kind) {
      case ConversationGoalSuggestionKind.needsClarification:
        final question = suggestion.question?.trim() ?? '';
        if (question.isEmpty ||
            _asksUnrequestedImplementationDetail(
              question: question,
              requestText: contract.combinedText,
            )) {
          return ConversationGoalSuggestion.suggested(
            contract.fallbackObjective,
          );
        }
        return suggestion;
      case ConversationGoalSuggestionKind.suggested:
        final objective = suggestion.objective?.trim() ?? '';
        if (objective.isEmpty ||
            _inventsUnrequestedImplementationArtifact(
              objective: objective,
              requestText: contract.combinedText,
            )) {
          return ConversationGoalSuggestion.suggested(
            contract.fallbackObjective,
          );
        }
        return suggestion;
    }
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

  static bool _asksUnrequestedImplementationDetail({
    required String question,
    required String requestText,
  }) {
    return _containsUnrequestedCategory(
      candidate: question,
      requestText: requestText,
      categories: _implementationDetailCategories,
    );
  }

  static bool _inventsUnrequestedImplementationArtifact({
    required String objective,
    required String requestText,
  }) {
    return _containsUnrequestedCategory(
      candidate: objective,
      requestText: requestText,
      categories: _implementationArtifactCategories,
    );
  }

  static bool _containsUnrequestedCategory({
    required String candidate,
    required String requestText,
    required List<List<String>> categories,
  }) {
    final normalizedCandidate = candidate.toLowerCase();
    final normalizedRequest = requestText.toLowerCase();
    for (final category in categories) {
      final candidateMentionsCategory = category.any(
        (term) => _containsCategoryTerm(normalizedCandidate, term),
      );
      if (!candidateMentionsCategory) {
        continue;
      }
      final requestMentionsCategory = category.any(
        (term) => _containsCategoryTerm(normalizedRequest, term),
      );
      if (!requestMentionsCategory) {
        return true;
      }
    }
    return false;
  }

  static bool _containsCategoryTerm(String value, String term) {
    final normalizedTerm = term.toLowerCase();
    if (RegExp(r'^[a-z0-9][a-z0-9 -]*[a-z0-9]$').hasMatch(normalizedTerm)) {
      return RegExp(
        '(^|[^a-z0-9])${RegExp.escape(normalizedTerm)}([^a-z0-9]|\$)',
      ).hasMatch(value);
    }
    return value.contains(normalizedTerm);
  }

  static String encodeForDebug(ConversationGoalSuggestion suggestion) {
    return jsonEncode({
      'kind': suggestion.kind.name,
      if (suggestion.objective != null) 'objective': suggestion.objective,
      if (suggestion.question != null) 'question': suggestion.question,
    });
  }

  static const _implementationArtifactCategories = <List<String>>[
    ['script', '\u30b9\u30af\u30ea\u30d7\u30c8'],
    ['cli', 'command-line', 'command line'],
    ['application', 'app', '\u30a2\u30d7\u30ea'],
    ['test', '\u30c6\u30b9\u30c8'],
    ['helper', '\u30d8\u30eb\u30d1\u30fc'],
    ['automation', 'automate', '\u81ea\u52d5\u5316'],
  ];

  static const _implementationDetailCategories = <List<String>>[
    ..._implementationArtifactCategories,
    ['api'],
    ['file name', 'filename', '\u30d5\u30a1\u30a4\u30eb\u540d'],
    ['path', 'directory', 'folder', '\u4fdd\u5b58\u5148', '\u30d1\u30b9'],
    ['framework', '\u30d5\u30ec\u30fc\u30e0\u30ef\u30fc\u30af'],
    ['library', 'package', '\u30e9\u30a4\u30d6\u30e9\u30ea'],
    [
      'programming language',
      'language',
      '\u30d7\u30ed\u30b0\u30e9\u30df\u30f3\u30b0\u8a00\u8a9e',
      '\u8a00\u8a9e',
    ],
    ['command', '\u30b3\u30de\u30f3\u30c9'],
  ];
}

class _GoalRequestContract {
  const _GoalRequestContract({
    required this.combinedText,
    required this.fallbackObjective,
  });

  final String combinedText;
  final String fallbackObjective;

  static _GoalRequestContract? fromContext({
    required Conversation conversation,
    required String? pendingUserMessage,
    required String? clarificationQuestion,
    required String? clarificationAnswer,
  }) {
    final primaryText = _primaryText(
      conversation: conversation,
      pendingUserMessage: pendingUserMessage,
      clarificationAnswer: clarificationAnswer,
    );
    if (primaryText == null) {
      return null;
    }

    final combinedText = _combinedText(
      conversation: conversation,
      pendingUserMessage: pendingUserMessage,
      clarificationQuestion: clarificationQuestion,
      clarificationAnswer: clarificationAnswer,
    );
    if (!_hasClearGoalContract(combinedText)) {
      return null;
    }

    return _GoalRequestContract(
      combinedText: combinedText,
      fallbackObjective: ConversationGoalSuggestionService._clampObjective(
        _fallbackObjective(primaryText),
      ),
    );
  }

  static String? _primaryText({
    required Conversation conversation,
    required String? pendingUserMessage,
    required String? clarificationAnswer,
  }) {
    final clarification = clarificationAnswer?.trim();
    if (clarification != null && clarification.isNotEmpty) {
      return clarification;
    }
    final pending = pendingUserMessage?.trim();
    if (pending != null && pending.isNotEmpty) {
      return pending;
    }
    final latestUserMessage = conversation.messages.reversed
        .where((message) => message.role == MessageRole.user)
        .map((message) => message.content.trim())
        .where((content) => content.isNotEmpty)
        .firstOrNull;
    if (latestUserMessage != null) {
      return latestUserMessage;
    }
    final workflowGoal = conversation.effectiveWorkflowSpec.goal.trim();
    return workflowGoal.isEmpty ? null : workflowGoal;
  }

  static String _combinedText({
    required Conversation conversation,
    required String? pendingUserMessage,
    required String? clarificationQuestion,
    required String? clarificationAnswer,
  }) {
    final parts = <String>[
      conversation.effectiveWorkflowSpec.goal.trim(),
      ...conversation.messages
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content.trim()),
      pendingUserMessage?.trim() ?? '',
      clarificationQuestion?.trim() ?? '',
      clarificationAnswer?.trim() ?? '',
    ].where((part) => part.isNotEmpty).toList(growable: false);
    return parts.join('\n');
  }

  static bool _hasClearGoalContract(String value) {
    final normalized = value.toLowerCase();
    final hasOutcomeAction = _containsAny(normalized, _outcomeActionTerms);
    final hasWorkProduct = _containsAny(normalized, _workProductTerms);
    final hasMarkdownSaveRequest =
        _containsAny(normalized, _markdownTerms) &&
        _containsAny(normalized, _saveOrReportTerms);
    return hasMarkdownSaveRequest || (hasOutcomeAction && hasWorkProduct);
  }

  static bool _containsAny(String value, List<String> terms) {
    return terms.any(value.contains);
  }

  static String _fallbackObjective(String value) {
    var cleaned = ConversationGoalSuggestionService._cleanLine(
      value,
    ).replaceAll(RegExp('[.!?\\u3002\\uff01\\uff1f]+\$'), '');
    cleaned = cleaned.replaceFirst(
      RegExp('\u4fdd\u5b58\u3092?\$'),
      '\u4fdd\u5b58\u3059\u308b',
    );
    cleaned = cleaned.replaceFirst(
      RegExp('\u4f5c\u6210\u3092?\$'),
      '\u4f5c\u6210\u3059\u308b',
    );
    cleaned = cleaned.replaceFirst(
      RegExp('\u51fa\u529b\u3092?\$'),
      '\u51fa\u529b\u3059\u308b',
    );
    return cleaned;
  }

  static const _outcomeActionTerms = <String>[
    'create',
    'save',
    'update',
    'inspect',
    'summarize',
    'report',
    'write',
    'add',
    'fix',
    'implement',
    'move',
    'refactor',
    'generate',
    'check',
    'output',
    'export',
    '\u4f5c\u6210',
    '\u4f5c\u308b',
    '\u4fdd\u5b58',
    '\u66f4\u65b0',
    '\u4fee\u6b63',
    '\u8abf\u3079',
    '\u8abf\u67fb',
    '\u307e\u3068\u3081',
    '\u8981\u7d04',
    '\u51fa\u529b',
    '\u8ffd\u52a0',
    '\u5b9f\u88c5',
    '\u79fb\u52d5',
  ];

  static const _workProductTerms = <String>[
    ..._markdownTerms,
    'report',
    'file',
    'json',
    'csv',
    'parser',
    'cli',
    'script',
    'test',
    'app',
    'application',
    'ui',
    'document',
    'doc',
    '\u30ec\u30dd\u30fc\u30c8',
    '\u30d5\u30a1\u30a4\u30eb',
    '\u30d1\u30fc\u30b5',
    '\u30b9\u30af\u30ea\u30d7\u30c8',
    '\u30c6\u30b9\u30c8',
    '\u30a2\u30d7\u30ea',
    '\u753b\u9762',
    '\u8a2d\u5b9a',
  ];

  static const _markdownTerms = <String>[
    'markdown',
    '.md',
    '\u30de\u30fc\u30af\u30c0\u30a6\u30f3',
  ];

  static const _saveOrReportTerms = <String>[
    'save',
    'report',
    'file',
    '\u4fdd\u5b58',
    '\u30ec\u30dd\u30fc\u30c8',
    '\u30d5\u30a1\u30a4\u30eb',
  ];
}
