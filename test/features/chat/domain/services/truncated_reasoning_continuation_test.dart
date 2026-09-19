import 'package:caverno/features/chat/domain/services/truncated_reasoning_continuation.dart';
import 'package:test/test.dart';

const _policy = TruncatedReasoningContinuation();

bool _cutOff({
  String? finishReason = 'length',
  required String content,
  bool hasToolCalls = false,
}) => _policy.isCutOffBeforeAnswer(
  finishReason: finishReason,
  content: content,
  hasToolCalls: hasToolCalls,
);

void main() {
  group('isCutOffBeforeAnswer', () {
    test('a reply that ran out mid-thought is not an answer', () {
      // Session 99587346: 8,192 completion tokens, all reasoning, ending on
      // "Let me write the release notes file now." The loop read it as a final
      // answer and stopped with three iterations unused.
      expect(
        _cutOff(content: '<think>Let me write the release notes file now.'),
        isTrue,
      );
    });

    test('a closed reasoning block with nothing after it is still cut off', () {
      expect(_cutOff(content: '<think>planning</think>'), isTrue);
      expect(_cutOff(content: '<think>planning</think>   \n'), isTrue);
    });

    test('an answer that was truncated is left alone', () {
      // Losing the tail of a real answer is a different problem, and this is
      // not the place to decide the model was not finished.
      expect(
        _cutOff(content: '<think>planning</think>The version is now 1.3.35'),
        isFalse,
      );
    });

    test('a reply that stopped normally is an answer', () {
      expect(
        _cutOff(finishReason: 'stop', content: '<think>done</think>'),
        isFalse,
      );
      expect(_cutOff(finishReason: null, content: '<think>x</think>'), isFalse);
    });

    test('a truncated reply that still asked for a tool is not this case', () {
      // The tool call survived, so the loop has work to do and needs no nudge.
      expect(_cutOff(content: '<think>x</think>', hasToolCalls: true), isFalse);
    });

    test('case and spacing in the finish reason do not matter', () {
      expect(_cutOff(finishReason: ' Length ', content: '<think>x'), isTrue);
    });
  });

  group('visibleText', () {
    test('drops a closed reasoning block', () {
      expect(_policy.visibleText('<think>why</think>answer'), 'answer');
    });

    test('treats an unterminated block as leaving nothing behind', () {
      expect(_policy.visibleText('<think>cut off here'), isEmpty);
    });

    test('passes through a reply that never reasoned', () {
      expect(_policy.visibleText('  plain answer '), 'plain answer');
    });

    test('keeps only what follows the last block', () {
      expect(
        _policy.visibleText('<think>a</think>mid<think>b</think>end'),
        'end',
      );
    });
  });

  test('the continuation prompt says why the reply vanished', () {
    final prompt = _policy.continuationPrompt();
    // A model that cannot see why its last reply disappeared plans the same
    // work again from the top.
    expect(prompt, contains('token limit'));
    expect(prompt, contains('no tool ran'));
    expect(prompt, contains('without restating'));
  });

  test('one continuation per turn', () {
    // A second truncation in a row is a budget question, not a retry.
    expect(TruncatedReasoningContinuation.maxContinuationsPerTurn, 1);
  });
}
