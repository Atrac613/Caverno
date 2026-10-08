import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_loop/tool_loop_exhaustion_policy.dart';
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
  bool hasPendingUserQuestion = false,
}) {
  return ToolLoopExhaustionDecisionInput(
    iteration: iteration,
    maxIterations: maxIterations,
    recoveryAlreadyAttempted: recoveryAlreadyAttempted,
    hasPendingToolCalls: hasPendingToolCalls,
    hasCurrentBatchToolResults: hasCurrentBatchToolResults,
    hasPendingFileMutation: hasPendingFileMutation,
    hasPendingWriteGitCommand: hasPendingWriteGitCommand,
    hasPendingUserQuestion: hasPendingUserQuestion,
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
        hasPendingUserQuestion: false,
      );

      expect(input.iteration, 13);
      expect(input.maxIterations, 12);
      expect(input.recoveryAlreadyAttempted, isFalse);
      expect(input.hasPendingToolCalls, isTrue);
      expect(input.hasCurrentBatchToolResults, isTrue);
      expect(input.hasPendingFileMutation, isFalse);
      expect(input.hasPendingWriteGitCommand, isFalse);
      expect(input.hasPendingUserQuestion, isFalse);
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
        (
          name: 'pending user question',
          input: _input(hasPendingUserQuestion: true),
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

  group('ToolLoopExhaustionDecisionInput.fromPendingCalls', () {
    ToolLoopExhaustionDecisionInput derive(List<ToolCallInfo> pending) =>
        ToolLoopExhaustionDecisionInput.fromPendingCalls(
          iteration: 12,
          maxIterations: 12,
          recoveryAlreadyAttempted: false,
          pendingToolCalls: pending,
          hasCurrentBatchToolResults: true,
        );
    ToolCallInfo call(
      String name, [
      Map<String, dynamic> arguments = const {},
    ]) => ToolCallInfo(id: 'call-$name', name: name, arguments: arguments);

    test('derives each pending-call fact from the calls', () {
      final read = derive([
        call('read_file', {'path': 'a.dart'}),
      ]);
      expect(read.hasPendingToolCalls, isTrue);
      expect(read.hasPendingFileMutation, isFalse);
      expect(read.hasPendingWriteGitCommand, isFalse);
      expect(read.hasPendingUserQuestion, isFalse);
      expect(read.hasPendingFileRead, isTrue);
      expect(_policy.shouldRequestRecovery(read), isFalse);

      expect(derive(const []).hasPendingToolCalls, isFalse);
      expect(
        derive([
          call('write_file', {'path': 'a.dart'}),
        ]).hasPendingFileMutation,
        isTrue,
      );
      expect(
        derive([
          call('git_execute_command', {'command': 'commit -m "x"'}),
        ]).hasPendingWriteGitCommand,
        isTrue,
      );
    });

    test('leaves a pending user question to the user, not to recovery', () {
      // Session dd50d110: only ask_user_question was pending at the limit, and
      // the recovery prompt ("do not ask for confirmation") had the model
      // settle the release version itself.
      final input = derive([
        call('read_file', {'path': 'pubspec.yaml'}),
        call('ask_user_question', {'question': 'Which version?'}),
      ]);

      expect(input.hasPendingUserQuestion, isTrue);
      expect(_policy.shouldRequestRecovery(input), isFalse);
    });

    test('retains a pending verifier for the final approved batch', () {
      final input = derive([
        call('local_execute_command', {
          'command': '.venv/bin/python -m pytest test_watcher.py -v',
        }),
      ]);
      expect(input.hasPendingCommandExecution, isTrue);
      expect(_policy.shouldRequestRecovery(input), isFalse);
    });

    test(
      'retains a requested fresh range instead of replaying old context',
      () {
        final input = derive([
          call('read_file', {'path': 'source.py', 'offset': 190, 'limit': 100}),
          call('search_files', {'query': 'query_interval'}),
        ]);
        expect(input.hasPendingFileRead, isTrue);
        expect(_policy.shouldRequestRecovery(input), isFalse);
        expect(
          _policy.shouldRequestRecovery(derive([call('search_files')])),
          isTrue,
        );
      },
    );
  });
}
