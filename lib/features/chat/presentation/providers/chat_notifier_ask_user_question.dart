// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierAskUserQuestion on ChatNotifier {
  Future<McpToolResult> _handleAskUserQuestion(
    ToolCallInfo toolCall, {
    int? interactionGeneration,
  }) async {
    final question = _trimStringArgument(toolCall.arguments, 'question');
    if (question.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'question is required',
      );
    }

    final options = _parseAskUserQuestionOptions(toolCall.arguments['options']);
    final savedTask = _currentSavedTaskForToolLoop();
    if (savedTask != null &&
        _terminalToolResponsePolicy.isSavedWorkflowContinuationQuestion(
          question,
        )) {
      appLog(
        '[AskUserQuestion] Resolving saved workflow continuation question '
        'from the execution policy',
      );
      return McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode({
          'status': 'policy_resolved',
          'question': question,
          'answer':
              'Continue autonomously with the current saved task. Run its '
              'saved validation before moving to the next task.',
          'saved_task_id': savedTask.id,
          if (savedTask.validationCommand.trim().isNotEmpty)
            'saved_validation_command': savedTask.validationCommand.trim(),
        }),
        isSuccess: true,
      );
    }
    final existingResult = interactionGeneration == null
        ? null
        : _askUserQuestionTurnCache.findReusable(
            generation: interactionGeneration,
            question: question,
            options: options,
          );
    if (existingResult != null) {
      appLog(
        '[AskUserQuestion] Reusing completed answer for repeated '
        'ask_user_question in the same turn',
      );
      return _buildRepeatedAskUserQuestionResult(existingResult);
    }

    final allowOther = toolCall.arguments['allow_other'] as bool? ?? true;
    if (options.isEmpty && !allowOther) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'at least one option or allow_other is required',
      );
    }

    final answer = await requestAskUserQuestion(
      question: question,
      help: _trimStringArgument(toolCall.arguments, 'help'),
      options: options,
      allowMultiple: toolCall.arguments['allow_multiple'] as bool? ?? false,
      allowOther: allowOther,
      otherPlaceholder: _trimStringArgument(
        toolCall.arguments,
        'other_placeholder',
      ),
      targetConversationId: interactionGeneration == null
          ? null
          : _activeResponseConversationIdForGeneration(interactionGeneration),
    );
    if (answer == null || !answer.hasAnswer) {
      final result = McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode({'question': question, 'status': 'cancelled'}),
        isSuccess: false,
        errorMessage: 'User dismissed the question',
      );
      if (interactionGeneration != null) {
        _askUserQuestionTurnCache.store(
          generation: interactionGeneration,
          question: question,
          options: options,
          result: result,
        );
      }
      return result;
    }

    final result = McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({'status': 'answered', ...answer.toJson()}),
      isSuccess: true,
    );
    if (interactionGeneration != null) {
      _askUserQuestionTurnCache.store(
        generation: interactionGeneration,
        question: question,
        options: options,
        result: result,
      );
    }
    return result;
  }

  McpToolResult _buildRepeatedAskUserQuestionResult(McpToolResult previous) {
    final decoded = _decodeJsonObject(previous.result);
    final result = decoded == null
        ? previous.result
        : jsonEncode({
            ...decoded,
            'reused': true,
            'note':
                'The user already answered ask_user_question during this turn. Continue using the existing answer and do not ask again.',
          });
    return McpToolResult(
      toolName: previous.toolName,
      result: result,
      isSuccess: previous.isSuccess,
      errorMessage: previous.errorMessage,
    );
  }

  Future<AskUserQuestionAnswer?> requestAskUserQuestion({
    required String question,
    required String help,
    required List<AskUserQuestionOption> options,
    required bool allowMultiple,
    required bool allowOther,
    required String otherPlaceholder,
    String? targetConversationId,
  }) {
    final resolvedTargetConversationId =
        targetConversationId ?? _activeResponseConversationId ?? conversationId;
    final existingPending = resolvedTargetConversationId == null
        ? state.pendingAskUserQuestion
        : _pendingAskUserQuestionsByThread[resolvedTargetConversationId];
    if (existingPending != null) {
      appLog('[AskUserQuestion] Ignoring question while another is pending');
      return Future<AskUserQuestionAnswer?>.value();
    }
    final completer = Completer<AskUserQuestionAnswer?>();
    final pending = PendingAskUserQuestion(
      id: const Uuid().v4(),
      conversationId: resolvedTargetConversationId,
      question: question,
      help: help,
      options: options,
      allowMultiple: allowMultiple,
      allowOther: allowOther,
      otherPlaceholder: otherPlaceholder,
      completer: completer,
      origin: _activeInteractionOrigin,
    );
    if (resolvedTargetConversationId != null) {
      _pendingAskUserQuestionsByThread[resolvedTargetConversationId] = pending;
    }
    if (resolvedTargetConversationId == null ||
        conversationId == resolvedTargetConversationId) {
      state = state.copyWith(pendingAskUserQuestion: pending);
    }
    return completer.future;
  }

  void resolveAskUserQuestion({
    required String id,
    AskUserQuestionAnswer? answer,
  }) {
    final pending = state.pendingAskUserQuestion?.id == id
        ? state.pendingAskUserQuestion
        : _pendingAskUserQuestionsByThread.values
              .where((item) => item.id == id)
              .firstOrNull;
    if (pending == null) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(answer);
    }
    final pendingConversationId = pending.conversationId;
    if (pendingConversationId != null) {
      _pendingAskUserQuestionsByThread.remove(pendingConversationId);
    }
    if (state.pendingAskUserQuestion?.id == id) {
      state = state.copyWith(pendingAskUserQuestion: null);
    }
  }

  void _dismissAllPendingAskUserQuestions() {
    final pendingQuestions = <PendingAskUserQuestion>[
      ..._pendingAskUserQuestionsByThread.values,
      if (state.pendingAskUserQuestion != null &&
          !_pendingAskUserQuestionsByThread.values.any(
            (pending) => pending.id == state.pendingAskUserQuestion!.id,
          ))
        state.pendingAskUserQuestion!,
    ];

    for (final pending in pendingQuestions) {
      if (!pending.completer.isCompleted) {
        pending.completer.complete();
      }
    }
    _pendingAskUserQuestionsByThread.clear();
    if (state.pendingAskUserQuestion != null) {
      state = state.copyWith(pendingAskUserQuestion: null);
    }
  }

  List<AskUserQuestionOption> _parseAskUserQuestionOptions(dynamic rawOptions) {
    if (rawOptions is! List) {
      return const [];
    }

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
        id = _askUserQuestionOptionId(label, index);
      } else if (rawOption is Map) {
        label = (rawOption['label'] as String?)?.trim() ?? '';
        id = (rawOption['id'] as String?)?.trim().isNotEmpty == true
            ? (rawOption['id'] as String).trim()
            : _askUserQuestionOptionId(label, index);
        description = (rawOption['description'] as String?)?.trim() ?? '';
        preview = (rawOption['preview'] as String?)?.trim() ?? '';
      } else {
        continue;
      }

      if (label.isEmpty) {
        continue;
      }
      var uniqueId = id;
      var suffix = 2;
      while (!usedIds.add(uniqueId)) {
        uniqueId = '$id-$suffix';
        suffix++;
      }
      options.add(
        AskUserQuestionOption(
          id: uniqueId,
          label: _clipAskUserQuestionText(label, 120),
          description: _clipAskUserQuestionText(description, 500),
          preview: _clipAskUserQuestionText(preview, 2000),
        ),
      );
    }
    return options;
  }

  String _askUserQuestionOptionId(String label, int index) {
    final normalized = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (normalized.isNotEmpty) {
      return normalized.length > 40 ? normalized.substring(0, 40) : normalized;
    }
    return 'option-${index + 1}';
  }

  String _clipAskUserQuestionText(String value, int maxLength) {
    final normalized = value.trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 3)}...';
  }
}

