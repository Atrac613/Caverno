import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/tool_loop_exit_reason.dart';

void main() {
  const classifier = ToolLoopExitClassifier();

  ToolLoopExitState state({
    String text = 'All done.',
    ToolLoopExitReason? hint,
    String? finishReason,
    int iteration = 1,
    int maxIterations = 10,
    bool pending = false,
    bool lastIsTool = false,
    String? lastTool,
  }) {
    return ToolLoopExitState(
      finalResponseText: text,
      explicitHint: hint,
      finishReason: finishReason,
      iteration: iteration,
      maxIterations: maxIterations,
      hadPendingToolCalls: pending,
      lastMessageIsToolResult: lastIsTool,
      lastToolName: lastTool,
    );
  }

  group('classify', () {
    test('an explicit loop hint wins over content derivation', () {
      // A healthy-looking answer that the loop still tagged as a failure abort.
      final reason = classifier.classify(
        state(text: 'Looks good.', hint: ToolLoopExitReason.toolFailureAbort),
      );
      expect(reason, ToolLoopExitReason.toolFailureAbort);
    });

    test('a normal answer is a healthy text response', () {
      expect(classifier.classify(state()), ToolLoopExitReason.textResponse);
    });

    test('a length finish reason is truncation, before content checks', () {
      expect(
        classifier.classify(
          state(text: 'The answer is', finishReason: 'length'),
        ),
        ToolLoopExitReason.lengthTruncated,
      );
    });

    test('a length finish reason overrides a pending-batch exit hint', () {
      expect(
        classifier.classify(
          state(
            text: 'A repeated but visible final answer',
            hint: ToolLoopExitReason.pendingBatchExecuted,
            finishReason: 'length',
          ),
        ),
        ToolLoopExitReason.lengthTruncated,
      );
    });

    test('empty content and the (empty) sentinel are emptyResponse', () {
      expect(
        classifier.classify(state(text: '')),
        ToolLoopExitReason.emptyResponse,
      );
      expect(
        classifier.classify(state(text: '  (empty) ')),
        ToolLoopExitReason.emptyResponse,
      );
    });

    test('reaching the cap with pending tool calls is maxIterations', () {
      expect(
        classifier.classify(
          state(text: '', iteration: 10, maxIterations: 10, pending: true),
        ),
        // empty content is checked first, so use non-empty interim text here
        ToolLoopExitReason.emptyResponse,
      );
      expect(
        classifier.classify(
          state(
            text: 'working on it',
            iteration: 10,
            maxIterations: 10,
            pending: true,
          ),
        ),
        ToolLoopExitReason.maxIterations,
      );
    });

    test('a short unterminated fragment is a partialFragment', () {
      expect(
        classifier.classify(state(text: 'The')),
        ToolLoopExitReason.partialFragment,
      );
    });

    test('a terse but terminated short answer stays a text response', () {
      expect(
        classifier.classify(state(text: 'Done.')),
        ToolLoopExitReason.textResponse,
      );
      expect(
        classifier.classify(state(text: 'Yes!')),
        ToolLoopExitReason.textResponse,
      );
    });
  });

  group('shouldExplain', () {
    test('explains empty and sentinel turns', () {
      expect(
        classifier.shouldExplain(ToolLoopExitReason.emptyResponse, ''),
        isTrue,
      );
      expect(
        classifier.shouldExplain(ToolLoopExitReason.emptyResponse, '(empty)'),
        isTrue,
      );
    });

    test('does not explain a healthy short answer', () {
      expect(
        classifier.shouldExplain(ToolLoopExitReason.textResponse, 'Done.'),
        isFalse,
      );
    });

    test(
      'explains a partial fragment but not a real reply on the same reason',
      () {
        expect(
          classifier.shouldExplain(ToolLoopExitReason.maxIterations, 'The'),
          isTrue,
        );
        expect(
          classifier.shouldExplain(
            ToolLoopExitReason.maxIterations,
            'I finished the first three files.',
          ),
          isFalse,
          reason:
              'a substantive reply is not overwritten just because the cap was hit',
        );
      },
    );
  });

  group('completionExplanation', () {
    test('is null for a healthy text response (terse answers stay silent)', () {
      expect(
        classifier.completionExplanation(ToolLoopExitReason.textResponse),
        isNull,
      );
      expect(
        classifier.completionExplanation(
          ToolLoopExitReason.pendingBatchExecuted,
        ),
        isNull,
      );
    });

    test('is a non-empty sentence for every abnormal reason', () {
      for (final reason in ToolLoopExitReason.values) {
        if (reason == ToolLoopExitReason.textResponse ||
            reason == ToolLoopExitReason.pendingBatchExecuted) {
          continue;
        }
        final explanation = classifier.completionExplanation(reason);
        expect(explanation, isNotNull, reason: '$reason should explain');
        expect(explanation!.trim(), isNotEmpty);
      }
    });
  });

  group('logToken', () {
    test('maps every reason to a stable distinct snake_case token', () {
      final tokens = ToolLoopExitReason.values
          .map(classifier.logToken)
          .toList();
      expect(
        tokens.toSet().length,
        tokens.length,
        reason: 'tokens are distinct',
      );
      expect(
        classifier.logToken(ToolLoopExitReason.maxIterations),
        'max_iterations',
      );
      expect(
        classifier.logToken(ToolLoopExitReason.pendingBatchExecuted),
        'pending_batch_executed',
      );
      expect(
        classifier.logToken(ToolLoopExitReason.unexecutedToolRequest),
        'unexecuted_tool_request',
      );
      expect(
        classifier.logToken(ToolLoopExitReason.toolFailureAbort),
        'tool_failure_abort',
      );
    });
  });

  group('isMidWorkStop', () {
    test('flags a turn whose last persisted message is a tool result', () {
      expect(
        classifier.isMidWorkStop(
          state(lastIsTool: true, lastTool: 'read_file'),
        ),
        isTrue,
      );
      expect(classifier.isMidWorkStop(state(lastIsTool: false)), isFalse);
    });
  });
}
