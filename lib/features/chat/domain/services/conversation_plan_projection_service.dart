import '../entities/conversation_workflow.dart';
import 'conversation_plan_hash.dart';

class ConversationPlanProjection {
  const ConversationPlanProjection({
    required this.workflowStage,
    required this.workflowSpec,
    required this.sourceHash,
    required this.derivedAt,
  });

  final ConversationWorkflowStage workflowStage;
  final ConversationWorkflowSpec workflowSpec;
  final String sourceHash;
  final DateTime derivedAt;
}

class ConversationPlanValidationResult {
  const ConversationPlanValidationResult._({
    this.projection,
    this.errorMessage,
  });

  const ConversationPlanValidationResult.valid(ConversationPlanProjection value)
    : this._(projection: value);

  const ConversationPlanValidationResult.invalid(String message)
    : this._(errorMessage: message);

  final ConversationPlanProjection? projection;
  final String? errorMessage;

  bool get isValid => projection != null;

  ConversationWorkflowStage? get workflowStage => projection?.workflowStage;

  ConversationWorkflowSpec? get workflowSpec => projection?.workflowSpec;

  List<ConversationWorkflowTask> get previewTasks =>
      workflowSpec?.tasks ?? const <ConversationWorkflowTask>[];
}

class ConversationPlanProjectionService {
  ConversationPlanProjectionService._();

  static const _taskIdReuseThreshold = 0.75;

  static ConversationPlanProjection deriveExecutionProjection({
    required String approvedMarkdown,
    DateTime? derivedAt,
    bool requireTasks = false,
  }) {
    final normalizedMarkdown = approvedMarkdown.trim();
    if (normalizedMarkdown.isEmpty) {
      throw const FormatException('approved plan document is empty');
    }
    if (!normalizedMarkdown.startsWith('# Plan')) {
      throw const FormatException('plan document must start with "# Plan"');
    }

    final sections = _parseSections(normalizedMarkdown);
    if (!sections.containsKey('Stage')) {
      throw const FormatException('plan document must include a Stage section');
    }
    final stage = _parseWorkflowStage(sections['Stage']);
    final goal = _joinFreeformSection(sections['Goal']);
    final constraints = _parseBulletSection(sections['Constraints']);
    final acceptanceCriteria = _parseBulletSection(
      sections['Acceptance Criteria'],
    );
    final openQuestions = _parseBulletSection(sections['Open Questions']);
    final taskParseResult = _parseTasks(
      sections['Tasks'],
      requireTasks: requireTasks,
    );
    if (taskParseResult.errorMessage != null) {
      throw FormatException(taskParseResult.errorMessage!);
    }
    final tasks = taskParseResult.tasks;

    final workflowSpec = ConversationWorkflowSpec(
      goal: goal,
      constraints: constraints,
      acceptanceCriteria: acceptanceCriteria,
      openQuestions: openQuestions,
      tasks: tasks,
    );

    final recognized =
        stage != ConversationWorkflowStage.idle ||
        workflowSpec.hasContent ||
        sections.isNotEmpty;
    if (!recognized) {
      throw const FormatException(
        'approved plan document did not contain recognizable sections',
      );
    }

    return ConversationPlanProjection(
      workflowStage: stage,
      workflowSpec: workflowSpec,
      sourceHash: computeSourceHash(normalizedMarkdown),
      derivedAt: derivedAt ?? DateTime.now(),
    );
  }

  static ConversationPlanValidationResult validateDocument({
    required String markdown,
    bool requireTasks = false,
  }) {
    try {
      return ConversationPlanValidationResult.valid(
        deriveExecutionProjection(
          approvedMarkdown: markdown,
          requireTasks: requireTasks,
        ),
      );
    } on FormatException catch (error) {
      final message = error.message.toString().trim();
      return ConversationPlanValidationResult.invalid(
        message.isEmpty ? 'plan document could not be parsed' : message,
      );
    }
  }

  static ConversationWorkflowSpec stabilizeTaskIds({
    required List<ConversationWorkflowTask> previousTasks,
    required ConversationWorkflowSpec workflowSpec,
  }) {
    if (previousTasks.isEmpty || workflowSpec.tasks.isEmpty) {
      return workflowSpec;
    }

    final remainingCandidates = previousTasks.indexed
        .map((entry) => _TaskCandidate(index: entry.$1, task: entry.$2))
        .toList(growable: true);
    final stabilizedTasks = <ConversationWorkflowTask>[];

    for (final entry in workflowSpec.tasks.indexed) {
      final nextIndex = entry.$1;
      final nextTask = entry.$2;
      final bestMatch = _pickBestTaskCandidate(
        nextTask: nextTask,
        nextIndex: nextIndex,
        candidates: remainingCandidates,
      );

      if (bestMatch == null) {
        stabilizedTasks.add(nextTask);
        continue;
      }

      remainingCandidates.remove(bestMatch);
      stabilizedTasks.add(nextTask.copyWith(id: bestMatch.task.id));
    }

    return workflowSpec.copyWith(tasks: stabilizedTasks);
  }

