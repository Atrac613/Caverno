import '../entities/conversation_compaction_artifact.dart';
import '../entities/message.dart';
import 'conversation_tool_result_pruner.dart';

enum ConversationTokenPressureLevel { normal, warning, critical }

/// An endpoint-reported prompt size paired with the estimate made for that
/// same request.
///
/// [estimatePromptTokens] walks conversation messages only, so it cannot see
/// the tool catalog, the serialized tool schemas, or the tokenizer's real
/// handling of the text. Measured over recorded sessions, that blind spot is
/// worth roughly 7.4k tokens on a tool-bearing request -- more than the entire
/// default budget -- which made the gauge read "under budget" on a fifth of
/// all requests whose real prompt had already passed it. Pairing what was
/// charged with what was estimated recovers the difference without guessing at
/// a tokenizer.
class PromptTokenCalibration {
  const PromptTokenCalibration({
    required this.measuredPromptTokens,
    required this.estimatedPromptTokens,
  });

  static const PromptTokenCalibration empty = PromptTokenCalibration(
    measuredPromptTokens: 0,
    estimatedPromptTokens: 0,
  );

  /// Prompt tokens the endpoint reported for the request.
  final int measuredPromptTokens;

  /// What [estimatePromptTokens] returned for that request's messages.
  final int estimatedPromptTokens;

  bool get hasMeasurement =>
      measuredPromptTokens > 0 && estimatedPromptTokens > 0;

