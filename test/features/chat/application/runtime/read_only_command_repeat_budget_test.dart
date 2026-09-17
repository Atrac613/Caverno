import 'package:caverno/features/chat/application/runtime/read_only_command_repeat_budget.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReadOnlyCommandRepeatBudget', () {
    test('allows one re-run of a read-only command, then stops', () {
      final budget = ReadOnlyCommandRepeatBudget();
      final call = _gitCall('tag --list --sort=-version:refname');

      expect(_exhausted(budget, call), isFalse);
      _record(budget, call);
      // The re-run session 96e27118 needed: the tag list was no longer in the
      // request and the digest told the model to fetch it again.
      expect(_exhausted(budget, call), isFalse);
      _record(budget, call);
      expect(_exhausted(budget, call), isTrue);
    });

    test('a mutating command is not budgeted here', () {
      // Its repeat is the duplicate guard's business; counting it would imply
      // this class had licensed a second side effect.
      final budget = ReadOnlyCommandRepeatBudget();
      final call = _gitCall('commit -m "wip"');

      _record(budget, call);
      _record(budget, call);
      _record(budget, call);
      expect(_exhausted(budget, call), isFalse);
    });

    test('a write hands the command a fresh budget', () {
      final budget = ReadOnlyCommandRepeatBudget();
      final call = _gitCall('status');

      _record(budget, call);
      _record(budget, call);
      expect(_exhausted(budget, call), isTrue);
      // `commandRetryGeneration` advances on every write_file / edit_file, so
      // the same observation after an edit is a different question.
      expect(_exhausted(budget, call, commandRetryGeneration: 1), isFalse);
    });

    test('a mutating command hands the observation a fresh budget', () {
      final budget = ReadOnlyCommandRepeatBudget();
      final call = _gitCall('status');

      _record(budget, call);
      _record(budget, call);
      expect(_exhausted(budget, call), isTrue);
      expect(_exhausted(budget, call, stateChangeGeneration: 1), isFalse);
    });

    test('rewording reason does not reset the budget', () {
      final budget = ReadOnlyCommandRepeatBudget();

      _record(budget, _gitCall('status', reason: 'Check the tree.'));
      _record(budget, _gitCall('status', reason: 'Check the tree once more.'));
      expect(
        _exhausted(budget, _gitCall('status', reason: 'One last look.')),
        isTrue,
      );
    });

    test('a new turn starts over', () {
      final budget = ReadOnlyCommandRepeatBudget();
      final call = _gitCall('status');

      _record(budget, call);
      _record(budget, call);
      expect(_exhausted(budget, call), isTrue);
      expect(_exhausted(budget, call, interactionGeneration: 2), isFalse);
    });
  });
}

ToolCallInfo _gitCall(String command, {String? reason}) => ToolCallInfo(
  id: 'call-$command',
  name: 'git_execute_command',
  arguments: <String, dynamic>{
    'command': command,
    'reason': ?reason,
  },
);

ReadOnlyCommandRepeatBudgetScope _scope(
  ReadOnlyCommandRepeatBudget budget, {
  int interactionGeneration = 1,
  int commandRetryGeneration = 0,
  int stateChangeGeneration = 0,
}) => budget.forBatch(
  interactionGeneration: interactionGeneration,
  commandRetryGeneration: commandRetryGeneration,
  stateChangeGeneration: stateChangeGeneration,
);

void _record(
  ReadOnlyCommandRepeatBudget budget,
  ToolCallInfo toolCall, {
  int interactionGeneration = 1,
  int commandRetryGeneration = 0,
  int stateChangeGeneration = 0,
}) => _scope(
  budget,
  interactionGeneration: interactionGeneration,
  commandRetryGeneration: commandRetryGeneration,
  stateChangeGeneration: stateChangeGeneration,
).recordExecution(toolCall);

bool _exhausted(
  ReadOnlyCommandRepeatBudget budget,
  ToolCallInfo toolCall, {
  int interactionGeneration = 1,
  int commandRetryGeneration = 0,
  int stateChangeGeneration = 0,
}) => _scope(
  budget,
  interactionGeneration: interactionGeneration,
  commandRetryGeneration: commandRetryGeneration,
  stateChangeGeneration: stateChangeGeneration,
).isExhausted(toolCall);
