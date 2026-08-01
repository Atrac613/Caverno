import 'package:caverno/features/chat/domain/services/tool_loop_exhaustion_policy.dart';
import 'package:test/test.dart';

const _policy = ToolLoopExhaustionPolicy();

ToolLoopExhaustionDecisionInput _input({
  int iteration = 12,
  int maxIterations = 12,
  bool recoveryAlreadyAttempted = false,
  bool hasPendingToolCalls = true,
  bool hasCurrentBatchToolResults = true,
  bool hasPendingFileMutation = false,
  bool hasPendingWriteGitCommand = false,
}) {
  return ToolLoopExhaustionDecisionInput(
    iteration: iteration,
    maxIterations: maxIterations,
    recoveryAlreadyAttempted: recoveryAlreadyAttempted,
    hasPendingToolCalls: hasPendingToolCalls,
    hasCurrentBatchToolResults: hasCurrentBatchToolResults,
    hasPendingFileMutation: hasPendingFileMutation,
    hasPendingWriteGitCommand: hasPendingWriteGitCommand,
  );
}

void main() {
  group('ToolLoopExhaustionDecisionInput', () {
    test('retains every named immutable decision fact', () {
      const input = ToolLoopExhaustionDecisionInput(
        iteration: 13,
        maxIterations: 12,
        recoveryAlreadyAttempted: false,
        hasPendingToolCalls: true,
        hasCurrentBatchToolResults: true,
        hasPendingFileMutation: false,
        hasPendingWriteGitCommand: false,
      );

      expect(input.iteration, 13);
      expect(input.maxIterations, 12);
      expect(input.recoveryAlreadyAttempted, isFalse);
      expect(input.hasPendingToolCalls, isTrue);
      expect(input.hasCurrentBatchToolResults, isTrue);
      expect(input.hasPendingFileMutation, isFalse);
      expect(input.hasPendingWriteGitCommand, isFalse);
      expect(input.iterationLimitReached, isTrue);
    });
  });

  group('ToolLoopExhaustionPolicy', () {
    test('allows recovery at and beyond the current iteration limit', () {
      for (final iteration in [12, 13]) {
        expect(
          _policy.shouldRequestRecovery(_input(iteration: iteration)),
          isTrue,
          reason: 'iteration=$iteration',
        );
      }
    });

    test('preserves the zero-budget iteration comparison', () {
      expect(
        _policy.shouldRequestRecovery(_input(iteration: 0, maxIterations: 0)),
        isTrue,
      );
    });

    test('rejects every individual blocking condition', () {
      final cases = <({String name, ToolLoopExhaustionDecisionInput input})>[
        (name: 'iteration limit not reached', input: _input(iteration: 11)),
        (
          name: 'recovery already attempted',
          input: _input(recoveryAlreadyAttempted: true),
        ),
        (
          name: 'pending file mutation',
          input: _input(hasPendingFileMutation: true),
        ),
        (
          name: 'no pending tool calls',
          input: _input(hasPendingToolCalls: false),
        ),
        (
          name: 'no current batch tool results',
          input: _input(hasCurrentBatchToolResults: false),
        ),
        (
          name: 'pending write git command',
          input: _input(hasPendingWriteGitCommand: true),
        ),
      ];

      for (final testCase in cases) {
        expect(
          _policy.shouldRequestRecovery(testCase.input),
          isFalse,
          reason: testCase.name,
        );
      }
    });

    test('rejects combinations of independent blockers', () {
      expect(
        _policy.shouldRequestRecovery(
          _input(
            iteration: 11,
            recoveryAlreadyAttempted: true,
            hasPendingFileMutation: true,
            hasPendingToolCalls: false,
            hasCurrentBatchToolResults: false,
            hasPendingWriteGitCommand: true,
          ),
        ),
        isFalse,
      );
      expect(
        _policy.shouldRequestRecovery(
          _input(hasPendingFileMutation: true, hasPendingWriteGitCommand: true),
        ),
        isFalse,
      );
    });

    test('allows read-only pending work with current owner-turn results', () {
      expect(
        _policy.shouldRequestRecovery(
          _input(
            hasPendingFileMutation: false,
            hasPendingWriteGitCommand: false,
          ),
        ),
        isTrue,
      );
    });
  });
}