  /// Tokens the estimator never counted.
  ///
  /// Clamped at zero: the correction only ever adds what was missed. An
  /// estimator that over-counts is already erring toward compacting early,
  /// which costs a summary, while erring late costs a rejected request.
  int get uncountedTokens {
    if (!hasMeasurement) return 0;
    final difference = measuredPromptTokens - estimatedPromptTokens;
    return difference > 0 ? difference : 0;
  }
}

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

  static const int artifactVersion = 3;
  static const int minMessagesBeforeCompaction = 14;
  static const int recentMessagesToKeep = 8;
  static const int retainedTailTokenBudget = 1000;
  static const int maxEstimatedPromptTokens = 6000;

  /// Held back from a known context window for the parts of a request that
  /// arrive after the budget is computed, such as a steering directive
  /// appended at send time or a tool catalog larger than the last measured one.
  static const int contextSafetyMarginTokens = 1024;

  /// Floor for a resolved budget, so a model whose window barely exceeds its
  /// own response allowance still compacts rather than dividing into nothing.
  static const int minimumPromptTokenBudget = 2000;
  static const int maxSummaryBullets = 12;
  static const int maxPlanBullets = 4;
  static const int maxBulletLength = 180;
  static const int imageAttachmentTokenFloor = 256;
  static const int imageAttachmentTokenCeiling = 4096;
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
    int? promptTokenBudget,
    PromptTokenCalibration calibration = PromptTokenCalibration.empty,
  }) {
    final normalizedMessages = messages
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    if (!force &&
        !_needsCompaction(
          normalizedMessages,
          promptTokenBudget: promptTokenBudget,
          calibration: calibration,
        )) {
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
    final structurallyPruned = ConversationToolResultPruner.prune(
      compactedMessages,
    );
    final summary = _buildSummary(
      structurallyPruned.messages,
      planDocument: planDocument,
    );
    if (summary.isEmpty) {
      return null;
    }

    final retainedMessages = normalizedMessages.sublist(compactedMessageCount);
    return ConversationCompactionArtifact(
      version: artifactVersion,
      summary: summary,
      sourceMessageCount: normalizedMessages.length,
      compactedMessageCount: compactedMessageCount,
      retainedMessageCount: normalizedMessages.length - compactedMessageCount,
      retainedMessageContentOverrides: _buildRetainedContentOverrides(
        retainedMessages,
      ),
      estimatedPromptTokens: estimatePromptTokens(normalizedMessages),
      updatedAt: now ?? DateTime.now(),
    );
  }

  static bool shouldCompact(
    List<Message> messages, {
    int? promptTokenBudget,
    PromptTokenCalibration calibration = PromptTokenCalibration.empty,
  }) {
    final normalizedMessages = messages
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    return _needsCompaction(
      normalizedMessages,
      promptTokenBudget: promptTokenBudget,
      calibration: calibration,
    );
  }

  static ConversationTokenPressure assessTokenPressure({
    required List<Message> messages,
    int? promptTokenBudget,
    PromptTokenCalibration calibration = PromptTokenCalibration.empty,
  }) {
    final normalizedMessages = messages
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    final budget = _resolveBudget(promptTokenBudget);
    final projectedTokens = projectPromptTokens(
      messages: normalizedMessages,
      calibration: calibration,
    );
    final warningThreshold = (budget * tokenWarningRatio).round();
    final level = projectedTokens >= budget
        ? ConversationTokenPressureLevel.critical
        : projectedTokens >= warningThreshold
        ? ConversationTokenPressureLevel.warning
        : ConversationTokenPressureLevel.normal;

    return ConversationTokenPressure(
      estimatedPromptTokens: projectedTokens,
      promptTokenBudget: budget,
      warningThresholdTokens: warningThreshold,
      level: level,
      shouldAutoCompact: _needsCompaction(
        normalizedMessages,
        promptTokenBudget: promptTokenBudget,
        calibration: calibration,
      ),
    );
  }

  /// Prompt budget for a model whose usable window is known.
  ///
  /// Returns [maxEstimatedPromptTokens] when the window is unknown, which
  /// keeps the message-count rule in [_needsCompaction] as the deciding
  /// fallback.
  static int resolvePromptTokenBudget({
    required int usableContextTokens,
    required int maxResponseTokens,
  }) {
    if (usableContextTokens <= 0) {
      return maxEstimatedPromptTokens;
    }
    final responseReserve = maxResponseTokens > 0 ? maxResponseTokens : 0;
    final reserved =
        usableContextTokens - responseReserve - contextSafetyMarginTokens;
    return reserved < minimumPromptTokenBudget
        ? minimumPromptTokenBudget
        : reserved;
  }

  /// The estimate plus whatever the last measurement proved it fails to count.
  static int projectPromptTokens({
    required List<Message> messages,
    PromptTokenCalibration calibration = PromptTokenCalibration.empty,
  }) => estimatePromptTokens(messages) + calibration.uncountedTokens;

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

    final retainedMessages = normalizedMessages.sublist(compactedCount);
    final overrides = artifact.retainedMessageContentOverrides;
    if (overrides.isEmpty) {
      return retainedMessages;
    }
    return retainedMessages
        .map((message) {
          final content = overrides[message.id];
          if (content == null ||
              content.isEmpty ||
              content == message.content) {
            return message;
          }
          return message.copyWith(content: content);
        })
        .toList(growable: false);
  }

  static Map<String, String> _buildRetainedContentOverrides(
    List<Message> retainedMessages,
  ) {
    var verbatimTokens = 0;
    var overflowEnd = 0;
    for (var index = retainedMessages.length - 1; index >= 0; index--) {
      final messageTokens = estimatePromptTokens([retainedMessages[index]]);
      if (verbatimTokens + messageTokens <= retainedTailTokenBudget) {
        verbatimTokens += messageTokens;
        continue;
      }
      overflowEnd = index + 1;
      break;
    }
    if (overflowEnd == 0) {
      return const <String, String>{};
    }

    final overflowMessages = retainedMessages.sublist(0, overflowEnd);
    final prunedMessages = ConversationToolResultPruner.prune(
      overflowMessages,
    ).messages;
    final overrides = <String, String>{};
    for (var index = 0; index < overflowMessages.length; index++) {
      final original = overflowMessages[index];
      final prunedContent = prunedMessages[index].content;
      if (prunedContent.isNotEmpty && prunedContent != original.content) {
        overrides[original.id] = prunedContent;
      }
    }
    return Map<String, String>.unmodifiable(overrides);
  }

  static int estimatePromptTokens(List<Message> messages) {
    final characterCount = messages.fold<int>(0, (count, message) {
      return count + _normalizeMessageContent(message).length;
    });
    final textTokens = (characterCount / 4).ceil();
    final imageTokens = messages.fold<int>(0, (count, message) {
      return count + _estimateImageAttachmentTokens(message);
    });
    return textTokens + imageTokens;
  }

  static int _resolveBudget(int? promptTokenBudget) =>
      promptTokenBudget == null || promptTokenBudget <= 0
      ? maxEstimatedPromptTokens
      : promptTokenBudget;

  static bool _needsCompaction(
    List<Message> messages, {
    int? promptTokenBudget,
    PromptTokenCalibration calibration = PromptTokenCalibration.empty,
  }) {
    if (messages.length <= recentMessagesToKeep) {
      return false;
    }
    final budget = _resolveBudget(promptTokenBudget);
    final projectedTokens = projectPromptTokens(
      messages: messages,
      calibration: calibration,
    );
    if (projectedTokens > budget) {
      return true;
    }
    // The message count is a fallback ceiling, not a policy: it decides only
    // while the real prompt size is unknown. Once the window is known and a
    // measurement has landed, the token projection describes the same limit
    // far more accurately, and enforcing a count on top of it would discard
    // context the model can still hold.
    if (promptTokenBudget != null &&
        promptTokenBudget > 0 &&
        calibration.hasMeasurement) {
      return false;
    }
    return messages.length > minMessagesBeforeCompaction;
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

  static int _estimateImageAttachmentTokens(Message message) {
    final imageBase64 = message.imageBase64;
    if (imageBase64 == null || imageBase64.isEmpty) {
      return 0;
    }

    final base64Payload = imageBase64.contains(',')
        ? imageBase64.split(',').last
        : imageBase64;
    final normalizedLength = base64Payload
        .replaceAll(_whitespaceRunPattern, '')
        .length;
    if (normalizedLength <= 0) {
      return imageAttachmentTokenFloor;
    }

    // Vision tokenization varies by provider, so cap the byte-size heuristic.
    final estimatedBytes = (normalizedLength * 3 / 4).ceil();
    final estimatedTokens = (estimatedBytes / 512).ceil();
    return estimatedTokens
        .clamp(imageAttachmentTokenFloor, imageAttachmentTokenCeiling)
        .toInt();
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
