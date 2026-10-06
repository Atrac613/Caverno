import '../../../chat/data/datasources/chat_datasource.dart';
import '../entities/live_llm_diagnostic.dart';

/// How a probe's evidence is written into the diagnostic report: token usage
/// summed from the replies it took, and bounded previews of what the model
/// said.
///
/// Moved out of `LiveLlmDiagnosticService` unchanged (F5) so probe families
/// extracted from the service report evidence the same way it does.
abstract final class LiveLlmDiagnosticEvidence {
  static LiveLlmDiagnosticTokenUsage usage(ChatCompletionResult result) {
    return LiveLlmDiagnosticTokenUsage(
      promptTokens: result.usage.promptTokens,
      completionTokens: result.usage.completionTokens,
      totalTokens: result.usage.totalTokens,
    );
  }

  static LiveLlmDiagnosticTokenUsage totalUsage(
    Iterable<ChatCompletionResult> results,
  ) {
    var promptTokens = 0;
    var completionTokens = 0;
    var totalTokens = 0;
    for (final result in results) {
      promptTokens += result.usage.promptTokens;
      completionTokens += result.usage.completionTokens;
      totalTokens += result.usage.totalTokens;
    }
    return LiveLlmDiagnosticTokenUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
    );
  }

  static LiveLlmDiagnosticTokenUsage sumUsage(
    Iterable<LiveLlmDiagnosticTokenUsage> usages,
  ) {
    var promptTokens = 0;
    var completionTokens = 0;
    var totalTokens = 0;
    for (final usage in usages) {
      promptTokens += usage.promptTokens;
      completionTokens += usage.completionTokens;
      totalTokens += usage.totalTokens;
    }
    return LiveLlmDiagnosticTokenUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
    );
  }

  /// The trimmed text, cut to [maxChars] with an ellipsis.
  static String preview(String value, {int maxChars = 2000}) {
    final trimmed = value.trim();
    if (trimmed.length <= maxChars) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxChars)}...';
  }
}
