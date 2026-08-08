import '../../../../core/utils/logger.dart';
import '../../data/datasources/chat_datasource.dart';
import '../entities/message.dart';
import '../entities/session_memory.dart';
import '../entities/tool_call_info.dart';
import 'memory_extraction_draft_service.dart';
import 'secondary_call_budget.dart';
import 'secondary_completion_router.dart';
import 'session_memory_service.dart';

/// Runs the optional secondary completion used to extract session memory.
final class MemoryExtractionCoordinator {
  const MemoryExtractionCoordinator();

  Future<MemoryExtractionDraft?> extract({
    required bool enabled,
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    required UserMemoryProfile Function() loadProfile,
    required SecondaryCompletionRouter<ChatDataSource> router,
    required ChatDataSource primaryDataSource,
    required SecondaryCompletionRouteSnapshot route,
    required int maxTokens,
  }) async {
    if (!enabled) {
      appLog(
        '[Memory] Skipping LLM memory extraction for selected provider '
        '(using rule-based fallback)',
      );
      return null;
    }
    if (!messages.any(
      (message) =>
          message.role == MessageRole.user && message.content.trim().isNotEmpty,
    )) {
      return null;
    }

    final now = DateTime.now();
    final input = MemoryExtractionDraftService.buildInput(
      messages,
      loadProfile(),
      toolResults: toolResults,
    );
    final extractionMessages = [
      Message(
        id: 'memory_extractor_system',
        role: MessageRole.system,
        timestamp: now,
        content: MemoryExtractionDraftService.systemPrompt,
      ),
      Message(
        id: 'memory_extractor_user',
        role: MessageRole.user,
        timestamp: now,
        content: input,
      ),
    ];

    try {
      final result = await router.run(
        primaryDataSource: primaryDataSource,
        route: route,
        operation: (dataSource, model) => dataSource.createChatCompletion(
          messages: extractionMessages,
          model: model,
          temperature: 0.1,
          maxTokens: SecondaryCallBudget.resolve(maxTokens, 1200),
        ),
      );
      final draft = MemoryExtractionDraftService.parseDraft(
        result.content,
        inputContext: input,
        onRepair: (message) => appLog('[Memory] $message'),
        onError: (error) =>
            appLog('[Memory] Failed to parse memory extraction JSON: $error'),
      );
      appLog(
        draft == null
            ? '[Memory] Failed to parse LLM memory extraction JSON '
                  '(falling back to rule-based)'
            : '[Memory] LLM memory extraction succeeded',
      );
      return draft;
    } catch (error) {
      appLog('[Memory] LLM memory extraction error: $error');
      return null;
    }
  }
}
