import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/pro_reasoning_synthesis_recovery.dart';
import 'package:caverno/features/chat/domain/services/truncation_notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const recovery = ProReasoningSynthesisRecovery();

  test('continues only a length-limited synthesis', () {
    expect(recovery.shouldContinue(_message('length')), isTrue);
    expect(recovery.shouldContinue(_message('stop')), isFalse);
    expect(recovery.shouldContinue(_message(null)), isFalse);
  });

  test('merges one continuation and preserves its terminal status', () {
    final initial = _message(
      'length',
      content: TruncationNotice.withMaxTokenNotice('First half.'),
      promptTokens: 10,
      completionTokens: 20,
      elapsedMilliseconds: 30,
    );
    final continuation = _message(
      'stop',
      id: 'continuation',
      content: 'Second half.',
      promptTokens: 40,
      completionTokens: 50,
      elapsedMilliseconds: 60,
    );

    final merged = recovery.merge(initial, continuation);

    expect(merged.id, initial.id);
    expect(merged.content, 'First half.\n\nSecond half.');
    expect(merged.content, isNot(contains(TruncationNotice.maxTokenNotice)));
    expect(merged.responseMetrics?.finishReason, 'stop');
    expect(merged.responseMetrics?.promptTokens, 50);
    expect(merged.responseMetrics?.completionTokens, 70);
    expect(merged.responseMetrics?.totalTokens, 120);
    expect(merged.responseMetrics?.elapsedMilliseconds, 90);
  });

  test('keeps the continuation truncation notice after the bounded retry', () {
    final merged = recovery.merge(
      _message(
        'length',
        content: TruncationNotice.withMaxTokenNotice('First half.'),
      ),
      _message(
        'length',
        id: 'continuation',
        content: TruncationNotice.withMaxTokenNotice('Still incomplete.'),
      ),
    );

    expect(merged.responseMetrics?.finishReason, 'length');
    expect(merged.content, endsWith(TruncationNotice.maxTokenNotice));
  });
}

Message _message(
  String? finishReason, {
  String id = 'initial',
  String content = 'Answer',
  int promptTokens = 0,
  int completionTokens = 0,
  int elapsedMilliseconds = 0,
}) => Message(
  id: id,
  content: content,
  role: MessageRole.assistant,
  timestamp: DateTime(2026),
  responseMetrics: MessageResponseMetrics(
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    totalTokens: promptTokens + completionTokens,
    elapsedMilliseconds: elapsedMilliseconds,
    finishReason: finishReason,
  ),
);
