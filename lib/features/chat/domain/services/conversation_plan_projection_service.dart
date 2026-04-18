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

class ConversationPlanProjectionService {
  ConversationPlanProjectionService._();

  static ConversationPlanProjection deriveExecutionProjection({
    required String approvedMarkdown,
    DateTime? derivedAt,
  }) {
    final normalizedMarkdown = approvedMarkdown.trim();
    if (normalizedMarkdown.isEmpty) {
      throw const FormatException('approved plan document is empty');
    }

    final sections = _parseSections(normalizedMarkdown);
    final stage = _parseWorkflowStage(sections['Stage']);
    final goal = _joinFreeformSection(sections['Goal']);
    final constraints = _parseBulletSection(sections['Constraints']);
    final acceptanceCriteria = _parseBulletSection(
      sections['Acceptance Criteria'],
    );
    final openQuestions = _parseBulletSection(sections['Open Questions']);
    final tasks = _parseTasks(sections['Tasks']);

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
            .firstWhere(
              (line) => line.isNotEmpty,
              orElse: () => ConversationWorkflowStage.idle.name,
            ) ??
        ConversationWorkflowStage.idle.name;

    return switch (value.toLowerCase()) {
      'clarify' => ConversationWorkflowStage.clarify,
      'plan' => ConversationWorkflowStage.plan,
      'tasks' => ConversationWorkflowStage.tasks,
      'implement' => ConversationWorkflowStage.implement,
      'review' => ConversationWorkflowStage.review,
      _ => ConversationWorkflowStage.idle,
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

  static List<ConversationWorkflowTask> _parseTasks(List<String>? lines) {
    if (lines == null) {
      return const [];
    }

    final tasks = <ConversationWorkflowTask>[];
    _TaskDraft? currentTask;

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }

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
        continue;
      }

      final detail = trimmed.startsWith('- ')
          ? trimmed.substring(2).trim()
          : null;
      if (detail == null || detail.isEmpty) {
        continue;
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
      }
    }

    if (currentTask != null) {
      tasks.add(currentTask.build());
    }

    return tasks;
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
}

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
