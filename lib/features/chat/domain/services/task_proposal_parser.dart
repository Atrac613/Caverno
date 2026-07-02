import 'package:uuid/uuid.dart';

import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';
import '../../presentation/providers/chat_state.dart';
import 'proposal_parsing_text_utils.dart';
import 'workflow_proposal_parser.dart';
import 'workflow_task_proposal_quality_service.dart';

class TaskProposalParser {
  TaskProposalParser({
    required WorkflowTaskProposalQualityService qualityService,
    String Function()? createId,
    void Function()? onJsonRepair,
    WorkflowProposalParser? workflowProposalParser,
  }) : _qualityService = qualityService,
       _createId = createId ?? _defaultCreateId,
       _jsonExtractor = ProposalJsonExtractor(onJsonRepair: onJsonRepair),
       _workflowProposalParser =
           workflowProposalParser ??
           WorkflowProposalParser(
             qualityService: qualityService,
             onJsonRepair: onJsonRepair,
           );

  final WorkflowTaskProposalQualityService _qualityService;
  final String Function() _createId;
  final ProposalJsonExtractor _jsonExtractor;
  final WorkflowProposalParser _workflowProposalParser;

  static String _defaultCreateId() => const Uuid().v4();

  WorkflowTaskProposalDraft? parse(String rawContent) {
    final normalizedContent = ProposalParsingTextUtils.normalizeProposalContent(
      rawContent,
    );
    final decoded = _jsonExtractor.extractJsonMap(normalizedContent);
    final fromJson = decoded == null ? null : parseTaskProposalMap(decoded);
    if (fromJson != null) {
      return fromJson;
    }
    return parseTaskProposalFromSections(normalizedContent);
  }

  WorkflowTaskProposalDraft? parseWithFallback(String rawContent) {
    final direct = parse(rawContent);
    final looseJson = parseTaskProposalFromLooseJson(rawContent);
    if (direct != null) {
      if (looseJson != null && looseJson.tasks.length > direct.tasks.length) {
        return looseJson;
      }
      return direct;
    }

    if (looseJson != null) {
      return looseJson;
    }

    final reasoningContent =
        ProposalParsingTextUtils.extractProposalReasoningContent(rawContent);
    if (reasoningContent.isEmpty) {
      return null;
    }

    final fromReasoning = parse(reasoningContent);
    if (fromReasoning != null &&
        _qualityService.isReasoningTaskProposalPlausible(fromReasoning)) {
      return fromReasoning;
    }

    final structuredReasoning =
        ProposalParsingTextUtils.extractStructuredTaskProposalReasoning(
          reasoningContent,
        );
    if (structuredReasoning.isNotEmpty) {
      final sanitized = parse(structuredReasoning);
      if (sanitized != null &&
          _qualityService.isReasoningTaskProposalPlausible(sanitized)) {
        return sanitized;
      }
    }

    final inlineReasoning = parseTaskProposalFromInlineReasoningPlan(
      reasoningContent,
    );
    if (inlineReasoning != null &&
        _qualityService.isReasoningTaskProposalPlausible(inlineReasoning)) {
      return inlineReasoning;
    }

    final inlineVisible = parseTaskProposalFromInlineReasoningPlan(
      ProposalParsingTextUtils.normalizeProposalContent(rawContent),
    );
    if (inlineVisible != null &&
        _qualityService.isReasoningTaskProposalPlausible(inlineVisible)) {
      return inlineVisible;
    }
    return null;
  }

  WorkflowTaskProposalDraft? buildTruncationFallback({
    required Conversation currentConversation,
    required String rawContent,
    required bool projectLooksEmpty,
    ConversationWorkflowSpec? workflowSpecOverride,
  }) {
    final reasoningContent =
        ProposalParsingTextUtils.extractProposalReasoningContent(rawContent);
    final visibleContent = ProposalParsingTextUtils.normalizeProposalContent(
      rawContent,
    );
    final workflowSpec =
        workflowSpecOverride ?? currentConversation.effectiveWorkflowSpec;
    final rawGoal = workflowSpec.goal.trim().isNotEmpty
        ? workflowSpec.goal.trim()
        : _workflowProposalParser.deriveWorkflowFallbackGoalFromConversation(
            currentConversation,
          );
    if (rawGoal == null || rawGoal.isEmpty) {
      return null;
    }

    final inferredTasks = _qualityService
        .buildHeuristicTaskProposalFallbackTasks(
          contextLines: <String>[
            rawGoal,
            ...workflowSpec.constraints,
            ...workflowSpec.acceptanceCriteria,
            ...workflowSpec.openQuestions,
            reasoningContent,
            visibleContent,
          ],
          projectLooksEmpty: projectLooksEmpty,
        );
    if (inferredTasks.isEmpty) {
      return null;
    }

    return WorkflowTaskProposalDraft(tasks: inferredTasks);
  }

