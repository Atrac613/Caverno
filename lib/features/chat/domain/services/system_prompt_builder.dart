import '../../../../core/constants/system_prompt_constants.dart';
import '../../../../core/types/assistant_mode.dart';

class SystemPromptBuilder {
  SystemPromptBuilder._();

  static const List<String> _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static String build({
    required DateTime now,
    required AssistantMode assistantMode,
    String languageCode = 'en',
    List<String> toolNames = const [],
    String? sessionMemoryContext,
    bool isVoiceMode = false,
  }) {
    final uniqueToolNames = toolNames.toSet().toList()..sort();
    final hasTools = uniqueToolNames.isNotEmpty;
    final hasSearchTool = uniqueToolNames.any(
      (name) => name == 'searxng_web_search' || name == 'web_search',
    );
    final hasWebReader = uniqueToolNames.contains('web_url_read');
    final hasDatetimeTool = uniqueToolNames.contains('get_current_datetime');

    final date = _formatDate(now);
    final time = _formatTime(now);
    final weekday = _weekdays[now.weekday - 1];
    final timeZoneName = now.timeZoneName.isEmpty ? 'Local' : now.timeZoneName;
    final utcOffset = _formatUtcOffset(now.timeZoneOffset);

    final buffer = StringBuffer()
      ..writeln(
        'Current local date and time (source of truth): '
        '$date ($weekday) $time $timeZoneName (UTC$utcOffset).',
      )
      ..writeln(
        'Resolve relative date/time references (today, yesterday, tomorrow, '
        'this week, recently, now, latest, current) against this source of truth.',
      )
      ..writeln(
        'When responding to time-relative questions, include exact dates '
        '(YYYY-MM-DD) to avoid ambiguity.',
      )
      ..writeln(SystemPromptConstants.coreAssistantPrompt)
      ..writeln(SystemPromptConstants.priorityInstruction)
      ..writeln(SystemPromptConstants.judgmentInstruction)
      ..writeln(SystemPromptConstants.communicationInstruction)
      ..writeln(SystemPromptConstants.oversightInstruction)
      ..writeln(SystemPromptConstants.languageInstruction(languageCode))
      ..writeln(SystemPromptConstants.optionalFollowUpQuestionInstruction);

    if (assistantMode == AssistantMode.general) {
      buffer.writeln(SystemPromptConstants.generalModeInstruction);
    } else {
      buffer.writeln(SystemPromptConstants.codingModeInstruction);
    }

    if (isVoiceMode) {
      buffer.writeln(SystemPromptConstants.voiceModeInstruction);
      if (hasTools) {
        buffer.writeln(SystemPromptConstants.voiceModeToolInstruction);
      }
    }

    final hasMemorySearch = uniqueToolNames.contains(
      'search_past_conversations',
    );
    final hasRecallMemory = uniqueToolNames.contains('recall_memory');

    if (hasTools) {
      buffer.writeln(
        'Use available tools when they materially improve accuracy, '
        'grounding, or recency.',
      );
      buffer.writeln('Available tools: ${uniqueToolNames.join(', ')}.');
      if (hasDatetimeTool) {
        buffer.writeln(
          'When the user asks about dates/times such as today, this week, '
          'recent, current, latest, or now, call get_current_datetime before '
          'answering.',
        );
      }
      if (hasMemorySearch || hasRecallMemory) {
        buffer.writeln(
          'When the user asks about something they previously mentioned, '
          'discussed, bought, decided, or any past event from their '
          'conversations, use search_past_conversations to find the relevant '
          'information before answering from memory alone. '
          'Use recall_memory for quick lookups of known facts and preferences.',
        );
      }
    }

    if (hasSearchTool || hasWebReader) {
      buffer.writeln(
        'When current or external information matters, use the web '
        'tools before answering from memory.',
      );
      if (hasSearchTool) {
        final searchToolNames = uniqueToolNames
            .where(
              (name) => name == 'searxng_web_search' || name == 'web_search',
            )
            .join(', ');
        buffer.writeln('Use $searchToolNames for web search.');
      }
      if (hasWebReader) {
        buffer.writeln(
          'Use web_url_read to inspect page contents when snippets are '
          'insufficient.',
        );
      }
      buffer.writeln(
        'Do not claim that you cannot access real-time information '
        'when these tools are available.',
      );
      buffer.writeln(SystemPromptConstants.webCitationInstruction);
    }

    final memoryContext = sessionMemoryContext?.trim();
    if (memoryContext != null && memoryContext.isNotEmpty) {
      buffer.writeln(
        'Use the following context from past conversations to maintain '
        'continuity when helpful.',
      );
      buffer.writeln(memoryContext);
      buffer.writeln(
        'Treat low-confidence memories as hypotheses and verify against the '
        'current user message.',
      );
      buffer.writeln(
        'If memory conflicts with the current request, prioritize the current '
        'request.',
      );
    }

    return buffer.toString().trimRight();
  }

  static String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static String _formatUtcOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final absoluteMinutes = offset.inMinutes.abs();
    final hours = (absoluteMinutes ~/ 60).toString().padLeft(2, '0');
    final minutes = (absoluteMinutes % 60).toString().padLeft(2, '0');
    return '$sign$hours:$minutes';
  }
}
