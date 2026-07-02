import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';
import '../entities/message.dart';
import '../../presentation/providers/chat_state.dart';
import 'proposal_option_extraction.dart';
import 'proposal_parsing_text_utils.dart';
import 'workflow_task_proposal_quality_service.dart';

sealed class WorkflowProposalParseResult {
  const WorkflowProposalParseResult();
}

final class WorkflowProposalParsedDraft extends WorkflowProposalParseResult {
  const WorkflowProposalParsedDraft(this.proposal);

  final WorkflowProposalDraft proposal;
}

final class WorkflowProposalParsedDecisions
    extends WorkflowProposalParseResult {
  const WorkflowProposalParsedDecisions(this.decisions);

  final List<WorkflowPlanningDecision> decisions;
}

class WorkflowProposalParser {
  WorkflowProposalParser({
    required WorkflowTaskProposalQualityService qualityService,
    void Function()? onJsonRepair,
  }) : _qualityService = qualityService,
       _jsonExtractor = ProposalJsonExtractor(onJsonRepair: onJsonRepair);

  final WorkflowTaskProposalQualityService _qualityService;
  final ProposalJsonExtractor _jsonExtractor;

  WorkflowProposalParseResult? parse(String rawContent) {
    final normalizedContent = ProposalParsingTextUtils.normalizeProposalContent(
      rawContent,
    );
    final decoded = _jsonExtractor.extractJsonMap(normalizedContent);
    if (decoded != null) {
      final decisionResponse = parseWorkflowDecisionResponseMap(decoded);
      if (decisionResponse != null) {
        return decisionResponse;
      }
      final proposalResponse = parseWorkflowProposalMap(decoded);
      if (proposalResponse != null) {
        return WorkflowProposalParsedDraft(proposalResponse);
      }
    }
    final proposalFromSections = parseWorkflowProposalFromSections(
      normalizedContent,
    );
    if (proposalFromSections != null) {
      return WorkflowProposalParsedDraft(proposalFromSections);
    }
    final looseProposal = parseWorkflowProposalFromLooseJson(normalizedContent);
    if (looseProposal != null) {
      return WorkflowProposalParsedDraft(looseProposal);
    }
    return null;
  }

  WorkflowProposalParseResult? parseWithFallback(String rawContent) {
    final direct = parse(rawContent);
    if (direct != null) {
      return direct;
    }

    final visibleNarrativeSource =
        ProposalParsingTextUtils.normalizeProposalContent(rawContent);
    if (visibleNarrativeSource.isNotEmpty) {
      final directNarrative = parseWorkflowProposalFromNarrative(
        visibleNarrativeSource,
      );
      if (directNarrative != null) {
        return WorkflowProposalParsedDraft(directNarrative);
      }
    }

    final reasoningContent =
        ProposalParsingTextUtils.extractProposalReasoningContent(rawContent);
    if (reasoningContent.isEmpty) {
      return null;
    }

    final fromReasoning = parse(reasoningContent);
    if (fromReasoning case WorkflowProposalParsedDecisions()) {
      return fromReasoning;
    }
    if (fromReasoning case WorkflowProposalParsedDraft(:final proposal)) {
      if (_qualityService.isReasoningWorkflowProposalPlausible(proposal)) {
        return fromReasoning;
      }
    }

    final structuredReasoning =
        ProposalParsingTextUtils.extractStructuredWorkflowProposalReasoning(
          reasoningContent,
        );
    if (structuredReasoning.isEmpty) {
      return null;
    }
    final sanitized = parse(structuredReasoning);
    if (sanitized case WorkflowProposalParsedDraft(:final proposal)) {
      return _qualityService.isReasoningWorkflowProposalPlausible(proposal)
          ? sanitized
          : null;
    }
    if (sanitized != null) {
      return sanitized;
    }

    final narrative = parseWorkflowProposalFromNarrative(reasoningContent);
    if (narrative != null) {
      return WorkflowProposalParsedDraft(narrative);
    }
    return null;
  }

