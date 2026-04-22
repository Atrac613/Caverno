import '../../../../core/utils/content_parser.dart';
import '../entities/coding_project.dart';
import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';
import '../entities/message.dart';
import 'conversation_execution_summary_service.dart';

class ConversationPlanningPromptService {
  ConversationPlanningPromptService._();

  static String buildWorkflowProposalRequest({
    required Conversation currentConversation,
    required List<Message> messages,
    required String languageCode,
    CodingProject? project,
    String? researchContextBlock,
    List<String> selectedDecisionLines = const <String>[],
    String? additionalPlanningContext,
    bool compact = false,
  }) {
    final savedSpec = currentConversation.effectiveWorkflowSpec;
    final savedPlanMarkdown = currentConversation.effectivePlanningDocument;
    final executionDelta = _buildExecutionDeltaBlock(currentConversation);
    final openQuestionDelta = _buildOpenQuestionDeltaBlock(currentConversation);
    final transcript = buildProposalTranscript(messages);
    final buffer = StringBuffer()
      ..writeln('Create a workflow proposal for the current coding thread.')
      ..writeln('Return only a single valid JSON object with no markdown.')
      ..writeln(
        'Write all text fields in ${proposalLanguageName(languageCode)}.',
      )
      ..writeln(
        'Keep JSON keys and workflowStage enum values in English exactly as shown in the schema.',
      )
      ..writeln(
        'Schema: {"kind":"proposal|decision","workflowStage":"clarify|plan|tasks|implement|review","goal":string,"constraints":[string],"acceptanceCriteria":[string],"openQuestions":[string],"decisions":[{"id":string,"question":string,"help":string,"inputMode":"singleChoice|freeText","placeholder":string,"options":[{"id":string,"label":string,"description":string}]}]}',
      )
      ..writeln('Rules:')
      ..writeln('- Prefer concise, high-signal wording.')
      ..writeln(
        '- If a user choice would materially change the plan, return kind="decision" instead of guessing.',
      )
      ..writeln(
        '- Reserve openQuestions for missing facts, unresolved dependencies, or research gaps that cannot be answered as a simple user choice.',
      )
      ..writeln(
        '- In decision mode, return one to three single-choice decisions with two to four mutually exclusive options each.',
      )
      ..writeln(
        '- If the user must answer in their own words instead of picking from known options, return inputMode="freeText" with an empty options array.',
      )
      ..writeln(
        '- Use freeText decisions only when the answer is truly required to shape the initial plan right now. Otherwise, keep the item in openQuestions.',
      )
      ..writeln(
        '- In proposal mode, return kind="proposal" and set decisions to an empty array.',
      )
      ..writeln(
        compact
            ? '- Keep constraints and acceptanceCriteria to at most three items.'
            : '- Keep each list to at most five items.',
      )
      ..writeln(
        compact
            ? '- Keep openQuestions to at most two items and use short phrases.'
            : '- If important information is missing, use openQuestions.',
      )
      ..writeln(
        compact
            ? '- Keep goal to one short sentence and keep the whole response under 220 tokens.'
            : '- Do not include tasks in this response.',
      )
      ..writeln(
        compact
            ? '- Do not include tasks in this response.'
            : '- Keep list items short and easy to review.',
      )
      ..writeln(
        compact
            ? '- If important information is missing, prefer short openQuestions.'
            : '- If important information is missing, use openQuestions.',
      )
      ..writeln(
        '- Do not put yes/no, direct preference choices, or direct user-input prompts into openQuestions when they should be decisions instead.',
      )
      ..writeln('- Never output explanatory prose outside JSON.');

    if (project != null) {
      buffer
        ..writeln()
        ..writeln('Project:')
        ..writeln('- name: ${project.name}')
        ..writeln('- rootPath: ${project.normalizedRootPath}');
    }
    if (currentConversation.hasWorkflowContext) {
      buffer
        ..writeln()
        ..writeln('Current saved workflow:')
        ..writeln('- stage: ${currentConversation.workflowStage.name}')
        ..writeln('- goal: ${savedSpec.goal}')
        ..writeln('- constraints: ${savedSpec.constraints.join(' | ')}')
        ..writeln(
          '- acceptanceCriteria: ${savedSpec.acceptanceCriteria.join(' | ')}',
        )
        ..writeln('- openQuestions: ${savedSpec.openQuestions.join(' | ')}');
    }
    if (savedPlanMarkdown != null) {
      buffer
        ..writeln()
        ..writeln('Saved plan document:')
        ..writeln(_clipProposalPlanDocument(savedPlanMarkdown));
    }
    if (executionDelta != null) {
      buffer
        ..writeln()
        ..writeln('Execution progress:')
        ..writeln(executionDelta);
    }
    if (openQuestionDelta != null) {
      buffer
        ..writeln()
        ..writeln('Open question progress:')
        ..writeln(openQuestionDelta);
    }
    if (researchContextBlock != null &&
        researchContextBlock.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Research context:')
        ..writeln(_clipPlanningResearchContext(researchContextBlock));
    }
    if (selectedDecisionLines.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Selected planning decisions:');
      for (final line in selectedDecisionLines) {
        buffer.writeln('- $line');
      }
    }
    final normalizedPlanningContext = additionalPlanningContext?.trim();
    if (normalizedPlanningContext != null &&
        normalizedPlanningContext.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Requested replan focus:')
        ..writeln(_clipAdditionalPlanningContext(normalizedPlanningContext));
    }

    buffer
      ..writeln()
      ..writeln('Recent conversation:')
      ..writeln(transcript.isEmpty ? '- (empty)' : transcript);

    return buffer.toString().trimRight();
  }

