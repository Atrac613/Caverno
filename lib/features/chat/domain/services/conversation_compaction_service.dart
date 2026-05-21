import '../entities/conversation_compaction_artifact.dart';
import '../entities/message.dart';

enum ConversationTokenPressureLevel { normal, warning, critical }

class ConversationTokenPressure {
  const ConversationTokenPressure({
    required this.estimatedPromptTokens,
    required this.promptTokenBudget,
    required this.warningThresholdTokens,
    required this.level,
    required this.shouldAutoCompact,
  });

  final int estimatedPromptTokens;
  final int promptTokenBudget;
  final int warningThresholdTokens;
  final ConversationTokenPressureLevel level;
  final bool shouldAutoCompact;
}

class ConversationCompactionService {
  ConversationCompactionService._();

  static const int artifactVersion = 2;
  static const int minMessagesBeforeCompaction = 14;
  static const int recentMessagesToKeep = 8;
  static const int maxEstimatedPromptTokens = 6000;
  static const int maxSummaryBullets = 12;
  static const int maxPlanBullets = 4;
  static const int maxBulletLength = 180;
  static const double tokenWarningRatio = 0.8;

  static final RegExp _thinkBlockPattern = RegExp(
    r'<think>.*?</think>',
    dotAll: true,
    caseSensitive: false,
  );
  static final RegExp _toolBlockPattern = RegExp(
    r'<tool_(call|use|result)>.*?</tool_(call|use|result)>',
    dotAll: true,
    caseSensitive: false,
  );
  static final RegExp _whitespaceRunPattern = RegExp(r'\s+');
  static final RegExp _headingPrefixPattern = RegExp(r'^#+\s*');
  static final RegExp _bulletMarkerPattern = RegExp(r'[-*]\s+');
  static final RegExp _contextLengthErrorPattern = RegExp(
    r'(context length|context window|maximum context|prompt too long|too many tokens|token limit|tokens? exceed|exceeds? .*context|input .*too long|max(?:imum)? tokens)',
    caseSensitive: false,
  );

  static ConversationCompactionArtifact? buildArtifact({
    required List<Message> messages,
    String? planDocument,
    DateTime? now,
    bool force = false,
  }) {
    final normalizedMessages = messages
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    if (!force && !_needsCompaction(normalizedMessages)) {
      return null;
    }

    final compactedMessageCount =
        normalizedMessages.length - recentMessagesToKeep;
    if (compactedMessageCount <= 0) {
      return null;
    }

    final compactedMessages = normalizedMessages
        .sublist(0, compactedMessageCount)
        .toList(growable: false);
    final summary = _buildSummary(
      compactedMessages,
      planDocument: planDocument,
    );
    if (summary.isEmpty) {
      return null;
    }

    return ConversationCompactionArtifact(
      version: artifactVersion,
      summary: summary,
      sourceMessageCount: normalizedMessages.length,
      compactedMessageCount: compactedMessageCount,
      retainedMessageCount: normalizedMessages.length - compactedMessageCount,
      estimatedPromptTokens: estimatePromptTokens(normalizedMessages),
      updatedAt: now ?? DateTime.now(),
    );
  }

  static bool shouldCompact(List<Message> messages) {
    final normalizedMessages = messages
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    return _needsCompaction(normalizedMessages);
  }

  static ConversationTokenPressure assessTokenPressure({
    required List<Message> messages,
    int promptTokenBudget = maxEstimatedPromptTokens,
  }) {
    final normalizedMessages = messages
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    final budget = promptTokenBudget <= 0
        ? maxEstimatedPromptTokens
        : promptTokenBudget;
    final estimatedTokens = estimatePromptTokens(normalizedMessages);
    final warningThreshold = (budget * tokenWarningRatio).round();
    final level = estimatedTokens >= budget
        ? ConversationTokenPressureLevel.critical
        : estimatedTokens >= warningThreshold
        ? ConversationTokenPressureLevel.warning
        : ConversationTokenPressureLevel.normal;

    return ConversationTokenPressure(
      estimatedPromptTokens: estimatedTokens,
      promptTokenBudget: budget,
      warningThresholdTokens: warningThreshold,
      level: level,
      shouldAutoCompact: _needsCompaction(normalizedMessages),
    );
  }