  WorkflowProposalDraft? buildFallback({
    WorkflowProposalDraft? latestProposal,
    required List<WorkflowPlanningDecision> outstandingDecisions,
  }) {
    final unresolvedQuestions = outstandingDecisions
        .map((decision) => decision.question.trim())
        .where((question) => question.isNotEmpty)
        .toList(growable: false);

    if (latestProposal != null) {
      final mergedOpenQuestions = <String>[
        ...latestProposal.workflowSpec.openQuestions,
      ];
      final existingQuestions = mergedOpenQuestions
          .map(PlanningDecisionPromotion.normalizeWorkflowDecisionText)
          .where((value) => value.isNotEmpty)
          .toSet();

      for (final question in unresolvedQuestions) {
        final normalized =
            PlanningDecisionPromotion.normalizeWorkflowDecisionText(question);
        if (normalized.isEmpty || existingQuestions.contains(normalized)) {
          continue;
        }
        existingQuestions.add(normalized);
        mergedOpenQuestions.add(question);
      }

      return WorkflowProposalDraft(
        workflowStage: mergedOpenQuestions.isNotEmpty
            ? ConversationWorkflowStage.clarify
            : latestProposal.workflowStage,
        workflowSpec: latestProposal.workflowSpec.copyWith(
          openQuestions: mergedOpenQuestions.take(6).toList(growable: false),
        ),
      );
    }

    if (unresolvedQuestions.isEmpty) {
      return null;
    }

    return WorkflowProposalDraft(
      workflowStage: ConversationWorkflowStage.clarify,
      workflowSpec: ConversationWorkflowSpec(
        openQuestions: unresolvedQuestions.take(6).toList(growable: false),
      ),
    );
  }

  WorkflowProposalDraft? buildTruncationFallback({
    required Conversation currentConversation,
    required String rawContent,
    required List<WorkflowPlanningDecisionAnswer> decisionAnswers,
  }) {
    final reasoningContent =
        ProposalParsingTextUtils.extractProposalReasoningContent(rawContent);
    final visibleContent = ProposalParsingTextUtils.normalizeProposalContent(
      rawContent,
    );
    final goal =
        extractNarrativeWorkflowGoal(reasoningContent) ??
        extractNarrativeWorkflowGoal(visibleContent) ??
        deriveWorkflowFallbackGoalFromConversation(currentConversation);
    if (goal == null || goal.trim().isEmpty) {
      return null;
    }

    final constraints = <String>[
      ...extractNarrativeWorkflowList(
        reasoningContent,
        keys: const ['constraints', 'guardrails'],
      ),
      ...decisionAnswers
          .map((answer) {
            final question = answer.question.trim();
            final optionLabel = answer.optionLabel.trim();
            if (question.isEmpty || optionLabel.isEmpty) {
              return '';
            }
            return 'Resolved decision: $question -> $optionLabel';
          })
          .where((line) => line.isNotEmpty),
    ].take(3).toList(growable: false);

    final acceptanceCriteria = <String>[
      ...extractNarrativeWorkflowList(
        reasoningContent,
        keys: const ['acceptance criteria', 'completion criteria'],
      ),
    ];
    if (acceptanceCriteria.isEmpty) {
      acceptanceCriteria.add(
        'Produce a concrete saved task plan that implements and validates the requested feature.',
      );
      if (decisionAnswers.isNotEmpty) {
        acceptanceCriteria.add(
          'Reflect the resolved planning decisions in the saved tasks.',
        );
      }
    }

    final proposal = WorkflowProposalDraft(
      workflowStage: ConversationWorkflowStage.plan,
      workflowSpec: ConversationWorkflowSpec(
        goal: goal,
        constraints: constraints,
        acceptanceCriteria: acceptanceCriteria.take(3).toList(growable: false),
      ),
    );
    return proposal.workflowSpec.hasContent ? proposal : null;
  }