  static String buildTaskProposalRequest({
    required Conversation currentConversation,
    required List<Message> messages,
    required String languageCode,
    CodingProject? project,
    String? researchContextBlock,
    ConversationWorkflowStage? workflowStageOverride,
    ConversationWorkflowSpec? workflowSpecOverride,
    String? additionalPlanningContext,
    bool compact = false,
  }) {
    final savedSpec =
        workflowSpecOverride ?? currentConversation.effectiveWorkflowSpec;
    final savedStage =
        workflowStageOverride ?? currentConversation.workflowStage;
    final savedTasks =
        workflowSpecOverride?.tasks ??
        currentConversation.projectedExecutionTasks;
    final savedPlanMarkdown = currentConversation.effectivePlanningDocument;
    final executionDelta = _buildExecutionDeltaBlock(currentConversation);
    final openQuestionDelta = _buildOpenQuestionDeltaBlock(currentConversation);
    final transcript = buildProposalTranscript(messages);
    final constraints = compact
        ? savedSpec.constraints.take(2).toList(growable: false)
        : savedSpec.constraints;
    final acceptanceCriteria = compact
        ? savedSpec.acceptanceCriteria.take(2).toList(growable: false)
        : savedSpec.acceptanceCriteria;
    final openQuestions = compact
        ? savedSpec.openQuestions.take(2).toList(growable: false)
        : savedSpec.openQuestions;
    final buffer = StringBuffer()
      ..writeln('Create a task proposal for the current coding thread.')
      ..writeln('Return only a single valid JSON object with no markdown.')
      ..writeln(
        'Write all text fields in ${proposalLanguageName(languageCode)}.',
      )
      ..writeln('Keep JSON keys in English exactly as shown in the schema.')
      ..writeln(
        'Schema: {"tasks":[{"title":string,"targetFiles":[string],"validationCommand":string,"notes":string}]}',
      )
      ..writeln('Rules:')
      ..writeln('- Return the full suggested task list for the current thread.')
      ..writeln(
        compact
            ? '- Keep the list to at most four tasks.'
            : '- Keep the list to at most six tasks.',
      )
      ..writeln(
        compact
            ? '- Keep titles concrete, short, and implementation-oriented.'
            : '- Keep titles concrete and implementation-oriented.',
      )
      ..writeln(
        '- Every task title must describe an action the agent can perform immediately.',
      )
      ..writeln(
        '- Do not turn research notes, current-state observations, or repo summaries into task titles.',
      )
      ..writeln(
        '- Do not emit placeholder headings as tasks, such as "Subsequent tasks should involve:" or any heading-like label that only introduces later tasks.',
      )
      ..writeln(
        '- Order tasks by dependency so the first task can start immediately.',
      )
      ..writeln(
        '- If the workspace is empty or nearly empty, put scaffolding or initial file creation before feature tasks.',
      )
      ..writeln(
        '- If the workspace is empty or nearly empty, include at least one concrete implementation or validation follow-up task after scaffolding.',
      )
      ..writeln(
        '- Do not stop at a single generic setup task such as "Initialize project structure" when the user asked for a feature to be built.',
      )
      ..writeln('- Use repo-relative file paths when you can infer them.')
      ..writeln(
        '- For implementation tasks, validationCommand must verify the target file or module directly. Avoid generic checks such as "module importable" or validation that only appends src to sys.path.',
      )
      ..writeln(
        '- For ping or other long-running CLI tasks, validationCommand must be bounded and exit on its own. Prefer one-shot checks such as --help, -c 1, --count 1, or a dedicated verification script instead of commands that can run forever.',
      )
      ..writeln(
        '- For simple Python CLI tasks, prefer Python standard-library or subprocess-based implementations over third-party runtime dependencies unless the user explicitly requests a package.',
      )
      ..writeln(
        compact
            ? '- Keep notes brief and keep the whole response under 180 tokens.'
            : '- validationCommand and notes may be empty strings.',
      )
      ..writeln('- Never output explanatory prose outside JSON.');

    if (project != null) {
      buffer
        ..writeln()
        ..writeln('Project:')
        ..writeln('- name: ${project.name}')
        ..writeln('- rootPath: ${project.normalizedRootPath}');
    }

    buffer
      ..writeln()
      ..writeln('Saved workflow:')
      ..writeln('- stage: ${savedStage.name}')
      ..writeln('- goal: ${savedSpec.goal}')
      ..writeln('- constraints: ${constraints.join(' | ')}')
      ..writeln(
        '- acceptanceCriteria: ${acceptanceCriteria.join(' | ')}',
      )
      ..writeln('- openQuestions: ${openQuestions.join(' | ')}');

    if (savedTasks.isNotEmpty && !compact) {
      buffer.writeln('- existingTasks:');
      for (final task in savedTasks) {
        buffer.writeln(
          '  - [${task.status.name}] ${task.title} | files: ${task.targetFiles.join(', ')} | validate: ${task.validationCommand} | notes: ${task.notes}',
        );
      }
    }
    if (!compact && savedPlanMarkdown != null) {
      buffer
        ..writeln()
        ..writeln('Saved plan document:')
        ..writeln(_clipProposalPlanDocument(savedPlanMarkdown));
    }
    if (!compact && executionDelta != null) {
      buffer
        ..writeln()
        ..writeln('Execution progress:')
        ..writeln(executionDelta);
    }
    if (!compact && openQuestionDelta != null) {
      buffer
        ..writeln()
        ..writeln('Open question progress:')
        ..writeln(openQuestionDelta);
    }
    if (researchContextBlock != null &&
        researchContextBlock.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Research context:')
        ..writeln(_clipPlanningResearchContext(researchContextBlock));
    }
    final normalizedPlanningContext = additionalPlanningContext?.trim();
    if (normalizedPlanningContext != null &&
        normalizedPlanningContext.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Requested replan focus:')
        ..writeln(_clipAdditionalPlanningContext(normalizedPlanningContext));
    }

    buffer
      ..writeln()
      ..writeln('Recent conversation:')
      ..writeln(
        transcript.isEmpty
            ? '- (empty)'
            : compact
            ? _clipCompactProposalTranscript(transcript)
            : transcript,
      );

    return buffer.toString().trimRight();
  }

