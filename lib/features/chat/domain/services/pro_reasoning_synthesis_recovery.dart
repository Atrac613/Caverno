import '../entities/message.dart';
import 'proposal_parsing_text_utils.dart';
import 'truncation_notice.dart';

/// Recovers a Pro Reasoning synthesis that reached the model token limit.
final class ProReasoningSynthesisRecovery {
  const ProReasoningSynthesisRecovery();

  static const String continuationPrompt = '''
Continue the immediately preceding Pro Reasoning answer from its exact stopping
point. Do not repeat earlier content or add a new introduction. Complete every
unfinished section and end with a self-contained conclusion.
''';

  bool shouldContinue(Message message) =>
      ProposalParsingTextUtils.isCompletionTruncated(
        message.responseMetrics?.finishReason ?? '',
      );

  Message merge(Message initial, Message continuation) {
    final initialContent = TruncationNotice.withoutMaxTokenNotice(
      initial.content,
    );
    final continuationContent = continuation.content.trim();
    final content = [
      initialContent.trimRight(),
      continuationContent,
    ].where((part) => part.isNotEmpty).join('\n\n');
    final initialMetrics = initial.responseMetrics;
    final continuationMetrics = continuation.responseMetrics;
    return initial.copyWith(
      content: content,
      responseMetrics: MessageResponseMetrics(
        promptTokens:
            (initialMetrics?.promptTokens ?? 0) +
            (continuationMetrics?.promptTokens ?? 0),
        completionTokens:
            (initialMetrics?.completionTokens ?? 0) +
            (continuationMetrics?.completionTokens ?? 0),
        totalTokens:
            (initialMetrics?.totalTokens ?? 0) +
            (continuationMetrics?.totalTokens ?? 0),
        elapsedMilliseconds:
            (initialMetrics?.elapsedMilliseconds ?? 0) +
            (continuationMetrics?.elapsedMilliseconds ?? 0),
        finishReason: continuationMetrics?.finishReason,
      ),
    );
  }
}