  ConversationWorkflowStage? parseWorkflowStage(Object? rawStage) {
    final normalized = rawStage?.toString().trim().toLowerCase();
    return switch (normalized) {
      'clarify' => ConversationWorkflowStage.clarify,
      'clarification' => ConversationWorkflowStage.clarify,
      'question' => ConversationWorkflowStage.clarify,
      'questions' => ConversationWorkflowStage.clarify,
      '確認' => ConversationWorkflowStage.clarify,
      'plan' => ConversationWorkflowStage.plan,
      'planning' => ConversationWorkflowStage.plan,
      '計画' => ConversationWorkflowStage.plan,
      'tasks' => ConversationWorkflowStage.tasks,
      'task' => ConversationWorkflowStage.tasks,
      'tasking' => ConversationWorkflowStage.tasks,
      'タスク' => ConversationWorkflowStage.tasks,
      'タスク化' => ConversationWorkflowStage.tasks,
      'implement' => ConversationWorkflowStage.implement,
      'implementation' => ConversationWorkflowStage.implement,
      'coding' => ConversationWorkflowStage.implement,
      '実装' => ConversationWorkflowStage.implement,
      'review' => ConversationWorkflowStage.review,
      'validation' => ConversationWorkflowStage.review,
      'レビュー' => ConversationWorkflowStage.review,
      _ => null,
    };
  }

  ConversationWorkflowStage? inferWorkflowStageFromProposal(
    Map<String, dynamic> decoded,
  ) {
    final openQuestions = ProposalParsingTextUtils.asStringList(
      decoded['openQuestions'],
    );
    if (openQuestions.isNotEmpty) {
      return ConversationWorkflowStage.clarify;
    }
    return ConversationWorkflowStage.plan;
  }

  WorkflowProposalDraft? parseWorkflowProposalMap(
    Map<String, dynamic> decoded,
  ) {
    final workflowStage =
        parseWorkflowStage(
          decoded['workflowStage'] ??
              decoded['stage'] ??
              decoded['workflow_stage'] ??
              decoded['ワークフローステージ'] ??
              decoded['ステージ'],
        ) ??
        inferWorkflowStageFromProposal(decoded);
    if (workflowStage == null ||
        workflowStage == ConversationWorkflowStage.idle) {
      return null;
    }

    final workflowSpec = ConversationWorkflowSpec(
      goal: ProposalParsingTextUtils.asCleanString(
        decoded['goal'] ?? decoded['目的'],
      ),
      constraints: ProposalParsingTextUtils.asStringList(
        decoded['constraints'] ?? decoded['制約'],
      ),
      acceptanceCriteria: ProposalParsingTextUtils.asStringList(
        decoded['acceptanceCriteria'] ??
            decoded['acceptance_criteria'] ??
            decoded['acceptance'] ??
            decoded['完了条件'],
      ),
      openQuestions: ProposalParsingTextUtils.asStringList(
        decoded['openQuestions'] ??
            decoded['open_questions'] ??
            decoded['questions'] ??
            decoded['未解決の確認事項'],
      ),
    );

    if (!workflowSpec.hasContent) {
      return null;
    }

    return WorkflowProposalDraft(
      workflowStage: workflowStage,
      workflowSpec: workflowSpec,
    );
  }

