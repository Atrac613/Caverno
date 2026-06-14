import '../entities/conversation.dart';
import '../entities/message.dart';
import 'conversation_compaction_service.dart';
import 'conversation_plan_execution_coordinator.dart';

class ModelSwitchHandoffBriefService {
  ModelSwitchHandoffBriefService._();

  static const int _maxSectionChars = 900;
  static const int _maxLineChars = 180;
  static const int _maxRecentMessages = 4;
  static final RegExp _thinkBlockPattern = RegExp(
    r'<think>.*?</think>',
    dotAll: true,
    caseSensitive: false,
  );
  static final RegExp _toolBlockPattern = RegExp(
    r'<tool_(?:call|use|result)>.*?</tool_(?:call|use|result)>',
    dotAll: true,
    caseSensitive: false,
  );
  static final RegExp _whitespacePattern = RegExp(r'\s+');

  static String? build({
    required Conversation? conversation,
    required List<Message> messages,
    required String previousModel,
    required String nextModel,
  }) {
    final normalizedMessages = messages
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    final sections = <String>[
      'MODEL SWITCH HANDOFF BRIEF',
      'Previous model: ${_cleanScalar(previousModel)}',
      'Next model: ${_cleanScalar(nextModel)}',
      'Purpose: Preserve continuity after a model change with compact, model-agnostic context. This is not a new user request.',
      'Evidence rule: Do not treat this brief as proof that file writes, command runs, git operations, browser actions, network calls, or validation completed. Trust retained application-executed tool results over this brief.',
    ];

    final conversationLines = _conversationLines(conversation);
    if (conversationLines.isNotEmpty) {
      sections.add('Conversation context:\n${conversationLines.join('\n')}');
    }

    final workflowLines = _workflowLines(conversation);
    if (workflowLines.isNotEmpty) {
      sections.add('Workflow context:\n${workflowLines.join('\n')}');
    }

    final compactionSummary = _compactionSummary(
      conversation,
      normalizedMessages,
    );
    if (compactionSummary != null) {
      sections.add('Earlier context summary:\n$compactionSummary');
    }

    final recentLines = _recentMessageLines(normalizedMessages);
    if (recentLines.isNotEmpty) {
      sections.add('Recent retained turns:\n${recentLines.join('\n')}');
    }

    if (sections.length <= 5) {
      return null;
    }
    return sections.join('\n\n').trimRight();
  }

  static List<String> _conversationLines(Conversation? conversation) {
    if (conversation == null) return const [];
    final lines = <String>[];
    final title = conversation.title.trim();
    if (title.isNotEmpty) {
      lines.add('- Title: ${_truncateLine(title)}');
    }
    final goal = conversation.goal?.normalizedObjective;
    if (goal != null) {
      lines.add('- Goal: ${_truncateLine(goal)}');
    }
    final completionSummary = conversation.goal?.normalizedCompletionSummary;
    if (completionSummary != null) {
      lines.add(
        '- Goal completion summary: ${_truncateLine(completionSummary)}',
      );
    }
    final blockedReason = conversation.goal?.normalizedBlockedReason;
    if (blockedReason != null) {
      lines.add('- Goal blocker: ${_truncateLine(blockedReason)}');
    }
    return lines;
  }

  static List<String> _workflowLines(Conversation? conversation) {
    if (conversation == null || !conversation.hasWorkflowContext) {
      return const [];
    }
    final lines = <String>['- Stage: ${conversation.workflowStage.name}'];
    final spec = conversation.effectiveWorkflowSpec;
    if (spec.goal.trim().isNotEmpty) {
      lines.add('- Workflow goal: ${_truncateLine(spec.goal)}');
    }
    final focusTask = ConversationPlanExecutionCoordinator.executionFocusTask(
      conversation,
    );
    if (focusTask != null) {
      lines.add(
        '- Focus task: [${focusTask.status.name}] ${_truncateLine(focusTask.title)}',
      );
      if (focusTask.targetFiles.isNotEmpty) {
        lines.add('- Target files: ${focusTask.targetFiles.join(', ')}');
      }
      if (focusTask.validationCommand.trim().isNotEmpty) {
        lines.add(
          '- Validation command: ${_truncateLine(focusTask.validationCommand)}',
        );
      }
    }
    final planDocument = conversation.displayPlanDocument(
      isPlanning: conversation.isPlanningSession,
    );
    final planLines = _planLines(planDocument);
    if (planLines.isNotEmpty) {
      lines.add('- Plan excerpt:');
      lines.addAll(planLines.map((line) => '  $line'));
    }
    return lines;
  }

  static String? _compactionSummary(
    Conversation? conversation,
    List<Message> messages,
  ) {
    final persisted =
        conversation?.effectiveCompactionArtifact.normalizedSummary;
    if (persisted != null) {
      return _truncateSection(persisted);
    }
    final artifact = ConversationCompactionService.buildArtifact(
      messages: messages,
      planDocument: conversation?.displayPlanDocument(
        isPlanning: conversation.isPlanningSession,
      ),
      force: true,
    );
    final summary = artifact?.normalizedSummary;
    if (summary == null) return null;
    return _truncateSection(summary);
  }

  static List<String> _recentMessageLines(List<Message> messages) {
    return messages.reversed
        .where((message) => message.role != MessageRole.system)
        .take(_maxRecentMessages)
        .map((message) {
          final content = _normalizeContent(message.content);
          if (content.isEmpty) return null;
          final role = switch (message.role) {
            MessageRole.user => 'User',
            MessageRole.assistant => 'Assistant',
            MessageRole.system => 'System',
          };
          final qualifier = message.role == MessageRole.assistant
              ? ' (claims are unverified unless supported by retained tool results)'
              : '';
          return '- $role$qualifier: ${_truncateLine(content)}';
        })
        .whereType<String>()
        .toList(growable: false)
        .reversed
        .toList(growable: false);
  }

  static List<String> _planLines(String? planDocument) {
    if (planDocument == null) return const [];
    final lines = planDocument
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => line.startsWith('-') || line.startsWith('#'))
        .take(6)
        .map(_truncateLine)
        .toList(growable: false);
    return lines;
  }

  static String _normalizeContent(String content) {
    return content
        .replaceAll(_thinkBlockPattern, ' ')
        .replaceAll(_toolBlockPattern, ' ')
        .replaceAll(_whitespacePattern, ' ')
        .trim();
  }

  static String _cleanScalar(String value) {
    final normalized = value.replaceAll(_whitespacePattern, ' ').trim();
    return normalized.isEmpty ? 'unknown' : normalized;
  }

  static String _truncateSection(String value) {
    final normalized = _normalizeContent(value);
    if (normalized.length <= _maxSectionChars) return normalized;
    return '${normalized.substring(0, _maxSectionChars).trimRight()}...';
  }

  static String _truncateLine(String value) {
    final normalized = _normalizeContent(value);
    if (normalized.length <= _maxLineChars) return normalized;
    return '${normalized.substring(0, _maxLineChars).trimRight()}...';
  }
}