  static bool isContextLengthError(String error) {
    return _contextLengthErrorPattern.hasMatch(error);
  }

  static List<Message> retainMessages({
    required List<Message> messages,
    ConversationCompactionArtifact? artifact,
  }) {
    final normalizedMessages = messages
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    if (artifact == null || !artifact.hasContent) {
      return normalizedMessages;
    }

    final compactedCount = artifact.compactedMessageCount;
    if (compactedCount <= 0 || compactedCount >= normalizedMessages.length) {
      return normalizedMessages;
    }

    return normalizedMessages.sublist(compactedCount);
  }

  static int estimatePromptTokens(List<Message> messages) {
    final characterCount = messages.fold<int>(0, (count, message) {
      return count + _normalizeMessageContent(message).length;
    });
    return (characterCount / 4).ceil();
  }

  static bool _needsCompaction(List<Message> messages) {
    if (messages.length <= recentMessagesToKeep) {
      return false;
    }
    final estimatedTokens = estimatePromptTokens(messages);
    return estimatedTokens > maxEstimatedPromptTokens ||
        messages.length > minMessagesBeforeCompaction;
  }

  static String _buildSummary(List<Message> messages, {String? planDocument}) {
    final sections = <String>[];
    final planBullets = _extractPlanBullets(planDocument);
    if (planBullets.isNotEmpty) {
      sections.add('Active plan context:\n${planBullets.join('\n')}');
    }

    final bullets = <String>[];

    for (final message in messages) {
      final normalizedContent = _normalizeMessageContent(message);
      if (normalizedContent.isEmpty) {
        continue;
      }

      final prefix = switch (message.role) {
        MessageRole.user => 'User',
        MessageRole.assistant => 'Assistant',
        MessageRole.system => 'System',
      };
      bullets.add('- $prefix: ${_truncate(normalizedContent)}');
      if (bullets.length >= maxSummaryBullets) {
        break;
      }
    }

    if (bullets.isNotEmpty) {
      sections.add('Earlier turns:\n${bullets.join('\n')}');
    }

    return sections.join('\n\n');
  }

  static String _normalizeMessageContent(Message message) {
    final raw = message.content;
    final withoutThinkBlocks = raw.replaceAll(_thinkBlockPattern, ' ');
    final withoutToolBlocks = withoutThinkBlocks.replaceAll(
      _toolBlockPattern,
      ' ',
    );
    final normalized = withoutToolBlocks
        .replaceAll(_whitespaceRunPattern, ' ')
        .trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }

    if (raw.contains('<tool_call>') ||
        raw.contains('<tool_use>') ||
        raw.contains('<tool_result>')) {
      return 'Assistant executed tool calls and returned structured results.';
    }

    if (message.imageBase64 != null) {
      return 'Image attachment shared in the conversation.';
    }
    return '';
  }

  static List<String> _extractPlanBullets(String? planDocument) {
    if (planDocument == null) {
      return const [];
    }

    final bullets = <String>[];
    final seen = <String>{};
    for (final rawLine in planDocument.split('\n')) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty || trimmed.startsWith('```')) {
        continue;
      }

      String normalizedLine = trimmed;
      if (normalizedLine.startsWith('#')) {
        normalizedLine = normalizedLine.replaceFirst(_headingPrefixPattern, '');
      } else if (normalizedLine.startsWith('- [ ]')) {
        normalizedLine = normalizedLine.substring(5).trim();
      } else if (normalizedLine.startsWith('- [x]')) {
        normalizedLine = normalizedLine.substring(5).trim();
      } else if (normalizedLine.startsWith(_bulletMarkerPattern)) {
        normalizedLine = normalizedLine.substring(1).trim();
      }

      normalizedLine = normalizedLine
          .replaceAll(_whitespaceRunPattern, ' ')
          .trim();
      if (normalizedLine.isEmpty) {
        continue;
      }

      final compact = _truncate(normalizedLine);
      if (!seen.add(compact)) {
        continue;
      }
      bullets.add('- $compact');
      if (bullets.length >= maxPlanBullets) {
        break;
      }
    }

    return bullets;
  }

  static String _truncate(String value) {
    if (value.length <= maxBulletLength) {
      return value;
    }
    return '${value.substring(0, maxBulletLength - 1)}...';
  }
}