  WorkflowProposalParsedDecisions? parseWorkflowDecisionResponseMap(
    Map<String, dynamic> decoded,
  ) {
    final kind = ProposalParsingTextUtils.asCleanString(
      decoded['kind'],
    ).toLowerCase();
    if (kind.isNotEmpty && kind != 'decision') {
      return null;
    }

    final rawDecisions =
        decoded['decisions'] ?? decoded['planningDecisions'] ?? decoded['選択'];
    if (rawDecisions is! List) {
      return null;
    }

    final decisions = <WorkflowPlanningDecision>[];
    for (final entry in rawDecisions.take(3)) {
      if (entry is! Map) continue;
      final item = Map<String, dynamic>.from(entry);
      final question = ProposalParsingTextUtils.asCleanString(
        item['question'] ?? item['title'] ?? item['prompt'] ?? item['質問'],
      );
      final rawOptions = item['options'] ?? item['choices'] ?? item['選択肢'];
      final inputMode = ProposalParsingTextUtils.asCleanString(
        item['inputMode'],
      ).toLowerCase();
      final allowFreeText =
          inputMode == 'freetext' ||
          inputMode == 'free_text' ||
          item['allowFreeText'] == true;
      if (question.isEmpty) {
        continue;
      }

      final options = <WorkflowPlanningDecisionOption>[];
      if (rawOptions is List) {
        for (final optionEntry in rawOptions.take(4)) {
          if (optionEntry is! Map) continue;
          final option = Map<String, dynamic>.from(optionEntry);
          final label = ProposalParsingTextUtils.asCleanString(
            option['label'] ??
                option['title'] ??
                option['name'] ??
                option['候補'],
          );
          if (label.isEmpty) continue;
          final optionId = ProposalParsingTextUtils.asCleanString(
            option['id'] ?? option['value'] ?? option['key'],
          );
          options.add(
            WorkflowPlanningDecisionOption(
              id: optionId.isEmpty ? label : optionId,
              label: label,
              description: ProposalParsingTextUtils.asCleanString(
                option['description'] ?? option['detail'] ?? option['説明'],
              ),
            ),
          );
        }
      }

      if (!allowFreeText && options.length < 2) {
        continue;
      }

      final decisionId = ProposalParsingTextUtils.asCleanString(
        item['id'] ?? item['key'] ?? item['name'],
      );
      decisions.add(
        WorkflowPlanningDecision(
          id: decisionId.isEmpty ? question : decisionId,
          question: question,
          help: ProposalParsingTextUtils.asCleanString(
            item['help'] ??
                item['description'] ??
                item['details'] ??
                item['補足'],
          ),
          allowFreeText: allowFreeText,
          freeTextPlaceholder: ProposalParsingTextUtils.asCleanString(
            item['placeholder'] ?? item['inputPlaceholder'] ?? item['入力例'],
          ),
          options: options,
        ),
      );
    }

    if (decisions.isEmpty) {
      return null;
    }
    return WorkflowProposalParsedDecisions(decisions);
  }

  WorkflowProposalDraft? parseWorkflowProposalFromSections(String rawContent) {
    final sections = ProposalParsingTextUtils.collectProposalSections(
      rawContent,
    );
    final workflowStage =
        parseWorkflowStage(sections['workflowStage']?.firstOrNull) ??
        ProposalParsingTextUtils.inferWorkflowStageFromSectionKeys(sections);
    if (workflowStage == null ||
        workflowStage == ConversationWorkflowStage.idle) {
      return null;
    }

    final workflowSpec = ConversationWorkflowSpec(
      goal: sections['goal']?.join(' ').trim() ?? '',
      constraints: sections['constraints'] ?? const [],
      acceptanceCriteria: sections['acceptanceCriteria'] ?? const [],
      openQuestions: sections['openQuestions'] ?? const [],
    );
    if (!workflowSpec.hasContent) {
      return null;
    }

    return WorkflowProposalDraft(
      workflowStage: workflowStage,
      workflowSpec: workflowSpec,
    );
  }