  static String _clipCompactProposalTranscript(String transcript) {
    final lines = transcript
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(4)
        .toList(growable: false);
    if (lines.isEmpty) {
      return '- (empty)';
    }

    final clipped = lines
        .map((line) => line.length > 140 ? '${line.substring(0, 140)}...' : line)
        .join('\n');
    if (clipped.length <= 420) {
      return clipped;
    }
    return '${clipped.substring(0, 417)}...';
  }

  static String buildProposalTranscript(List<Message> messages) {
    final visibleMessages = messages
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    final tail = visibleMessages.length > 12
        ? visibleMessages.sublist(visibleMessages.length - 12)
        : visibleMessages;
    final buffer = StringBuffer();

    for (final message in tail) {
      final plainText = _extractPlainText(message.content);
      if (plainText.isEmpty) {
        continue;
      }
      final clipped = plainText.length > 500
          ? '${plainText.substring(0, 500)}...'
          : plainText;
      buffer.writeln('- ${message.role.name}: $clipped');
    }

    return buffer.toString().trimRight();
  }

  static String proposalLanguageName(String languageCode) {
    return switch (languageCode) {
      'ja' => 'Japanese',
      'en' => 'English',
      _ => 'English',
    };
  }

  static String? _buildExecutionDeltaBlock(Conversation currentConversation) {
    final projectedTasks = currentConversation.projectedExecutionTasks;
    final progressEntries = currentConversation.effectiveExecutionProgress;
    if (projectedTasks.isEmpty && progressEntries.isEmpty) {
      return null;
    }

    final buffer = StringBuffer();
    if (currentConversation.effectiveExecutionDocument != null) {
      buffer.writeln(
        '- projectionState: ${currentConversation.isWorkflowProjectionFresh
            ? 'fresh'
            : currentConversation.isWorkflowProjectionStale
            ? 'stale'
            : 'unavailable'}',
      );
    }