  WorkflowTaskProposalDraft? parseTaskProposalMap(
    Map<String, dynamic> decoded,
  ) {
    final rawTasks = decoded['tasks'] ?? decoded['taskList'] ?? decoded['タスク'];
    if (rawTasks is! List) return null;

    final tasks = <ConversationWorkflowTask>[];
    for (final entry in rawTasks.take(6)) {
      if (entry is! Map) continue;
      final item = Map<String, dynamic>.from(entry);
      final title = ProposalParsingTextUtils.asCleanString(
        item['title'] ?? item['task'] ?? item['taskTitle'] ?? item['タスク名'],
      );
      if (title.isEmpty) continue;
      tasks.add(
        ConversationWorkflowTask(
          id: _createId(),
          title: title,
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: ProposalParsingTextUtils.asStringList(
            item['targetFiles'] ?? item['files'] ?? item['対象ファイル'],
          ),
          validationCommand: ProposalParsingTextUtils.asCleanString(
            item['validationCommand'] ?? item['validation'] ?? item['確認コマンド'],
          ),
          notes: ProposalParsingTextUtils.asCleanString(
            item['notes'] ?? item['memo'] ?? item['メモ'],
          ),
        ),
      );
    }

    final sanitizedTasks = _qualityService.sanitizeTaskProposalTasks(tasks);
    if (sanitizedTasks.isEmpty) return null;
    return WorkflowTaskProposalDraft(tasks: sanitizedTasks);
  }

  WorkflowTaskProposalDraft? parseTaskProposalFromLooseJson(String rawContent) {
    final titlePattern = RegExp(
      r'''["']?(?:title|task|taskTitle|タスク名)["']?\s*:\s*(?:"([^"]+)"|'([^']+)')''',
      caseSensitive: false,
      dotAll: true,
    );
    final titleMatches = titlePattern
        .allMatches(rawContent)
        .toList(growable: false);
    if (titleMatches.isEmpty) {
      return null;
    }

    final tasks = <ConversationWorkflowTask>[];
    for (
      var index = 0;
      index < titleMatches.length && tasks.length < 6;
      index++
    ) {
      final match = titleMatches[index];
      final rawTitle = (match.group(1) ?? match.group(2) ?? '').trim();
      if (rawTitle.isEmpty) {
        continue;
      }

      final fragmentStart = rawContent.lastIndexOf('{', match.start);
      final safeStart = fragmentStart >= 0 ? fragmentStart : match.start;
      final safeEnd = index + 1 < titleMatches.length
          ? titleMatches[index + 1].start
          : rawContent.length;
      final fragment = rawContent.substring(safeStart, safeEnd).trim();

      tasks.add(
        ConversationWorkflowTask(
          id: _createId(),
          title: rawTitle,
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: ProposalParsingTextUtils.extractLooseJsonStringList(
            fragment,
            keys: const ['targetFiles', 'files', '対象ファイル'],
          ),
          validationCommand:
              ProposalParsingTextUtils.extractLooseJsonScalar(
                fragment,
                keys: const ['validationCommand', 'validation', '確認コマンド'],
              ) ??
              '',
          notes:
              ProposalParsingTextUtils.extractLooseJsonScalar(
                fragment,
                keys: const ['notes', 'memo', 'メモ'],
              ) ??
              '',
        ),
      );
    }

    final sanitizedTasks = _qualityService.sanitizeTaskProposalTasks(tasks);
    if (sanitizedTasks.isEmpty) {
      return null;
    }
    return WorkflowTaskProposalDraft(tasks: sanitizedTasks);
  }

