import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';

import '../../data/datasources/llm_request_failure.dart';
import '../../domain/entities/message.dart';
import 'chat_error_text.dart';
import 'llm_failure_headline.dart';

export '../../data/datasources/llm_request_failure.dart'
    show LlmRequestFailure, LlmRequestFailureCode;
export 'chat_error_text.dart' show ChatErrorText;

typedef ChatFailureProjection = ({
  String displayError,
  CavernoRuntimeFailureClassification runtimeFailure,
});

/// Converts provider and transport failures into concise user-facing text.
///
/// The headline is chosen from [LlmRequestFailure.code], never from the error
/// text, so a status-like digit run inside an embedded payload cannot change
/// it. The text is only bounded and shown as details.
final class ChatErrorMessageBuilder {
  const ChatErrorMessageBuilder._();

  static String build(Object error, {required String baseUrl}) =>
      buildFor(LlmRequestFailure.from(error), error, baseUrl: baseUrl);

  /// The display text and runtime terminal classification for a failed turn.
  ///
  /// [fallback] decides the runtime code only when the failure code does not.
  static ChatFailureProjection project(
    Object error, {
    required String baseUrl,
    required CavernoRuntimeFailureClassifier fallback,
  }) {
    final failure = LlmRequestFailure.from(error);
    return (
      displayError: buildFor(failure, error, baseUrl: baseUrl),
      runtimeFailure:
          failure.runtimeClassification ?? fallback.classify(error.toString()),
    );
  }

  static String buildFor(
    LlmRequestFailure failure,
    Object error, {
    required String baseUrl,
  }) {
    final details = ChatErrorText.details(
      ChatErrorText.clean(error.toString()),
    );
    final headline = LlmFailureHeadline.of(failure, baseUrl: baseUrl);
    if (headline == null) return details;
    final requestId = failure.requestId;
    final suffix = requestId == null ? '' : ' (request id: $requestId)';
    return '$headline\nDetails: $details$suffix';
  }
}

/// Applies a terminal error to the owning transcript without reading UI state.
final class TurnErrorMessageProjection {
  const TurnErrorMessageProjection._();

  static List<Message> apply({
    required Iterable<Message> messages,
    required String displayError,
    required Message Function() createAssistant,
  }) {
    final updated = [...messages];
    if (updated.isEmpty || updated.last.role != MessageRole.assistant) {
      updated.add(createAssistant());
    } else {
      final lastIndex = updated.length - 1;
      updated[lastIndex] = updated[lastIndex].copyWith(
        isStreaming: false,
        error: displayError,
      );
    }
    return updated;
  }
}