    final completed = projectedTasks
        .where(
          (task) => task.status == ConversationWorkflowTaskStatus.completed,
        )
        .length;
    final inProgress = projectedTasks
        .where(
          (task) => task.status == ConversationWorkflowTaskStatus.inProgress,
        )
        .length;
    final blocked = projectedTasks
        .where((task) => task.status == ConversationWorkflowTaskStatus.blocked)
        .length;
    final pending = projectedTasks.length - completed - inProgress - blocked;
    buffer.writeln(
      '- taskCounts: pending=$pending, inProgress=$inProgress, completed=$completed, blocked=$blocked',
    );

    if (projectedTasks.isNotEmpty) {
      buffer.writeln('- tasks:');
      for (final task in projectedTasks) {
        final progress = currentConversation.executionProgressForTask(task.id);
        final summary = ConversationExecutionSummaryService.summarize(progress);
        final blockedReason = progress?.normalizedBlockedReason;
        final updatedAt = progress?.updatedAt?.toIso8601String() ?? '';
        final blockedSince = summary.blockedSince?.toIso8601String() ?? '';
        final recentEvents =
            progress?.recentEvents.reversed
                .take(2)
                .toList(growable: false)
                .reversed
                .map((event) {
                  final eventSummary = event.normalizedSummary ?? '';
                  if (eventSummary.isEmpty) {
                    return event.type.name;
                  }
                  return '${event.type.name}: $eventSummary';
                })
                .join(' || ') ??
            '';
        buffer.writeln(
          '  - [${task.status.name}] ${task.title} | files: ${task.targetFiles.join(', ')} | validate: ${task.validationCommand} | summary: ${summary.lastOutcome ?? ''} | validation: ${summary.lastValidation ?? ''} | recentEvents: $recentEvents | blockedReason: ${blockedReason ?? ''} | blockedSince: $blockedSince | updatedAt: $updatedAt',
        );
      }
    }

    return buffer.toString().trimRight();
  }

  static String? _buildOpenQuestionDeltaBlock(
    Conversation currentConversation,
  ) {
    final openQuestions = currentConversation
        .effectiveWorkflowSpec
        .openQuestions
        .where((question) => question.trim().isNotEmpty)
        .toList(growable: false);
    if (openQuestions.isEmpty) {
      return null;
    }

    final buffer = StringBuffer();
    for (final question in openQuestions) {
      final progress = currentConversation.openQuestionProgressForQuestion(
        question,
      );
      final status =
          progress?.status.name ??
          ConversationOpenQuestionStatus.unresolved.name;
      final note = progress?.normalizedNote;
      final updatedAt = progress?.updatedAt?.toIso8601String() ?? '';
      buffer.writeln(
        '- [$status] ${question.trim()} | note: ${note ?? ''} | updatedAt: $updatedAt',
      );
    }

    return buffer.toString().trimRight();
  }

  static String _clipProposalPlanDocument(String markdown) {
    final normalized = markdown.replaceAll(RegExp(r'\s+\n'), '\n').trim();
    if (normalized.length <= 1800) {
      return normalized;
    }
    return '${normalized.substring(0, 1800)}...';
  }

  static String _clipPlanningResearchContext(String context) {
    final normalized = context.replaceAll(RegExp(r'\s+\n'), '\n').trim();
    if (normalized.length <= 1600) {
      return normalized;
    }
    return '${normalized.substring(0, 1600)}...';
  }

  static String _clipAdditionalPlanningContext(String context) {
    final normalized = context.replaceAll(RegExp(r'\s+\n'), '\n').trim();
    if (normalized.length <= 1200) {
      return normalized;
    }
    return '${normalized.substring(0, 1200)}...';
  }

  static String _extractPlainText(String content) {
    final parsed = ContentParser.parse(content);
    final buffer = StringBuffer();
    for (final segment in parsed.segments) {
      if (segment.type == ContentType.text) {
        buffer.write(segment.content);
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