  WorkflowTaskProposalDraft? parseTaskProposalFromSections(String rawContent) {
    final tasks = <ConversationWorkflowTask>[];
    String currentTitle = '';
    final currentTargetFiles = <String>[];
    String currentValidationCommand = '';
    String currentNotes = '';
    String? currentField;

    void commitCurrentTask() {
      final normalizedTitle = currentTitle.trim();
      if (normalizedTitle.isEmpty) return;
      tasks.add(
        ConversationWorkflowTask(
          id: _createId(),
          title: normalizedTitle,
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: List<String>.from(currentTargetFiles),
          validationCommand: currentValidationCommand.trim(),
          notes: currentNotes.trim(),
        ),
      );
      currentTitle = '';
      currentTargetFiles.clear();
      currentValidationCommand = '';
      currentNotes = '';
      currentField = null;
    }

    for (final rawLine in rawContent.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final taskTitle = ProposalParsingTextUtils.matchTaskTitleLine(
        line,
        currentField: currentField,
      );
      if (taskTitle != null) {
        commitCurrentTask();
        currentTitle = taskTitle;
        currentField = null;
        continue;
      }

      final taskField = ProposalParsingTextUtils.matchTaskFieldLine(line);
      if (taskField != null) {
        currentField = taskField.$1;
        final value = ProposalParsingTextUtils.stripMarkdownListMarker(
          taskField.$2,
        );
        if (value.isNotEmpty) {
          switch (currentField) {
            case 'targetFiles':
              currentTargetFiles.add(value);
              break;
            case 'validationCommand':
              currentValidationCommand = value;
              break;
            case 'notes':
              currentNotes = ProposalParsingTextUtils.appendTextValue(
                currentNotes,
                value,
              );
              break;
          }
        }
        continue;
      }

      if (currentTitle.isEmpty || currentField == null) {
        continue;
      }

      final value = ProposalParsingTextUtils.stripMarkdownListMarker(line);
      if (value.isEmpty) continue;
      switch (currentField) {
        case 'targetFiles':
          currentTargetFiles.add(value);
          break;
        case 'validationCommand':
          currentValidationCommand = ProposalParsingTextUtils.appendTextValue(
            currentValidationCommand,
            value,
          );
          break;
        case 'notes':
          currentNotes = ProposalParsingTextUtils.appendTextValue(
            currentNotes,
            value,
          );
          break;
      }
    }

    commitCurrentTask();
    final sanitizedTasks = _qualityService.sanitizeTaskProposalTasks(tasks);
    if (sanitizedTasks.isEmpty) return null;
    return WorkflowTaskProposalDraft(
      tasks: sanitizedTasks.take(6).toList(growable: false),
    );
  }

  WorkflowTaskProposalDraft? parseTaskProposalFromInlineReasoningPlan(
    String rawContent,
  ) {
    final normalizedContent = rawContent.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalizedContent.isEmpty) {
      return null;
    }

    final candidate = ProposalParsingTextUtils.extractInlineTaskPlanCandidate(
      normalizedContent,
    );
    final taskMatches = RegExp(
      r'(?:^|(?<=\s))\d+[.)]\s+',
    ).allMatches(candidate).toList(growable: false);
    if (taskMatches.length < 2) {
      return null;
    }

    final tasks = <ConversationWorkflowTask>[];
    for (var index = 0; index < taskMatches.length; index++) {
      final start = taskMatches[index].end;
      final end = index + 1 < taskMatches.length
          ? taskMatches[index + 1].start
          : candidate.length;
      final rawTitle = candidate.substring(start, end).trim();
      final title = ProposalParsingTextUtils.sanitizeInlineReasoningTaskTitle(
        rawTitle,
      );
      if (title.isEmpty) {
        continue;
      }
      tasks.add(
        ConversationWorkflowTask(
          id: _createId(),
          title: title,
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: const <String>[],
          validationCommand: '',
          notes: '',
        ),
      );
      if (tasks.length == 6) {
        break;
      }
    }

    final sanitizedTasks = _qualityService.sanitizeTaskProposalTasks(tasks);
    if (sanitizedTasks.length < 2) {
      return null;
    }
    return WorkflowTaskProposalDraft(tasks: sanitizedTasks);
  }
}