  WorkflowProposalDraft? parseWorkflowProposalFromLooseJson(String rawContent) {
    final workflowStage =
        parseWorkflowStage(
          ProposalParsingTextUtils.extractLooseJsonScalar(
            rawContent,
            keys: const [
              'workflowStage',
              'stage',
              'workflow_stage',
              'ワークフローステージ',
              'ステージ',
            ],
          ),
        ) ??
        ProposalParsingTextUtils.inferWorkflowStageFromLooseProposalContent(
          rawContent,
        );
    if (workflowStage == ConversationWorkflowStage.idle) {
      return null;
    }

    final workflowSpec = ConversationWorkflowSpec(
      goal:
          ProposalParsingTextUtils.extractLooseJsonScalar(
            rawContent,
            keys: const ['goal', '目的'],
          ) ??
          '',
      constraints: ProposalParsingTextUtils.extractLooseJsonStringList(
        rawContent,
        keys: const ['constraints', '制約'],
      ),
      acceptanceCriteria: ProposalParsingTextUtils.extractLooseJsonStringList(
        rawContent,
        keys: const [
          'acceptanceCriteria',
          'acceptance_criteria',
          'acceptance',
          '完了条件',
        ],
      ),
      openQuestions: ProposalParsingTextUtils.extractLooseJsonStringList(
        rawContent,
        keys: const [
          'openQuestions',
          'open_questions',
          'questions',
          '未解決の確認事項',
        ],
      ),
    );
    if (!workflowSpec.hasContent) {
      return null;
    }

    return WorkflowProposalDraft(
      workflowStage: workflowStage,
      workflowSpec: workflowSpec,
    );
  }

  WorkflowProposalDraft? parseWorkflowProposalFromNarrative(String rawContent) {
    final goal = extractNarrativeWorkflowGoal(rawContent);
    if (goal == null) {
      return null;
    }

    final acceptanceCriteria = extractNarrativeWorkflowList(
      rawContent,
      keys: const ['acceptance criteria', 'completion criteria'],
    );
    final constraints = extractNarrativeWorkflowList(
      rawContent,
      keys: const ['constraints', 'guardrails'],
    );
    final openQuestions = extractNarrativeWorkflowList(
      rawContent,
      keys: const ['open questions', 'unresolved questions'],
    );

    final proposal = WorkflowProposalDraft(
      workflowStage: openQuestions.isNotEmpty
          ? ConversationWorkflowStage.clarify
          : ConversationWorkflowStage.plan,
      workflowSpec: ConversationWorkflowSpec(
        goal: goal,
        constraints: constraints,
        acceptanceCriteria: acceptanceCriteria,
        openQuestions: openQuestions,
      ),
    );
    if (!proposal.workflowSpec.hasContent ||
        !_qualityService.isReasoningWorkflowProposalPlausible(proposal)) {
      return null;
    }
    return proposal;
  }

  String? extractNarrativeWorkflowGoal(String rawContent) {
    final normalizedContent = rawContent.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalizedContent.isEmpty) {
      return null;
    }

    const userGoalPrefixes = <String>[
      'The user wants a workflow proposal for ',
      'The user wants to ',
    ];
    final lowerContent = normalizedContent.toLowerCase();
    for (final prefix in userGoalPrefixes) {
      final start = lowerContent.indexOf(prefix.toLowerCase());
      if (start < 0) {
        continue;
      }
      final candidate = sanitizeNarrativeWorkflowGoal(
        trimNarrativeWorkflowGoalCandidate(
          normalizedContent.substring(start + prefix.length),
        ),
      );
      if (candidate != null) {
        return candidate;
      }
    }

    final quotedRequestMatch = RegExp(
      r'''The user(?:'s)? request is ["'](.+?)["']''',
      caseSensitive: false,
    ).firstMatch(normalizedContent);
    if (quotedRequestMatch != null) {
      final candidate = sanitizeNarrativeWorkflowGoal(
        quotedRequestMatch.group(1) ?? '',
      );
      if (candidate != null) {
        return candidate;
      }
    }

    final userWantsMatch = RegExp(
      r'''The user wants (?:a workflow proposal for |to )(.+?)(?:(?:[.!?](?:\s|$))|(?:\s+The project name is\b)|(?:\s+Project name is\b)|(?:\s+The current state is\b)|(?:\s+The project root\b)|(?:\s+The research context\b)|(?:\s+The user's\b)|$)''',
      caseSensitive: false,
    ).firstMatch(normalizedContent);
    if (userWantsMatch != null) {
      final candidate = sanitizeNarrativeWorkflowGoal(
        userWantsMatch.group(1) ?? '',
      );
      if (candidate != null) {
        return candidate;
      }
    }