  static String computeSourceHash(String markdown) {
    return computeConversationPlanHash(markdown);
  }

  static String replaceWorkflowStage({
    required String markdown,
    required ConversationWorkflowStage workflowStage,
  }) {
    final normalizedMarkdown = markdown.trimRight();
    if (normalizedMarkdown.isEmpty) {
      return normalizedMarkdown;
    }

    final lines = normalizedMarkdown.split('\n');
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].trim() != '## Stage') {
        continue;
      }

      for (
        var valueIndex = index + 1;
        valueIndex < lines.length;
        valueIndex++
      ) {
        final line = lines[valueIndex].trim();
        if (line.isEmpty) {
          continue;
        }
        if (line.startsWith('## ')) {
          lines.insert(valueIndex, workflowStage.name);
          return lines.join('\n');
        }
        lines[valueIndex] = workflowStage.name;
        return lines.join('\n');
      }

      lines.add(workflowStage.name);
      return lines.join('\n');
    }

    return [normalizedMarkdown, '', '## Stage', workflowStage.name].join('\n');
  }

  static Map<String, List<String>> _parseSections(String markdown) {
    final sections = <String, List<String>>{};
    String? currentHeading;

    for (final rawLine in markdown.split('\n')) {
      final line = rawLine.trimRight();
      if (line.startsWith('## ')) {
        currentHeading = line.substring(3).trim();
        sections.putIfAbsent(currentHeading, () => <String>[]);
        continue;
      }
      if (currentHeading == null) {
        continue;
      }
      sections[currentHeading]!.add(line);
    }

    return sections;
  }

  static ConversationWorkflowStage _parseWorkflowStage(List<String>? lines) {
    final value =
        lines
            ?.map((line) => line.trim())
            .firstWhere((line) => line.isNotEmpty, orElse: () => '') ??
        '';

    if (value.isEmpty) {
      throw const FormatException('plan document must define a workflow stage');
    }

    return switch (value.toLowerCase()) {
      'idle' => ConversationWorkflowStage.idle,
      'clarify' => ConversationWorkflowStage.clarify,
      'plan' => ConversationWorkflowStage.plan,
      'tasks' => ConversationWorkflowStage.tasks,
      'implement' => ConversationWorkflowStage.implement,
      'review' => ConversationWorkflowStage.review,
      _ => throw FormatException(
        'plan document contains an unknown stage "$value"',
      ),
    };
  }

  static String _joinFreeformSection(List<String>? lines) {
    if (lines == null) {
      return '';
    }

    return lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  static List<String> _parseBulletSection(List<String>? lines) {
    if (lines == null) {
      return const [];
    }

    return lines
        .map((line) => line.trim())
        .where((line) => line.startsWith('- '))
        .map((line) => line.substring(2).trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  static _TaskParseResult _parseTasks(
    List<String>? lines, {
    required bool requireTasks,
  }) {
    if (lines == null) {
      return requireTasks
          ? const _TaskParseResult.error(
              'plan document must include a Tasks section',
            )
          : const _TaskParseResult(tasks: <ConversationWorkflowTask>[]);
    }

    final tasks = <ConversationWorkflowTask>[];
    _TaskDraft? currentTask;
    var sawContent = false;

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      sawContent = true;

      final headingMatch = RegExp(r'^(\d+)\.\s+(.+)$').firstMatch(trimmed);
      if (headingMatch != null) {
        if (currentTask != null) {
          tasks.add(currentTask.build());
        }
        currentTask = _TaskDraft(
          id: _deriveTaskId(headingMatch.group(2)!.trim(), tasks.length + 1),
          title: headingMatch.group(2)!.trim(),
        );
        continue;
      }

      if (currentTask == null) {
        return const _TaskParseResult.error(
          'task details must follow a numbered task heading',
        );
      }

      final detail = trimmed.startsWith('- ')
          ? trimmed.substring(2).trim()
          : null;
      if (detail == null || detail.isEmpty) {
        return const _TaskParseResult.error(
          'task details must start with "- "',
        );
      }

      if (detail.startsWith('Status:')) {
        currentTask.status = _parseTaskStatus(detail.substring(7).trim());
        continue;
      }
      if (detail.startsWith('Target files:')) {
        currentTask.targetFiles = detail
            .substring(13)
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        continue;
      }
      if (detail.startsWith('Validation:')) {
        currentTask.validationCommand = detail.substring(11).trim();
        continue;
      }
      if (detail.startsWith('Notes:')) {
        currentTask.notes = detail.substring(6).trim();
        continue;
      }
      return _TaskParseResult.error(
        'unsupported task detail "$detail"; use Status, Target files, Validation, or Notes',
      );
    }

    if (currentTask != null) {
      tasks.add(currentTask.build());
    }

    if (requireTasks && tasks.isEmpty) {
      return const _TaskParseResult.error(
        'plan document must include at least one numbered task',
      );
    }
    if (sawContent && tasks.isEmpty) {
      return const _TaskParseResult.error(
        'plan document Tasks section could not be parsed into tasks',
      );
    }

    return _TaskParseResult(tasks: tasks);
  }

  static ConversationWorkflowTaskStatus _parseTaskStatus(String rawStatus) {
    final normalized = rawStatus.trim().toLowerCase();
    return switch (normalized) {
      'inprogress' ||
      'in progress' => ConversationWorkflowTaskStatus.inProgress,
      'completed' || 'done' => ConversationWorkflowTaskStatus.completed,
      'blocked' => ConversationWorkflowTaskStatus.blocked,
      _ => ConversationWorkflowTaskStatus.pending,
    };
  }

  static String _deriveTaskId(String title, int index) {
    final normalizedTitle = title.trim();
    final hashedTitle = computeConversationPlanHash(
      normalizedTitle.isEmpty ? 'task-$index' : normalizedTitle,
    );
    return 'derived-task-$index-${hashedTitle.substring(0, 6)}';
  }

  static _TaskCandidate? _pickBestTaskCandidate({
    required ConversationWorkflowTask nextTask,
    required int nextIndex,
    required List<_TaskCandidate> candidates,
  }) {
    _TaskCandidate? bestCandidate;
    var bestScore = 0.0;

    for (final candidate in candidates) {
      final score = _scoreTaskMatch(
        previousTask: candidate.task,
        previousIndex: candidate.index,
        nextTask: nextTask,
        nextIndex: nextIndex,
      );
      if (score <= bestScore) {
        continue;
      }
      bestScore = score;
      bestCandidate = candidate;
    }

    if (bestScore < _taskIdReuseThreshold) {
      return null;
    }
    return bestCandidate;
  }

  static double _scoreTaskMatch({
    required ConversationWorkflowTask previousTask,
    required int previousIndex,
    required ConversationWorkflowTask nextTask,
    required int nextIndex,
  }) {
    final titleSimilarity = _taskTitleSimilarity(
      previousTask.title,
      nextTask.title,
    );
    if (titleSimilarity == 0) {
      return 0;
    }

    var score = titleSimilarity;
    if (_normalizedText(previousTask.validationCommand) ==
            _normalizedText(nextTask.validationCommand) &&
        _normalizedText(previousTask.validationCommand).isNotEmpty) {
      score += 0.15;
    }
    if (_normalizedSet(
      previousTask.targetFiles,
    ).intersection(_normalizedSet(nextTask.targetFiles)).isNotEmpty) {
      score += 0.1;
    }
    if (previousTask.status == nextTask.status) {
      score += 0.05;
    }
    if (previousIndex == nextIndex) {
      score += 0.05;
    }
    return score;
  }

  static double _taskTitleSimilarity(String previousTitle, String nextTitle) {
    final previousTokens = _titleTokens(previousTitle);
    final nextTokens = _titleTokens(nextTitle);
    if (previousTokens.isEmpty || nextTokens.isEmpty) {
      return 0;
    }
    final overlap = previousTokens.intersection(nextTokens).length;
    if (overlap == 0) {
      return 0;
    }
    final union = previousTokens.union(nextTokens).length;
    return overlap / union;
  }

  static Set<String> _titleTokens(String title) {
    return title
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .map((token) => token.trim())
        .where(
          (token) => token.length >= 3 && !_ignoredTitleTokens.contains(token),
        )
        .toSet();
  }

  static String _normalizedText(String value) => value.trim().toLowerCase();

  static Set<String> _normalizedSet(Iterable<String> values) {
    return values
        .map(_normalizedText)
        .where((value) => value.isNotEmpty)
        .toSet();
  }
}

const _ignoredTitleTokens = <String>{
  'the',
  'and',
  'for',
  'with',
  'from',
  'into',
  'that',
  'this',
  'task',
  'step',
};

class _TaskDraft {
  _TaskDraft({required this.id, required this.title});

  final String id;
  final String title;
  ConversationWorkflowTaskStatus status =
      ConversationWorkflowTaskStatus.pending;
  List<String> targetFiles = const [];
  String validationCommand = '';
  String notes = '';

  ConversationWorkflowTask build() {
    return ConversationWorkflowTask(
      id: id,
      title: title,
      status: status,
      targetFiles: targetFiles,
      validationCommand: validationCommand,
      notes: notes,
    );
  }
}

class _TaskCandidate {
  const _TaskCandidate({required this.index, required this.task});

  final int index;
  final ConversationWorkflowTask task;
}

class _TaskParseResult {
  const _TaskParseResult({required this.tasks, this.errorMessage});

  const _TaskParseResult.error(String message)
    : this(tasks: const <ConversationWorkflowTask>[], errorMessage: message);

  final List<ConversationWorkflowTask> tasks;
  final String? errorMessage;
}