class _AskUserQuestionTurnCache {
  final Map<int, List<_CachedAskUserQuestionResult>> _entriesByGeneration =
      <int, List<_CachedAskUserQuestionResult>>{};

  McpToolResult? findReusable({
    required int generation,
    required String question,
    required List<AskUserQuestionOption> options,
  }) {
    final entries = _entriesByGeneration[generation];
    if (entries == null || entries.isEmpty) {
      return null;
    }

    final normalizedQuestion = _normalizeText(question);
    for (final entry in entries.reversed) {
      if (entry.normalizedQuestion == normalizedQuestion) {
        return entry.result;
      }
    }

    final optionLabels = _normalizedOptionLabels(options);
    if (optionLabels.isEmpty) {
      return null;
    }
    for (final entry in entries.reversed) {
      final canReuseAcrossWording =
          entry.result.isSuccess &&
          (entry.optionLabels.length > 1 || optionLabels.length > 1) &&
          entry.optionLabels.intersection(optionLabels).isNotEmpty;
      if (canReuseAcrossWording) {
        return entry.result;
      }
    }
    return null;
  }

  void store({
    required int generation,
    required String question,
    required List<AskUserQuestionOption> options,
    required McpToolResult result,
  }) {
    final entries = _entriesByGeneration[generation] ??=
        <_CachedAskUserQuestionResult>[];
    entries.add(
      _CachedAskUserQuestionResult(
        normalizedQuestion: _normalizeText(question),
        optionLabels: _normalizedOptionLabels(options),
        result: result,
      ),
    );
  }

  bool anyResult(
    int generation,
    bool Function(McpToolResult result) predicate,
  ) {
    final entries = _entriesByGeneration[generation];
    if (entries == null || entries.isEmpty) {
      return false;
    }
    return entries.map((entry) => entry.result).any(predicate);
  }

  void removeGeneration(int generation) {
    _entriesByGeneration.remove(generation);
  }

  void clear() {
    _entriesByGeneration.clear();
  }

  static Set<String> _normalizedOptionLabels(
    List<AskUserQuestionOption> options,
  ) {
    return options
        .map((option) => _normalizeText(option.label))
        .where((label) => label.isNotEmpty)
        .toSet();
  }

  static String _normalizeText(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}

class _CachedAskUserQuestionResult {
  const _CachedAskUserQuestionResult({
    required this.normalizedQuestion,
    required this.optionLabels,
    required this.result,
  });

  final String normalizedQuestion;
  final Set<String> optionLabels;
  final McpToolResult result;
}