    final goalMatch = RegExp(
      r'''Goal\s*:\s*(.+?)(?:\.|$)''',
      caseSensitive: false,
    ).firstMatch(normalizedContent);
    if (goalMatch != null) {
      final candidate = sanitizeNarrativeWorkflowGoal(goalMatch.group(1) ?? '');
      if (candidate != null) {
        return candidate;
      }
    }

    return null;
  }

  String trimNarrativeWorkflowGoalCandidate(String rawValue) {
    var candidate = rawValue.trim();
    if (candidate.isEmpty) {
      return '';
    }

    const contextMarkers = <String>[
      ' The project name is ',
      ' Project name is ',
      ' The current state is ',
      ' The project root ',
      ' The research context ',
      " The user's request is ",
      ' Current State:',
      ' Recent Context:',
    ];

    final lowerCandidate = candidate.toLowerCase();
    var cutIndex = candidate.length;
    for (final marker in contextMarkers) {
      final index = lowerCandidate.indexOf(marker.trim().toLowerCase());
      if (index > 0 && index < cutIndex) {
        cutIndex = index;
      }
    }
    candidate = candidate.substring(0, cutIndex).trim();

    final sentenceBreak = RegExp(r'(?<=[.!?])\s+').firstMatch(candidate);
    if (sentenceBreak != null && sentenceBreak.start > 24) {
      candidate = candidate.substring(0, sentenceBreak.start).trim();
    }

    return candidate;
  }

  String? sanitizeNarrativeWorkflowGoal(String rawValue) {
    final candidate = ProposalParsingTextUtils.sanitizeReasoningProposalValue(
      rawValue,
      preferSingleSentence: true,
    );
    if (candidate.isEmpty) {
      return null;
    }

    final normalized = candidate.toLowerCase();
    const blockedFragments = <String>[
      'workflow proposal',
      'current coding thread',
      'single valid json object',
      'return only',
      'research context',
      'project name is',
      'the project is currently empty',
      'the prompt asks',
    ];
    if (blockedFragments.any(normalized.contains)) {
      return null;
    }

    if (!RegExp(
      r'\b(create|build|implement|add|ship|make|refine|improve|develop|diagnose|ping)\b',
      caseSensitive: false,
    ).hasMatch(candidate)) {
      return null;
    }
    return candidate;
  }

  List<String> extractNarrativeWorkflowList(
    String rawContent, {
    required List<String> keys,
  }) {
    final normalizedContent = rawContent.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalizedContent.isEmpty) {
      return const [];
    }

    for (final key in keys) {
      final match = RegExp(
        '${RegExp.escape(key)}\\s*[:\\-]\\s*(.+?)(?:\\.|\\\$)',
        caseSensitive: false,
      ).firstMatch(normalizedContent);
      if (match == null) {
        continue;
      }
      final value = ProposalParsingTextUtils.sanitizeReasoningProposalValue(
        match.group(1) ?? '',
      );
      if (value.isEmpty) {
        continue;
      }
      return [value];
    }
    return const [];
  }

  String? deriveWorkflowFallbackGoalFromConversation(
    Conversation currentConversation,
  ) {
    String rawGoal = '';
    for (final message in currentConversation.messages.reversed) {
      if (message.role != MessageRole.user) {
        continue;
      }
      rawGoal = message.content.trim();
      if (rawGoal.isNotEmpty) {
        break;
      }
    }
    if (rawGoal.isEmpty) {
      return null;
    }

    final sanitized = sanitizeNarrativeWorkflowGoal(rawGoal);
    if (sanitized != null && sanitized.isNotEmpty) {
      return sanitized;
    }
    return rawGoal.length > 180 ? rawGoal.substring(0, 180).trim() : rawGoal;
  }
}
